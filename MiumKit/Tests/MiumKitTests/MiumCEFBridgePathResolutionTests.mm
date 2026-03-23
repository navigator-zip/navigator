#import "MiumCEFBridgeNativeTestSupport.h"

using namespace MiumCEFBridgeNativeTestSupport;

@interface MiumCEFBridgePathResolutionTests : MiumCEFBridgeNativeTestCase
@end

static NSView* embeddedParentViewForHostView(NSView* hostView) {
  if (hostView == nil) {
    return nil;
  }

  Class containerClass = NSClassFromString(@"MiumBrowserContainerView");
  for (NSView* subview in hostView.subviews) {
    if (containerClass != Nil && [subview isKindOfClass:containerClass]) {
      return subview;
    }
  }
  return hostView;
}

@implementation MiumCEFBridgePathResolutionTests

- (void)testPathLayoutAndHelperWrappers {
  NSString* runtimeRoot = [self temporaryDirectory];
  NSString* resourcesDir = [runtimeRoot stringByAppendingPathComponent:@"Contents/Resources"];
  NSString* localesPak = [resourcesDir stringByAppendingPathComponent:@"locales/en.lproj/locale.pak"];
  NSString* metadataPath = resourcesDir;
  NSString* customResources = [runtimeRoot stringByAppendingPathComponent:@"Contents/Custom Resources"];
  NSString* customLocalesRoot = [runtimeRoot stringByAppendingPathComponent:@"Contents/CustomLocales"];
  NSString* customLocalesPak = [customLocalesRoot stringByAppendingPathComponent:@"locales/fr.lproj/locale.pak"];
  NSString* customHelpers = [runtimeRoot stringByAppendingPathComponent:@"Contents/Custom Helpers"];
  NSString* testFile = [runtimeRoot stringByAppendingPathComponent:@"notes.txt"];
  [self createDirectoryAtPath:[localesPak stringByDeletingLastPathComponent]];
  [self createDirectoryAtPath:[customLocalesPak stringByDeletingLastPathComponent]];
  [self createDirectoryAtPath:customResources];
  [self createDirectoryAtPath:customHelpers];
  [self writeText:@"pak" toPath:localesPak];
  [self writeText:@"pak" toPath:customLocalesPak];
  [self writeText:@"note" toPath:testFile];

  XCTAssertEqual(miumNativeCEFTestNormalizePath(nullptr), "");
  XCTAssertEqual(miumNativeCEFTestTrimWhitespaceInString(" \n value \t "), "value");
  XCTAssertEqual(
    miumNativeCEFTestMakePathFromRootAndRelative(runtimeRoot.UTF8String, "Contents/Resources"),
    miumNativeCEFTestNormalizePath(resourcesDir.UTF8String)
  );
  XCTAssertEqual(miumNativeCEFTestMakePathFromRootAndRelative(nullptr, "Contents/Resources"), "");
  XCTAssertTrue(miumNativeCEFTestDirectoryContainsCefLocaleResources(resourcesDir.UTF8String));
  XCTAssertFalse(miumNativeCEFTestDirectoryContainsCefLocaleResources(runtimeRoot.UTF8String));
  XCTAssertEqual(
    miumNativeCEFTestNormalizeChromiumLocalesPathCandidate(resourcesDir.UTF8String),
    miumNativeCEFTestNormalizePath([[resourcesDir stringByAppendingPathComponent:@"locales"] UTF8String])
  );
  XCTAssertEqual(
    miumNativeCEFTestResolveChromiumLocalesPath(runtimeRoot.UTF8String),
    miumNativeCEFTestNormalizePath([[resourcesDir stringByAppendingPathComponent:@"locales"] UTF8String])
  );

  const auto defaultLayout = miumNativeCEFTestResolveRuntimeLayoutConfig(runtimeRoot.UTF8String, metadataPath.UTF8String);
  XCTAssertEqual(defaultLayout.resourcesDir, miumNativeCEFTestNormalizePath(resourcesDir.UTF8String));
  XCTAssertEqual(
    defaultLayout.localesDir,
    miumNativeCEFTestNormalizePath([[resourcesDir stringByAppendingPathComponent:@"locales"] UTF8String])
  );
  XCTAssertEqual(
    defaultLayout.helpersDir,
    miumNativeCEFTestNormalizePath([[runtimeRoot stringByAppendingPathComponent:@"Contents/Frameworks"] UTF8String])
  );

  NSString* runtimeLayoutJSON = @"{\"expectedPaths\":{\"resourcesRelativePath\":\" Contents/Custom Resources \",\"localesRelativePath\":\" Contents/CustomLocales \",\"helpersDirRelativePath\":\" Contents/Custom Helpers \"}}";
  [self writeText:runtimeLayoutJSON toPath:[metadataPath stringByAppendingPathComponent:@"runtime_layout.json"]];

  const auto overriddenLayout = miumNativeCEFTestResolveRuntimeLayoutConfig(runtimeRoot.UTF8String, metadataPath.UTF8String);
  XCTAssertEqual(overriddenLayout.resourcesDir, miumNativeCEFTestNormalizePath(customResources.UTF8String));
  XCTAssertEqual(
    overriddenLayout.localesDir,
    miumNativeCEFTestNormalizePath([[customLocalesRoot stringByAppendingPathComponent:@"locales"] UTF8String])
  );
  XCTAssertEqual(overriddenLayout.helpersDir, miumNativeCEFTestNormalizePath(customHelpers.UTF8String));

  const auto candidatePaths = miumNativeCEFTestCandidatePaths(runtimeRoot.UTF8String, metadataPath.UTF8String);
  XCTAssertFalse(candidatePaths.empty());
  XCTAssertTrue(std::find(candidatePaths.begin(), candidatePaths.end(),
    miumNativeCEFTestNormalizePath([[runtimeRoot stringByAppendingPathComponent:@"Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework"] UTF8String])) != candidatePaths.end());
  XCTAssertFalse(miumNativeCEFTestHostExecutableBasename().empty());
  XCTAssertTrue(miumNativeCEFTestPathExistsAndIsDirectory(resourcesDir.UTF8String, true));
  XCTAssertTrue(miumNativeCEFTestPathExistsAndIsDirectory(testFile.UTF8String, false));
  XCTAssertFalse(miumNativeCEFTestPathExistsAndIsDirectory(testFile.UTF8String, true));
  XCTAssertTrue(miumNativeCEFTestPathExistsAsFile(testFile.UTF8String));
  XCTAssertFalse(miumNativeCEFTestPathExistsAsFile(resourcesDir.UTF8String));

  NSString* helperApp = [self createHelperAppInDirectory:customHelpers
                                                    name:@"Chromium Helper"
                                          executableName:@"Custom Helper"
                                     infoPlistExecutable:@"Custom Helper"];
  NSString* helperExecutable = [[[helperApp stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:@"Custom Helper"];
  XCTAssertEqual(miumNativeCEFTestResolveHelperBundlePath(customHelpers.UTF8String), miumNativeCEFTestNormalizePath(helperExecutable.UTF8String));

  NSString* fallbackHelpers = [self temporaryDirectory];
  NSString* fallbackApp = [self createHelperAppInDirectory:fallbackHelpers
                                                      name:@"Mium Helper"
                                            executableName:@"Navigator Helper"
                                       infoPlistExecutable:nil];
  NSString* fallbackExecutable = [[[fallbackApp stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:@"Navigator Helper"];
  XCTAssertEqual(miumNativeCEFTestResolveHelperBundlePath(fallbackHelpers.UTF8String), miumNativeCEFTestNormalizePath(fallbackExecutable.UTF8String));

  ScopedEnvironmentVariable subprocessOverride("MIUM_CEF_BROWSER_SUBPROCESS_PATH");
  subprocessOverride.set(fallbackExecutable.UTF8String);
  XCTAssertEqual(
    miumNativeCEFTestResolveHelperSubprocessPath(runtimeRoot.UTF8String, metadataPath.UTF8String),
    miumNativeCEFTestNormalizePath(fallbackExecutable.UTF8String)
  );
  subprocessOverride.set(nullptr);
  XCTAssertEqual(
    miumNativeCEFTestResolveHelperSubprocessPath(runtimeRoot.UTF8String, metadataPath.UTF8String),
    miumNativeCEFTestNormalizePath(helperExecutable.UTF8String)
  );

  XCTAssertTrue(miumNativeCEFTestDescribeFrameworkCandidateFailure({}).find("No candidate paths were discovered") != std::string::npos);
  std::vector<std::string> manyCandidates(30, "/tmp/candidate");
  XCTAssertTrue(miumNativeCEFTestDescribeFrameworkCandidateFailure(manyCandidates).find("and 6 more") != std::string::npos);
}

- (void)testPathLayoutAndHelperWrappersCoverAdditionalBranches {
  NSString* runtimeRoot = [self temporaryDirectory];
  NSString* metadataPath = [runtimeRoot stringByAppendingPathComponent:@"Contents/Resources"];
  NSString* helpersDir = [runtimeRoot stringByAppendingPathComponent:@"Contents/Frameworks"];
  [self createDirectoryAtPath:metadataPath];
  [self createDirectoryAtPath:[runtimeRoot stringByAppendingPathComponent:@"Contents/Resources/locales/en.lproj"]];
  [self writeText:@"pak"
           toPath:[[runtimeRoot stringByAppendingPathComponent:@"Contents/Resources/locales/en.lproj"] stringByAppendingPathComponent:@"locale.pak"]];

  char invalidUTF8[] = { static_cast<char>(0xFF), 0 };
  XCTAssertEqual(miumNativeCEFTestNormalizePath(invalidUTF8), "");
  XCTAssertEqual(miumNativeCEFTestTrimWhitespaceInString(nullptr), "");
  XCTAssertEqual(miumNativeCEFTestMakePathFromRootAndRelative("", "Contents/Resources"), "");
  XCTAssertEqual(miumNativeCEFTestMakePathFromRootAndRelative(runtimeRoot.UTF8String, invalidUTF8), "");
  const auto defaultCandidates = miumNativeCEFTestCandidatePaths(nullptr, nullptr);
  const auto invalidRootCandidates = miumNativeCEFTestCandidatePaths(invalidUTF8, invalidUTF8);
  XCTAssertEqual(invalidRootCandidates, defaultCandidates);
  XCTAssertFalse(defaultCandidates.empty());
  XCTAssertTrue(
    std::find_if(
      defaultCandidates.begin(),
      defaultCandidates.end(),
      [](const std::string& candidate) {
        return candidate.find("Chromium Embedded Framework.framework") != std::string::npos;
      }
    ) != defaultCandidates.end()
  );
  XCTAssertFalse(miumNativeCEFTestDirectoryContainsCefLocaleResources(nullptr));
  XCTAssertFalse(miumNativeCEFTestDirectoryContainsCefLocaleResources(invalidUTF8));
  NSString* unreadableLocalesDirectory = [self temporaryDirectory];
  [self createDirectoryAtPath:[unreadableLocalesDirectory stringByAppendingPathComponent:@"empty"]];
  XCTAssertEqual(chmod(unreadableLocalesDirectory.fileSystemRepresentation, 0000), 0);
  XCTAssertFalse(miumNativeCEFTestDirectoryContainsCefLocaleResources(unreadableLocalesDirectory.UTF8String));
  XCTAssertEqual(chmod(unreadableLocalesDirectory.fileSystemRepresentation, 0700), 0);

  NSString* missingLocalePakDirectory = [self temporaryDirectory];
  [self createDirectoryAtPath:[missingLocalePakDirectory stringByAppendingPathComponent:@"fr.lproj"]];
  XCTAssertFalse(miumNativeCEFTestDirectoryContainsCefLocaleResources(missingLocalePakDirectory.UTF8String));

  NSString* loosePakDirectory = [self temporaryDirectory];
  [self writeText:@"pak" toPath:[loosePakDirectory stringByAppendingPathComponent:@"chrome_100_percent.pak"]];
  XCTAssertTrue(miumNativeCEFTestDirectoryContainsCefLocaleResources(loosePakDirectory.UTF8String));
  XCTAssertEqual(miumNativeCEFTestNormalizeChromiumLocalesPathCandidate(nullptr), "");
  XCTAssertEqual(miumNativeCEFTestNormalizeChromiumLocalesPathCandidate(invalidUTF8), "");
  XCTAssertEqual(miumNativeCEFTestResolveChromiumLocalesPath(nullptr), "");
  XCTAssertEqual(miumNativeCEFTestResolveHelperSubprocessPath(nullptr, nullptr), "");
  const auto emptyLayout = miumNativeCEFTestResolveRuntimeLayoutConfig(nullptr, nullptr);
  XCTAssertTrue(emptyLayout.resourcesDir.empty());
  XCTAssertTrue(emptyLayout.localesDir.empty());
  XCTAssertTrue(emptyLayout.helpersDir.empty());
  const auto emptyMetadataLayout = miumNativeCEFTestResolveRuntimeLayoutConfig(runtimeRoot.UTF8String, "");
  XCTAssertFalse(emptyMetadataLayout.resourcesDir.empty());
  XCTAssertFalse(emptyMetadataLayout.helpersDir.empty());
  XCTAssertFalse(miumNativeCEFTestPathExistsAndIsDirectory(nullptr, true));
  XCTAssertFalse(miumNativeCEFTestPathExistsAsFile(nullptr));

  [self writeText:@"{invalid" toPath:[metadataPath stringByAppendingPathComponent:@"runtime_layout.json"]];
  const auto invalidJSONLayout = miumNativeCEFTestResolveRuntimeLayoutConfig(runtimeRoot.UTF8String, metadataPath.UTF8String);
  XCTAssertFalse(invalidJSONLayout.resourcesDir.empty());

  [self writeText:@"[]" toPath:[metadataPath stringByAppendingPathComponent:@"runtime_layout.json"]];
  const auto arrayLayout = miumNativeCEFTestResolveRuntimeLayoutConfig(runtimeRoot.UTF8String, metadataPath.UTF8String);
  XCTAssertFalse(arrayLayout.helpersDir.empty());

  [self writeText:@"{\"expectedPaths\":\"invalid\"}" toPath:[metadataPath stringByAppendingPathComponent:@"runtime_layout.json"]];
  const auto invalidExpectedPathsLayout = miumNativeCEFTestResolveRuntimeLayoutConfig(runtimeRoot.UTF8String, metadataPath.UTF8String);
  XCTAssertFalse(invalidExpectedPathsLayout.localesDir.empty());

  [self writeText:@"{\"expectedPaths\":{\"resourcesRelativePath\":\"   \",\"localesRelativePath\":\"   \",\"helpersDirRelativePath\":\"   \"}}"
           toPath:[metadataPath stringByAppendingPathComponent:@"runtime_layout.json"]];
  const auto whitespaceLayout = miumNativeCEFTestResolveRuntimeLayoutConfig(runtimeRoot.UTF8String, metadataPath.UTF8String);
  XCTAssertFalse(whitespaceLayout.resourcesDir.empty());

  NSString* emptyHelpers = [self temporaryDirectory];
  XCTAssertEqual(miumNativeCEFTestResolveHelperBundlePath(nullptr), "");
  XCTAssertEqual(miumNativeCEFTestResolveHelperBundlePath(emptyHelpers.UTF8String), "");
  NSString* brokenHelpers = [self temporaryDirectory];
  [self createDirectoryAtPath:[brokenHelpers stringByAppendingPathComponent:@"Navigator Helper.app/Contents/MacOS"]];
  XCTAssertEqual(miumNativeCEFTestResolveHelperBundlePath(brokenHelpers.UTF8String), "");

  const std::string hostBaseString = miumNativeCEFTestHostExecutableBasename();
  NSString* hostBase = stringFromCString(hostBaseString.c_str());
  XCTAssertTrue(hostBase.length > 0);
  NSString* hostFallbackHelpers = [self temporaryDirectory];
  [self createHelperAppInDirectory:hostFallbackHelpers
                              name:@"Navigator Helper"
                    executableName:hostBase
               infoPlistExecutable:@"Missing Helper"];
  NSString* hostFallbackExecutable = [[[[hostFallbackHelpers stringByAppendingPathComponent:@"Navigator Helper.app"] stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:hostBase];
  XCTAssertEqual(
    miumNativeCEFTestResolveHelperBundlePath(hostFallbackHelpers.UTF8String),
    miumNativeCEFTestNormalizePath(hostFallbackExecutable.UTF8String)
  );
}

- (void)testEnvironmentSingletonAndUserDataHelpers {
  ScopedEnvironmentVariable sandboxOverride("MIUM_DISABLE_CEF_SANDBOX");
  ScopedEnvironmentVariable legacySandboxOverride("MIUM_CEF_NO_SANDBOX");
  ScopedEnvironmentVariable rootCacheOverride("MIUM_CEF_ROOT_CACHE_PATH");
  sandboxOverride.set(nullptr);
  legacySandboxOverride.set(nullptr);
  rootCacheOverride.set(nullptr);

  XCTAssertFalse(miumNativeCEFTestParseBooleanEnvironmentFlag(nullptr));
  XCTAssertFalse(miumNativeCEFTestParseBooleanEnvironmentFlag("MIUM_DISABLE_CEF_SANDBOX"));
  XCTAssertFalse(miumNativeCEFTestHasEnvironmentValue(nullptr));
  XCTAssertFalse(miumNativeCEFTestHasEnvironmentValue("MIUM_DISABLE_CEF_SANDBOX"));
  XCTAssertTrue(miumNativeCEFTestShouldDisableCEFChildProcessSandbox());

  sandboxOverride.set("");
  XCTAssertFalse(miumNativeCEFTestParseBooleanEnvironmentFlag("MIUM_DISABLE_CEF_SANDBOX"));
  XCTAssertFalse(miumNativeCEFTestShouldDisableCEFChildProcessSandbox());

  sandboxOverride.set("0");
  XCTAssertFalse(miumNativeCEFTestParseBooleanEnvironmentFlag("MIUM_DISABLE_CEF_SANDBOX"));
  XCTAssertTrue(miumNativeCEFTestHasEnvironmentValue("MIUM_DISABLE_CEF_SANDBOX"));
  XCTAssertFalse(miumNativeCEFTestShouldDisableCEFChildProcessSandbox());

  sandboxOverride.set("YES");
  XCTAssertTrue(miumNativeCEFTestParseBooleanEnvironmentFlag("MIUM_DISABLE_CEF_SANDBOX"));
  XCTAssertTrue(miumNativeCEFTestShouldDisableCEFChildProcessSandbox());

  legacySandboxOverride.set("enabled");
  XCTAssertTrue(miumNativeCEFTestParseBooleanEnvironmentFlag("MIUM_CEF_NO_SANDBOX"));

  XCTAssertEqual(miumNativeCEFTestSingletonOwnerPIDFromLockDestination(nullptr), 0);
  XCTAssertEqual(miumNativeCEFTestSingletonOwnerPIDFromLockDestination("SingletonLock"), 0);
  XCTAssertEqual(miumNativeCEFTestSingletonOwnerPIDFromLockDestination("SingletonLock-"), 0);
  XCTAssertEqual(miumNativeCEFTestSingletonOwnerPIDFromLockDestination("SingletonLock-not-a-pid"), 0);
  std::ostringstream pidString;
  pidString << "SingletonLock-" << getpid();
  XCTAssertEqual(miumNativeCEFTestSingletonOwnerPIDFromLockDestination(pidString.str().c_str()), getpid());
  XCTAssertFalse(miumNativeCEFTestIsLiveNavigatorProcess(0));
  XCTAssertFalse(miumNativeCEFTestIsLiveNavigatorProcess(-1));
  XCTAssertTrue(miumNativeCEFTestIsLiveNavigatorProcess(getpid()));

  miumNativeCEFTestRemoveStaleSingletonArtifacts(nullptr);
  NSString* staleDirectory = [self temporaryDirectory];
  [self writeText:@"cookie" toPath:[staleDirectory stringByAppendingPathComponent:@"SingletonCookie"]];
  [self writeText:@"socket" toPath:[staleDirectory stringByAppendingPathComponent:@"SingletonSocket"]];
  XCTAssertTrue([[NSFileManager defaultManager] createSymbolicLinkAtPath:[staleDirectory stringByAppendingPathComponent:@"SingletonLock"]
                                                     withDestinationPath:@"SingletonLock-999999"
                                                                   error:nil]);
  miumNativeCEFTestRemoveStaleSingletonArtifacts(staleDirectory.UTF8String);
  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[staleDirectory stringByAppendingPathComponent:@"SingletonCookie"]]);
  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[staleDirectory stringByAppendingPathComponent:@"SingletonSocket"]]);
  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[staleDirectory stringByAppendingPathComponent:@"SingletonLock"]]);

  NSString* liveDirectory = [self temporaryDirectory];
  [self writeText:@"cookie" toPath:[liveDirectory stringByAppendingPathComponent:@"SingletonCookie"]];
  NSString* liveLockDestination = [NSString stringWithFormat:@"SingletonLock-%d", getpid()];
  XCTAssertTrue([[NSFileManager defaultManager] createSymbolicLinkAtPath:[liveDirectory stringByAppendingPathComponent:@"SingletonLock"]
                                                     withDestinationPath:liveLockDestination
                                                                   error:nil]);
  miumNativeCEFTestRemoveStaleSingletonArtifacts(liveDirectory.UTF8String);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[liveDirectory stringByAppendingPathComponent:@"SingletonCookie"]]);

  NSString* overrideDirectory = [self temporaryDirectory];
  [self writeText:@"cookie" toPath:[overrideDirectory stringByAppendingPathComponent:@"SingletonCookie"]];
  [self writeText:@"socket" toPath:[overrideDirectory stringByAppendingPathComponent:@"SingletonSocket"]];
  XCTAssertTrue([[NSFileManager defaultManager] createSymbolicLinkAtPath:[overrideDirectory stringByAppendingPathComponent:@"SingletonLock"]
                                                     withDestinationPath:@"SingletonLock-999999"
                                                                   error:nil]);
  rootCacheOverride.set(overrideDirectory.UTF8String);
  XCTAssertEqual(miumNativeCEFTestResolveCEFUserDataDirectory(), miumNativeCEFTestNormalizePath(overrideDirectory.UTF8String));
  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[overrideDirectory stringByAppendingPathComponent:@"SingletonCookie"]]);

  NSString* removalFailureDirectory = [self temporaryDirectory];
  NSString* removalFailureCookie = [removalFailureDirectory stringByAppendingPathComponent:@"SingletonCookie"];
  [self writeText:@"cookie" toPath:removalFailureCookie];
  XCTAssertEqual(chmod(removalFailureDirectory.fileSystemRepresentation, 0500), 0);
  miumNativeCEFTestRemoveStaleSingletonArtifacts(removalFailureDirectory.UTF8String);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:removalFailureCookie]);
  XCTAssertEqual(chmod(removalFailureDirectory.fileSystemRepresentation, 0700), 0);

  NSString* blockingFile = [[self temporaryDirectory] stringByAppendingPathComponent:@"cache.file"];
  [self writeText:@"block" toPath:blockingFile];
  rootCacheOverride.set(blockingFile.UTF8String);
  const std::string fallbackCacheDirectory = miumNativeCEFTestResolveCEFUserDataDirectory();
  XCTAssertFalse(fallbackCacheDirectory.empty());
  XCTAssertNotEqual(fallbackCacheDirectory, miumNativeCEFTestNormalizePath(blockingFile.UTF8String));
}

