#import "MiumCEFBridgeNativeTestSupport.h"

using namespace MiumCEFBridgeNativeTestSupport;

@interface MiumCEFBridgeSnapshotTests : MiumCEFBridgeNativeTestCase
@end

@implementation MiumCEFBridgeSnapshotTests

- (void)testRequestSnapshotWritesPNGFile {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);
  FakeCreateBrowserFactory factory;
  gCreateBrowserFactory = &factory;

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle hostViewHandle = nullptr;

  NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 80, 60)
                                                 styleMask:NSWindowStyleMaskBorderless
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
  TestSnapshotView* hostView = [[TestSnapshotView alloc] initWithFrame:NSMakeRect(0, 0, 80, 60)];
  hostView.wantsLayer = YES;
  window.contentView = hostView;
  [window orderFrontRegardless];
  [window displayIfNeeded];
  XCTAssertEqual(
    miumNativeCEFCreateBrowserHostViewForNSView(browserHandle, (__bridge void*)hostView, &hostViewHandle),
    MiumCEFResultOK
  );

  NSString* outputPath = [[self temporaryDirectory] stringByAppendingPathComponent:@"snapshot.png"];
  CallbackProbe probe;
  probe.expectation = [self expectationWithDescription:@"snapshot completed"];

  const MiumCEFResultCode result = miumNativeCEFRequestSnapshot(browserHandle, outputPath.UTF8String, nullptr, &probe, testNativeCallback);

  XCTAssertEqual(result, MiumCEFResultOK);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(probe.code, MiumCEFResultOK, @"%s", probe.message.c_str());
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:outputPath]);
  NSData* data = [NSData dataWithContentsOfFile:outputPath];
  XCTAssertGreaterThan(data.length, static_cast<NSUInteger>(0));
  [window orderOut:nil];
}

- (void)testRequestSnapshotRejectsInvalidOptions {
  [self installBasicAPI];
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle hostViewHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &hostViewHandle), MiumCEFResultOK);

  TestSnapshotView* hostView = [[TestSnapshotView alloc] initWithFrame:NSMakeRect(0, 0, 80, 60)];
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(hostViewHandle, (__bridge void*)hostView));

  NSString* outputPath = [[self temporaryDirectory] stringByAppendingPathComponent:@"snapshot.png"];
  CallbackProbe probe;
  probe.expectation = [self expectationWithDescription:@"snapshot failure delivered"];

  const MiumCEFResultCode result = miumNativeCEFRequestSnapshot(
    browserHandle,
    outputPath.UTF8String,
    "{\"quality\":0.5}",
    &probe,
    testNativeCallback
  );

  XCTAssertEqual(result, MiumCEFResultInvalidArgument);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(probe.code, MiumCEFResultInvalidArgument);
  XCTAssertTrue(probe.message.find("JPEG snapshots") != std::string::npos);
}

- (void)testRequestSnapshotWritesPDFWithClip {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);
  FakeCreateBrowserFactory factory;
  gCreateBrowserFactory = &factory;

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle hostViewHandle = nullptr;

  NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 120, 90)
                                                 styleMask:NSWindowStyleMaskBorderless
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
  TestSnapshotView* hostView = [[TestSnapshotView alloc] initWithFrame:NSMakeRect(0, 0, 120, 90)];
  hostView.wantsLayer = YES;
  hostView.forcedPDFData = [@"%PDF-1.4\n%" dataUsingEncoding:NSUTF8StringEncoding];
  window.contentView = hostView;
  [window orderFrontRegardless];
  [window displayIfNeeded];
  XCTAssertEqual(
    miumNativeCEFCreateBrowserHostViewForNSView(browserHandle, (__bridge void*)hostView, &hostViewHandle),
    MiumCEFResultOK
  );

  NSString* outputPath = [[self temporaryDirectory] stringByAppendingPathComponent:@"snapshot.pdf"];
  CallbackProbe probe;
  probe.expectation = [self expectationWithDescription:@"pdf snapshot completed"];

  const MiumCEFResultCode result = miumNativeCEFRequestSnapshot(
    browserHandle,
    outputPath.UTF8String,
    "{\"clip\":{\"x\":10,\"y\":10,\"width\":40,\"height\":20}}",
    &probe,
    testNativeCallback
  );

  XCTAssertEqual(result, MiumCEFResultOK);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(probe.code, MiumCEFResultOK, @"%s", probe.message.c_str());
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:outputPath]);
  NSData* data = [NSData dataWithContentsOfFile:outputPath];
  XCTAssertGreaterThan(data.length, static_cast<NSUInteger>(0));
  [window orderOut:nil];
}

