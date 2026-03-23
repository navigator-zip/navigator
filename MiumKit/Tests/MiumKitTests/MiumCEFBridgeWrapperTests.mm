#import "MiumCEFBridgeNativeTestSupport.h"

using namespace MiumCEFBridgeNativeTestSupport;

@interface MiumCEFBridgeWrapperTests : MiumCEFBridgeNativeTestCase
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

@implementation MiumCEFBridgeWrapperTests

- (void)testCloseBrowserRetainsHostViewUntilNativeCloseCompletes {
  FakeCefLibrary library = [self buildFakeCefLibraryVariant:@"default"];
  NSString* cachePath = [[self temporaryDirectory] stringByAppendingPathComponent:@"cef-cache-close-retain"];
  NSString* helperExecutable = [[[[library.runtimeRoot stringByAppendingPathComponent:@"Contents/Frameworks/Navigator Helper.app/Contents"] stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:@"Navigator Helper"] stringByStandardizingPath];

  XCTAssertEqual(CEFBridge_Initialize(library.metadataPath.UTF8String, nullptr, cachePath.UTF8String, helperExecutable.UTF8String), 1);

  MiumCEFBridgeTestAPI browserAPI{};
  browserAPI.utf8ToUTF16 = fakeUTF8ToUTF16;
  browserAPI.utf16Clear = fakeUTF16Clear;
  browserAPI.createBrowserSync = fakeCreateBrowserSync;
  browserAPI.createProcessMessage = fakeCreateProcessMessage;
  browserAPI.shutdown = fakeShutdown;
  miumNativeCEFTestInstallAPI(&browserAPI);
  miumNativeCEFTestSetInitialized(true, 1);

  FakeCreateBrowserFactory factory;
  gCreateBrowserFactory = &factory;

  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];
  __weak NSView* weakHostView = hostView;
  const CEFBridgeBrowserRef browserRef = CEFBridge_CreateBrowser((__bridge void*)hostView, nullptr, 120, 80, 2.0);
  XCTAssertNotEqual(browserRef, nullptr);
  factory.createdBrowsers.back()->host->invalidatesOwnerOnClose = false;

  @autoreleasepool {
    CEFBridge_CloseBrowser(browserRef);
    hostView = nil;
  }

  XCTAssertEqual(CEFBridge_HasPendingBrowserClose(), 1);
  XCTAssertNotNil(weakHostView);

  NSDate* closeDeadline = [NSDate dateWithTimeIntervalSinceNow:3.0];
  while (CEFBridge_HasPendingBrowserClose() != 0 && [closeDeadline timeIntervalSinceNow] > 0.0) {
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                             beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    [[NSRunLoop currentRunLoop] runMode:NSRunLoopCommonModes
                             beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }

  XCTAssertEqual(CEFBridge_HasPendingBrowserClose(), 0);
  CEFBridge_Shutdown();
}

- (void)testCEFBridgeLifecycleAndBrowserWrappers {
  XCTAssertEqual(CEFBridge_MaybeRunSubprocess(0, nullptr), -1);
  const char* nonSubprocessArgv[] = { "xctest", "--flag" };
  XCTAssertEqual(CEFBridge_MaybeRunSubprocess(2, nonSubprocessArgv), -1);

  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.executeProcess = fakeExecuteProcess;
  miumNativeCEFTestInstallAPI(&api);

  gExecuteProcessReturnCode = 23;
  const char* subprocessArgv[] = { "xctest", "--type=renderer" };
  XCTAssertEqual(CEFBridge_MaybeRunSubprocess(2, subprocessArgv), 23);

  FakeCefLibrary library = [self buildFakeCefLibraryVariant:@"default"];
  NSString* cachePath = [[self temporaryDirectory] stringByAppendingPathComponent:@"cef-cache"];
  NSString* helperExecutable = [[[[library.runtimeRoot stringByAppendingPathComponent:@"Contents/Frameworks/Navigator Helper.app/Contents"] stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:@"Navigator Helper"] stringByStandardizingPath];

  XCTAssertEqual(CEFBridge_Initialize(nullptr, nullptr, nullptr, nullptr), 0);
  XCTAssertEqual(CEFBridge_Initialize(library.metadataPath.UTF8String, nullptr, cachePath.UTF8String, helperExecutable.UTF8String), 1);
  const char* rootCacheEnv = std::getenv("MIUM_CEF_ROOT_CACHE_PATH");
  XCTAssertNotEqual(rootCacheEnv, nullptr);
  if (rootCacheEnv != nullptr) {
    XCTAssertEqual(std::string(rootCacheEnv), std::string(cachePath.UTF8String));
  }
  const char* subprocessEnv = std::getenv("MIUM_CEF_BROWSER_SUBPROCESS_PATH");
  XCTAssertNotEqual(subprocessEnv, nullptr);
  if (subprocessEnv != nullptr) {
    XCTAssertEqual(std::string(subprocessEnv), std::string(helperExecutable.UTF8String));
  }
  XCTAssertEqual(CEFBridge_Initialize(library.metadataPath.UTF8String, nullptr, nullptr, nullptr), 1);
  XCTAssertEqual(std::getenv("MIUM_CEF_ROOT_CACHE_PATH"), nullptr);
  XCTAssertEqual(std::getenv("MIUM_CEF_BROWSER_SUBPROCESS_PATH"), nullptr);

  library.handle = [self openTrackedLibraryAtPath:library.frameworkPath];
  XCTAssertNotEqual(library.handle, nullptr);
  auto initializeCalls = reinterpret_cast<IntGetterFn>([self symbolNamed:"mium_test_get_initialize_calls" inHandle:library.handle]);
  auto shutdownCalls = reinterpret_cast<IntGetterFn>([self symbolNamed:"mium_test_get_shutdown_calls" inHandle:library.handle]);
  auto messageLoopCalls = reinterpret_cast<IntGetterFn>([self symbolNamed:"mium_test_get_message_loop_calls" inHandle:library.handle]);
  auto subprocessPath = reinterpret_cast<CStringGetterFn>([self symbolNamed:"mium_test_get_browser_subprocess_path" inHandle:library.handle]);
  auto resourcesPath = reinterpret_cast<CStringGetterFn>([self symbolNamed:"mium_test_get_resources_dir_path" inHandle:library.handle]);
  auto localesPath = reinterpret_cast<CStringGetterFn>([self symbolNamed:"mium_test_get_locales_dir_path" inHandle:library.handle]);
  auto configuredCachePath = reinterpret_cast<CStringGetterFn>([self symbolNamed:"mium_test_get_cache_path" inHandle:library.handle]);
  auto configuredRootCachePath = reinterpret_cast<CStringGetterFn>([self symbolNamed:"mium_test_get_root_cache_path" inHandle:library.handle]);
  XCTAssertEqual(initializeCalls(), 1);
  XCTAssertEqualObjects(stringFromCString(subprocessPath()), helperExecutable);
  XCTAssertEqualObjects(stringFromCString(resourcesPath()), [library.metadataPath stringByStandardizingPath]);
  XCTAssertFalse(stringFromCString(localesPath()).length == 0);
  XCTAssertEqualObjects(stringFromCString(configuredCachePath()), [cachePath stringByStandardizingPath]);
  XCTAssertEqualObjects(stringFromCString(configuredRootCachePath()), [cachePath stringByStandardizingPath]);

  CEFBridge_DoMessageLoopWork();
  XCTAssertEqual(messageLoopCalls(), 1);
  XCTAssertEqual(CEFBridge_HasPendingBrowserClose(), 0);
  CEFBridge_Shutdown();
  XCTAssertEqual(shutdownCalls(), 1);
  CEFBridge_Shutdown();

  XCTAssertEqual(CEFBridge_Initialize(library.metadataPath.UTF8String, nullptr, cachePath.UTF8String, helperExecutable.UTF8String), 1);
  MiumCEFBridgeTestAPI browserAPI{};
  browserAPI.utf8ToUTF16 = fakeUTF8ToUTF16;
  browserAPI.utf16Clear = fakeUTF16Clear;
  browserAPI.createBrowserSync = fakeCreateBrowserSync;
  browserAPI.createProcessMessage = fakeCreateProcessMessage;
  browserAPI.shutdown = fakeShutdown;
  miumNativeCEFTestInstallAPI(&browserAPI);
  miumNativeCEFTestSetInitialized(true, 1);
  XCTAssertEqual(CEFBridge_CreateBrowser(nullptr, nullptr, 120, 80, 2.0), nullptr);
  NSView* invalidHostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 20, 20)];
  XCTAssertEqual(CEFBridge_CreateBrowser((__bridge void*)invalidHostView, nullptr, 0, 80, 2.0), nullptr);
  XCTAssertEqual(CEFBridge_CreateBrowser((__bridge void*)invalidHostView, nullptr, 20, 0, 2.0), nullptr);

  FakeCreateBrowserFactory factory;
  gCreateBrowserFactory = &factory;
  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];
  CEFBridgeBrowserRef browserRef = CEFBridge_CreateBrowser((__bridge void*)hostView, nullptr, 120, 80, 2.0);
  XCTAssertNotEqual(browserRef, nullptr);
  XCTAssertEqual(factory.callCount, 1);
  XCTAssertEqual(factory.lastParentView, (__bridge void*)embeddedParentViewForHostView(hostView));
  XCTAssertEqual(factory.lastWidth, 120);
  XCTAssertEqual(factory.lastHeight, 80);
  XCTAssertEqual(factory.lastURL, "about:blank");

  auto* createdBrowser = factory.createdBrowsers.back()->browser;
  auto* createdHost = factory.createdBrowsers.back()->host;
  auto* createdFrame = factory.createdBrowsers.back()->frame;
  XCTAssertTrue(createdFrame->lastLoadedURL.empty());

  createdBrowser->canGoBackResult = 1;
  createdBrowser->canGoForwardResult = 1;
  createdBrowser->isLoadingResult = 1;

  CEFBridge_ResizeBrowser(browserRef, 0, 10, 2.0);
  XCTAssertEqual(createdHost->notifyMoveOrResizeStartedCalls, 0);
  CEFBridge_ResizeBrowser(browserRef, 300, 200, 2.0);
  XCTAssertEqual(createdHost->notifyMoveOrResizeStartedCalls, 1);
  XCTAssertEqual(createdHost->wasResizedCalls, 1);
  XCTAssertEqual(CEFBridge_CanGoBack(browserRef), 1);
  XCTAssertEqual(CEFBridge_CanGoForward(browserRef), 1);
  XCTAssertEqual(CEFBridge_IsLoading(browserRef), 1);

  CEFBridge_LoadUrl(browserRef, "https://example.com/load");
  XCTAssertEqual(createdFrame->lastLoadedURL, "https://example.com/load");
  CEFBridge_GoBack(browserRef);
  CEFBridge_GoForward(browserRef);
  CEFBridge_Reload(browserRef);
  XCTAssertEqual(createdBrowser->goBackCalls, 1);
  XCTAssertEqual(createdBrowser->goForwardCalls, 1);
  XCTAssertEqual(createdBrowser->reloadCalls, 1);

  CEFBridge_ExecuteJavaScript(browserRef, "window.bridge = true;");
  XCTAssertEqual(createdFrame->lastExecutedScript, "window.bridge = true;");

  BridgeMessageProbe messageProbe;
  messageProbe.expectation = [self expectationWithDescription:@"bridge message"];
  CEFBridge_SetMessageHandler(browserRef, bridgeMessageCallback, &messageProbe);
  XCTAssertEqual(
    miumNativeCEFEmitMessage(reinterpret_cast<MiumCEFBrowserHandle>(browserRef), "__addressChange__", "https://navigator.test"),
    MiumCEFResultOK
  );
  BridgeMessageProbe faviconProbe;
  faviconProbe.expectation = [self expectationWithDescription:@"bridge favicon message"];
  CEFBridge_SetFaviconURLChangeHandler(browserRef, bridgeMessageCallback, &faviconProbe);
  XCTAssertEqual(
    miumNativeCEFEmitMessage(
      reinterpret_cast<MiumCEFBrowserHandle>(browserRef),
      "__faviconURLChange__",
      "https://navigator.test/favicon.ico"
    ),
    MiumCEFResultOK
  );
  BridgeMessageProbe titleProbe;
  titleProbe.expectation = [self expectationWithDescription:@"bridge title message"];
  CEFBridge_SetTitleChangeHandler(browserRef, bridgeMessageCallback, &titleProbe);
  XCTAssertEqual(
    miumNativeCEFEmitMessage(
      reinterpret_cast<MiumCEFBrowserHandle>(browserRef),
      "__titleChange__",
      "Example Page"
    ),
    MiumCEFResultOK
  );
  BridgeMessageProbe pictureInPictureProbe;
  pictureInPictureProbe.expectation = [self expectationWithDescription:@"bridge picture in picture message"];
  CEFBridge_SetPictureInPictureStateChangeHandler(browserRef, bridgeMessageCallback, &pictureInPictureProbe);
  XCTAssertEqual(
    miumNativeCEFEmitMessage(
      reinterpret_cast<MiumCEFBrowserHandle>(browserRef),
      MiumCEFPictureInPictureStateChangeChannel,
      "{\"sequenceNumber\":1,\"event\":\"bootstrap\",\"location\":\"https://navigator.test\",\"isCurrentWindowPictureInPicture\":false,\"isVideoPictureInPictureActive\":false,\"isVideoPictureInPictureSupported\":true,\"isDocumentPictureInPictureSupported\":true,\"isDocumentPictureInPictureWindowOpen\":false,\"currentWindowInnerWidth\":1280,\"currentWindowInnerHeight\":720,\"videoPictureInPictureWindowWidth\":null,\"videoPictureInPictureWindowHeight\":null,\"documentPictureInPictureWindowWidth\":null,\"documentPictureInPictureWindowHeight\":null,\"activeVideo\":null,\"videoElementCount\":1,\"errorDescription\":null}"
    ),
    MiumCEFResultOK
  );
  BridgeMessageProbe renderTerminationProbe;
  renderTerminationProbe.expectation = [self expectationWithDescription:@"bridge render termination message"];
  CEFBridge_SetRenderProcessTerminationHandler(browserRef, bridgeMessageCallback, &renderTerminationProbe);
  XCTAssertEqual(
    miumNativeCEFEmitMessage(
      reinterpret_cast<MiumCEFBrowserHandle>(browserRef),
      MiumCEFRenderProcessTerminationChannel,
      "{\"status\":2,\"errorCode\":9,\"errorDescription\":\"Renderer crashed\"}"
    ),
    MiumCEFResultOK
  );
  BridgeMessageProbe mainFrameNavigationProbe;
  mainFrameNavigationProbe.expectation = [self expectationWithDescription:@"bridge main frame navigation message"];
  CEFBridge_SetMainFrameNavigationHandler(browserRef, bridgeMessageCallback, &mainFrameNavigationProbe);
  XCTAssertEqual(
    miumNativeCEFEmitMessage(
      reinterpret_cast<MiumCEFBrowserHandle>(browserRef),
      MiumCEFMainFrameNavigationChannel,
      "{\"url\":\"https://accounts.google.com/o/oauth2/v2/auth\",\"userGesture\":false,\"isRedirect\":true}"
    ),
    MiumCEFResultOK
  );
  BridgeMessageProbe openURLInTabProbe;
  openURLInTabProbe.expectation = [self expectationWithDescription:@"bridge open URL in tab message"];
  CEFBridge_SetOpenURLInTabHandler(browserRef, bridgeMessageCallback, &openURLInTabProbe);
  XCTAssertEqual(
    miumNativeCEFEmitMessage(
      reinterpret_cast<MiumCEFBrowserHandle>(browserRef),
      MiumCEFOpenURLInTabChannel,
      "{\"url\":\"https://navigator.test/new-tab\",\"activatesTab\":false}"
    ),
    MiumCEFResultOK
  );
  BridgeMessageProbe cameraRoutingProbe;
  cameraRoutingProbe.expectation = [self expectationWithDescription:@"bridge camera routing message"];
  CEFBridge_SetCameraRoutingEventHandler(browserRef, bridgeMessageCallback, &cameraRoutingProbe);
  XCTAssertEqual(
    miumNativeCEFEmitMessage(
      reinterpret_cast<MiumCEFBrowserHandle>(browserRef),
      MiumCEFCameraRoutingEventChannel,
      "{\"event\":\"track-started\",\"activeManagedTrackCount\":1,\"managedTrackID\":\"track-1\",\"managedDeviceID\":\"navigator-camera-managed-output\",\"preferredFilterPreset\":\"folia\"}"
    ),
    MiumCEFResultOK
  );

  BridgeJavaScriptProbe javaScriptProbe;
  javaScriptProbe.expectation = [self expectationWithDescription:@"bridge javascript result"];
  CEFBridge_ExecuteJavaScriptWithResult(browserRef, "1 + 1", bridgeJavaScriptCallback, &javaScriptProbe);
  CEFBridge_ExecuteJavaScriptWithResult(browserRef, "ignored", nullptr, nullptr);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];

  XCTAssertEqual(messageProbe.messages.size(), static_cast<size_t>(1));
  XCTAssertEqual(messageProbe.messages[0], "https://navigator.test");
  XCTAssertEqual(faviconProbe.messages.size(), static_cast<size_t>(1));
  XCTAssertEqual(faviconProbe.messages[0], "https://navigator.test/favicon.ico");
  XCTAssertEqual(titleProbe.messages.size(), static_cast<size_t>(1));
  XCTAssertEqual(titleProbe.messages[0], "Example Page");
  XCTAssertEqual(pictureInPictureProbe.messages.size(), static_cast<size_t>(1));
  XCTAssertTrue(pictureInPictureProbe.messages[0].find("\"event\":\"bootstrap\"") != std::string::npos);
  XCTAssertEqual(mainFrameNavigationProbe.messages.size(), static_cast<size_t>(1));
  XCTAssertTrue(mainFrameNavigationProbe.messages[0].find("\"isRedirect\":true") != std::string::npos);
  XCTAssertEqual(openURLInTabProbe.messages.size(), static_cast<size_t>(1));
  XCTAssertTrue(openURLInTabProbe.messages[0].find("\"activatesTab\":false") != std::string::npos);
  XCTAssertEqual(cameraRoutingProbe.messages.size(), static_cast<size_t>(1));
  XCTAssertTrue(cameraRoutingProbe.messages[0].find("\"event\":\"track-started\"") != std::string::npos);
  XCTAssertEqual(javaScriptProbe.result, "{\"dispatched\":true}");
  XCTAssertEqual(javaScriptProbe.error, "");

  CEFBridge_SetMessageHandler(browserRef, nullptr, nullptr);
  CEFBridge_SetTitleChangeHandler(browserRef, nullptr, nullptr);
  CEFBridge_SetFaviconURLChangeHandler(browserRef, nullptr, nullptr);
  CEFBridge_SetPictureInPictureStateChangeHandler(browserRef, nullptr, nullptr);
  CEFBridge_SetRenderProcessTerminationHandler(browserRef, nullptr, nullptr);
  CEFBridge_SetMainFrameNavigationHandler(browserRef, nullptr, nullptr);
  CEFBridge_SetOpenURLInTabHandler(browserRef, nullptr, nullptr);
  CEFBridge_SetCameraRoutingEventHandler(browserRef, nullptr, nullptr);
  XCTAssertEqual(
    miumNativeCEFEmitMessage(reinterpret_cast<MiumCEFBrowserHandle>(browserRef), "__addressChange__", "https://navigator.test/ignored"),
    MiumCEFResultError
  );
  XCTAssertEqual(
    miumNativeCEFEmitMessage(
      reinterpret_cast<MiumCEFBrowserHandle>(browserRef),
      "__faviconURLChange__",
      "https://navigator.test/favicon-ignored.ico"
    ),
    MiumCEFResultError
  );
  XCTAssertEqual(
    miumNativeCEFEmitMessage(
      reinterpret_cast<MiumCEFBrowserHandle>(browserRef),
      "__titleChange__",
      "Ignored"
    ),
    MiumCEFResultError
  );
  XCTAssertEqual(
    miumNativeCEFEmitMessage(
      reinterpret_cast<MiumCEFBrowserHandle>(browserRef),
      MiumCEFPictureInPictureStateChangeChannel,
      "{\"sequenceNumber\":2}"
    ),
    MiumCEFResultError
  );
  XCTAssertEqual(
    miumNativeCEFEmitMessage(
      reinterpret_cast<MiumCEFBrowserHandle>(browserRef),
      MiumCEFMainFrameNavigationChannel,
      "{\"url\":\"https://accounts.google.com/o/oauth2/v2/auth\",\"userGesture\":false,\"isRedirect\":true}"
    ),
    MiumCEFResultError
  );
  XCTAssertEqual(
    miumNativeCEFEmitMessage(
      reinterpret_cast<MiumCEFBrowserHandle>(browserRef),
      MiumCEFRenderProcessTerminationChannel,
      "{\"status\":3}"
    ),
    MiumCEFResultError
  );
  XCTAssertEqual(
    miumNativeCEFEmitMessage(
      reinterpret_cast<MiumCEFBrowserHandle>(browserRef),
      MiumCEFCameraRoutingEventChannel,
      "{\"event\":\"track-stopped\",\"activeManagedTrackCount\":0}"
    ),
    MiumCEFResultError
  );

  BridgeJavaScriptProbe failingJavaScriptProbe;
  failingJavaScriptProbe.expectation = [self expectationWithDescription:@"bridge javascript failure"];
  FakeBrowserHarness missingFrameBrowser;
  missingFrameBrowser.browser->browser.get_main_frame = nullptr;
  XCTAssertTrue(
    miumNativeCEFTestAttachNativeBrowser(reinterpret_cast<MiumCEFBrowserHandle>(browserRef), missingFrameBrowser.browserRef(), nullptr)
  );
  CEFBridge_ExecuteJavaScriptWithResult(browserRef, "window.fail()", bridgeJavaScriptCallback, &failingJavaScriptProbe);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(failingJavaScriptProbe.result, "");
  XCTAssertEqual(failingJavaScriptProbe.error, "CEF execute_java_script unavailable");

  const MiumCEFHostViewHandle hostViewHandle = miumNativeCEFTestHostViewHandleForBrowser(reinterpret_cast<MiumCEFBrowserHandle>(browserRef));
  XCTAssertNotEqual(hostViewHandle, nullptr);
  CEFBridge_CloseBrowser(browserRef);
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(hostViewHandle), nullptr);
  CEFBridge_CloseBrowser(browserRef);

  CEFBridge_Shutdown();
  XCTAssertEqual(gShutdownCalls, 1);
  CEFBridge_Shutdown();

  MiumCEFBridgeTestAPI failureAPI{};
  failureAPI.utf8ToUTF16 = fakeUTF8ToUTF16;
  failureAPI.utf16Clear = fakeUTF16Clear;
  failureAPI.shutdown = fakeShutdown;
  miumNativeCEFTestInstallAPI(&failureAPI);
  XCTAssertEqual(CEFBridge_Initialize(library.metadataPath.UTF8String, nullptr, cachePath.UTF8String, helperExecutable.UTF8String), 1);
  XCTAssertEqual(CEFBridge_CreateBrowser((__bridge void*)hostView, "https://explicit.example", 120, 80, 2.0), nullptr);
  CEFBridge_Shutdown();
}