- (void)testResizeEmbeddedBrowserHostViewWrapperIgnoresUnmanagedSubviews {
  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 50)];
  hostView.wantsLayer = YES;
  hostView.layer.contentsScale = 2.0;
  NSView* child = [[NSView alloc] initWithFrame:NSMakeRect(10, 10, 10, 10)];
  [hostView addSubview:child];

  miumNativeCEFTestResizeEmbeddedBrowserHostView(nullptr, 100, 100);
  miumNativeCEFTestResizeEmbeddedBrowserHostView((__bridge void*)hostView, 0, 100);
  XCTAssertEqualWithAccuracy(child.frame.size.width, 10.0, 0.001);

  miumNativeCEFTestResizeEmbeddedBrowserHostView((__bridge void*)hostView, 320, 180);

  XCTAssertEqualWithAccuracy(child.frame.origin.x, 10.0, 0.001);
  XCTAssertEqualWithAccuracy(child.frame.origin.y, 10.0, 0.001);
  XCTAssertEqualWithAccuracy(child.frame.size.width, 10.0, 0.001);
  XCTAssertEqualWithAccuracy(child.frame.size.height, 10.0, 0.001);
}

- (void)testTestingHelpersCoverNullCallbacksFastPathsAndInactiveLookups {
  miumNativeCEFTestRunOnCefExecutor(nullptr, nullptr);
  miumNativeCEFTestRunOnCefExecutorAsync(nullptr, nullptr);
  miumNativeCEFTestRunOnMainThread(nullptr, nullptr);
  miumNativeCEFTestRunOffMainThread(nullptr, nullptr);
  miumNativeCEFTestRunOnMessageQueue(nullptr, MiumCEFResultOK, "ignored", nullptr, 0);

  XCTAssertEqual(blockingFakeInitialize(nullptr, nullptr, nullptr, nullptr), 0);

  __block int offMainCounter = 0;
  [self runOnBackgroundQueueAndWait:^{
    miumNativeCEFTestRunOffMainThread(&offMainCounter, incrementIntegerCallback);
  }];
  XCTAssertEqual(offMainCounter, 1);

  __block int mainThreadCounter = 0;
  [self runOnBackgroundQueueAndWait:^{
    miumNativeCEFTestRunOnMainThread(&mainThreadCounter, incrementIntegerCallback);
  }];
  XCTAssertEqual(mainThreadCounter, 1);

  __block int nestedExecutorCounter = 0;
  miumNativeCEFTestRunOnCefExecutor(&nestedExecutorCounter, runNestedExecutorIncrement);
  XCTAssertEqual(nestedExecutorCounter, 1);

  __block int executorThenMainCounter = 0;
  miumNativeCEFTestRunOnCefExecutor(&executorThenMainCounter, runExecutorThenMainThreadIncrement);
  XCTAssertEqual(executorThenMainCounter, 1);

  __block int asyncExecutorCounter = 0;
  miumNativeCEFTestRunOnCefExecutorAsync(&asyncExecutorCounter, runNestedExecutorAsyncIncrement);
  XCTAssertEqual(asyncExecutorCounter, 0);
  [self waitUntil:^BOOL {
    return asyncExecutorCounter == 1;
  } description:@"async executor wrapper"];
  XCTAssertEqual(asyncExecutorCounter, 1);

  TestSnapshotView* hostView = [[TestSnapshotView alloc] initWithFrame:NSMakeRect(0, 0, 40, 30)];
  std::string error;
  XCTAssertTrue(miumNativeCEFTestSnapshotBoundsForHostView((__bridge void*)hostView, nullptr, &error));
  XCTAssertEqual(error, "");

  miumNativeCEFTestSetInitialized(false, 4);
  XCTAssertEqual(miumNativeCEFDoMessageLoopWork(), MiumCEFResultNotInitialized);

  const MiumCEFRuntimeHandle inactiveRuntime = miumNativeCEFTestInsertRuntime(nullptr, nullptr, false);
  XCTAssertNotEqual(inactiveRuntime, nullptr);
  XCTAssertEqual(miumNativeCEFTestHostViewHandleForBrowser(nullptr), nullptr);
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(nullptr), nullptr);
  XCTAssertEqual(miumNativeCEFTestGetBrowserHostViewId(nullptr), static_cast<uint64_t>(0));

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle hostViewHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &hostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFTestGetHostViewPointer(hostViewHandle), nullptr);
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(hostViewHandle, (__bridge void*)hostView));
  XCTAssertEqual(miumNativeCEFTestGetHostViewPointer(hostViewHandle), (__bridge void*)hostView);
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(hostViewHandle), nullptr);
  XCTAssertEqual(miumNativeCEFTestGetBrowserHostViewId(browserHandle), static_cast<uint64_t>(0));
  XCTAssertEqual(miumNativeCEFTestHostViewHandleForBrowser(browserHandle), nullptr);

  XCTAssertEqual(miumNativeCEFDestroyBrowserHostView(hostViewHandle), MiumCEFResultOK);
  XCTAssertFalse(miumNativeCEFTestSetHostViewPointer(hostViewHandle, (__bridge void*)hostView));
  XCTAssertEqual(miumNativeCEFTestGetHostViewPointer(hostViewHandle), nullptr);
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(hostViewHandle), nullptr);
}