- (void)testParseSnapshotOptionsWrapperCoversFormatsAndErrors {
  MiumCEFBridgeTestSnapshotOptions options{};
  std::string error;

  XCTAssertTrue(miumNativeCEFTestParseSnapshotOptions(nullptr, "/tmp/out.png", &options, &error));
  XCTAssertEqual(options.bitmapFileType, static_cast<long>(NSBitmapImageFileTypePNG));
  XCTAssertFalse(options.captureAsPDF);
  XCTAssertFalse(options.usesJPEGCompressionFactor);

  XCTAssertTrue(miumNativeCEFTestParseSnapshotOptions(" {\"format\":\"jpeg\",\"quality\":0.4,\"clipRect\":{\"x\":1,\"y\":2,\"width\":3,\"height\":4}} ", "/tmp/out.jpg", &options, &error));
  XCTAssertEqual(options.bitmapFileType, static_cast<long>(NSBitmapImageFileTypeJPEG));
  XCTAssertTrue(options.usesJPEGCompressionFactor);
  XCTAssertEqualWithAccuracy(options.jpegCompressionFactor, 0.4, 0.0001);
  XCTAssertTrue(options.hasClipRect);
  XCTAssertEqualWithAccuracy(options.clipX, 1.0, 0.0001);
  XCTAssertEqualWithAccuracy(options.clipHeight, 4.0, 0.0001);

  XCTAssertTrue(miumNativeCEFTestParseSnapshotOptions("{\"format\":\"pdf\"}", "/tmp/out.png", &options, &error));
  XCTAssertTrue(options.captureAsPDF);
  XCTAssertTrue(miumNativeCEFTestParseSnapshotOptions("{\"format\":\"gif\"}", "/tmp/out.png", &options, &error));
  XCTAssertEqual(options.bitmapFileType, static_cast<long>(NSBitmapImageFileTypeGIF));
  XCTAssertTrue(miumNativeCEFTestParseSnapshotOptions("{\"format\":\"bmp\"}", "/tmp/out.png", &options, &error));
  XCTAssertEqual(options.bitmapFileType, static_cast<long>(NSBitmapImageFileTypeBMP));
  XCTAssertTrue(miumNativeCEFTestParseSnapshotOptions("{\"format\":\"tiff\"}", "/tmp/out.png", &options, &error));
  XCTAssertEqual(options.bitmapFileType, static_cast<long>(NSBitmapImageFileTypeTIFF));
  XCTAssertTrue(miumNativeCEFTestParseSnapshotOptions(" \n\t ", "/tmp/out.png", &options, &error));
  XCTAssertTrue(miumNativeCEFTestParseSnapshotOptions("null", "/tmp/out.png", &options, &error));
  XCTAssertTrue(miumNativeCEFTestParseSnapshotOptions(nullptr, nullptr, &options, &error));

  XCTAssertFalse(miumNativeCEFTestParseSnapshotOptions("{\"format\":\"webp\"}", "/tmp/out.png", &options, &error));
  XCTAssertTrue(error.find("Unsupported snapshot format") != std::string::npos);
  XCTAssertFalse(miumNativeCEFTestParseSnapshotOptions("{invalid", "/tmp/out.png", &options, &error));
  XCTAssertFalse(miumNativeCEFTestParseSnapshotOptions("[1,2,3]", "/tmp/out.png", &options, &error));
  XCTAssertEqual(error, "Snapshot options must be a JSON object");
  XCTAssertFalse(miumNativeCEFTestParseSnapshotOptions("{\"unsupported\":1}", "/tmp/out.png", &options, &error));
  XCTAssertEqual(error, "Unsupported snapshot option 'unsupported'");
  XCTAssertFalse(miumNativeCEFTestParseSnapshotOptions("{\"format\":1}", "/tmp/out.png", &options, &error));
  XCTAssertEqual(error, "Snapshot format must be a non-empty string");
  XCTAssertFalse(miumNativeCEFTestParseSnapshotOptions("{\"clip\":{},\"clipRect\":{}}", "/tmp/out.png", &options, &error));
  XCTAssertEqual(error, "Provide either 'clip' or 'clipRect', not both");
  XCTAssertFalse(miumNativeCEFTestParseSnapshotOptions("{\"clip\":1}", "/tmp/out.png", &options, &error));
  XCTAssertEqual(error, "Snapshot clip must be an object with x, y, width, and height");
  XCTAssertFalse(miumNativeCEFTestParseSnapshotOptions("{\"clip\":{\"x\":\"1\",\"y\":2,\"width\":3,\"height\":4}}", "/tmp/out.png", &options, &error));
  XCTAssertEqual(error, "Snapshot clip 'x' must be numeric");
  XCTAssertFalse(miumNativeCEFTestParseSnapshotOptions("{\"clip\":{\"x\":1,\"y\":2,\"width\":0,\"height\":4}}", "/tmp/out.png", &options, &error));
  XCTAssertEqual(error, "Snapshot clip must have finite x, y, width, and height values");
  XCTAssertFalse(miumNativeCEFTestParseSnapshotOptions("{\"quality\":\"0.5\"}", "/tmp/out.jpg", &options, &error));
  XCTAssertEqual(error, "Snapshot quality must be numeric");
  XCTAssertFalse(miumNativeCEFTestParseSnapshotOptions("{\"quality\":2.0}", "/tmp/out.jpg", &options, &error));
  XCTAssertEqual(error, "Snapshot quality must be between 0.0 and 1.0");
  XCTAssertFalse(miumNativeCEFTestParseSnapshotOptions("{\"quality\":0.5}", "/tmp/out.png", &options, &error));
  XCTAssertEqual(error, "Snapshot quality is only supported for JPEG snapshots");

  char invalidJSON[] = { static_cast<char>(0xFF), 0 };
  XCTAssertFalse(miumNativeCEFTestParseSnapshotOptions(invalidJSON, "/tmp/out.png", &options, &error));
  XCTAssertEqual(error, "Snapshot options are not UTF8");
}