- (void)testCEFBridgeTestingHelpersCoverInternalBranches {
  CEFBridge_DoMessageLoopWork();

  XCTAssertFalse(CEFBridgeTestIsCefSubprocessArgv(0, nullptr));
  const char* subprocessArgv[] = { nullptr, "--type=renderer" };
  XCTAssertTrue(CEFBridgeTestIsCefSubprocessArgv(2, subprocessArgv));

  char invalidUTF8[] = { static_cast<char>(0xFF), 0 };
  const std::string emptyString;
  XCTAssertTrue(CEFBridgeTestNormalizeCPath(nullptr) == emptyString);
  XCTAssertTrue(CEFBridgeTestNormalizeCPath("") == emptyString);
  XCTAssertTrue(CEFBridgeTestNormalizeCPath(invalidUTF8) == emptyString);
  XCTAssertFalse(CEFBridgeTestResolveRuntimeRoot(nullptr).empty());
  XCTAssertTrue(CEFBridgeTestResolveMetadataPath(nullptr) == emptyString);
  XCTAssertTrue(CEFBridgeTestResolveMetadataPath(invalidUTF8) == emptyString);

  CEFBridgeTestBrowserBridgeMessageHandler(MiumCEFResultOK, "ignored", nullptr);
  CEFBridgeTestBrowserBridgeMessageHandlerForBrowser(
    reinterpret_cast<CEFBridgeBrowserRef>(static_cast<uintptr_t>(0x44)),
    MiumCEFAddressChangeChannel,
    MiumCEFResultOK,
    "ignored"
  );

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  const CEFBridgeBrowserRef browserRef = reinterpret_cast<CEFBridgeBrowserRef>(browserHandle);

  BridgeMessageProbe messageProbe;
  messageProbe.expectation = [self expectationWithDescription:@"bridge helper nil message"];
  CEFBridge_SetMessageHandler(browserRef, bridgeMessageCallback, &messageProbe);
  CEFBridge_SetMessageHandler(nullptr, bridgeMessageCallback, &messageProbe);
  CEFBridgeTestBrowserBridgeMessageHandlerForBrowser(
    browserRef,
    MiumCEFAddressChangeChannel,
    MiumCEFResultOK,
    nullptr
  );
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(messageProbe.messages.size(), static_cast<size_t>(1));
  XCTAssertEqual(messageProbe.messages[0], "");

  CEFBridgeTestBrowserBridgeMessageHandlerForBrowser(
    browserRef,
    MiumCEFFaviconURLChangeChannel,
    MiumCEFResultOK,
    "missing-channel"
  );
  XCTAssertEqual(messageProbe.messages.size(), static_cast<size_t>(1));

  CEFBridge_SetMessageHandler(browserRef, nullptr, nullptr);
  CEFBridgeTestBrowserBridgeMessageHandlerForBrowser(
    browserRef,
    MiumCEFAddressChangeChannel,
    MiumCEFResultOK,
    "removed"
  );
  XCTAssertEqual(messageProbe.messages.size(), static_cast<size_t>(1));

  BridgeJavaScriptProbe successProbe;
  successProbe.expectation = [self expectationWithDescription:@"bridge helper success"];
  CEFBridgeTestForwardJavaScriptResult(MiumCEFResultOK, nullptr, bridgeJavaScriptCallback, &successProbe, false);

  BridgeJavaScriptProbe failureProbe;
  failureProbe.expectation = [self expectationWithDescription:@"bridge helper failure"];
  CEFBridgeTestForwardJavaScriptResult(MiumCEFResultError, nullptr, bridgeJavaScriptCallback, &failureProbe, false);
  CEFBridgeTestForwardJavaScriptResult(MiumCEFResultOK, nullptr, bridgeJavaScriptCallback, &failureProbe, true);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];

  XCTAssertEqual(successProbe.result, "");
  XCTAssertEqual(successProbe.error, "");
  XCTAssertEqual(failureProbe.result, "");
  XCTAssertEqual(failureProbe.error, "cef execute javascript failed");
}