- (void)testBrowserClientAndNativeBrowserOverridesCoverAdditionalCreationPaths {
  miumNativeCEFTestSetNextBrowserClientMissingDisplayHandler(true);
  cef_client_t* clientWithoutHandler = miumNativeCEFTestCreateBrowserClient();
  XCTAssertNotEqual(clientWithoutHandler, nullptr);
  XCTAssertEqual(clientWithoutHandler->get_display_handler(clientWithoutHandler), nullptr);
  XCTAssertEqual(clientWithoutHandler->base.release(&clientWithoutHandler->base), 1);

  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  XCTAssertFalse(miumNativeCEFTestEnsureNativeBrowser(browserHandle, nullptr));

  FakeCreateBrowserFactory factory;
  gCreateBrowserFactory = &factory;
  MiumCEFHostViewHandle hostViewHandle = nullptr;
  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 70)];
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &hostViewHandle), MiumCEFResultOK);
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(hostViewHandle, (__bridge void*)hostView));
  miumNativeCEFTestSetCreateBrowserClientReturnsNull(true);
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(browserHandle, hostViewHandle), MiumCEFResultError);
}

- (void)testBrowserMappingAndCloseTestingWrappersCoverInternalFallbacks {
  miumNativeCEFTestSetNextIds(0, 0, 0);
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  const MiumCEFBrowserHandle skippedLookupBrowser = [self createBrowserForRuntime:runtimeHandle];
  const MiumCEFBrowserHandle mappedLookupBrowser = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle hostViewHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &hostViewHandle), MiumCEFResultOK);
  (void)skippedLookupBrowser;

  FakeBrowserHarness mappedBrowser;
  mappedBrowser.browser->identifier = 9001;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(mappedLookupBrowser, mappedBrowser.browserRef(), nullptr));
  const uint64_t mappedBrowserId = miumNativeCEFTestBrowserIdFromNativeBrowser(mappedBrowser.browserRef());
  XCTAssertGreaterThan(mappedBrowserId, static_cast<uint64_t>(0));

  miumNativeCEFTestEraseNativeBrowserPointerMapping(mappedBrowser.browserRef());
  XCTAssertEqual(miumNativeCEFTestBrowserIdFromNativeBrowser(mappedBrowser.browserRef()), mappedBrowserId);
  miumNativeCEFTestEraseNativeBrowserIdentifierMapping(9001);
  XCTAssertEqual(miumNativeCEFTestBrowserIdFromNativeBrowser(mappedBrowser.browserRef()), mappedBrowserId);
  miumNativeCEFTestBindNativeBrowserMappings(browserHandle, mappedBrowser.browserRef(), mappedBrowser.browserRef());

  FakeBrowserHarness unknownBrowser;
  unknownBrowser.browser->browser.get_identifier = nullptr;
  XCTAssertEqual(miumNativeCEFTestBrowserIdFromNativeBrowser(unknownBrowser.browserRef()), static_cast<uint64_t>(0));

  cef_client_t* clientOnly = miumNativeCEFTestCreateBrowserClient();
  const MiumCEFBrowserHandle clientOnlyBrowser = [self createBrowserForRuntime:runtimeHandle];
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(clientOnlyBrowser, nullptr, clientOnly));
  uint64_t completedRuntimeId = 0;
  cef_browser_t* completedBrowser = reinterpret_cast<cef_browser_t*>(0x1);
  cef_client_t* completedClient = reinterpret_cast<cef_client_t*>(0x1);
  XCTAssertEqual(
    miumNativeCEFTestBeginClosingNativeBrowser(
      clientOnlyBrowser,
      false,
      false,
      &completedRuntimeId,
      &completedBrowser,
      &completedClient
    ),
    MiumCEFBridgeTestBrowserCloseDisposition::completedSynchronously
  );
  XCTAssertEqual(completedBrowser, nullptr);
  XCTAssertEqual(completedClient, reinterpret_cast<cef_client_t*>(0x1));

  const MiumCEFBrowserHandle closePendingBrowser = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness closePendingNative;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(closePendingBrowser, closePendingNative.browserRef(), nullptr));
  uint64_t closePendingRuntimeId = 0;
  cef_browser_t* closePendingRawBrowser = nullptr;
  cef_client_t* closePendingRawClient = nullptr;
  XCTAssertEqual(
    miumNativeCEFTestBeginClosingNativeBrowser(
      closePendingBrowser,
      true,
      true,
      &closePendingRuntimeId,
      &closePendingRawBrowser,
      &closePendingRawClient
    ),
    MiumCEFBridgeTestBrowserCloseDisposition::closePending
  );
  XCTAssertNotEqual(closePendingRawBrowser, nullptr);

  const MiumCEFBrowserHandle closePendingNoClientBrowser = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness closePendingNoClientNative;
  cef_client_t* closePendingClient = miumNativeCEFTestCreateBrowserClient();
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(
    closePendingNoClientBrowser,
    closePendingNoClientNative.browserRef(),
    closePendingClient
  ));
  cef_browser_t* closePendingBrowserWithoutClient = nullptr;
  XCTAssertEqual(
    miumNativeCEFTestBeginClosingNativeBrowser(
      closePendingNoClientBrowser,
      false,
      false,
      nullptr,
      &closePendingBrowserWithoutClient,
      nullptr
    ),
    MiumCEFBridgeTestBrowserCloseDisposition::closePending
  );
  XCTAssertNotEqual(closePendingBrowserWithoutClient, nullptr);
  miumNativeCEFTestFinalizeClosedBrowserState(closePendingNoClientBrowser, runtimeHandle);
  miumNativeCEFTestFinishPendingBrowserClose(MiumCEFBridgeTestCloseKind::teardown);
  if (closePendingBrowserWithoutClient != nullptr && closePendingBrowserWithoutClient->base.release != nullptr) {
    closePendingBrowserWithoutClient->base.release(&closePendingBrowserWithoutClient->base);
  }

  miumNativeCEFTestFinalizeClosedBrowserState(closePendingBrowser, runtimeHandle);
  miumNativeCEFTestSetBrowserStateFlags(closePendingBrowser, true, true);
  XCTAssertEqual(
    miumNativeCEFTestBeginClosingNativeBrowser(
      closePendingBrowser,
      false,
      true,
      nullptr,
      nullptr,
      nullptr
    ),
    MiumCEFBridgeTestBrowserCloseDisposition::failed
  );

  __block int nullCloseCompletionCount = 0;
  cef_client_t* closeClient = miumNativeCEFTestCreateBrowserClient();
  miumNativeCEFTestCloseBrowserDirect(
    nullptr,
    closeClient,
    MiumCEFBridgeTestCloseKind::teardown,
    &nullCloseCompletionCount,
    incrementIntegerCallback
  );
  XCTAssertEqual(nullCloseCompletionCount, 1);

  __block int polledCloseCompletionCount = 0;
  FakeBrowserHarness polledBrowser;
  polledBrowser.host->invalidatesOwnerOnClose = false;
  miumNativeCEFTestCloseBrowserDirect(
    polledBrowser.browserRef(),
    nullptr,
    MiumCEFBridgeTestCloseKind::replacement,
    &polledCloseCompletionCount,
    incrementIntegerCallback
  );
  polledBrowser.browser->isValid = false;
  [self waitUntil:^BOOL {
    return polledCloseCompletionCount == 1;
  } description:@"browser close polling completed"];
  XCTAssertEqual(polledCloseCompletionCount, 1);
}