- (void)testSnapshotAndResizeTestingOverridesCoverAdditionalBranches {
  [self installBasicAPI];
  NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 80, 60)
                                                 styleMask:NSWindowStyleMaskBorderless
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
  TestSnapshotView* windowView = [[TestSnapshotView alloc] initWithFrame:NSMakeRect(0, 0, 80, 60)];
  window.contentView = windowView;
  [window orderFrontRegardless];
  [window displayIfNeeded];

  miumNativeCEFTestSetWindowSnapshotMode(MiumCEFBridgeTestWindowSnapshotMode::forceOnePixelImage);
  miumNativeCEFTestSetOnePixelImageFailureMode(MiumCEFBridgeTestOnePixelImageFailureMode::nullProvider);
  XCTAssertFalse(miumNativeCEFTestSnapshotBitmapRepForHostViewFromWindow((__bridge void*)windowView, 0.0, 0.0, 20.0, 10.0));
  miumNativeCEFTestSetOnePixelImageFailureMode(MiumCEFBridgeTestOnePixelImageFailureMode::nullColorSpace);
  XCTAssertFalse(miumNativeCEFTestSnapshotBitmapRepForHostViewFromWindow((__bridge void*)windowView, 0.0, 0.0, 20.0, 10.0));
  miumNativeCEFTestSetOnePixelImageFailureMode(MiumCEFBridgeTestOnePixelImageFailureMode::none);
  miumNativeCEFTestSetWindowSnapshotMode(MiumCEFBridgeTestWindowSnapshotMode::live);
  [window orderOut:nil];

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness browserWithoutHost;
  browserWithoutHost.browser->browser.get_host = [](cef_browser_t*) -> cef_browser_host_t* {
    return nullptr;
  };
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, browserWithoutHost.browserRef(), nullptr));
  XCTAssertEqual(miumNativeCEFResizeBrowser(browserHandle, 120, 80), MiumCEFResultError);
}