- (void)testCEFBridgeTitleChangeHandlerHelpersCoverRegistrationAndRemoval {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  const CEFBridgeBrowserRef browserRef = reinterpret_cast<CEFBridgeBrowserRef>(browserHandle);

  BridgeMessageProbe titleProbe;
  titleProbe.expectation = [self expectationWithDescription:@"bridge title helper messages"];
  titleProbe.expectation.expectedFulfillmentCount = 2;
  CEFBridge_SetTitleChangeHandler(browserRef, bridgeMessageCallback, &titleProbe);
  CEFBridge_SetTitleChangeHandler(nullptr, bridgeMessageCallback, &titleProbe);

  CEFBridgeTestBrowserBridgeMessageHandlerForBrowser(
    browserRef,
    MiumCEFTitleChangeChannel,
    MiumCEFResultOK,
    nullptr
  );
  CEFBridgeTestBrowserBridgeMessageHandlerForBrowser(
    browserRef,
    MiumCEFTitleChangeChannel,
    MiumCEFResultOK,
    "Navigator Title"
  );
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];

  XCTAssertEqual(titleProbe.messages.size(), static_cast<size_t>(2));
  XCTAssertEqual(titleProbe.messages[0], "");
  XCTAssertEqual(titleProbe.messages[1], "Navigator Title");

  CEFBridgeTestBrowserBridgeMessageHandlerForBrowser(
    browserRef,
    MiumCEFAddressChangeChannel,
    MiumCEFResultOK,
    "address-only"
  );
  XCTAssertEqual(titleProbe.messages.size(), static_cast<size_t>(2));

  CEFBridge_SetTitleChangeHandler(browserRef, nullptr, nullptr);
  CEFBridgeTestBrowserBridgeMessageHandlerForBrowser(
    browserRef,
    MiumCEFTitleChangeChannel,
    MiumCEFResultOK,
    "removed"
  );
  XCTAssertEqual(titleProbe.messages.size(), static_cast<size_t>(2));
}