- (void)testBindingEnsureAndHandleWrappersCoverStaleAndRaceBranches {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle firstBrowser = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle firstHostViewHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(firstBrowser, &firstHostViewHandle), MiumCEFResultOK);

  NSView* firstHostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 90, 60)];
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(firstHostViewHandle, (__bridge void*)firstHostView));

  const uint64_t firstBrowserId = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(firstBrowser));
  const uint64_t firstHostViewId = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(firstHostViewHandle));
  const MiumCEFBrowserHandle invalidBrowserHandle =
    reinterpret_cast<MiumCEFBrowserHandle>(static_cast<uintptr_t>(firstBrowserId + 1000));
  const MiumCEFHostViewHandle invalidHostViewHandle =
    reinterpret_cast<MiumCEFHostViewHandle>(static_cast<uintptr_t>(firstHostViewId + 1000));

  XCTAssertFalse(miumNativeCEFTestCanBindBrowserToHostView(firstBrowser, invalidHostViewHandle, (__bridge void*)firstHostView));
  XCTAssertFalse(miumNativeCEFTestBindBrowserToHostView(nullptr, firstHostViewHandle, (__bridge void*)firstHostView));
  XCTAssertFalse(miumNativeCEFTestBindBrowserToHostView(firstBrowser, invalidHostViewHandle, (__bridge void*)firstHostView));
  miumNativeCEFTestClearBrowserHostViewBinding(invalidBrowserHandle);
  miumNativeCEFTestBindNativeBrowserMappings(invalidBrowserHandle, nullptr, nullptr);
  XCTAssertFalse(miumNativeCEFTestSetHostViewBrowserId(invalidHostViewHandle, firstBrowserId));

  XCTAssertTrue(miumNativeCEFTestSetHostViewBrowserId(firstHostViewHandle, firstBrowserId + 77));
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(firstHostViewHandle), nullptr);
  XCTAssertTrue(miumNativeCEFTestSetHostViewBrowserId(firstHostViewHandle, firstBrowserId));

  XCTAssertTrue(miumNativeCEFTestBindBrowserToHostView(firstBrowser, firstHostViewHandle, (__bridge void*)firstHostView));
  FakeBrowserHarness firstNativeBrowser;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(firstBrowser, firstNativeBrowser.browserRef(), nullptr));
  XCTAssertTrue(miumNativeCEFTestEnsureNativeBrowser(firstBrowser, nullptr));
  XCTAssertFalse(miumNativeCEFTestEnsureNativeBrowser(invalidBrowserHandle, firstHostViewHandle));

  const MiumCEFBrowserHandle secondBrowser = [self createBrowserForRuntime:runtimeHandle];
  XCTAssertFalse(miumNativeCEFTestEnsureNativeBrowser(secondBrowser, firstHostViewHandle));

  const MiumCEFBrowserHandle staleBrowser = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle staleHostViewHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(staleBrowser, &staleHostViewHandle), MiumCEFResultOK);
  NSView* staleHostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 80, 50)];
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(staleHostViewHandle, (__bridge void*)staleHostView));
  XCTAssertTrue(miumNativeCEFTestBindBrowserToHostView(staleBrowser, staleHostViewHandle, (__bridge void*)staleHostView));
  XCTAssertTrue(miumNativeCEFTestSetHostViewBrowserId(staleHostViewHandle, firstBrowserId + 99));
  XCTAssertEqual(miumNativeCEFDestroyBrowserHostView(staleHostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFTestHostViewHandleForBrowser(staleBrowser), nullptr);

  const MiumCEFBrowserHandle raceBrowser = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle raceHostViewHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(raceBrowser, &raceHostViewHandle), MiumCEFResultOK);
  NSView* raceHostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 70)];
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(raceHostViewHandle, (__bridge void*)raceHostView));

  FakeCreateBrowserFactory deactivateDuringCreateFactory;
  deactivateDuringCreateFactory.onCreate = [&] {
    if (!deactivateDuringCreateFactory.createdBrowsers.empty()) {
      deactivateDuringCreateFactory.createdBrowsers.back()->host->invalidatesOwnerOnClose = false;
    }
    miumNativeCEFTestSetBrowserStateFlags(raceBrowser, false, false);
  };
  gCreateBrowserFactory = &deactivateDuringCreateFactory;
  XCTAssertFalse(miumNativeCEFTestEnsureNativeBrowser(raceBrowser, raceHostViewHandle));
  XCTAssertEqual(miumNativeCEFTestPendingReplacementBrowserCloseCount(), static_cast<size_t>(1));
  deactivateDuringCreateFactory.createdBrowsers.back()->browser->isValid = false;
  [self waitUntil:^BOOL {
    return miumNativeCEFTestPendingReplacementBrowserCloseCount() == static_cast<size_t>(0);
  } description:@"replacement close from failed install drained"];

  const MiumCEFBrowserHandle conflictBrowser = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle conflictHostViewHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(conflictBrowser, &conflictHostViewHandle), MiumCEFResultOK);
  NSView* conflictHostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 98, 68)];
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(conflictHostViewHandle, (__bridge void*)conflictHostView));

  FakeCreateBrowserFactory conflictFactory;
  conflictFactory.onCreate = [&] {
    if (!conflictFactory.createdBrowsers.empty()) {
      conflictFactory.createdBrowsers.back()->host->invalidatesOwnerOnClose = false;
    }
    XCTAssertTrue(miumNativeCEFTestSetHostViewBrowserId(conflictHostViewHandle, firstBrowserId));
  };
  gCreateBrowserFactory = &conflictFactory;
  XCTAssertFalse(miumNativeCEFTestEnsureNativeBrowser(conflictBrowser, conflictHostViewHandle));
  XCTAssertEqual(miumNativeCEFTestPendingReplacementBrowserCloseCount(), static_cast<size_t>(1));
  conflictFactory.createdBrowsers.back()->browser->isValid = false;
  [self waitUntil:^BOOL {
    return miumNativeCEFTestPendingReplacementBrowserCloseCount() == static_cast<size_t>(0);
  } description:@"replacement close from host binding conflict drained"];

  const MiumCEFBrowserHandle attachRaceBrowser = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle attachRaceHostViewHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(attachRaceBrowser, &attachRaceHostViewHandle), MiumCEFResultOK);
  NSView* attachRaceHostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 110, 75)];
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(attachRaceHostViewHandle, (__bridge void*)attachRaceHostView));

  FakeCreateBrowserFactory attachRaceFactory;
  attachRaceFactory.onCreate = [&] {
    miumNativeCEFTestSetBrowserStateFlags(attachRaceBrowser, false, false);
  };
  gCreateBrowserFactory = &attachRaceFactory;
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(attachRaceBrowser, attachRaceHostViewHandle), MiumCEFResultNotInitialized);

  const MiumCEFBrowserHandle installedDuringCreateBrowser = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle installedDuringCreateHostViewHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(installedDuringCreateBrowser, &installedDuringCreateHostViewHandle), MiumCEFResultOK);
  NSView* installedDuringCreateHostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(installedDuringCreateHostViewHandle, (__bridge void*)installedDuringCreateHostView));

  FakeBrowserHarness preinstalledNativeBrowser;
  FakeCreateBrowserFactory installedDuringCreateFactory;
  installedDuringCreateFactory.onCreate = [&] {
    XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(
      installedDuringCreateBrowser,
      preinstalledNativeBrowser.browserRef(),
      nullptr
    ));
    XCTAssertTrue(miumNativeCEFTestBindBrowserToHostView(
      installedDuringCreateBrowser,
      installedDuringCreateHostViewHandle,
      (__bridge void*)installedDuringCreateHostView
    ));
  };
  gCreateBrowserFactory = &installedDuringCreateFactory;
  XCTAssertTrue(miumNativeCEFTestEnsureNativeBrowser(installedDuringCreateBrowser, installedDuringCreateHostViewHandle));
  gCreateBrowserFactory = nullptr;
}