- (void)testLoadJavaScriptSendMessageAndSnapshotFailurePaths {
  MiumCEFBridgeTestAPI missingUTF8API{};
  missingUTF8API.utf16Clear = fakeUTF16Clear;
  miumNativeCEFTestInstallAPI(&missingUTF8API);
  miumNativeCEFTestSetInitialized(true, 1);

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness browserWithoutFrame;
  browserWithoutFrame.browser->browser.get_main_frame = nullptr;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, browserWithoutFrame.browserRef(), nullptr));

  CallbackProbe loadProbe;
  loadProbe.expectation = [self expectationWithDescription:@"load failure"];
  XCTAssertEqual(miumNativeCEFLoadURL(browserHandle, "https://example.com", &loadProbe, testNativeCallback), MiumCEFResultError);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertTrue(loadProbe.message.find("UTF8->UTF16") != std::string::npos);

  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createProcessMessage = fakeCreateProcessMessageWithoutArguments;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  CallbackProbe loadFrameProbe;
  loadFrameProbe.expectation = [self expectationWithDescription:@"load no frame"];
  XCTAssertEqual(miumNativeCEFLoadURL(browserHandle, "https://example.com", &loadFrameProbe, testNativeCallback), MiumCEFResultError);
  CallbackProbe scriptProbe;
  scriptProbe.expectation = [self expectationWithDescription:@"script no frame"];
  XCTAssertEqual(miumNativeCEFEvaluateJavaScript(browserHandle, "window.test()", &scriptProbe, testNativeCallback), MiumCEFResultError);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertTrue(loadFrameProbe.message.find("load_url unavailable") != std::string::npos);
  XCTAssertTrue(scriptProbe.message.find("execute_java_script unavailable") != std::string::npos);

  FakeBrowserHarness browserWithoutSend;
  browserWithoutSend.frame->frame.send_process_message = nullptr;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, browserWithoutSend.browserRef(), nullptr));
  CallbackProbe sendFailureProbe;
  sendFailureProbe.expectation = [self expectationWithDescription:@"send renderer unavailable"];
  XCTAssertEqual(miumNativeCEFSendMessage(browserHandle, "bridge", "{}", &sendFailureProbe, testNativeCallback), MiumCEFResultError);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertTrue(sendFailureProbe.message.find("message delivery unavailable") != std::string::npos);

  api.utf8ToUTF16 = failingUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createProcessMessage = fakeCreateProcessMessage;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);
  CallbackProbe conversionProbe;
  conversionProbe.expectation = [self expectationWithDescription:@"send conversion failure"];
  XCTAssertEqual(miumNativeCEFSendMessage(browserHandle, "bridge", "{}", &conversionProbe, testNativeCallback), MiumCEFResultError);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertTrue(conversionProbe.message.find("convert UTF8 to UTF16") != std::string::npos);

  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);
  FakeCreateBrowserFactory snapshotFactory;
  gCreateBrowserFactory = &snapshotFactory;
  const MiumCEFBrowserHandle snapshotBrowserHandle = [self createBrowserForRuntime:runtimeHandle];

  MiumCEFHostViewHandle hostViewHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(snapshotBrowserHandle, &hostViewHandle), MiumCEFResultOK);
  CallbackProbe hostUnavailableProbe;
  hostUnavailableProbe.expectation = [self expectationWithDescription:@"snapshot host unavailable"];
  XCTAssertEqual(miumNativeCEFRequestSnapshot(snapshotBrowserHandle, "/tmp/missing.png", nullptr, &hostUnavailableProbe, testNativeCallback), MiumCEFResultError);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertTrue(hostUnavailableProbe.message.find("host view unavailable") != std::string::npos);

  NSWindow* snapshotFailureWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 64, 48)
                                                                 styleMask:NSWindowStyleMaskBorderless
                                                                   backing:NSBackingStoreBuffered
                                                                     defer:NO];
  TestSnapshotView* attachableView = [[TestSnapshotView alloc] initWithFrame:NSMakeRect(0, 0, 64, 48)];
  snapshotFailureWindow.contentView = attachableView;
  [snapshotFailureWindow orderFrontRegardless];
  [snapshotFailureWindow displayIfNeeded];
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(hostViewHandle, (__bridge void*)attachableView));
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(snapshotBrowserHandle, hostViewHandle), MiumCEFResultOK);
  [attachableView setFrameSize:NSMakeSize(0, 0)];
  NSString* zeroSizedOutput = [[self temporaryDirectory] stringByAppendingPathComponent:@"zero.png"];
  CallbackProbe zeroSizedProbe;
  zeroSizedProbe.expectation = [self expectationWithDescription:@"snapshot zero-sized"];
  XCTAssertEqual(miumNativeCEFRequestSnapshot(snapshotBrowserHandle, zeroSizedOutput.UTF8String, nullptr, &zeroSizedProbe, testNativeCallback), MiumCEFResultError);

  [attachableView setFrameSize:NSMakeSize(40, 30)];
  NSString* clipOutput = [[self temporaryDirectory] stringByAppendingPathComponent:@"clip.png"];
  CallbackProbe clipProbe;
  clipProbe.expectation = [self expectationWithDescription:@"snapshot clip invalid"];
  XCTAssertEqual(miumNativeCEFRequestSnapshot(snapshotBrowserHandle, clipOutput.UTF8String, "{\"clip\":{\"x\":500,\"y\":500,\"width\":10,\"height\":10}}", &clipProbe, testNativeCallback), MiumCEFResultError);

  NSString* directoryFailureParent = [[self temporaryDirectory] stringByAppendingPathComponent:@"file-parent"];
  [self writeText:@"block" toPath:directoryFailureParent];
  NSString* directoryFailureOutput = [directoryFailureParent stringByAppendingPathComponent:@"child.png"];
  CallbackProbe directoryFailureProbe;
  directoryFailureProbe.expectation = [self expectationWithDescription:@"snapshot directory failure"];
  XCTAssertEqual(miumNativeCEFRequestSnapshot(snapshotBrowserHandle, directoryFailureOutput.UTF8String, nullptr, &directoryFailureProbe, testNativeCallback), MiumCEFResultError);

  NSString* writeFailureOutput = [self temporaryDirectory];
  CallbackProbe writeFailureProbe;
  writeFailureProbe.expectation = [self expectationWithDescription:@"snapshot write failure"];
  XCTAssertEqual(miumNativeCEFRequestSnapshot(snapshotBrowserHandle, writeFailureOutput.UTF8String, nullptr, &writeFailureProbe, testNativeCallback), MiumCEFResultError);

  char invalidPath[] = { '/', 't', 'm', 'p', '/', static_cast<char>(0xFF), 0 };
  CallbackProbe invalidPathProbe;
  invalidPathProbe.expectation = [self expectationWithDescription:@"snapshot invalid path utf8"];
  XCTAssertEqual(miumNativeCEFRequestSnapshot(snapshotBrowserHandle, invalidPath, nullptr, &invalidPathProbe, testNativeCallback), MiumCEFResultError);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertTrue(zeroSizedProbe.message.find("no visible size") != std::string::npos);
  XCTAssertTrue(clipProbe.message.find("outside the browser host view bounds") != std::string::npos);
  XCTAssertFalse(directoryFailureProbe.message.empty());
  XCTAssertTrue(writeFailureProbe.message.find("write browser snapshot") != std::string::npos);
  XCTAssertTrue(invalidPathProbe.message.find("Output path is not UTF8") != std::string::npos);
  [snapshotFailureWindow orderOut:nil];
  FakeCreateBrowserFactory jpegFactory;
  gCreateBrowserFactory = &jpegFactory;

  const MiumCEFBrowserHandle jpegBrowserHandle = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle jpegHostViewHandle = nullptr;
  NSWindow* jpegWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 64, 48)
                                                     styleMask:NSWindowStyleMaskBorderless
                                                       backing:NSBackingStoreBuffered
                                                         defer:NO];
  TestSnapshotView* jpegView = [[TestSnapshotView alloc] initWithFrame:NSMakeRect(0, 0, 64, 48)];
  jpegView.wantsLayer = YES;
  jpegWindow.contentView = jpegView;
  [jpegWindow orderFrontRegardless];
  [jpegWindow displayIfNeeded];
  XCTAssertEqual(
    miumNativeCEFCreateBrowserHostViewForNSView(jpegBrowserHandle, (__bridge void*)jpegView, &jpegHostViewHandle),
    MiumCEFResultOK
  );
  NSString* jpegOutput = [[self temporaryDirectory] stringByAppendingPathComponent:@"snapshot.jpg"];
  CallbackProbe jpegProbe;
  jpegProbe.expectation = [self expectationWithDescription:@"snapshot jpeg"];
  XCTAssertEqual(
    miumNativeCEFRequestSnapshot(jpegBrowserHandle, jpegOutput.UTF8String, "{\"quality\":0.25}", &jpegProbe, testNativeCallback),
    MiumCEFResultOK
  );
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(jpegProbe.code, MiumCEFResultOK, @"%s", jpegProbe.message.c_str());
  [jpegWindow orderOut:nil];
}