- (void)testCEFBridgeTopLevelNativeContentHandlerHelpersCoverRegistrationAndRemoval {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  const CEFBridgeBrowserRef browserRef = reinterpret_cast<CEFBridgeBrowserRef>(browserHandle);

  BridgeMessageProbe contentProbe;
  contentProbe.expectation = [self expectationWithDescription:@"bridge top-level native content helper messages"];
  contentProbe.expectation.expectedFulfillmentCount = 2;
  CEFBridge_SetTopLevelNativeContentHandler(
    browserRef,
    bridgeMessageCallback,
    &contentProbe
  );
  CEFBridge_SetTopLevelNativeContentHandler(
    nullptr,
    bridgeMessageCallback,
    &contentProbe
  );

  CEFBridgeTestBrowserBridgeMessageHandlerForBrowser(
    browserRef,
    MiumCEFTopLevelNativeContentChannel,
    MiumCEFResultOK,
    nullptr
  );
  CEFBridgeTestBrowserBridgeMessageHandlerForBrowser(
    browserRef,
    MiumCEFTopLevelNativeContentChannel,
    MiumCEFResultOK,
    "{\"kind\":\"image\",\"url\":\"https://navigator.test/image.png\"}"
  );
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];

  XCTAssertEqual(contentProbe.messages.size(), static_cast<size_t>(2));
  XCTAssertEqual(contentProbe.messages[0], "");
  XCTAssertEqual(contentProbe.messages[1], "{\"kind\":\"image\",\"url\":\"https://navigator.test/image.png\"}");

  CEFBridgeTestBrowserBridgeMessageHandlerForBrowser(
    browserRef,
    MiumCEFTitleChangeChannel,
    MiumCEFResultOK,
    "title-only"
  );
  XCTAssertEqual(contentProbe.messages.size(), static_cast<size_t>(2));

  CEFBridge_SetTopLevelNativeContentHandler(browserRef, nullptr, nullptr);
  CEFBridgeTestBrowserBridgeMessageHandlerForBrowser(
    browserRef,
    MiumCEFTopLevelNativeContentChannel,
    MiumCEFResultOK,
    "removed"
  );
  XCTAssertEqual(contentProbe.messages.size(), static_cast<size_t>(2));
}