- (void)testHostViewInspectionHelpersTrackActiveAndInactiveBindings {
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
  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 90, 60)];
  MiumCEFHostViewHandle unboundHostViewHandle = nullptr;
  MiumCEFHostViewHandle boundHostViewHandle = nullptr;

  XCTAssertFalse(miumNativeCEFTestSetHostViewPointer(nullptr, (__bridge void*)hostView));
  XCTAssertEqual(miumNativeCEFTestGetHostViewPointer(nullptr), nullptr);
  XCTAssertEqual(miumNativeCEFTestGetBrowserHostViewId(nullptr), static_cast<uint64_t>(0));
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &unboundHostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFTestGetBrowserHostViewId(browserHandle), static_cast<uint64_t>(0));
  XCTAssertEqual(miumNativeCEFTestGetHostViewPointer(unboundHostViewHandle), nullptr);
  XCTAssertEqual(miumNativeCEFTestHostViewHandleForBrowser(browserHandle), nullptr);
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(unboundHostViewHandle), nullptr);

  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(unboundHostViewHandle, (__bridge void*)hostView));
  XCTAssertEqual(miumNativeCEFTestGetHostViewPointer(unboundHostViewHandle), (__bridge void*)hostView);
  XCTAssertEqual(miumNativeCEFDestroyBrowserHostView(unboundHostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFTestGetHostViewPointer(unboundHostViewHandle), nullptr);

  XCTAssertEqual(
    miumNativeCEFCreateBrowserHostViewForNSView(browserHandle, (__bridge void*)hostView, &boundHostViewHandle),
    MiumCEFResultOK
  );
  XCTAssertNotEqual(miumNativeCEFTestGetBrowserHostViewId(browserHandle), static_cast<uint64_t>(0));
  XCTAssertEqual(miumNativeCEFTestGetHostViewPointer(boundHostViewHandle), (__bridge void*)hostView);
  XCTAssertEqual(miumNativeCEFTestHostViewHandleForBrowser(browserHandle), boundHostViewHandle);
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(boundHostViewHandle), browserHandle);

  XCTAssertEqual(miumNativeCEFDestroyBrowserHostView(boundHostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFTestGetHostViewPointer(boundHostViewHandle), nullptr);
  XCTAssertEqual(miumNativeCEFTestGetBrowserHostViewId(browserHandle), static_cast<uint64_t>(0));
  XCTAssertEqual(miumNativeCEFTestHostViewHandleForBrowser(browserHandle), nullptr);
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(boundHostViewHandle), nullptr);
  XCTAssertFalse(miumNativeCEFTestSetHostViewPointer(boundHostViewHandle, (__bridge void*)hostView));
}