- (void)testSnapshotCoversDisplayCacheAndEncodingFailures {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);
  FakeCreateBrowserFactory factory;
  gCreateBrowserFactory = &factory;

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle hostViewHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &hostViewHandle), MiumCEFResultOK);

  TestSnapshotView* displayCacheView = [[TestSnapshotView alloc] initWithFrame:NSMakeRect(0, 0, 60, 40)];
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(hostViewHandle, (__bridge void*)displayCacheView));
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(browserHandle, hostViewHandle), MiumCEFResultOK);
  NSString* displayCacheOutput = [[self temporaryDirectory] stringByAppendingPathComponent:@"fallback.png"];
  CallbackProbe displayCacheProbe;
  displayCacheProbe.expectation = [self expectationWithDescription:@"snapshot fallback"];
  XCTAssertEqual(miumNativeCEFRequestSnapshot(browserHandle, displayCacheOutput.UTF8String, nullptr, &displayCacheProbe, testNativeCallback), MiumCEFResultOK);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(displayCacheProbe.code, MiumCEFResultOK);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:displayCacheOutput]);

  TestSnapshotView* noBitmapView = [[TestSnapshotView alloc] initWithFrame:NSMakeRect(0, 0, 60, 40)];
  noBitmapView.returnsNilBitmapRep = YES;
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(hostViewHandle, (__bridge void*)noBitmapView));
  NSString* noBitmapOutput = [[self temporaryDirectory] stringByAppendingPathComponent:@"nobitmap.png"];
  CallbackProbe noBitmapProbe;
  noBitmapProbe.expectation = [self expectationWithDescription:@"snapshot no bitmap"];
  XCTAssertEqual(miumNativeCEFRequestSnapshot(browserHandle, noBitmapOutput.UTF8String, nullptr, &noBitmapProbe, testNativeCallback), MiumCEFResultError);

  TestSnapshotView* failingBitmapView = [[TestSnapshotView alloc] initWithFrame:NSMakeRect(0, 0, 60, 40)];
  failingBitmapView.usesFailingBitmapRep = YES;
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(hostViewHandle, (__bridge void*)failingBitmapView));
  NSString* failingBitmapOutput = [[self temporaryDirectory] stringByAppendingPathComponent:@"encode.png"];
  CallbackProbe failingBitmapProbe;
  failingBitmapProbe.expectation = [self expectationWithDescription:@"snapshot encode failure"];
  XCTAssertEqual(miumNativeCEFRequestSnapshot(browserHandle, failingBitmapOutput.UTF8String, nullptr, &failingBitmapProbe, testNativeCallback), MiumCEFResultError);

  TestSnapshotView* nilPDFView = [[TestSnapshotView alloc] initWithFrame:NSMakeRect(0, 0, 60, 40)];
  nilPDFView.returnsNilPDFData = YES;
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(hostViewHandle, (__bridge void*)nilPDFView));
  NSString* nilPDFOutput = [[self temporaryDirectory] stringByAppendingPathComponent:@"nil.pdf"];
  CallbackProbe nilPDFProbe;
  nilPDFProbe.expectation = [self expectationWithDescription:@"snapshot nil pdf"];
  XCTAssertEqual(miumNativeCEFRequestSnapshot(browserHandle, nilPDFOutput.UTF8String, "{\"format\":\"pdf\"}", &nilPDFProbe, testNativeCallback), MiumCEFResultError);

  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertTrue(noBitmapProbe.message.find("allocate snapshot buffer") != std::string::npos);
  XCTAssertTrue(failingBitmapProbe.message.find("encode browser snapshot") != std::string::npos);
  XCTAssertTrue(nilPDFProbe.message.find("capture PDF snapshot") != std::string::npos);
}