- (void)testCEFBridgeCloseBrowserClearsCameraRoutingHandlerRegistration {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  const CEFBridgeBrowserRef browserRef = reinterpret_cast<CEFBridgeBrowserRef>(browserHandle);

  BridgeMessageProbe cameraProbe;
  cameraProbe.expectation = [self expectationWithDescription:@"bridge camera routing helper message"];
  CEFBridge_SetCameraRoutingEventHandler(browserRef, bridgeMessageCallback, &cameraProbe);

  CEFBridgeTestBrowserBridgeMessageHandlerForBrowser(
    browserRef,
    MiumCEFCameraRoutingEventChannel,
    MiumCEFResultOK,
    "{\"event\":\"track-started\"}"
  );
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];

  XCTAssertEqual(cameraProbe.messages.size(), static_cast<size_t>(1));
  XCTAssertEqual(cameraProbe.messages[0], "{\"event\":\"track-started\"}");

  CEFBridge_CloseBrowser(browserRef);
  CEFBridgeTestBrowserBridgeMessageHandlerForBrowser(
    browserRef,
    MiumCEFCameraRoutingEventChannel,
    MiumCEFResultOK,
    "{\"event\":\"track-stopped\"}"
  );
  XCTAssertEqual(cameraProbe.messages.size(), static_cast<size_t>(1));
}

- (void)testCEFBridgeTestingFailureModesCoverRemainingPathBranches {
  const std::string expectedRuntimeRoot = CEFBridgeTestNormalizeCPath("/tmp/plain-runtime-root");
  XCTAssertEqual(CEFBridgeTestResolveRuntimeRoot("/tmp/plain-runtime-root"), expectedRuntimeRoot);

  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::normalizeStandardizeReturnsNil);
  XCTAssertTrue(CEFBridgeTestNormalizeCPath("/tmp/normalize-nil").empty());

  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::normalizeUTF8ReturnsNull);
  XCTAssertTrue(CEFBridgeTestNormalizeCPath("/tmp/utf8-null").empty());

  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::bundlePathReturnsNil);
  XCTAssertTrue(CEFBridgeTestResolveRuntimeRoot(nullptr).empty());
  XCTAssertEqual(CEFBridge_Initialize(nullptr, nullptr, nullptr, nullptr), 0);

  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::bundleFileSystemRepresentationReturnsNull);
  XCTAssertTrue(CEFBridgeTestResolveRuntimeRoot(nullptr).empty());

  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::none);
}

- (void)testCEFBridgeCreateBrowserExplicitURLAndNativeFailurePaths {
  char invalidUTF8[] = { static_cast<char>(0xFF), 0 };
  XCTAssertEqual(CEFBridge_Initialize(invalidUTF8, nullptr, nullptr, nullptr), 0);

  FakeCefLibrary library = [self buildFakeCefLibraryVariant:@"default"];
  NSString* cachePath = [[self temporaryDirectory] stringByAppendingPathComponent:@"cef-cache"];
  NSString* helperExecutable = [[[[library.runtimeRoot stringByAppendingPathComponent:@"Contents/Frameworks/Navigator Helper.app/Contents"] stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:@"Navigator Helper"] stringByStandardizingPath];

  XCTAssertEqual(CEFBridge_Initialize(library.metadataPath.UTF8String, nullptr, cachePath.UTF8String, helperExecutable.UTF8String), 1);

  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createBrowserSync = fakeCreateBrowserSync;
  api.shutdown = fakeShutdown;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  FakeCreateBrowserFactory factory;
  gCreateBrowserFactory = &factory;
  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];
  CEFBridgeBrowserRef browserRef = CEFBridge_CreateBrowser((__bridge void*)hostView, "https://explicit.example", 120, 80, 2.0);
  XCTAssertNotEqual(browserRef, nullptr);
  XCTAssertEqual(factory.callCount, 1);
  XCTAssertEqual(factory.lastURL, "about:blank");
  XCTAssertTrue(factory.createdBrowsers.back()->frame->lastLoadedURL.empty());
  CEFBridge_LoadUrl(browserRef, "https://explicit.example");
  XCTAssertEqual(factory.createdBrowsers.back()->frame->lastLoadedURL, "https://explicit.example");

  CEFBridge_CloseBrowser(browserRef);
  miumNativeCEFTestResetState();
  FakeBrowserHarness::resetRetainedHarnesses();
  XCTAssertEqual(CEFBridge_CreateBrowser((__bridge void*)hostView, nullptr, 120, 80, 2.0), nullptr);
  CEFBridge_Shutdown();
}