- (void)testAttachNativeBrowserReplacementUpdatesNativeBrowserLookup {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness firstBrowser;
  FakeBrowserHarness secondBrowser;
  secondBrowser.browser->identifier = 7331;

  XCTAssertFalse(miumNativeCEFTestAttachNativeBrowser(nullptr, firstBrowser.browserRef(), nullptr));
  XCTAssertEqual(miumNativeCEFTestBrowserIdFromNativeBrowser(nullptr), static_cast<uint64_t>(0));

  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, firstBrowser.browserRef(), nullptr));
  const uint64_t browserId = miumNativeCEFTestBrowserIdFromNativeBrowser(firstBrowser.browserRef());
  XCTAssertGreaterThan(browserId, static_cast<uint64_t>(0));

  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, secondBrowser.browserRef(), nullptr));
  XCTAssertEqual(miumNativeCEFTestBrowserIdFromNativeBrowser(firstBrowser.browserRef()), static_cast<uint64_t>(0));
  XCTAssertEqual(miumNativeCEFTestBrowserIdFromNativeBrowser(secondBrowser.browserRef()), browserId);

  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, nullptr, nullptr));
  XCTAssertEqual(miumNativeCEFTestBrowserIdFromNativeBrowser(secondBrowser.browserRef()), static_cast<uint64_t>(0));
}

