#import "MiumCEFBridgeNativeTestSupport.h"

using namespace MiumCEFBridgeNativeTestSupport;

@implementation TestSnapshotView

- (BOOL)isFlipped {
  return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
  [[NSColor systemBlueColor] setFill];
  NSRectFill(dirtyRect);
}

- (NSBitmapImageRep*)bitmapImageRepForCachingDisplayInRect:(NSRect)rect {
  if (self.returnsNilBitmapRep) {
    return nil;
  }

  Class repClass = self.usesFailingBitmapRep ? [FailingBitmapImageRep class] : [NSBitmapImageRep class];
  return [[repClass alloc] initWithBitmapDataPlanes:nullptr
                                         pixelsWide:std::max(1, static_cast<int>(std::ceil(NSWidth(rect))))
                                         pixelsHigh:std::max(1, static_cast<int>(std::ceil(NSHeight(rect))))
                                      bitsPerSample:8
                                    samplesPerPixel:4
                                           hasAlpha:YES
                                           isPlanar:NO
                                     colorSpaceName:NSCalibratedRGBColorSpace
                                        bytesPerRow:0
                                       bitsPerPixel:0];
}

- (void)cacheDisplayInRect:(NSRect)rect toBitmapImageRep:(NSBitmapImageRep*)bitmapImageRep {
  NSGraphicsContext* context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmapImageRep];
  [NSGraphicsContext saveGraphicsState];
  [NSGraphicsContext setCurrentContext:context];
  [[NSColor systemBlueColor] setFill];
  NSRectFill(NSMakeRect(0, 0, NSWidth(rect), NSHeight(rect)));
  [context flushGraphics];
  [NSGraphicsContext restoreGraphicsState];
}

- (NSData*)dataWithPDFInsideRect:(NSRect)rect {
  if (self.returnsNilPDFData) {
    return nil;
  }
  return self.forcedPDFData ?: [super dataWithPDFInsideRect:rect];
}

@end

@implementation FailingBitmapImageRep

- (NSData*)representationUsingType:(NSBitmapImageFileType)storageType properties:(NSDictionary<NSBitmapImageRepPropertyKey, id>*)properties {
  (void)storageType;
  (void)properties;
  return nil;
}

@end

@implementation MiumCEFBridgeNativeTestCase

- (void)acquireSuiteLock {
  static constexpr const char* kSuiteLockPath = "/tmp/MiumCEFBridgeNativeTestCase.lock";
  _suiteLockFD = open(kSuiteLockPath, O_CREAT | O_RDWR, 0666);
  XCTAssertGreaterThanOrEqual(_suiteLockFD, 0);
  if (_suiteLockFD >= 0) {
    XCTAssertEqual(flock(_suiteLockFD, LOCK_EX), 0);
  }
}

- (void)releaseSuiteLock {
  if (_suiteLockFD < 0) {
    return;
  }
  XCTAssertEqual(flock(_suiteLockFD, LOCK_UN), 0);
  close(_suiteLockFD);
  _suiteLockFD = -1;
}

- (void)waitForMainQueueToDrain {
  XCTestExpectation* expectation = [self expectationWithDescription:@"main queue drained"];
  dispatch_async(dispatch_get_main_queue(), ^{
    [expectation fulfill];
  });
  [self waitForExpectations:@[ expectation ] timeout:kCallbackTimeout];
}

- (void)waitForMessageQueueToDrain {
  // The current test hook targets the non-UI browser message queue only.
  CallbackProbe nonUIProbe;
  nonUIProbe.expectation = [self expectationWithDescription:@"non-ui message queue drained"];
  miumNativeCEFTestRunOnMessageQueue(
    testNativeCallback,
    MiumCEFResultOK,
    "non-ui-drain",
    &nonUIProbe,
    0
  );

  [self waitForExpectations:@[ nonUIProbe.expectation ] timeout:kCallbackTimeout];
}