- (void)testSnapshotTestingWrappersCoverBoundsAndWindowPaths {
  TestSnapshotView* zeroSizedView = [[TestSnapshotView alloc] initWithFrame:NSMakeRect(0, 0, 0, 0)];
  MiumCEFBridgeTestSnapshotOptions options{};
  std::string error;
  XCTAssertFalse(miumNativeCEFTestSnapshotBoundsForHostView((__bridge void*)zeroSizedView, &options, &error));
  XCTAssertEqual(error, "Browser host view has no visible size");

  TestSnapshotView* boundedView = [[TestSnapshotView alloc] initWithFrame:NSMakeRect(0, 0, 40, 30)];
  options.hasClipRect = true;
  options.clipX = 200.0;
  options.clipY = 200.0;
  options.clipWidth = 10.0;
  options.clipHeight = 10.0;
  error.clear();
  XCTAssertFalse(miumNativeCEFTestSnapshotBoundsForHostView((__bridge void*)boundedView, &options, &error));
  XCTAssertEqual(error, "Snapshot clip is outside the browser host view bounds");

  NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 80, 60)
                                                 styleMask:NSWindowStyleMaskBorderless
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
  TestSnapshotView* windowView = [[TestSnapshotView alloc] initWithFrame:NSMakeRect(0, 0, 80, 60)];
  window.contentView = windowView;
  [window orderFrontRegardless];
  [window displayIfNeeded];

  XCTAssertFalse(
    miumNativeCEFTestSnapshotBitmapRepForHostViewFromWindow(
      (__bridge void*)windowView,
      0.0,
      0.0,
      0.0,
      10.0
    )
  );

  miumNativeCEFTestSetWindowSnapshotMode(MiumCEFBridgeTestWindowSnapshotMode::forceNullImage);
  XCTAssertFalse(
    miumNativeCEFTestSnapshotBitmapRepForHostViewFromWindow(
      (__bridge void*)windowView,
      0.0,
      0.0,
      20.0,
      10.0
    )
  );

  miumNativeCEFTestSetWindowSnapshotMode(MiumCEFBridgeTestWindowSnapshotMode::forceOnePixelImage);
  XCTAssertTrue(
    miumNativeCEFTestSnapshotBitmapRepForHostViewFromWindow(
      (__bridge void*)windowView,
      0.0,
      0.0,
      20.0,
      10.0
    )
  );
  miumNativeCEFTestSetWindowSnapshotMode(MiumCEFBridgeTestWindowSnapshotMode::live);
  [window orderOut:nil];
}

@end