- (void)testAdditionalTestingWrappersCoverHelperFormattingAndBindingPaths {
  [self installBasicAPI];

  std::string error;
  XCTAssertTrue(miumNativeCEFTestSetCefSettingPath("", &error));
  XCTAssertEqual(error, "");

  miumNativeCEFTestInstallAPI(nullptr);
  error.clear();
  XCTAssertFalse(miumNativeCEFTestSetCefSettingPath("/tmp/mium-path", &error));
  XCTAssertTrue(error.find("UTF8->UTF16") != std::string::npos);

  [self installBasicAPI];
  MiumCEFBridgeTestSnapshotOptions options{};
  error.clear();
  XCTAssertFalse(miumNativeCEFTestConfigureSnapshotFormat("png", nullptr, &error));
  XCTAssertTrue(error.find("Snapshot options unavailable") != std::string::npos);

  error.clear();
  XCTAssertTrue(miumNativeCEFTestConfigureSnapshotFormat("JPG", &options, &error));
  XCTAssertTrue(options.usesJPEGCompressionFactor);
  XCTAssertFalse(options.captureAsPDF);
  XCTAssertEqual(error, "");

  error.clear();
  XCTAssertTrue(miumNativeCEFTestConfigureSnapshotFormat("PDF", &options, &error));
  XCTAssertTrue(options.captureAsPDF);
  XCTAssertEqual(error, "");

  error.clear();
  XCTAssertFalse(miumNativeCEFTestParseSnapshotOptions(nullptr, "/tmp/snapshot.xyz", &options, &error));
  XCTAssertTrue(error.find("Unsupported snapshot format") != std::string::npos);
  XCTAssertEqualWithAccuracy(miumNativeCEFTestBackingScaleFactorForHostView(nullptr), 1.0, 0.001);

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle firstBrowser = [self createBrowserForRuntime:runtimeHandle];
  const MiumCEFBrowserHandle secondBrowser = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle hostViewHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(firstBrowser, &hostViewHandle), MiumCEFResultOK);

  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 80, 40)];
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(hostViewHandle, (__bridge void*)hostView));
  XCTAssertFalse(miumNativeCEFTestCanBindBrowserToHostView(nullptr, hostViewHandle, (__bridge void*)hostView));
  XCTAssertFalse(miumNativeCEFTestCanBindBrowserToHostView(firstBrowser, nullptr, (__bridge void*)hostView));
  XCTAssertFalse(miumNativeCEFTestCanBindBrowserToHostView(firstBrowser, hostViewHandle, nullptr));
  XCTAssertFalse(miumNativeCEFTestCanBindBrowserToHostView(firstBrowser, hostViewHandle, (__bridge void*)[[NSView alloc] initWithFrame:NSZeroRect]));
  XCTAssertTrue(miumNativeCEFTestCanBindBrowserToHostView(firstBrowser, hostViewHandle, (__bridge void*)hostView));
  XCTAssertTrue(miumNativeCEFTestBindBrowserToHostView(firstBrowser, hostViewHandle, (__bridge void*)hostView));
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(hostViewHandle), firstBrowser);
  XCTAssertEqual(miumNativeCEFTestHostViewHandleForBrowser(firstBrowser), hostViewHandle);
  XCTAssertFalse(miumNativeCEFTestCanBindBrowserToHostView(secondBrowser, hostViewHandle, (__bridge void*)hostView));

  const uint64_t firstBrowserId = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(firstBrowser));
  XCTAssertTrue(miumNativeCEFTestIsBrowserHandleAvailableForCallbacks(0));
  XCTAssertTrue(miumNativeCEFTestIsBrowserHandleAvailableForCallbacks(firstBrowserId));
  miumNativeCEFTestSetBrowserStateFlags(firstBrowser, false, false);
  XCTAssertFalse(miumNativeCEFTestIsBrowserHandleAvailableForCallbacks(firstBrowserId));
  miumNativeCEFTestSetBrowserStateFlags(firstBrowser, false, true);
  XCTAssertFalse(miumNativeCEFTestIsBrowserHandleAvailableForCallbacks(firstBrowserId));
  miumNativeCEFTestSetBrowserStateFlags(firstBrowser, true, false);

  miumNativeCEFTestClearBrowserHostViewBinding(nullptr);
  miumNativeCEFTestClearBrowserHostViewBinding(firstBrowser);
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(hostViewHandle), nullptr);
  XCTAssertEqual(miumNativeCEFTestHostViewHandleForBrowser(firstBrowser), nullptr);
  XCTAssertFalse(miumNativeCEFTestSetHostViewBrowserId(nullptr, firstBrowserId));
  XCTAssertTrue(miumNativeCEFTestSetHostViewBrowserId(hostViewHandle, firstBrowserId));
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(hostViewHandle), firstBrowser);
  XCTAssertFalse(miumNativeCEFTestEnsureNativeBrowser(nullptr, hostViewHandle));
  miumNativeCEFTestBindNativeBrowserMappings(nullptr, nullptr, nullptr);
  miumNativeCEFTestSetBrowserStateFlags(nullptr, true, true);

  miumNativeCEFTestSetBrowserStateFlags(firstBrowser, false, false);
  XCTAssertEqual(miumNativeCEFGoBack(firstBrowser), MiumCEFResultNotInitialized);
  XCTAssertEqual(miumNativeCEFGoForward(firstBrowser), MiumCEFResultNotInitialized);
  XCTAssertEqual(miumNativeCEFCanGoBack(firstBrowser), 0);
  XCTAssertEqual(miumNativeCEFCanGoForward(firstBrowser), 0);
  XCTAssertEqual(miumNativeCEFIsLoading(firstBrowser), 0);
  XCTAssertEqual(miumNativeCEFReload(firstBrowser), MiumCEFResultNotInitialized);
  XCTAssertEqual(miumNativeCEFStopLoad(firstBrowser), MiumCEFResultNotInitialized);
  XCTAssertEqual(miumNativeCEFResizeBrowser(firstBrowser, 40, 20), MiumCEFResultNotInitialized);

  MiumCEFHostViewHandle inactiveHostView = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(firstBrowser, &inactiveHostView), MiumCEFResultNotInitialized);
  XCTAssertEqual(
    miumNativeCEFCreateBrowserHostViewForNSView(firstBrowser, (__bridge void*)hostView, &inactiveHostView),
    MiumCEFResultNotInitialized
  );
  XCTAssertEqual(miumNativeCEFTestGetBrowserHostViewId(firstBrowser), static_cast<uint64_t>(0));
  XCTAssertFalse(miumNativeCEFTestAttachNativeBrowser(firstBrowser, nullptr, nullptr));

  uint64_t runtimeId = 999;
  cef_browser_t* rawBrowser = nullptr;
  cef_client_t* rawClient = nullptr;
  XCTAssertEqual(
    miumNativeCEFTestBeginClosingNativeBrowser(nullptr, false, true, &runtimeId, &rawBrowser, &rawClient),
    MiumCEFBridgeTestBrowserCloseDisposition::failed
  );
}