- (void)drainPendingAsyncWork {
  miumNativeCEFTestSetCallbackQueueDraining(MiumCEFBridgeTestCallbackRoute::ui, false);
  miumNativeCEFTestSetCallbackQueueDraining(MiumCEFBridgeTestCallbackRoute::nonUI, false);

  NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:kCallbackTimeout];
  while (true) {
    [self waitForMainQueueToDrain];
    [self waitForMessageQueueToDrain];

    if (miumNativeCEFTestPendingTeardownBrowserCloseCount() > 0) {
      miumNativeCEFTestFinishPendingBrowserClose(MiumCEFBridgeTestCloseKind::teardown);
    }
    if (miumNativeCEFTestPendingReplacementBrowserCloseCount() > 0) {
      miumNativeCEFTestFinishPendingBrowserClose(MiumCEFBridgeTestCloseKind::replacement);
    }
    if (miumNativeCEFTestIsShutdownPumpScheduled()) {
      miumNativeCEFTestPumpPendingShutdownMessageLoop();
    }
    miumNativeCEFTestMaybeCompletePendingCefShutdown();

    const bool callbacksDrained =
      miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::ui) == static_cast<size_t>(0)
      && miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI) == static_cast<size_t>(0);
    const bool shutdownDrained = !miumNativeCEFTestIsShutdownPumpScheduled();
    const bool closesDrained = miumNativeCEFHasPendingBrowserClose() == 0;

    if (callbacksDrained && shutdownDrained && closesDrained) {
      return;
    }

    if ([deadline timeIntervalSinceNow] <= 0.0) {
      XCTFail(@"Timed out draining pending async test work");
      return;
    }

    [[NSRunLoop currentRunLoop] runMode:NSRunLoopCommonModes
                             beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }
}

- (void*)openTrackedLibraryAtPath:(NSString*)path {
  void* handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
  if (handle != nullptr) {
    _openedLibraryHandles.push_back(handle);
  }
  return handle;
}

- (void)closeTrackedLibraries {
  for (auto handleIter = _openedLibraryHandles.rbegin(); handleIter != _openedLibraryHandles.rend(); ++handleIter) {
    if (*handleIter != nullptr) {
      dlclose(*handleIter);
    }
  }
  _openedLibraryHandles.clear();
}

- (void)setUp {
  [super setUp];
  _suiteLockFD = -1;
  _openedLibraryHandles.clear();
  [self acquireSuiteLock];
  _fixture.resetGlobals();
  clearBridgeEnvironmentOverrides();
  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::none);
  CEFBridge_Shutdown();
  CEFBridgeTestResetState();
  miumNativeCEFTestResetState();
  FakeBrowserHarness::resetRetainedHarnesses();
  FakeMediaAccessCallbackHarness::resetRetainedHarnesses();
  FakePermissionPromptCallbackHarness::resetRetainedHarnesses();
}

- (void)tearDown {
  [self drainPendingAsyncWork];
  clearBridgeEnvironmentOverrides();
  CEFBridge_Shutdown();
  CEFBridgeTestResetState();
  miumNativeCEFTestResetState();
  [self closeTrackedLibraries];
  FakeBrowserHarness::resetRetainedHarnesses();
  FakeMediaAccessCallbackHarness::resetRetainedHarnesses();
  FakePermissionPromptCallbackHarness::resetRetainedHarnesses();
  _fixture.resetGlobals();
  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::none);
  [self releaseSuiteLock];
  [super tearDown];
}

- (MiumCEFRuntimeHandle)seedRuntime {
  MiumCEFRuntimeHandle runtimeHandle = miumNativeCEFTestInsertRuntime("/tmp/mium-runtime", "/tmp/mium-runtime/metadata", true);
  XCTAssertNotEqual(runtimeHandle, nullptr);
  return runtimeHandle;
}

- (MiumCEFBrowserHandle)createBrowserForRuntime:(MiumCEFRuntimeHandle)runtimeHandle {
  MiumCEFBrowserHandle browserHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowser(runtimeHandle, &browserHandle), MiumCEFResultOK);
  XCTAssertNotEqual(browserHandle, nullptr);
  return browserHandle;
}

- (NSString*)temporaryDirectory {
  NSString* directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  NSError* error = nil;
  XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:directory
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:&error]);
  XCTAssertNil(error);
  return directory;
}

- (void)installBasicAPI {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.userfreeFree = fakeUserFreeUTF16Free;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);
}

- (void)runOnBackgroundQueueAndWait:(dispatch_block_t)block {
  XCTestExpectation* expectation = [self expectationWithDescription:@"background queue work finished"];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
    block();
    // Bounce through the main queue so work forwarded there by `block` runs before we resume.
    dispatch_async(dispatch_get_main_queue(), ^{
      [expectation fulfill];
    });
  });
  [self waitForExpectations:@[ expectation ] timeout:kCallbackTimeout];
}

- (void)runOnBackgroundQueueAndDrain:(dispatch_block_t)block {
  [self runOnBackgroundQueueAndWait:block];
  [self drainPendingAsyncWork];
}