- (void)testCEFBridgeAdditionalCoveragePaths {
  const std::string emptyString;
  const std::string fallbackRuntimeRoot = CEFBridgeTestResolveRuntimeRoot(nullptr);
  XCTAssertFalse(CEFBridgeTestIsCefSubprocessArgv(1, nullptr));
  XCTAssertEqual(CEFBridge_MaybeRunSubprocess(1, nullptr), -1);

  XCTAssertEqual(CEFBridgeTestResolveRuntimeRoot(""), fallbackRuntimeRoot);
  XCTAssertTrue(CEFBridgeTestResolveMetadataPath("") == emptyString);

  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::resourcesFileSystemRepresentationReturnsNull);
  XCTAssertEqual(CEFBridgeTestResolveRuntimeRoot("/tmp/resources-root/Contents/Resources"), fallbackRuntimeRoot);

  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::resourcesFileSystemRepresentationReturnsEmpty);
  XCTAssertEqual(CEFBridgeTestResolveRuntimeRoot("/tmp/resources-root/Contents/Resources"), fallbackRuntimeRoot);

  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::bundleFileSystemRepresentationReturnsEmpty);
  XCTAssertTrue(CEFBridgeTestResolveRuntimeRoot(nullptr).empty());

  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::none);

  FakeCefLibrary library = [self buildFakeCefLibraryVariant:@"default"];
  NSString* cachePath = [[self temporaryDirectory] stringByAppendingPathComponent:@"cef-cache"];
  NSString* helperExecutable = [[[[library.runtimeRoot stringByAppendingPathComponent:@"Contents/Frameworks/Navigator Helper.app/Contents"] stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:@"Navigator Helper"] stringByStandardizingPath];

  MiumCEFBridgeTestAPI browserAPI{};
  browserAPI.utf8ToUTF16 = fakeUTF8ToUTF16;
  browserAPI.utf16Clear = fakeUTF16Clear;
  browserAPI.createBrowserSync = fakeCreateBrowserSync;
  browserAPI.shutdown = fakeShutdown;
  miumNativeCEFTestInstallAPI(&browserAPI);

  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];
  XCTAssertEqual(CEFBridge_CreateBrowser((__bridge void*)hostView, nullptr, 120, 80, 2.0), nullptr);

  XCTAssertEqual(CEFBridge_Initialize(library.metadataPath.UTF8String, nullptr, "", ""), 1);
  XCTAssertEqual(std::getenv("MIUM_CEF_ROOT_CACHE_PATH"), nullptr);
  XCTAssertEqual(std::getenv("MIUM_CEF_BROWSER_SUBPROCESS_PATH"), nullptr);
  CEFBridge_Shutdown();
  CEFBridgeTestResetState();
  miumNativeCEFTestResetState();

  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::initializeReturnsOKWithNullRuntime);
  XCTAssertEqual(CEFBridge_Initialize(library.metadataPath.UTF8String, nullptr, cachePath.UTF8String, helperExecutable.UTF8String), 0);
  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::none);
  CEFBridgeTestResetState();
  miumNativeCEFTestResetState();

  XCTAssertEqual(CEFBridge_Initialize(library.metadataPath.UTF8String, nullptr, cachePath.UTF8String, helperExecutable.UTF8String), 1);
  miumNativeCEFTestInstallAPI(&browserAPI);
  miumNativeCEFTestSetInitialized(true, 1);

  FakeCreateBrowserFactory factory;
  gCreateBrowserFactory = &factory;
  CEFBridgeBrowserRef browserRef = CEFBridge_CreateBrowser((__bridge void*)hostView, nullptr, 120, 80, 2.0);
  XCTAssertNotEqual(browserRef, nullptr);
  auto* createdHost = factory.createdBrowsers.back()->host;

  CEFBridge_ResizeBrowser(browserRef, 10, 0, 2.0);
  XCTAssertEqual(createdHost->notifyMoveOrResizeStartedCalls, 0);

  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::createBrowserReturnsOKWithNullHandle);
  XCTAssertEqual(CEFBridge_CreateBrowser((__bridge void*)hostView, nullptr, 120, 80, 2.0), nullptr);

  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::createHostViewReturnsOKWithNullHandle);
  XCTAssertEqual(CEFBridge_CreateBrowser((__bridge void*)hostView, nullptr, 120, 80, 2.0), nullptr);
  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::none);

  BridgeMessageProbe messageProbe;
  messageProbe.expectation = [self expectationWithDescription:@"bridge coverage delivery"];

  CEFBridgeTestSetBrowserBridgeMessageHandler(browserRef, nullptr, bridgeMessageCallback, &messageProbe);
  CEFBridgeTestSetBrowserBridgeMessageHandler(nullptr, MiumCEFAddressChangeChannel, nullptr, nullptr);
  CEFBridgeTestSetBrowserBridgeMessageHandler(browserRef, MiumCEFAddressChangeChannel, bridgeMessageCallback, &messageProbe);

  CEFBridgeTestBrowserBridgeMessageHandlerForBrowser(browserRef, nullptr, MiumCEFResultOK, "ignored");
  CEFBridgeTestBrowserBridgeMessageHandlerForBrowser(browserRef, MiumCEFAddressChangeChannel, MiumCEFResultError, "ignored");
  XCTAssertEqual(messageProbe.messages.size(), static_cast<size_t>(0));

  CEFBridgeTestInstallRawMessageHandlerState(browserRef, MiumCEFAddressChangeChannel, nullptr, &messageProbe);
  CEFBridgeTestBrowserBridgeMessageHandlerForBrowser(browserRef, MiumCEFAddressChangeChannel, MiumCEFResultOK, "ignored");
  XCTAssertEqual(messageProbe.messages.size(), static_cast<size_t>(0));

  CEFBridgeTestSetBrowserBridgeMessageHandler(browserRef, MiumCEFAddressChangeChannel, bridgeMessageCallback, &messageProbe);
  CEFBridgeTestBrowserBridgeMessageHandlerForBrowser(browserRef, MiumCEFAddressChangeChannel, MiumCEFResultOK, "delivered");

  CEFBridgeTestForwardJavaScriptResult(MiumCEFResultOK, "ignored", nullptr, &messageProbe, false);

  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(messageProbe.messages.size(), static_cast<size_t>(1));
  XCTAssertEqual(messageProbe.messages[0], "delivered");

  CEFBridge_CloseBrowser(browserRef);
  CEFBridgeTestSetBridgeRuntimeState(nullptr, true);
  CEFBridge_Shutdown();
  CEFBridgeTestResetState();
}