- (void)testAdditionalTestingWrappersCoverSubprocessCreationAndShutdownHelpers {
  FakeCefLibrary library = [self buildFakeCefLibraryVariant:@"default"];

  const char* argv[] = { "Navigator" };
  MiumCEFBridgeTestAPI emptyAPI{};
  miumNativeCEFTestInstallAPI(&emptyAPI);
  miumNativeCEFTestSetBundlePathNil(true);
  XCTAssertEqual(miumNativeCEFMaybeRunSubprocess(1, argv), -1);
  miumNativeCEFTestSetBundlePathNil(false);

  FakeCefLibrary badSubprocessLibrary = [self buildFakeCefLibraryVariant:@"missing-api-hash"];
  miumNativeCEFTestSetSubprocessFrameworkCandidates({ std::string(badSubprocessLibrary.frameworkPath.UTF8String) });
  XCTAssertEqual(miumNativeCEFMaybeRunSubprocess(1, argv), -1);
  miumNativeCEFTestSetSubprocessFrameworkCandidates({});

  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.executeProcess = fakeExecuteProcess;
  api.initialize = fakeInitialize;
  api.shutdown = fakeShutdown;
  api.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&api);

  XCTAssertFalse(miumNativeCEFTestShouldInterceptProcessExitCode(7));
  miumNativeCEFTestSetInterceptProcessExit(true);
  XCTAssertTrue(miumNativeCEFTestShouldInterceptProcessExitCode(8));
  XCTAssertEqual(miumNativeCEFTestLastInterceptedProcessExitCode(), 8);
  miumNativeCEFTestSetInterceptProcessExit(false);
  XCTAssertEqual(miumNativeCEFTestLastInterceptedProcessExitCode(), -1);

  gExecuteProcessReturnCode = 19;
  miumNativeCEFTestSetProcessExitCallback(captureProcessExitCode);
  std::string failureReason;
  XCTAssertFalse(
    miumNativeCEFTestEnsureCefInitialized(
      library.runtimeRoot.UTF8String,
      library.metadataPath.UTF8String,
      &failureReason
    )
  );
  XCTAssertEqual(gProcessExitCallbackCode, 19);
  XCTAssertTrue(failureReason.find("process termination") != std::string::npos);

  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 70)];
  cef_browser_t* createdBrowser = reinterpret_cast<cef_browser_t*>(0x1);
  cef_client_t* createdClient = reinterpret_cast<cef_client_t*>(0x1);

  MiumCEFBridgeTestAPI noCreateAPI{};
  noCreateAPI.utf8ToUTF16 = fakeUTF8ToUTF16;
  noCreateAPI.utf16Clear = fakeUTF16Clear;
  miumNativeCEFTestInstallAPI(&noCreateAPI);
  miumNativeCEFTestSetInitialized(true, 1);
  XCTAssertFalse(miumNativeCEFTestCreateBrowserWithWindowInfo((__bridge void*)hostView, &createdBrowser, &createdClient));
  XCTAssertEqual(createdBrowser, nullptr);
  XCTAssertEqual(createdClient, nullptr);

  MiumCEFBridgeTestAPI failingUTF8API{};
  failingUTF8API.utf8ToUTF16 = fakeUTF8ToUTF16MaybeFail;
  failingUTF8API.utf16Clear = fakeUTF16Clear;
  failingUTF8API.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&failingUTF8API);
  miumNativeCEFTestSetInitialized(true, 1);
  gUTF8ConversionFailureNeedle = "about:blank";
  XCTAssertFalse(miumNativeCEFTestCreateBrowserWithWindowInfo((__bridge void*)hostView, &createdBrowser, &createdClient));
  gUTF8ConversionFailureNeedle.clear();

  MiumCEFBridgeTestAPI createAPI{};
  createAPI.utf8ToUTF16 = fakeUTF8ToUTF16;
  createAPI.utf16Clear = fakeUTF16Clear;
  createAPI.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&createAPI);
  miumNativeCEFTestSetInitialized(true, 1);
  miumNativeCEFTestSetCreateBrowserClientReturnsNull(true);
  XCTAssertFalse(miumNativeCEFTestCreateBrowserWithWindowInfo((__bridge void*)hostView, &createdBrowser, &createdClient));
  miumNativeCEFTestSetCreateBrowserClientReturnsNull(false);

  FakeCreateBrowserFactory factory;
  gCreateBrowserFactory = &factory;
  __block bool didCreateBrowser = false;
  __block cef_browser_t* createdOnBackground = nullptr;
  __block cef_client_t* createdClientOnBackground = nullptr;
  [self runOnBackgroundQueueAndWait:^{
    didCreateBrowser = miumNativeCEFTestCreateBrowserWithWindowInfo(
      (__bridge void*)hostView,
      &createdOnBackground,
      &createdClientOnBackground
    );
  }];
  XCTAssertTrue(didCreateBrowser);
  XCTAssertNotEqual(createdOnBackground, nullptr);
  XCTAssertNotEqual(createdClientOnBackground, nullptr);
  XCTAssertEqual(factory.callCount, 1);
  XCTAssertEqual(factory.lastParentView, (__bridge void*)embeddedParentViewForHostView(hostView));
  XCTAssertEqual(factory.lastURL, "about:blank");
  XCTAssertEqual(factory.lastWidth, 120);
  XCTAssertEqual(factory.lastHeight, 70);
  XCTAssertEqual(createdOnBackground->base.release(&createdOnBackground->base), 1);
  XCTAssertEqual(createdClientOnBackground->base.release(&createdClientOnBackground->base), 1);

  MiumCEFBridgeTestAPI shutdownAPI{};
  shutdownAPI.shutdown = fakeShutdown;
  miumNativeCEFTestInstallAPI(&shutdownAPI);
  gShutdownCalls = 0;
  miumNativeCEFTestSetInitialized(true, 0);
  miumNativeCEFTestSetShutdownState(true, false);
  miumNativeCEFTestMaybeCompletePendingCefShutdown();
  XCTAssertEqual(gShutdownCalls, 1);

  miumNativeCEFTestInstallAPI(&shutdownAPI);
  miumNativeCEFTestSetInitialized(true, 0);
  miumNativeCEFTestSetShutdownState(true, false);
  miumNativeCEFTestRegisterPendingBrowserClose(MiumCEFBridgeTestCloseKind::teardown);
  miumNativeCEFTestMaybeCompletePendingCefShutdown();
  XCTAssertEqual(gShutdownCalls, 1);
  miumNativeCEFTestFinishPendingBrowserClose(MiumCEFBridgeTestCloseKind::teardown);
  XCTAssertEqual(gShutdownCalls, 2);

  const MiumCEFRuntimeHandle pendingShutdownRuntime = [self seedRuntime];
  const MiumCEFBrowserHandle pendingShutdownBrowser = [self createBrowserForRuntime:pendingShutdownRuntime];
  FakeBrowserHarness pendingShutdownNativeBrowser;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(
    pendingShutdownBrowser,
    pendingShutdownNativeBrowser.browserRef(),
    nullptr
  ));
  uint64_t pendingShutdownRuntimeId = 0;
  cef_browser_t* pendingShutdownRawBrowser = nullptr;
  cef_client_t* pendingShutdownRawClient = nullptr;
  XCTAssertEqual(
    miumNativeCEFTestBeginClosingNativeBrowser(
      pendingShutdownBrowser,
      true,
      true,
      &pendingShutdownRuntimeId,
      &pendingShutdownRawBrowser,
      &pendingShutdownRawClient
    ),
    MiumCEFBridgeTestBrowserCloseDisposition::closePending
  );
  gShutdownCalls = 0;
  miumNativeCEFTestInstallAPI(&shutdownAPI);
  miumNativeCEFTestSetInitialized(true, 0);
  miumNativeCEFTestSetShutdownState(true, false);
  miumNativeCEFTestFinalizeClosedBrowserState(pendingShutdownBrowser, pendingShutdownRuntime);
  miumNativeCEFTestFinishPendingBrowserClose(MiumCEFBridgeTestCloseKind::teardown);
  if (pendingShutdownRawBrowser != nullptr && pendingShutdownRawBrowser->base.release != nullptr) {
    pendingShutdownRawBrowser->base.release(&pendingShutdownRawBrowser->base);
  }
  if (pendingShutdownRawClient != nullptr && pendingShutdownRawClient->base.release != nullptr) {
    pendingShutdownRawClient->base.release(&pendingShutdownRawClient->base);
  }
}

- (void)testBrowserClientGetterRetainsHandlersAndClientReleaseDropsOwnedReferences {
  cef_client_t* client = miumNativeCEFTestCreateBrowserClient();
  XCTAssertNotEqual(client, nullptr);

  cef_display_handler_t* displayHandler = client->get_display_handler(client);
  cef_life_span_handler_t* lifeSpanHandler = client->get_life_span_handler(client);
  cef_load_handler_t* loadHandler = client->get_load_handler(client);
  cef_request_handler_t* requestHandler = client->get_request_handler(client);

  XCTAssertNotEqual(displayHandler, nullptr);
  XCTAssertNotEqual(lifeSpanHandler, nullptr);
  XCTAssertNotEqual(loadHandler, nullptr);
  XCTAssertNotEqual(requestHandler, nullptr);
  XCTAssertEqual(displayHandler->base.release(&displayHandler->base), 0);
  XCTAssertEqual(lifeSpanHandler->base.release(&lifeSpanHandler->base), 0);
  XCTAssertEqual(loadHandler->base.release(&loadHandler->base), 0);
  XCTAssertEqual(requestHandler->base.release(&requestHandler->base), 0);

  cef_display_handler_t* retainedDisplayHandler = client->get_display_handler(client);
  XCTAssertNotEqual(retainedDisplayHandler, nullptr);
  XCTAssertEqual(client->base.release(&client->base), 1);
  XCTAssertEqual(retainedDisplayHandler->base.has_one_ref(&retainedDisplayHandler->base), 1);
  XCTAssertEqual(retainedDisplayHandler->base.release(&retainedDisplayHandler->base), 1);
}

@end