- (void)waitUntil:(BOOL (NS_NOESCAPE ^)(void))condition description:(NSString*)description {
  NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:kCallbackTimeout];
  while (!condition()) {
    if ([deadline timeIntervalSinceNow] <= 0.0) {
      XCTFail(@"Timed out waiting for %@", description);
      return;
    }
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                             beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    [[NSRunLoop currentRunLoop] runMode:NSRunLoopCommonModes
                             beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }
}

- (void)writeString:(NSString*)string toPath:(NSString*)path {
  NSError* error = nil;
  XCTAssertTrue([string writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]);
  XCTAssertNil(error);
}

- (void)createFileAtPath:(NSString*)path executable:(BOOL)executable {
  NSString* directory = path.stringByDeletingLastPathComponent;
  NSError* createError = nil;
  XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:directory
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:&createError]);
  XCTAssertNil(createError);

  XCTAssertTrue([[NSFileManager defaultManager] createFileAtPath:path contents:[NSData data] attributes:nil]);
  if (executable) {
    NSError* attributeError = nil;
    XCTAssertTrue([[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @0755 }
                                                   ofItemAtPath:path
                                                          error:&attributeError]);
    XCTAssertNil(attributeError);
  }
}

- (void)createLocalesAtDirectory:(NSString*)resourcesDirectory {
  NSString* localePath = [resourcesDirectory stringByAppendingPathComponent:@"locales/en.lproj/locale.pak"];
  [self createFileAtPath:localePath executable:NO];
}