- (void)testExecuteJavaScriptInRendererWrapperUsesRendererProcessMessaging {
  FakeCefLibrary library = [self buildFakeCefLibraryVariant:@"default"];
  NSString* cachePath = [[self temporaryDirectory] stringByAppendingPathComponent:@"cef-cache-renderer-script"];
  NSString* helperExecutable = [[[[library.runtimeRoot stringByAppendingPathComponent:@"Contents/Frameworks/Navigator Helper.app/Contents"] stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:@"Navigator Helper"] stringByStandardizingPath];

  XCTAssertEqual(CEFBridge_Initialize(library.metadataPath.UTF8String, nullptr, cachePath.UTF8String, helperExecutable.UTF8String), 1);

  MiumCEFBridgeTestAPI browserAPI{};
  browserAPI.utf8ToUTF16 = fakeUTF8ToUTF16;
  browserAPI.utf16Clear = fakeUTF16Clear;
  browserAPI.createBrowserSync = fakeCreateBrowserSync;
  browserAPI.createProcessMessage = fakeCreateProcessMessage;
  browserAPI.shutdown = fakeShutdown;
  miumNativeCEFTestInstallAPI(&browserAPI);
  miumNativeCEFTestSetInitialized(true, 1);

  FakeProcessMessageFactory messageFactory;
  gProcessMessageFactory = &messageFactory;
  FakeCreateBrowserFactory factory;
  gCreateBrowserFactory = &factory;

  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];
  const CEFBridgeBrowserRef browserRef = CEFBridge_CreateBrowser((__bridge void*)hostView, nullptr, 120, 80, 2.0);
  XCTAssertNotEqual(browserRef, nullptr);
  auto* createdBrowser = factory.createdBrowsers.back().get();
  createdBrowser->backing->v8Value->stringValue = "renderer-result";

  BridgeJavaScriptProbe probe;
  probe.expectation = [self expectationWithDescription:@"renderer javascript callback"];
  CEFBridge_ExecuteJavaScriptInRendererWithResult(
    browserRef,
    "window.rendererBridge = true;",
    bridgeJavaScriptCallback,
    &probe
  );

  XCTAssertEqual(messageFactory.lastCreatedName, MiumCEFRendererExecuteJavaScriptChannel);
  XCTAssertEqual(createdBrowser->frame->sendProcessMessageCalls, 1);
  XCTAssertNotEqual(createdBrowser->frame->lastMessage, nullptr);
  XCTAssertEqual(createdBrowser->frame->lastMessage->arguments.values.size(), static_cast<size_t>(2));
  XCTAssertEqual(createdBrowser->frame->lastMessage->lifetime.finalReleaseCount.load(std::memory_order_relaxed), 0);
  XCTAssertEqual(createdBrowser->frame->lastMessage->lifetime.refCount.load(std::memory_order_relaxed), 1);
  const std::string requestID = createdBrowser->frame->lastMessage->arguments.values[0];
  const std::string rendererScript = createdBrowser->frame->lastMessage->arguments.values[1];
  XCTAssertEqual(rendererScript, "window.rendererBridge = true;");
  XCTAssertTrue(
    miumNativeCEFTestHandleRendererExecuteJavaScriptRequestMessage(
      &createdBrowser->frame->frame,
      MiumCEFRendererExecuteJavaScriptChannel,
      requestID.c_str(),
      rendererScript.c_str()
    )
  );
  XCTAssertEqual(createdBrowser->frame->sendProcessMessageCalls, 2);
  XCTAssertNotEqual(createdBrowser->frame->lastMessage, nullptr);
  XCTAssertEqual(createdBrowser->frame->lastMessage->name, MiumCEFRendererExecuteJavaScriptResultChannel);
  XCTAssertEqual(createdBrowser->frame->lastMessage->arguments.values.size(), static_cast<size_t>(3));
  XCTAssertEqual(createdBrowser->frame->lastMessage->lifetime.finalReleaseCount.load(std::memory_order_relaxed), 0);
  XCTAssertEqual(createdBrowser->frame->lastMessage->lifetime.refCount.load(std::memory_order_relaxed), 1);
  XCTAssertTrue(
    miumNativeCEFTestHandleRendererExecuteJavaScriptResultMessage(
      createdBrowser->browserRef(),
      MiumCEFRendererExecuteJavaScriptResultChannel,
      createdBrowser->frame->lastMessage->arguments.values[0].c_str(),
      createdBrowser->frame->lastMessage->arguments.values[1].c_str(),
      createdBrowser->frame->lastMessage->arguments.values[2].c_str()
    )
  );

  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(probe.result, "renderer-result");
  XCTAssertEqual(probe.error, "");

  CEFBridge_CloseBrowser(browserRef);
  CEFBridge_Shutdown();
}

- (void)testExecuteJavaScriptInRendererWrapperFailsPendingCallbackWhenBrowserCloses {
  FakeCefLibrary library = [self buildFakeCefLibraryVariant:@"default"];
  NSString* cachePath = [[self temporaryDirectory] stringByAppendingPathComponent:@"cef-cache-renderer-close"];
  NSString* helperExecutable = [[[[library.runtimeRoot stringByAppendingPathComponent:@"Contents/Frameworks/Navigator Helper.app/Contents"] stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:@"Navigator Helper"] stringByStandardizingPath];

  XCTAssertEqual(CEFBridge_Initialize(library.metadataPath.UTF8String, nullptr, cachePath.UTF8String, helperExecutable.UTF8String), 1);

  MiumCEFBridgeTestAPI browserAPI{};
  browserAPI.utf8ToUTF16 = fakeUTF8ToUTF16;
  browserAPI.utf16Clear = fakeUTF16Clear;
  browserAPI.createBrowserSync = fakeCreateBrowserSync;
  browserAPI.createProcessMessage = fakeCreateProcessMessage;
  browserAPI.shutdown = fakeShutdown;
  miumNativeCEFTestInstallAPI(&browserAPI);
  miumNativeCEFTestSetInitialized(true, 1);

  FakeProcessMessageFactory messageFactory;
  gProcessMessageFactory = &messageFactory;
  FakeCreateBrowserFactory factory;
  gCreateBrowserFactory = &factory;

  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];
  const CEFBridgeBrowserRef browserRef = CEFBridge_CreateBrowser((__bridge void*)hostView, nullptr, 120, 80, 2.0);
  XCTAssertNotEqual(browserRef, nullptr);
  auto* createdBrowser = factory.createdBrowsers.back().get();
  createdBrowser->backing->v8Value->stringValue = "renderer-result";

  BridgeJavaScriptProbe probe;
  probe.expectation = [self expectationWithDescription:@"renderer javascript close failure"];
  CEFBridge_ExecuteJavaScriptInRendererWithResult(
    browserRef,
    "window.rendererBridge = true;",
    bridgeJavaScriptCallback,
    &probe
  );

  XCTAssertEqual(messageFactory.lastCreatedName, MiumCEFRendererExecuteJavaScriptChannel);
  const MiumCEFBrowserHandle browserHandle = reinterpret_cast<MiumCEFBrowserHandle>(browserRef);
  uint64_t runtimeId = 0;
  cef_browser_t* detachedBrowser = nullptr;
  cef_client_t* detachedClient = nullptr;
  XCTAssertEqual(
    miumNativeCEFTestBeginClosingNativeBrowser(
      browserHandle,
      false,
      true,
      &runtimeId,
      &detachedBrowser,
      &detachedClient
    ),
    MiumCEFBridgeTestBrowserCloseDisposition::closePending
  );
  if (detachedBrowser != nullptr && detachedBrowser->base.release != nullptr) {
    detachedBrowser->base.release(&detachedBrowser->base);
  }
  if (detachedClient != nullptr && detachedClient->base.release != nullptr) {
    detachedClient->base.release(&detachedClient->base);
  }
  miumNativeCEFTestFinalizeClosedBrowserState(
    browserHandle,
    reinterpret_cast<MiumCEFRuntimeHandle>(static_cast<uintptr_t>(runtimeId))
  );
  [self drainPendingAsyncWork];

  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(probe.invocationCount, 1);
  XCTAssertEqual(probe.result, "");
  XCTAssertEqual(probe.error, "Browser closed before renderer JavaScript completed");

  CEFBridge_Shutdown();
}