- (void)createHelperAppNamed:(NSString*)bundleName
              executableName:(NSString*)executableName
              infoExecutable:(NSString* _Nullable)infoExecutable
                 inDirectory:(NSString*)helpersDirectory {
  NSString* appDirectory = [helpersDirectory stringByAppendingPathComponent:[bundleName stringByAppendingString:@".app"]];
  NSString* contentsDirectory = [appDirectory stringByAppendingPathComponent:@"Contents"];
  NSString* executablePath = [[contentsDirectory stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:executableName];
  [self createFileAtPath:executablePath executable:YES];

  if (infoExecutable != nil) {
    NSString* plistPath = [contentsDirectory stringByAppendingPathComponent:@"Info.plist"];
    NSString* plist = [NSString stringWithFormat:
      @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
       "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
       "<plist version=\"1.0\"><dict><key>CFBundleExecutable</key><string>%@</string></dict></plist>\n",
      infoExecutable];
    [self writeString:plist toPath:plistPath];
  }
}

- (NSString*)fakeCEFRuntimeSource {
  return [NSString stringWithUTF8String:R"CPP(
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "include/MiumCEFBridgeCefTypes.h"
#include "include/cef_api_hash.h"

static void append_line(const char* line) {
  const char* logPath = std::getenv("MIUM_CEF_TEST_LOG_PATH");
  if (logPath == nullptr || logPath[0] == '\0' || line == nullptr) {
    return;
  }

  FILE* file = std::fopen(logPath, "a");
  if (file == nullptr) {
    return;
  }

  std::fputs(line, file);
  std::fputc('\n', file);
  std::fclose(file);
}

static void append_key_value(const char* key, const char* value) {
  char buffer[4096] = {};
  std::snprintf(buffer, sizeof(buffer), "%s=%s", key == nullptr ? "" : key, value == nullptr ? "" : value);
  append_line(buffer);
}

static void append_utf16_value(const char* key, const cef_string_t* value) {
  if (value == nullptr || value->str == nullptr || value->length == 0) {
    append_key_value(key, "");
    return;
  }

  char buffer[4096] = {};
  const size_t maxCount = sizeof(buffer) - 1;
  const size_t count = value->length < maxCount ? value->length : maxCount;
  for (size_t index = 0; index < count; ++index) {
    buffer[index] = static_cast<char>(value->str[index]);
  }
  buffer[count] = '\0';
  append_key_value(key, buffer);
}

#if !defined(OMIT_CEF_API_HASH)
extern "C" const char* cef_api_hash(int, int) {
  return CEF_API_HASH_PLATFORM;
}
#endif

extern "C" int cef_api_version(void) {
  return CEF_API_VERSION;
}

#if !defined(OMIT_CEF_GET_VERSION)
extern "C" const void* cef_get_version(void) {
  append_line("get_version");
  return reinterpret_cast<const void*>(0x1);
}
#endif

#if defined(INCLUDE_CEF_VERSION_INFO)
extern "C" int cef_version_info(int entry) {
  return entry == 0 ? 123 : 0;
}
#endif

extern "C" int cef_string_utf8_to_utf16(const char* source, size_t source_length, cef_string_t* output) {
  if (output == nullptr) {
    return 0;
  }

  output->str = nullptr;
  output->length = 0;
  output->dtor = nullptr;

  const char* failureNeedle = std::getenv("MIUM_CEF_TEST_FAIL_UTF8_CONVERSION_CONTAINING");
  if (failureNeedle != nullptr && source != nullptr && std::strstr(source, failureNeedle) != nullptr) {
    return 0;
  }

  if (source == nullptr || source_length == 0) {
    return 1;
  }

  auto* buffer = static_cast<char16_t*>(std::calloc(source_length + 1, sizeof(char16_t)));
  if (buffer == nullptr) {
    return 0;
  }

  for (size_t index = 0; index < source_length; ++index) {
    buffer[index] = static_cast<char16_t>(static_cast<unsigned char>(source[index]));
  }

  output->str = buffer;
  output->length = source_length;
  output->dtor = [](char16_t* value) {
    std::free(value);
  };
  return 1;
}

#if !defined(OMIT_CEF_UTF16_CLEAR)
extern "C" void cef_string_utf16_clear(cef_string_t* value) {
  if (value == nullptr) {
    return;
  }
  if (value->str != nullptr && value->dtor != nullptr) {
    value->dtor(value->str);
  }
  value->str = nullptr;
  value->length = 0;
  value->dtor = nullptr;
}
#endif

#if !defined(OMIT_CEF_STRING_USERFREE_UTF16_FREE)
extern "C" void cef_string_userfree_utf16_free(cef_string_userfree_utf16_t value) {
  if (value == nullptr) {
    return;
  }
  if (value->str != nullptr && value->dtor != nullptr) {
    value->dtor(value->str);
  }
  value->str = nullptr;
  value->length = 0;
  value->dtor = nullptr;
  std::free(value);
}
#endif

#if !defined(OMIT_CEF_STRING_LIST_SIZE)
extern "C" size_t cef_string_list_size(cef_string_list_t) {
  return 1;
}
#endif

#if !defined(OMIT_CEF_STRING_LIST_VALUE)
extern "C" int cef_string_list_value(cef_string_list_t, size_t index, cef_string_t* output) {
  static const char* kURL = "https://navigator.test/favicon.ico";
  return index == 0 ? cef_string_utf8_to_utf16(kURL, std::strlen(kURL), output) : 0;
}
#endif

extern "C" int cef_execute_process(const cef_main_args_t* args, cef_app_t*, void*) {
  append_line("execute_process");
  char argcLine[64] = {};
  std::snprintf(argcLine, sizeof(argcLine), "execute_argc=%d", args == nullptr ? -1 : args->argc);
  append_line(argcLine);

  if (args != nullptr && args->argv != nullptr) {
    for (int index = 0; index < args->argc; ++index) {
      char line[1024] = {};
      std::snprintf(
        line,
        sizeof(line),
        "execute_argv[%d]=%s",
        index,
        args->argv[index] == nullptr ? "" : args->argv[index]
      );
      append_line(line);
    }
  }

  const char* result = std::getenv("MIUM_CEF_TEST_EXECUTE_PROCESS_RESULT");
  return result == nullptr ? -1 : std::atoi(result);
}

#if !defined(OMIT_CEF_INITIALIZE)
extern "C" int cef_initialize(
  const cef_main_args_t* args,
  const cef_settings_t* settings,
  const void*,
  void*
) {
  append_line("initialize");
  char argcLine[64] = {};
  std::snprintf(argcLine, sizeof(argcLine), "initialize_argc=%d", args == nullptr ? -1 : args->argc);
  append_line(argcLine);

  if (args != nullptr && args->argv != nullptr) {
    for (int index = 0; index < args->argc; ++index) {
      char line[1024] = {};
      std::snprintf(
        line,
        sizeof(line),
        "initialize_argv[%d]=%s",
        index,
        args->argv[index] == nullptr ? "" : args->argv[index]
      );
      append_line(line);
    }
  }

  if (settings != nullptr) {
    char noSandboxLine[64] = {};
    std::snprintf(noSandboxLine, sizeof(noSandboxLine), "no_sandbox=%d", settings->no_sandbox);
    append_line(noSandboxLine);
    append_utf16_value("browser_subprocess_path", &settings->browser_subprocess_path);
    append_utf16_value("resources_dir_path", &settings->resources_dir_path);
    append_utf16_value("locales_dir_path", &settings->locales_dir_path);
    append_utf16_value("cache_path", &settings->cache_path);
    append_utf16_value("root_cache_path", &settings->root_cache_path);
  }

  const char* result = std::getenv("MIUM_CEF_TEST_INITIALIZE_RESULT");
  return result == nullptr ? 1 : std::atoi(result);
}
#endif

#if !defined(OMIT_CEF_SHUTDOWN)
extern "C" void cef_shutdown(void) {
  append_line("shutdown");
}
#endif

#if !defined(OMIT_CEF_DO_MESSAGE_LOOP_WORK)
extern "C" void cef_do_message_loop_work(void) {
  append_line("message_loop_work");
}
#endif

#if !defined(OMIT_CEF_CREATE_BROWSER_SYNC)
extern "C" cef_browser_t* cef_browser_host_create_browser_sync(
  const cef_window_info_t*,
  const void*,
  const cef_string_t*,
  const cef_browser_settings_t*,
  const void*,
  const void*
) {
  append_line("create_browser_sync");
  return nullptr;
}
#endif

#if !defined(OMIT_CEF_PROCESS_MESSAGE_CREATE)
extern "C" cef_process_message_t* cef_process_message_create(const cef_string_t* name) {
  append_line("process_message_create");
  append_utf16_value("process_message_name", name);
  return nullptr;
}
#endif
)CPP"];
}

- (NSString*)compileFakeCEFRuntimeAtPath:(NSString*)binaryPath defines:(NSArray<NSString*>*)defines {
  NSString* packageRoot = [[[[NSString stringWithUTF8String:__FILE__] stringByDeletingLastPathComponent]
    stringByDeletingLastPathComponent]
    stringByDeletingLastPathComponent];
  NSString* sourcePath = [[binaryPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"FakeCEFRuntime.cpp"];
  [self writeString:[self fakeCEFRuntimeSource] toPath:sourcePath];

  NSMutableArray<NSString*>* arguments = [NSMutableArray array];
  [arguments addObject:@"-dynamiclib"];
  [arguments addObject:@"-std=c++17"];
  for (NSString* define in defines) {
    [arguments addObject:[@"-D" stringByAppendingString:define]];
  }
  [arguments addObject:@"-I"];
  [arguments addObject:[packageRoot stringByAppendingPathComponent:@"Sources/MiumKit"]];
  [arguments addObject:@"-I"];
  [arguments addObject:[packageRoot stringByAppendingPathComponent:@"Sources/MiumKit/Vendor/CEF"]];
  [arguments addObject:sourcePath];
  [arguments addObject:@"-o"];
  [arguments addObject:binaryPath];

  NSPipe* outputPipe = [NSPipe pipe];
  NSTask* task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/clang++"];
  task.arguments = arguments;
  task.standardOutput = outputPipe;
  task.standardError = outputPipe;
  NSError* launchError = nil;
  XCTAssertTrue([task launchAndReturnError:&launchError]);
  XCTAssertNil(launchError);
  [task waitUntilExit];

  NSData* outputData = [[outputPipe fileHandleForReading] readDataToEndOfFile];
  NSString* output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding] ?: @"";
  XCTAssertEqual(task.terminationStatus, 0, @"clang++ failed: %@", output);
  return output;
}

- (NSDictionary<NSString*, NSString*>*)createFakeRuntimeWithDefines:(NSArray<NSString*>*)defines {
  NSString* root = [self temporaryDirectory];
  NSString* frameworkBinary = [root stringByAppendingPathComponent:@"Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework"];
  NSString* resourcesDirectory = [root stringByAppendingPathComponent:@"Contents/Resources"];
  NSString* helpersDirectory = [root stringByAppendingPathComponent:@"Contents/Frameworks"];
  NSString* metadataPath = resourcesDirectory;
  NSString* logPath = [root stringByAppendingPathComponent:@"cef.log"];

  [self createLocalesAtDirectory:resourcesDirectory];
  [self createHelperAppNamed:@"Navigator Helper"
              executableName:@"Navigator Helper"
              infoExecutable:nil
                 inDirectory:helpersDirectory];
  [self compileFakeCEFRuntimeAtPath:frameworkBinary defines:defines];

  return @{
    @"root": root,
    @"frameworkBinary": frameworkBinary,
    @"resourcesDirectory": resourcesDirectory,
    @"helpersDirectory": helpersDirectory,
    @"metadataPath": metadataPath,
    @"localesDirectory": [resourcesDirectory stringByAppendingPathComponent:@"locales"],
    @"logPath": logPath,
  };
}

- (NSArray<NSString*>*)logLinesAtPath:(NSString*)path {
  NSString* contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
  if (contents == nil || contents.length == 0) {
    return @[];
  }

  NSMutableArray<NSString*>* lines = [NSMutableArray array];
  [contents enumerateLinesUsingBlock:^(NSString* line, BOOL* stop) {
    (void)stop;
    [lines addObject:line];
  }];
  return lines;
}

- (NSString*)packageRoot {
  NSString* sourcePath = [[NSString stringWithUTF8String:__FILE__] stringByStandardizingPath];
  return [[[sourcePath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
}

- (void)createDirectoryAtPath:(NSString*)path {
  NSError* error = nil;
  XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:path
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:&error]);
  XCTAssertNil(error);
}

- (void)writeText:(NSString*)text toPath:(NSString*)path {
  NSData* data = [text dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertNotNil(data);
  XCTAssertTrue([[NSFileManager defaultManager] createFileAtPath:path contents:data attributes:nil]);
}

- (void)writeBinaryData:(NSData*)data toPath:(NSString*)path {
  XCTAssertTrue([[NSFileManager defaultManager] createFileAtPath:path contents:data attributes:nil]);
}

- (NSString*)createHelperAppInDirectory:(NSString*)helpersDir
                                   name:(NSString*)name
                         executableName:(NSString*)executableName
                    infoPlistExecutable:(NSString* _Nullable)infoPlistExecutable {
  NSString* appPath = [helpersDir stringByAppendingPathComponent:[name stringByAppendingString:@".app"]];
  NSString* macOSDir = [[appPath stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"MacOS"];
  [self createDirectoryAtPath:macOSDir];

  if (infoPlistExecutable != nil) {
    NSDictionary* plist = @{
      @"CFBundleExecutable": infoPlistExecutable,
      @"CFBundleIdentifier": [NSString stringWithFormat:@"com.mium.tests.%@", name]
    };
    NSData* plistData = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                   format:NSPropertyListXMLFormat_v1_0
                                                                  options:0
                                                                    error:nil];
    XCTAssertNotNil(plistData);
    [self writeBinaryData:plistData toPath:[[appPath stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"Info.plist"]];
  }

  [self writeText:@"#!/bin/sh\nexit 0\n" toPath:[macOSDir stringByAppendingPathComponent:executableName]];
  XCTAssertEqual(chmod([[macOSDir stringByAppendingPathComponent:executableName] fileSystemRepresentation], 0755), 0);
  return appPath;
}

- (FakeCefLibrary)buildFakeCefLibraryVariant:(NSString*)variant {
  FakeCefLibrary library;
  library.runtimeRoot = [self temporaryDirectory];
  library.metadataPath = [library.runtimeRoot stringByAppendingPathComponent:@"Contents/Resources"];
  NSString* frameworksDir = [library.runtimeRoot stringByAppendingPathComponent:@"Contents/Frameworks"];
  NSString* helpersDir = frameworksDir;
  [self createDirectoryAtPath:library.metadataPath];
  [self createDirectoryAtPath:[library.runtimeRoot stringByAppendingPathComponent:@"Contents/Resources/locales/en.lproj"]];
  [self writeText:@"pak" toPath:[[library.runtimeRoot stringByAppendingPathComponent:@"Contents/Resources/locales/en.lproj"] stringByAppendingPathComponent:@"locale.pak"]];
  [self createHelperAppInDirectory:helpersDir
                              name:@"Navigator Helper"
                    executableName:@"Navigator Helper"
               infoPlistExecutable:nil];

  NSString* frameworkDir = [frameworksDir stringByAppendingPathComponent:@"Chromium Embedded Framework.framework"];
  [self createDirectoryAtPath:frameworkDir];
  library.frameworkPath = [frameworkDir stringByAppendingPathComponent:@"Chromium Embedded Framework"];

  NSString* packageRoot = [self packageRoot];
  NSString* miumSourceRoot = [packageRoot stringByAppendingPathComponent:@"Sources/MiumKit"];
  NSString* cefVendorRoot = [packageRoot stringByAppendingPathComponent:@"Sources/MiumKit/Vendor/CEF"];
  NSString* cefIncludeDir = [packageRoot stringByAppendingPathComponent:@"Sources/MiumKit/Vendor/CEF/include"];
  NSString* sourcePath = [[self temporaryDirectory] stringByAppendingPathComponent:@"fake_cef.cpp"];
  NSString* dylibSource = [NSString stringWithFormat:
    @"#include <cstring>\n"
     "#include <cstdlib>\n"
     "#include <string>\n"
     "#include \"include/MiumCEFBridgeCefTypes.h\"\n"
     "#include \"include/cef_api_hash.h\"\n"
     "extern \"C\" {\n"
     "static int g_initialize_calls = 0;\n"
     "static int g_shutdown_calls = 0;\n"
     "static int g_execute_process_calls = 0;\n"
     "static int g_message_loop_calls = 0;\n"
     "static char g_browser_subprocess_path[4096] = {};\n"
     "static char g_resources_dir_path[4096] = {};\n"
     "static char g_locales_dir_path[4096] = {};\n"
     "static char g_cache_path[4096] = {};\n"
     "static char g_root_cache_path[4096] = {};\n"
     "static void copy_utf16(const cef_string_t* source, char* destination, size_t capacity) {\n"
     "  if (destination == nullptr || capacity == 0) { return; }\n"
     "  destination[0] = '\\0';\n"
     "  if (source == nullptr || source->str == nullptr) { return; }\n"
     "  const size_t length = source->length < capacity - 1 ? source->length : capacity - 1;\n"
     "  for (size_t index = 0; index < length; ++index) { destination[index] = static_cast<char>(source->str[index]); }\n"
     "  destination[length] = '\\0';\n"
     "}\n"
     "%@\n"
     "%@\n"
     "%@\n"
     "%@\n"
     "%@\n"
     "%@\n"
     "%@\n"
     "%@\n"
     "%@\n"
     "%@\n"
     "%@\n"
     "%@\n"
     "%@\n"
     "%@\n"
     "int mium_test_get_initialize_calls(void) { return g_initialize_calls; }\n"
     "int mium_test_get_shutdown_calls(void) { return g_shutdown_calls; }\n"
     "int mium_test_get_execute_process_calls(void) { return g_execute_process_calls; }\n"
     "int mium_test_get_message_loop_calls(void) { return g_message_loop_calls; }\n"
     "const char* mium_test_get_browser_subprocess_path(void) { return g_browser_subprocess_path; }\n"
     "const char* mium_test_get_resources_dir_path(void) { return g_resources_dir_path; }\n"
     "const char* mium_test_get_locales_dir_path(void) { return g_locales_dir_path; }\n"
     "const char* mium_test_get_cache_path(void) { return g_cache_path; }\n"
     "const char* mium_test_get_root_cache_path(void) { return g_root_cache_path; }\n"
     "}\n",
    [variant isEqualToString:@"mismatch-hash"]
      ? @"const char* cef_api_hash(int, int) { return \"bad-hash\"; }"
      : ([variant isEqualToString:@"null-hash"]
          ? @"const char* cef_api_hash(int, int) { return nullptr; }"
          : ([variant isEqualToString:@"missing-api-hash"]
              ? @""
              : @"const char* cef_api_hash(int, int) { return CEF_API_HASH_PLATFORM; }")),
    [variant isEqualToString:@"missing-api-version"] ? @"" : @"int cef_api_version(void) { return CEF_API_VERSION; }",
    [variant isEqualToString:@"missing-version-info"]
      ? @""
      : @"int cef_version_info(int entry) { return entry == 0 ? 777 : 0; }",
    [variant isEqualToString:@"missing-utf8-to-utf16"]
      ? @""
      : @"int cef_string_utf8_to_utf16(const char* source, size_t source_length, cef_string_t* output) {\n"
        "  if (output == nullptr) { return 0; }\n"
        "  output->str = nullptr; output->length = 0; output->dtor = nullptr;\n"
        "  if (source == nullptr || source_length == 0) { return 1; }\n"
        "  auto* buffer = static_cast<char16_t*>(std::calloc(source_length + 1, sizeof(char16_t)));\n"
        "  if (buffer == nullptr) { return 0; }\n"
        "  for (size_t index = 0; index < source_length; ++index) { buffer[index] = static_cast<char16_t>(static_cast<unsigned char>(source[index])); }\n"
        "  output->str = buffer; output->length = source_length;\n"
        "  output->dtor = [](char16_t* value) { std::free(value); };\n"
        "  return 1;\n"
        "}\n",
    [variant isEqualToString:@"missing-utf16-clear"]
      ? @""
      : @"void cef_string_utf16_clear(cef_string_t* value) { if (value != nullptr && value->str != nullptr && value->dtor != nullptr) { value->dtor(value->str); } if (value != nullptr) { value->str = nullptr; value->length = 0; value->dtor = nullptr; } }",
    [variant isEqualToString:@"missing-userfree-utf16-free"]
      ? @""
      : @"void cef_string_userfree_utf16_free(cef_string_userfree_utf16_t value) { if (value != nullptr && value->str != nullptr && value->dtor != nullptr) { value->dtor(value->str); } if (value != nullptr) { value->str = nullptr; value->length = 0; value->dtor = nullptr; std::free(value); } }",
    [variant isEqualToString:@"missing-string-list-size"]
      ? @""
      : @"size_t cef_string_list_size(cef_string_list_t) { return 1; }",
    [variant isEqualToString:@"missing-string-list-value"]
      ? @""
      : ([variant isEqualToString:@"missing-utf8-to-utf16"]
          ? @"int cef_string_list_value(cef_string_list_t, size_t, cef_string_t* output) { if (output != nullptr) { output->str = nullptr; output->length = 0; output->dtor = nullptr; } return 0; }"
          : @"int cef_string_list_value(cef_string_list_t, size_t index, cef_string_t* output) { static const char* kURL = \"https://navigator.test/favicon.ico\"; return index == 0 ? cef_string_utf8_to_utf16(kURL, std::strlen(kURL), output) : 0; }"),
    [variant isEqualToString:@"missing-execute-process"]
      ? @""
      : @"int cef_execute_process(const cef_main_args_t*, cef_app_t*, void*) { ++g_execute_process_calls; return -1; }",
    [variant isEqualToString:@"missing-initialize"]
      ? @""
      : [NSString stringWithFormat:
          @"int cef_initialize(const cef_main_args_t* args, const cef_settings_t* settings, cef_app_t*, void*) {\n"
           "  ++g_initialize_calls;\n"
           "  copy_utf16(&settings->browser_subprocess_path, g_browser_subprocess_path, sizeof(g_browser_subprocess_path));\n"
           "  copy_utf16(&settings->resources_dir_path, g_resources_dir_path, sizeof(g_resources_dir_path));\n"
           "  copy_utf16(&settings->locales_dir_path, g_locales_dir_path, sizeof(g_locales_dir_path));\n"
           "  copy_utf16(&settings->cache_path, g_cache_path, sizeof(g_cache_path));\n"
           "  copy_utf16(&settings->root_cache_path, g_root_cache_path, sizeof(g_root_cache_path));\n"
           "  (void)args;\n"
           "  return %@;\n"
           "}\n",
          [variant isEqualToString:@"initialize-false"] ? @"0" : @"1"],
    [variant isEqualToString:@"missing-shutdown"] ? @"" : @"void cef_shutdown(void) { ++g_shutdown_calls; }",
    [variant isEqualToString:@"missing-do-message-loop-work"] ? @"" : @"void cef_do_message_loop_work(void) { ++g_message_loop_calls; }",
    [variant isEqualToString:@"missing-create-browser-sync"]
      ? @""
      : @"cef_browser_t* cef_browser_host_create_browser_sync(const cef_window_info_t*, cef_client_t*, const cef_string_t*, const cef_browser_settings_t*, cef_dictionary_value_t*, cef_request_context_t*) { return nullptr; }",
    [variant isEqualToString:@"missing-process-message-create"]
      ? @""
      : @"cef_process_message_t* cef_process_message_create(const cef_string_t*) { return nullptr; }"];
  [self writeText:dylibSource toPath:sourcePath];

  NSTask* task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/xcrun"];
  task.arguments = @[
    @"clang++",
    @"-dynamiclib",
    @"-std=c++17",
    @"-I",
    miumSourceRoot,
    @"-I",
    cefVendorRoot,
    @"-I",
    cefIncludeDir,
    sourcePath,
    @"-o",
    library.frameworkPath
  ];
  NSPipe* stderrPipe = [NSPipe pipe];
  task.standardError = stderrPipe;
  task.standardOutput = [NSPipe pipe];
  NSError* launchError = nil;
  XCTAssertTrue([task launchAndReturnError:&launchError]);
  XCTAssertNil(launchError);
  [task waitUntilExit];
  NSData* stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
  XCTAssertEqual(task.terminationStatus, 0, @"%@", [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding]);
  return library;
}

- (void*)symbolNamed:(const char*)name inHandle:(void*)handle {
  XCTAssertNotEqual(handle, nullptr);
  void* symbol = dlsym(handle, name);
  XCTAssertNotEqual(symbol, nullptr);
  return symbol;
}

@end