- (void)testExecuteJavaScriptInRendererWrapperFailsPendingCallbackWhenRendererTerminates {
  FakeCefLibrary library = [self buildFakeCefLibraryVariant:@"default"];
  NSString* cachePath = [[self temporaryDirectory] stringByAppendingPathComponent:@"cef-cache-renderer-termination"];
  NSString* helperExecutable = [[[[library.runtimeRoot stringByAppendingPathComponent:@"Contents/Frameworks/Navigator Helper.app/Contents"] stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:@"Navigator Helper"] stringByStandardizingPath];

  XCTAssertEqual(CEFBridge_Initialize(library.metadataPath.UTF8String, nullptr, cachePath.UTF8String, helperExecutable.UTF8String), 1);

  MiumCEFBridgeTestAPI browserAPI{};
  browserAPI.utf8ToUTF16 = fakeUTF8ToUTF16;
  browserAPI.utf16Clear = fakeUTF16Clear;
  browserAPI.createBrowserSync = fakeCreateBrowserSync;
  browserAPI.createProcessMessage = fakeCreateProcessMessage;
  browserAPI.shutdown = fakeShutdown;
  miumNativeCEFTestInstallAPI(&browserAPI);
  miumNativeCEFTestSetInitialized(true, 1);

  FakeProcessMessageFactory messageFactory;
  gProcessMessageFactory = &messageFactory;
  FakeCreateBrowserFactory factory;
  gCreateBrowserFactory = &factory;

  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];
  const CEFBridgeBrowserRef browserRef = CEFBridge_CreateBrowser((__bridge void*)hostView, nullptr, 120, 80, 2.0);
  XCTAssertNotEqual(browserRef, nullptr);
  auto* createdBrowser = factory.createdBrowsers.back().get();
  createdBrowser->backing->v8Value->stringValue = "renderer-result";

  BridgeJavaScriptProbe probe;
  probe.expectation = [self expectationWithDescription:@"renderer javascript termination failure"];
  CEFBridge_ExecuteJavaScriptInRendererWithResult(
    browserRef,
    "window.rendererBridge = true;",
    bridgeJavaScriptCallback,
    &probe
  );

  XCTAssertEqual(messageFactory.lastCreatedName, MiumCEFRendererExecuteJavaScriptChannel);
  miumNativeCEFTestTriggerRenderProcessTerminated(
    createdBrowser->browserRef(),
    TS_PROCESS_CRASHED,
    9,
    "Renderer crashed"
  );

  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(probe.invocationCount, 1);
  XCTAssertEqual(probe.result, "");
  XCTAssertEqual(probe.error, "Renderer process terminated");

  CEFBridge_CloseBrowser(browserRef);
  CEFBridge_Shutdown();
}

- (void)testExecuteJavaScriptInRendererWrapperTimesOutPendingCallbackWhenRendererDoesNotReply {
  FakeCefLibrary library = [self buildFakeCefLibraryVariant:@"default"];
  NSString* cachePath = [[self temporaryDirectory] stringByAppendingPathComponent:@"cef-cache-renderer-timeout"];
  NSString* helperExecutable = [[[[library.runtimeRoot stringByAppendingPathComponent:@"Contents/Frameworks/Navigator Helper.app/Contents"] stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:@"Navigator Helper"] stringByStandardizingPath];

  XCTAssertEqual(CEFBridge_Initialize(library.metadataPath.UTF8String, nullptr, cachePath.UTF8String, helperExecutable.UTF8String), 1);

  MiumCEFBridgeTestAPI browserAPI{};
  browserAPI.utf8ToUTF16 = fakeUTF8ToUTF16;
  browserAPI.utf16Clear = fakeUTF16Clear;
  browserAPI.createBrowserSync = fakeCreateBrowserSync;
  browserAPI.createProcessMessage = fakeCreateProcessMessage;
  browserAPI.shutdown = fakeShutdown;
  miumNativeCEFTestInstallAPI(&browserAPI);
  miumNativeCEFTestSetInitialized(true, 1);
  miumNativeCEFTestSetRendererJavaScriptRequestTimeoutSeconds(0.01);

  FakeProcessMessageFactory messageFactory;
  gProcessMessageFactory = &messageFactory;
  FakeCreateBrowserFactory factory;
  gCreateBrowserFactory = &factory;

  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];
  const CEFBridgeBrowserRef browserRef = CEFBridge_CreateBrowser((__bridge void*)hostView, nullptr, 120, 80, 2.0);
  XCTAssertNotEqual(browserRef, nullptr);

  BridgeJavaScriptProbe probe;
  probe.expectation = [self expectationWithDescription:@"renderer javascript timeout failure"];
  CEFBridge_ExecuteJavaScriptInRendererWithResult(
    browserRef,
    "window.rendererBridge = true;",
    bridgeJavaScriptCallback,
    &probe
  );

  XCTAssertEqual(messageFactory.lastCreatedName, MiumCEFRendererExecuteJavaScriptChannel);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(probe.invocationCount, 1);
  XCTAssertEqual(probe.result, "");
  XCTAssertEqual(probe.error, "Renderer JavaScript timed out");

  CEFBridge_CloseBrowser(browserRef);
  CEFBridge_Shutdown();
}

- (void)testCEFBridgeTestingHookNegativePaths {
  CEFBridgeTestInstallRawMessageHandlerState(nullptr, MiumCEFAddressChangeChannel, bridgeMessageCallback, nullptr);
  CEFBridgeTestInstallRawMessageHandlerState(
    reinterpret_cast<CEFBridgeBrowserRef>(static_cast<uintptr_t>(0x1)),
    nullptr,
    bridgeMessageCallback,
    nullptr
  );

  NSString* cachePath = [[self temporaryDirectory] stringByAppendingPathComponent:@"cef-cache-negative"];
  FakeCefLibrary failingInitializeLibrary = [self buildFakeCefLibraryVariant:@"initialize-false"];
  NSString* failingHelperExecutable = [[[[failingInitializeLibrary.runtimeRoot stringByAppendingPathComponent:@"Contents/Frameworks/Navigator Helper.app/Contents"] stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:@"Navigator Helper"] stringByStandardizingPath];

  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::initializeReturnsOKWithNullRuntime);
  XCTAssertEqual(
    CEFBridge_Initialize(
      failingInitializeLibrary.metadataPath.UTF8String,
      nullptr,
      cachePath.UTF8String,
      failingHelperExecutable.UTF8String
    ),
    0
  );
  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::none);

  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];
  CEFBridgeTestSetBridgeRuntimeState(reinterpret_cast<MiumCEFRuntimeHandle>(static_cast<uintptr_t>(0x1)), true);
  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::createBrowserReturnsOKWithNullHandle);
  XCTAssertEqual(CEFBridge_CreateBrowser((__bridge void*)hostView, nullptr, 120, 80, 2.0), nullptr);
  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::none);
  CEFBridgeTestResetState();
  miumNativeCEFTestResetState();

  FakeCefLibrary library = [self buildFakeCefLibraryVariant:@"default"];
  NSString* helperExecutable = [[[[library.runtimeRoot stringByAppendingPathComponent:@"Contents/Frameworks/Navigator Helper.app/Contents"] stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:@"Navigator Helper"] stringByStandardizingPath];
  XCTAssertEqual(CEFBridge_Initialize(library.metadataPath.UTF8String, nullptr, cachePath.UTF8String, helperExecutable.UTF8String), 1);

  MiumCEFBridgeTestAPI failureAPI{};
  failureAPI.utf8ToUTF16 = fakeUTF8ToUTF16;
  failureAPI.utf16Clear = fakeUTF16Clear;
  failureAPI.shutdown = fakeShutdown;
  miumNativeCEFTestInstallAPI(&failureAPI);
  miumNativeCEFTestSetInitialized(true, 1);

  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::createHostViewReturnsOKWithNullHandle);
  XCTAssertEqual(CEFBridge_CreateBrowser((__bridge void*)hostView, nullptr, 120, 80, 2.0), nullptr);
  CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode::none);
}

@end
