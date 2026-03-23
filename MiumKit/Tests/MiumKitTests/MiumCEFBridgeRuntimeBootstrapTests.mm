#import "MiumCEFBridgeNativeTestSupport.h"

using namespace MiumCEFBridgeNativeTestSupport;

@interface MiumCEFBridgeRuntimeBootstrapTests : MiumCEFBridgeNativeTestCase
@end

@implementation MiumCEFBridgeRuntimeBootstrapTests

- (void)testIsLoadedReflectsInjectedFrameworkState {
  XCTAssertFalse(miumNativeCEFIsLoaded());

  miumNativeCEFTestSetFrameworkLoaded(true);
  XCTAssertTrue(miumNativeCEFIsLoaded());

  miumNativeCEFTestSetFrameworkLoaded(false);
  XCTAssertFalse(miumNativeCEFIsLoaded());
}

- (void)testMaybeRunSubprocessRejectsInvalidArguments {
  XCTAssertEqual(miumNativeCEFMaybeRunSubprocess(0, nullptr), -1);
}

- (void)testMaybeRunSubprocessUsesInjectedExecuteProcess {
  MiumCEFBridgeTestAPI api{};
  api.executeProcess = fakeExecuteProcess;
  miumNativeCEFTestInstallAPI(&api);
  gExecuteProcessReturnCode = 27;
  const char* arguments[] = { "navigator", "--type=renderer" };

  const int result = miumNativeCEFMaybeRunSubprocess(2, arguments);

  XCTAssertEqual(result, 27);
  XCTAssertEqual(gExecuteProcessCalls, 1);
  XCTAssertEqual(gExecuteProcessLastArgc, 2);
  XCTAssertTrue(gExecuteProcessLastHadApplication);
  XCTAssertFalse(gExecuteProcessLastAppHasBrowserProcessHandler);
  XCTAssertFalse(gExecuteProcessLastAppHasScheduleMessagePumpWork);
  XCTAssertTrue(gExecuteProcessLastAppHasRenderProcessHandler);
  XCTAssertTrue(gExecuteProcessLastAppHasProcessMessageReceivedHandler);
}

- (void)testMaybeRunSubprocessLoadsFrameworkFromTestCandidatesOffMainThread {
  FakeCefLibrary library = [self buildFakeCefLibraryVariant:@"default"];
  miumNativeCEFTestSetSubprocessFrameworkCandidates({ std::string(library.frameworkPath.UTF8String) });
  const char* arguments[] = { "navigator", "--type=renderer" };
  __block MaybeRunSubprocessContext invocation;
  invocation.argc = 2;
  invocation.argv = arguments;

  [self runOnBackgroundQueueAndWait:^{
    runMaybeRunSubprocess(&invocation);
  }];

  XCTAssertEqual(invocation.result, -1);
  XCTAssertTrue(miumNativeCEFIsLoaded());
  miumNativeCEFTestSetSubprocessFrameworkCandidates({});
}

- (void)testMaybeRunSubprocessAttemptsFrameworkBootstrapWhenExecuteProcessIsUnavailable {
  const char* arguments[] = { "navigator", "--type=renderer" };
  XCTAssertEqual(miumNativeCEFMaybeRunSubprocess(2, arguments), -1);
}

- (void)testRendererExecuteJavaScriptMessageRunsOnMainFrame {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.userfreeFree = fakeUserFreeUTF16Free;
  api.createProcessMessage = fakeCreateProcessMessage;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);
  FakeProcessMessageFactory messageFactory;
  gProcessMessageFactory = &messageFactory;
  FakeBrowserHarness browserHarness;
  browserHarness.backing->v8Value->stringValue = "handled";

  XCTAssertTrue(
    miumNativeCEFTestHandleRendererExecuteJavaScriptRequestMessage(
      &browserHarness.frame->frame,
      MiumCEFRendererExecuteJavaScriptChannel,
      "42",
      "window.rendererBridge = true;"
    )
  );
  XCTAssertEqual(browserHarness.backing->v8Context->lastEvaluatedScript, "window.rendererBridge = true;");
  XCTAssertEqual(browserHarness.frame->sendProcessMessageCalls, 1);
  XCTAssertNotEqual(browserHarness.frame->lastMessage, nullptr);
  XCTAssertEqual(browserHarness.frame->lastMessage->name, MiumCEFRendererExecuteJavaScriptResultChannel);
  XCTAssertEqual(browserHarness.frame->lastMessage->arguments.values[0], "42");
  XCTAssertEqual(browserHarness.frame->lastMessage->arguments.values[1], "handled");
  XCTAssertEqual(browserHarness.frame->lastMessage->arguments.values[2], "");
}

- (void)testRendererExecuteJavaScriptMessageRejectsUnknownChannelAndNonMainFrame {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.userfreeFree = fakeUserFreeUTF16Free;
  api.createProcessMessage = fakeCreateProcessMessage;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);
  FakeProcessMessageFactory messageFactory;
  gProcessMessageFactory = &messageFactory;
  FakeBrowserHarness browserHarness;

  XCTAssertFalse(
    miumNativeCEFTestHandleRendererExecuteJavaScriptRequestMessage(
      &browserHarness.frame->frame,
      MiumCEFAddressChangeChannel,
      "1",
      "window.rendererBridge = true;"
    )
  );
  XCTAssertEqual(browserHarness.backing->v8Context->lastEvaluatedScript, "");

  browserHarness.frame->isMainResult = 0;
  XCTAssertTrue(
    miumNativeCEFTestHandleRendererExecuteJavaScriptRequestMessage(
      &browserHarness.frame->frame,
      MiumCEFRendererExecuteJavaScriptChannel,
      "1",
      "window.rendererBridge = false;"
    )
  );
  XCTAssertEqual(browserHarness.backing->v8Context->lastEvaluatedScript, "");
  XCTAssertNotEqual(browserHarness.frame->lastMessage, nullptr);
  XCTAssertEqual(browserHarness.frame->lastMessage->arguments.values[0], "1");
  XCTAssertEqual(browserHarness.frame->lastMessage->arguments.values[1], "");
  XCTAssertEqual(browserHarness.frame->lastMessage->arguments.values[2], "Renderer frame is not the main frame");
}

- (void)testRendererExecuteJavaScriptMessageReportsEvaluationErrors {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.userfreeFree = fakeUserFreeUTF16Free;
  api.createProcessMessage = fakeCreateProcessMessage;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);
  FakeProcessMessageFactory messageFactory;
  gProcessMessageFactory = &messageFactory;
  FakeBrowserHarness browserHarness;
  browserHarness.backing->v8Context->nextEvalSucceeds = false;
  browserHarness.backing->v8Exception->message = "Renderer exploded";

  XCTAssertTrue(
    miumNativeCEFTestHandleRendererExecuteJavaScriptRequestMessage(
      &browserHarness.frame->frame,
      MiumCEFRendererExecuteJavaScriptChannel,
      "7",
      "window.rendererBridge = false;"
    )
  );
  XCTAssertEqual(browserHarness.backing->v8Context->lastEvaluatedScript, "window.rendererBridge = false;");
  XCTAssertNotEqual(browserHarness.frame->lastMessage, nullptr);
  XCTAssertEqual(browserHarness.frame->lastMessage->arguments.values[0], "7");
  XCTAssertEqual(browserHarness.frame->lastMessage->arguments.values[1], "");
  XCTAssertEqual(browserHarness.frame->lastMessage->arguments.values[2], "Renderer exploded");
}

- (void)testRendererManagedCameraFrameMessageRunsOnMainFrame {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.userfreeFree = fakeUserFreeUTF16Free;
  api.createProcessMessage = fakeCreateProcessMessage;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);
  FakeBrowserHarness browserHarness;

  XCTAssertTrue(
    miumNativeCEFTestHandleRendererManagedCameraFrameMessage(
      &browserHarness.frame->frame,
      MiumCEFCameraFrameDeliveryChannel,
      "{\"sequence\":7,\"width\":640,\"height\":480,\"imageDataURL\":\"data:image/jpeg;base64,Zm9v\"}"
    )
  );
  XCTAssertTrue(browserHarness.backing->v8Context->lastEvaluatedScript.find("shim.receiveFrame(") != std::string::npos);
  XCTAssertTrue(browserHarness.backing->v8Context->lastEvaluatedScript.find("\"sequence\":7") != std::string::npos);
  XCTAssertEqual(browserHarness.frame->sendProcessMessageCalls, 0);
}

- (void)testRendererManagedCameraClearMessageRunsOnMainFrame {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.userfreeFree = fakeUserFreeUTF16Free;
  api.createProcessMessage = fakeCreateProcessMessage;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);
  FakeBrowserHarness browserHarness;

  XCTAssertTrue(
    miumNativeCEFTestHandleRendererManagedCameraFrameMessage(
      &browserHarness.frame->frame,
      MiumCEFCameraFrameClearChannel,
      "{}"
    )
  );
  XCTAssertTrue(browserHarness.backing->v8Context->lastEvaluatedScript.find("shim.clearFrame()") != std::string::npos);
  XCTAssertEqual(browserHarness.frame->sendProcessMessageCalls, 0);
}

- (void)testRendererManagedCameraConfigUpdateMessageRunsOnMainFrame {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.userfreeFree = fakeUserFreeUTF16Free;
  api.createProcessMessage = fakeCreateProcessMessage;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);
  FakeBrowserHarness browserHarness;

  XCTAssertTrue(
    miumNativeCEFTestHandleRendererManagedCameraConfigMessage(
      &browserHarness.frame->frame,
      MiumCEFCameraRoutingConfigUpdateChannel,
      "{\"preferredFilterPreset\":\"supergold\",\"routingEnabled\":true}"
    )
  );
  XCTAssertTrue(browserHarness.backing->v8Context->lastEvaluatedScript.find("shim.applyConfig(") != std::string::npos);
  XCTAssertTrue(browserHarness.backing->v8Context->lastEvaluatedScript.find("\"preferredFilterPreset\":\"supergold\"") != std::string::npos);
  XCTAssertEqual(browserHarness.frame->sendProcessMessageCalls, 0);
}

- (void)testRendererCameraRoutingEventBridgeInstallsFunctionOnMainFrame {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createV8Function = fakeCreateV8Function;
  api.currentV8Context = fakeCurrentV8Context;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);
  FakeBrowserHarness browserHarness;

  XCTAssertTrue(
    miumNativeCEFTestInstallRendererCameraRoutingEventBridge(
      &browserHarness.frame->frame,
      &browserHarness.backing->v8Context->context
    )
  );

  const auto propertyIterator = browserHarness.backing->globalV8Value->keyedValues.find(
    MiumCEFCameraRoutingEventBridgeFunctionName
  );
  XCTAssertNotEqual(propertyIterator, browserHarness.backing->globalV8Value->keyedValues.end());
  XCTAssertNotEqual(propertyIterator->second, nullptr);
  XCTAssertEqual(browserHarness.backing->frame->lifetime.refCount.load(std::memory_order_relaxed), 1);
}

- (void)testRendererCameraRoutingEventBridgeFunctionSendsBrowserMessage {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.userfreeFree = fakeUserFreeUTF16Free;
  api.createProcessMessage = fakeCreateProcessMessage;
  api.createV8Function = fakeCreateV8Function;
  api.currentV8Context = fakeCurrentV8Context;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);
  FakeProcessMessageFactory messageFactory;
  gProcessMessageFactory = &messageFactory;
  FakeBrowserHarness browserHarness;

  XCTAssertTrue(
    miumNativeCEFTestInstallRendererCameraRoutingEventBridge(
      &browserHarness.frame->frame,
      &browserHarness.backing->v8Context->context
    )
  );

  browserHarness.backing->v8Value->kind = FakeV8ValueKind::stringValue;
  browserHarness.backing->v8Value->stringValue = "{\"event\":\"track-started\"}";
  const auto propertyIterator = browserHarness.backing->globalV8Value->keyedValues.find(
    MiumCEFCameraRoutingEventBridgeFunctionName
  );
  XCTAssertNotEqual(propertyIterator, browserHarness.backing->globalV8Value->keyedValues.end());
  auto* functionValue = propertyIterator->second;
  XCTAssertNotEqual(functionValue, nullptr);

  gCurrentV8Context = &browserHarness.backing->v8Context->context;
  cef_v8_value_t* arguments[] = { &browserHarness.backing->v8Value->value };
  cef_v8_value_t* retval = functionValue->execute_function(
    functionValue,
    &browserHarness.backing->globalV8Value->value,
    1,
    arguments
  );
  gCurrentV8Context = nullptr;

  XCTAssertEqual(retval, nullptr);
  XCTAssertEqual(browserHarness.frame->sendProcessMessageCalls, 1);
  XCTAssertEqual(browserHarness.frame->lastProcessId, PID_BROWSER);
  XCTAssertNotEqual(browserHarness.frame->lastMessage, nullptr);
  XCTAssertEqual(browserHarness.frame->lastMessage->name, MiumCEFCameraRoutingEventChannel);
  XCTAssertEqual(browserHarness.frame->lastMessage->arguments.values[0], "{\"event\":\"track-started\"}");
  XCTAssertEqual(browserHarness.frame->lastMessage->lifetime.finalReleaseCount.load(std::memory_order_relaxed), 0);
  XCTAssertEqual(browserHarness.frame->lastMessage->lifetime.refCount.load(std::memory_order_relaxed), 1);
  XCTAssertEqual(browserHarness.backing->frame->lifetime.refCount.load(std::memory_order_relaxed), 1);
}

- (void)testRendererCameraRoutingEventBridgeFunctionRejectsInvalidPayloads {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createV8Function = fakeCreateV8Function;
  api.currentV8Context = fakeCurrentV8Context;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);
  FakeBrowserHarness browserHarness;

  XCTAssertTrue(
    miumNativeCEFTestInstallRendererCameraRoutingEventBridge(
      &browserHarness.frame->frame,
      &browserHarness.backing->v8Context->context
    )
  );

  const auto propertyIterator = browserHarness.backing->globalV8Value->keyedValues.find(
    MiumCEFCameraRoutingEventBridgeFunctionName
  );
  XCTAssertNotEqual(propertyIterator, browserHarness.backing->globalV8Value->keyedValues.end());
  auto* functionState = reinterpret_cast<FakeV8ValueState*>(propertyIterator->second);
  XCTAssertNotEqual(functionState, nullptr);
  cef_string_t exception{};
  cef_v8_value_t* retval = nullptr;

  XCTAssertEqual(
    functionState->functionHandler->execute(
      functionState->functionHandler,
      nullptr,
      &browserHarness.backing->globalV8Value->value,
      0,
      nullptr,
      &retval,
      &exception
    ),
    1
  );

  XCTAssertEqual(retval, nullptr);
  XCTAssertEqual(browserHarness.frame->sendProcessMessageCalls, 0);
  XCTAssertEqual(
    stringFromCEFString(&exception),
    "Navigator camera routing event bridge expected a JSON string payload."
  );
  fakeUTF16Clear(&exception);
}

- (void)testDoMessageLoopWorkRequiresInitialization {
  XCTAssertEqual(miumNativeCEFDoMessageLoopWork(), MiumCEFResultNotInitialized);
}

- (void)testDoMessageLoopWorkInvokesBridgeHookWhenInitialized {
  MiumCEFBridgeTestAPI api{};
  api.doMessageLoopWork = fakeDoMessageLoopWork;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  const MiumCEFResultCode result = miumNativeCEFDoMessageLoopWork();

  XCTAssertEqual(result, MiumCEFResultOK);
  XCTAssertEqual(gMessageLoopWorkCalls, 1);
}

- (void)testInstallAPIResetsInitializationState {
  MiumCEFBridgeTestAPI api{};
  api.doMessageLoopWork = fakeDoMessageLoopWork;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  miumNativeCEFTestInstallAPI(&api);

  XCTAssertEqual(miumNativeCEFDoMessageLoopWork(), MiumCEFResultNotInitialized);
  XCTAssertEqual(gMessageLoopWorkCalls, 0);
}

- (void)testInitializeRejectsNilOutputPointerAndFiresEventCallback {
  CallbackProbe probe;
  probe.expectation = [self expectationWithDescription:@"initialize failure event"];

  const MiumCEFResultCode result = miumNativeCEFInitialize("/tmp/runtime", "/tmp/runtime/Resources", testNativeCallback, &probe, nullptr);

  XCTAssertEqual(result, MiumCEFResultInvalidArgument);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(probe.code, MiumCEFResultInvalidArgument);
  XCTAssertEqual(probe.message, "Runtime out pointer is nil");
}

- (void)testInitializeFailsWhenHelperExecutableIsMissing {
  NSString* runtimeRoot = [self temporaryDirectory];
  NSString* metadataPath = [runtimeRoot stringByAppendingPathComponent:@"Contents/Resources"];
  CallbackProbe probe;
  probe.expectation = [self expectationWithDescription:@"missing helper event"];
  MiumCEFRuntimeHandle runtimeHandle = nullptr;

  const MiumCEFResultCode result = miumNativeCEFInitialize(runtimeRoot.UTF8String, metadataPath.UTF8String, testNativeCallback, &probe, &runtimeHandle);

  XCTAssertEqual(result, MiumCEFResultNotInitialized);
  XCTAssertEqual(runtimeHandle, nullptr);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(probe.code, MiumCEFResultNotInitialized);
  XCTAssertTrue(probe.message.find("CEF helper executable unresolved") != std::string::npos);
}

- (void)testBundleAndUserDataOverridesCoverFallbackBranches {
  FakeCefLibrary library = [self buildFakeCefLibraryVariant:@"default"];

  FakeInitializeCapture capture;
  gInitializeCapture = &capture;
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.executeProcess = fakeExecuteProcess;
  api.initialize = fakeInitialize;
  miumNativeCEFTestInstallAPI(&api);

  miumNativeCEFTestSetBundleExecutablePathNil(true);
  std::string failureReason;
  XCTAssertTrue(miumNativeCEFTestEnsureCefInitialized(library.runtimeRoot.UTF8String, library.metadataPath.UTF8String, &failureReason));
  XCTAssertFalse(capture.argv.empty());
  XCTAssertEqual(capture.argv.front(), "Navigator");
  XCTAssertTrue(miumNativeCEFTestHostExecutableBasename().empty());
  XCTAssertFalse(miumNativeCEFTestIsLiveNavigatorProcess(getpid()));
  miumNativeCEFTestSetBundleExecutablePathNil(false);
  miumNativeCEFTestSetBundleExecutablePathOverride("/tmp/Navigator Helper.app/Contents/MacOS/Navigator Helper");
  XCTAssertEqual(miumNativeCEFTestHostExecutableBasename(), "Navigator Helper");

  NSString* cacheRoot = [self temporaryDirectory];
  miumNativeCEFTestSetBundleIdentifierNil(true);
  miumNativeCEFTestSetCachesDirectoryOverride(cacheRoot.UTF8String);
  const std::string defaultBundleCachePath = miumNativeCEFTestResolveCEFUserDataDirectory();
  XCTAssertTrue(defaultBundleCachePath.find("com.mium.desktop") != std::string::npos);
  miumNativeCEFTestSetBundleIdentifierNil(false);
  miumNativeCEFTestSetBundleIdentifierOverride("com.navigator.override");
  XCTAssertTrue(miumNativeCEFTestResolveCEFUserDataDirectory().find("com.navigator.override") != std::string::npos);

  miumNativeCEFTestSetCachesDirectoriesEmpty(true);
  XCTAssertTrue(miumNativeCEFTestResolveCEFUserDataDirectory().empty());

  miumNativeCEFTestSetCachesDirectoriesEmpty(false);
  NSString* brokenCacheRoot = [self temporaryDirectory];
  [self writeText:@"blocker" toPath:[brokenCacheRoot stringByAppendingPathComponent:@"MiumKit"]];
  miumNativeCEFTestSetCachesDirectoryOverride(brokenCacheRoot.UTF8String);
  XCTAssertTrue(miumNativeCEFTestResolveCEFUserDataDirectory().empty());
}

- (void)testFrameworkFallbackAndInterceptedExitCoverBootstrapBranches {
  FakeCefLibrary library = [self buildFakeCefLibraryVariant:@"default"];
  miumNativeCEFTestSetFrameworkFallbackCandidates({ std::string(library.frameworkPath.UTF8String) });
  XCTAssertTrue(miumNativeCEFTestOpenFrameworkIfNeeded({}));
  miumNativeCEFTestResetState();
  FakeBrowserHarness::resetRetainedHarnesses();

  FakeInitializeCapture capture;
  gInitializeCapture = &capture;
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.executeProcess = fakeExecuteProcess;
  api.initialize = fakeInitialize;
  miumNativeCEFTestInstallAPI(&api);
  gExecuteProcessReturnCode = 27;
  miumNativeCEFTestSetInterceptProcessExit(true);

  std::string failureReason;
  XCTAssertFalse(miumNativeCEFTestEnsureCefInitialized(library.runtimeRoot.UTF8String, library.metadataPath.UTF8String, &failureReason));
  XCTAssertEqual(miumNativeCEFTestLastInterceptedProcessExitCode(), 27);
  XCTAssertTrue(failureReason.find("process termination") != std::string::npos);
}

- (void)testEnsureCefInitializedDisablesLoggingByDefaultAndEnablesItViaEnvironment {
  FakeCefLibrary library = [self buildFakeCefLibraryVariant:@"default"];
  ScopedEnvironmentVariable enableLogging("MIUM_CEF_ENABLE_LOGGING");

  FakeInitializeCapture capture;
  gInitializeCapture = &capture;
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.executeProcess = fakeExecuteProcess;
  api.initialize = fakeInitialize;

  miumNativeCEFTestInstallAPI(&api);
  std::string failureReason;
  XCTAssertTrue(miumNativeCEFTestEnsureCefInitialized(library.runtimeRoot.UTF8String, library.metadataPath.UTF8String, &failureReason));
  XCTAssertTrue(failureReason.empty());
  XCTAssertEqual(capture.logSeverity, static_cast<int>(LOGSEVERITY_DISABLE));

  enableLogging.set("1");
  capture = FakeInitializeCapture{};
  gInitializeCapture = &capture;
  miumNativeCEFTestInstallAPI(&api);
  failureReason.clear();
  XCTAssertTrue(miumNativeCEFTestEnsureCefInitialized(library.runtimeRoot.UTF8String, library.metadataPath.UTF8String, &failureReason));
  XCTAssertTrue(failureReason.empty());
  XCTAssertEqual(capture.logSeverity, static_cast<int>(LOGSEVERITY_DEFAULT));
}

- (void)testEnsureCefInitializedWrapperCoversAdditionalConversionFailures {
  FakeCefLibrary library = [self buildFakeCefLibraryVariant:@"default"];
  ScopedEnvironmentVariable rootCacheOverride("MIUM_CEF_ROOT_CACHE_PATH");
  NSString* overrideCachePath = [self temporaryDirectory];
  rootCacheOverride.set(overrideCachePath.UTF8String);

  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16MaybeFail;
  api.utf16Clear = fakeUTF16Clear;
  api.executeProcess = fakeExecuteProcess;
  api.initialize = fakeInitialize;

  std::string failureReason;

  gUTF8ConversionFailureNeedle = [[[library.runtimeRoot stringByAppendingPathComponent:@"Contents/Resources"] stringByStandardizingPath] UTF8String];
  miumNativeCEFTestInstallAPI(&api);
  failureReason.clear();
  XCTAssertFalse(miumNativeCEFTestEnsureCefInitialized(library.runtimeRoot.UTF8String, library.metadataPath.UTF8String, &failureReason));
  XCTAssertTrue(failureReason.find("Failed to convert UTF8 to UTF16") != std::string::npos);

  gUTF8ConversionFailureNeedle.clear();
  api.utf8ToUTF16 = fakeUTF8ToUTF16MaybeFailOnCall;
  miumNativeCEFTestInstallAPI(&api);
  gUTF8ConversionCallCount = 0;
  gUTF8ConversionFailureCallIndex = 3;
  failureReason.clear();
  XCTAssertFalse(miumNativeCEFTestEnsureCefInitialized(library.runtimeRoot.UTF8String, library.metadataPath.UTF8String, &failureReason));
  XCTAssertTrue(failureReason.find("Failed to convert UTF8 to UTF16") != std::string::npos);

  miumNativeCEFTestInstallAPI(&api);
  gUTF8ConversionCallCount = 0;
  gUTF8ConversionFailureCallIndex = 4;
  failureReason.clear();
  XCTAssertFalse(miumNativeCEFTestEnsureCefInitialized(library.runtimeRoot.UTF8String, library.metadataPath.UTF8String, &failureReason));
  XCTAssertTrue(failureReason.find("Failed to convert UTF8 to UTF16") != std::string::npos);

  miumNativeCEFTestInstallAPI(&api);
  gUTF8ConversionCallCount = 0;
  gUTF8ConversionFailureCallIndex = 5;
  failureReason.clear();
  XCTAssertFalse(miumNativeCEFTestEnsureCefInitialized(library.runtimeRoot.UTF8String, library.metadataPath.UTF8String, &failureReason));
  XCTAssertTrue(failureReason.find("Failed to convert UTF8 to UTF16") != std::string::npos);
}

- (void)testInitializeFailureMatrixCoversResourcesLocalesAndFrameworkInitializeFailure {
  NSString* resourcesMissingRoot = [self temporaryDirectory];
  [self createHelperAppInDirectory:[resourcesMissingRoot stringByAppendingPathComponent:@"Contents/Frameworks"]
                              name:@"Navigator Helper"
                    executableName:@"Navigator Helper"
               infoPlistExecutable:nil];

  CallbackProbe resourcesProbe;
  resourcesProbe.expectation = [self expectationWithDescription:@"resources missing"];
  MiumCEFRuntimeHandle resourcesRuntime = reinterpret_cast<MiumCEFRuntimeHandle>(static_cast<uintptr_t>(0x1));
  XCTAssertEqual(
    miumNativeCEFInitialize(
      resourcesMissingRoot.UTF8String,
      [[resourcesMissingRoot stringByAppendingPathComponent:@"Contents/Resources"] UTF8String],
      testNativeCallback,
      &resourcesProbe,
      &resourcesRuntime
    ),
    MiumCEFResultNotInitialized
  );
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertTrue(resourcesProbe.message.find("CEF resources directory missing") != std::string::npos);
  XCTAssertEqual(resourcesRuntime, nullptr);

  NSString* localesMissingRoot = [self temporaryDirectory];
  NSString* localesMetadata = [localesMissingRoot stringByAppendingPathComponent:@"Contents/Resources"];
  [self createDirectoryAtPath:localesMetadata];
  [self createHelperAppInDirectory:[localesMissingRoot stringByAppendingPathComponent:@"Contents/Frameworks"]
                              name:@"Navigator Helper"
                    executableName:@"Navigator Helper"
               infoPlistExecutable:nil];
  [self writeText:@"{\"expectedPaths\":{\"localesRelativePath\":\"Contents/Resources/missing-locales\"}}"
           toPath:[localesMetadata stringByAppendingPathComponent:@"runtime_layout.json"]];

  CallbackProbe localesProbe;
  localesProbe.expectation = [self expectationWithDescription:@"locales missing"];
  MiumCEFRuntimeHandle localesRuntime = reinterpret_cast<MiumCEFRuntimeHandle>(static_cast<uintptr_t>(0x1));
  XCTAssertEqual(
    miumNativeCEFInitialize(
      localesMissingRoot.UTF8String,
      localesMetadata.UTF8String,
      testNativeCallback,
      &localesProbe,
      &localesRuntime
    ),
    MiumCEFResultNotInitialized
  );
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertTrue(localesProbe.message.find("CEF locales directory missing") != std::string::npos);
  XCTAssertEqual(localesRuntime, nullptr);

  FakeCefLibrary failureLibrary = [self buildFakeCefLibraryVariant:@"initialize-false"];
  CallbackProbe initializeProbe;
  initializeProbe.expectation = [self expectationWithDescription:@"initialize false"];
  MiumCEFRuntimeHandle failedRuntime = reinterpret_cast<MiumCEFRuntimeHandle>(static_cast<uintptr_t>(0x1));
  XCTAssertEqual(
    miumNativeCEFInitialize(
      failureLibrary.runtimeRoot.UTF8String,
      failureLibrary.metadataPath.UTF8String,
      testNativeCallback,
      &initializeProbe,
      &failedRuntime
    ),
    MiumCEFResultNotInitialized
  );
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertTrue(initializeProbe.message.find("Failed to initialize CEF runtime. cef_initialize() returned false") != std::string::npos);
  XCTAssertEqual(failedRuntime, nullptr);
}

- (void)testInitializeFailureFromBackgroundQueueUnloadsFrameworkState {
  FakeCefLibrary failureLibrary = [self buildFakeCefLibraryVariant:@"initialize-false"];
  __block MiumCEFResultCode result = MiumCEFResultOK;
  __block MiumCEFRuntimeHandle runtimeHandle = reinterpret_cast<MiumCEFRuntimeHandle>(static_cast<uintptr_t>(0x1));

  [self runOnBackgroundQueueAndWait:^{
    result = miumNativeCEFInitialize(
      failureLibrary.runtimeRoot.UTF8String,
      failureLibrary.metadataPath.UTF8String,
      nullptr,
      nullptr,
      &runtimeHandle
    );
  }];

  XCTAssertEqual(result, MiumCEFResultNotInitialized);
  XCTAssertEqual(runtimeHandle, nullptr);
  XCTAssertFalse(miumNativeCEFIsLoaded());
}

- (void)testInitializeCoversFallbackLocalesFrameworkFailureAndWaitLoop {
  FakeCefLibrary fallbackLibrary = [self buildFakeCefLibraryVariant:@"default"];
  [self writeText:@"{\"expectedPaths\":{\"localesRelativePath\":\"Contents/Resources/missing-locales\"}}"
           toPath:[fallbackLibrary.metadataPath stringByAppendingPathComponent:@"runtime_layout.json"]];

  CallbackProbe fallbackProbe;
  fallbackProbe.expectation = [self expectationWithDescription:@"fallback locales init"];
  MiumCEFRuntimeHandle fallbackRuntime = nullptr;
  XCTAssertEqual(
    miumNativeCEFInitialize(
      fallbackLibrary.runtimeRoot.UTF8String,
      fallbackLibrary.metadataPath.UTF8String,
      testNativeCallback,
      &fallbackProbe,
      &fallbackRuntime
    ),
    MiumCEFResultOK
  );
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertNotEqual(fallbackRuntime, nullptr);
  XCTAssertEqual(miumNativeCEFShutdown(fallbackRuntime), MiumCEFResultOK);

  NSString* noFrameworkRoot = [self temporaryDirectory];
  NSString* noFrameworkMetadata = [noFrameworkRoot stringByAppendingPathComponent:@"Contents/Resources"];
  [self createDirectoryAtPath:[noFrameworkMetadata stringByAppendingPathComponent:@"locales/en.lproj"]];
  [self writeText:@"pak"
           toPath:[[noFrameworkMetadata stringByAppendingPathComponent:@"locales/en.lproj"] stringByAppendingPathComponent:@"locale.pak"]];
  [self createHelperAppInDirectory:[noFrameworkRoot stringByAppendingPathComponent:@"Contents/Frameworks"]
                              name:@"Navigator Helper"
                    executableName:@"Navigator Helper"
               infoPlistExecutable:nil];

  CallbackProbe frameworkFailureProbe;
  frameworkFailureProbe.expectation = [self expectationWithDescription:@"framework load failure"];
  MiumCEFRuntimeHandle missingFrameworkRuntime = nullptr;
  XCTAssertEqual(
    miumNativeCEFInitialize(
      noFrameworkRoot.UTF8String,
      noFrameworkMetadata.UTF8String,
      testNativeCallback,
      &frameworkFailureProbe,
      &missingFrameworkRuntime
    ),
    MiumCEFResultNotInitialized
  );
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertTrue(frameworkFailureProbe.message.find("Candidate paths attempted") != std::string::npos);

  NSString* concurrentRoot = [self temporaryDirectory];
  NSString* concurrentMetadata = [concurrentRoot stringByAppendingPathComponent:@"Contents/Resources"];
  [self createDirectoryAtPath:[concurrentMetadata stringByAppendingPathComponent:@"locales/en.lproj"]];
  [self writeText:@"pak"
           toPath:[[concurrentMetadata stringByAppendingPathComponent:@"locales/en.lproj"] stringByAppendingPathComponent:@"locale.pak"]];
  [self createHelperAppInDirectory:[concurrentRoot stringByAppendingPathComponent:@"Contents/Frameworks"]
                              name:@"Navigator Helper"
                    executableName:@"Navigator Helper"
               infoPlistExecutable:nil];

  void* frameworkHandle = dlopen(nullptr, RTLD_NOW);
  XCTAssertNotEqual(frameworkHandle, nullptr);

  BlockingInitializeState blockingState;
  gBlockingInitializeState = &blockingState;

  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.executeProcess = fakeExecuteProcess;
  api.initialize = slowFakeInitialize;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetFrameworkHandle(frameworkHandle);
  miumNativeCEFTestSetFrameworkLoaded(true);

  __block MiumCEFRuntimeHandle firstRuntime = nullptr;
  __block MiumCEFRuntimeHandle secondRuntime = nullptr;
  __block MiumCEFResultCode firstResult = MiumCEFResultError;
  __block MiumCEFResultCode secondResult = MiumCEFResultError;
  dispatch_group_t group = dispatch_group_create();

  dispatch_group_enter(group);
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    firstResult = miumNativeCEFInitialize(
      concurrentRoot.UTF8String,
      concurrentMetadata.UTF8String,
      nullptr,
      nullptr,
      &firstRuntime
    );
    dispatch_group_leave(group);
  });

  [NSThread sleepForTimeInterval:0.05];

  dispatch_group_enter(group);
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    secondResult = miumNativeCEFInitialize(
      concurrentRoot.UTF8String,
      concurrentMetadata.UTF8String,
      nullptr,
      nullptr,
      &secondRuntime
    );
    dispatch_group_leave(group);
  });

  NSDate* groupDeadline = [NSDate dateWithTimeIntervalSinceNow:kCallbackTimeout];
  while (dispatch_group_wait(group, DISPATCH_TIME_NOW) != 0) {
    if ([groupDeadline timeIntervalSinceNow] <= 0.0) {
      XCTFail(@"Timed out waiting for concurrent initialize calls to complete");
      break;
    }
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }

  XCTAssertEqual(dispatch_group_wait(group, DISPATCH_TIME_NOW), 0L);
  XCTAssertEqual(blockingState.callCount, 1);
  XCTAssertEqual(firstResult, MiumCEFResultOK);
  XCTAssertEqual(secondResult, MiumCEFResultOK);
  XCTAssertNotEqual(firstRuntime, nullptr);
  XCTAssertNotEqual(secondRuntime, nullptr);
  XCTAssertEqual(miumNativeCEFShutdown(secondRuntime), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFShutdown(firstRuntime), MiumCEFResultOK);
}

- (void)testEnsureCefInitializedWrapperCapturesSettingsAndFailures {
  FakeCefLibrary library = [self buildFakeCefLibraryVariant:@"default"];
  ScopedEnvironmentVariable rootCacheOverride("MIUM_CEF_ROOT_CACHE_PATH");
  ScopedEnvironmentVariable mediaStreamOverride("MIUM_CEF_ENABLE_MEDIA_STREAM");
  ScopedEnvironmentVariable gestureAutoplayOverride("MIUM_CEF_REQUIRE_USER_GESTURE_AUTOPLAY");
  ScopedEnvironmentVariable sandboxOverride("MIUM_DISABLE_CEF_SANDBOX");
  NSString* overrideCachePath = [self temporaryDirectory];
  rootCacheOverride.set(overrideCachePath.UTF8String);
  mediaStreamOverride.set("1");
  gestureAutoplayOverride.set(nullptr);
  sandboxOverride.set("1");

  FakeInitializeCapture capture;
  gInitializeCapture = &capture;
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.executeProcess = fakeExecuteProcess;
  api.initialize = fakeInitialize;
  miumNativeCEFTestInstallAPI(&api);
  __block std::string failureReason;
  __block bool ensureInitialized = false;
  XCTestExpectation* expectation = [self expectationWithDescription:@"ensure initialized on background queue"];

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
    ensureInitialized = miumNativeCEFTestEnsureCefInitialized(
      library.runtimeRoot.UTF8String,
      library.metadataPath.UTF8String,
      &failureReason
    );
    [expectation fulfill];
  });
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];

  XCTAssertTrue(ensureInitialized);
  XCTAssertEqual(capture.callCount, 1);
  XCTAssertEqual(capture.lastArgc, 4);
  XCTAssertEqual(capture.multiThreadedMessageLoop, 0);
  XCTAssertEqual(capture.externalMessagePump, 1);
  XCTAssertEqual(capture.noSandbox, 1);
  XCTAssertTrue(capture.lastHadApplication);
  XCTAssertTrue(capture.lastAppHasBrowserProcessHandler);
  XCTAssertTrue(capture.lastAppHasScheduleMessagePumpWork);
  XCTAssertEqual(
    capture.browserSubprocessPath,
    miumNativeCEFTestNormalizePath([[[[library.runtimeRoot stringByAppendingPathComponent:@"Contents/Frameworks/Navigator Helper.app/Contents"] stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:@"Navigator Helper"] UTF8String])
  );
  XCTAssertEqual(capture.resourcesDirPath, miumNativeCEFTestNormalizePath([[library.runtimeRoot stringByAppendingPathComponent:@"Contents/Resources"] UTF8String]));
  XCTAssertFalse(capture.localesDirPath.empty());
  XCTAssertEqual(capture.cachePath, miumNativeCEFTestNormalizePath(overrideCachePath.UTF8String));
  XCTAssertEqual(capture.rootCachePath, miumNativeCEFTestNormalizePath(overrideCachePath.UTF8String));
  XCTAssertFalse(capture.locale.empty());
  XCTAssertFalse(capture.acceptLanguageList.empty());
  XCTAssertEqual(capture.persistSessionCookies, 1);
  XCTAssertTrue(std::find(capture.argv.begin(), capture.argv.end(), "--autoplay-policy=no-user-gesture-required") != capture.argv.end());
  XCTAssertTrue(std::find(capture.argv.begin(), capture.argv.end(), "--use-mock-keychain") != capture.argv.end());
  XCTAssertTrue(std::find(capture.argv.begin(), capture.argv.end(), "--enable-media-stream") != capture.argv.end());

  api.utf8ToUTF16 = failingUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.executeProcess = fakeExecuteProcess;
  api.initialize = fakeInitialize;
  miumNativeCEFTestInstallAPI(&api);
  failureReason.clear();
  XCTAssertFalse(miumNativeCEFTestEnsureCefInitialized(library.runtimeRoot.UTF8String, library.metadataPath.UTF8String, &failureReason));
  XCTAssertTrue(failureReason.find("Failed to convert UTF8 to UTF16") != std::string::npos);

  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.executeProcess = fakeExecuteProcess;
  api.initialize = fakeInitialize;
  miumNativeCEFTestInstallAPI(&api);
  capture.returnValue = 0;
  failureReason.clear();
  XCTAssertFalse(miumNativeCEFTestEnsureCefInitialized(library.runtimeRoot.UTF8String, library.metadataPath.UTF8String, &failureReason));
  XCTAssertTrue(failureReason.find("cef_initialize() returned false") != std::string::npos);
}

- (void)testEnsureCefInitializedSkipsMediaStreamOverrideWhenDevelopmentEligibilityIsDisabled {
  FakeCefLibrary library = [self buildFakeCefLibraryVariant:@"default"];
  ScopedEnvironmentVariable mediaStreamOverride("MIUM_CEF_ENABLE_MEDIA_STREAM", "1");
  miumNativeCEFTestSetMediaStreamOverrideDevelopmentEligible(false);

  FakeInitializeCapture capture;
  gInitializeCapture = &capture;
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.executeProcess = fakeExecuteProcess;
  api.initialize = fakeInitialize;
  miumNativeCEFTestInstallAPI(&api);

  std::string failureReason;
  XCTAssertTrue(miumNativeCEFTestEnsureCefInitialized(
    library.runtimeRoot.UTF8String,
    library.metadataPath.UTF8String,
    &failureReason
  ));
  XCTAssertTrue(failureReason.empty());
  XCTAssertFalse(std::find(capture.argv.begin(), capture.argv.end(), "--enable-media-stream") != capture.argv.end());
  miumNativeCEFTestResetMediaStreamOverrideDevelopmentEligibility();
}

- (void)testEnsureCefInitializedUsesExternalMessagePumpWhenEnabled {
  FakeCefLibrary library = [self buildFakeCefLibraryVariant:@"default"];
  ScopedEnvironmentVariable externalPumpOverride("MIUM_CEF_ENABLE_EXTERNAL_MESSAGE_PUMP");
  externalPumpOverride.set("1");

  FakeInitializeCapture capture;
  gInitializeCapture = &capture;
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.executeProcess = fakeExecuteProcess;
  api.initialize = fakeInitialize;
  miumNativeCEFTestInstallAPI(&api);

  std::string failureReason;
  XCTAssertTrue(miumNativeCEFTestEnsureCefInitialized(library.runtimeRoot.UTF8String, library.metadataPath.UTF8String, &failureReason));
  XCTAssertTrue(failureReason.empty());
  XCTAssertEqual(capture.externalMessagePump, 1);
  XCTAssertTrue(capture.lastHadApplication);
  XCTAssertTrue(capture.lastAppHasBrowserProcessHandler);
  XCTAssertTrue(capture.lastAppHasScheduleMessagePumpWork);
}

- (void)testFrameworkLoadingAndPublicInitializeShutdownIntegration {
  XCTAssertFalse(miumNativeCEFTestOpenFrameworkIfNeeded({}));
  XCTAssertFalse(miumNativeCEFTestLoadRequiredCefSymbols(nullptr));

  FakeCefLibrary mismatchLibrary = [self buildFakeCefLibraryVariant:@"mismatch-hash"];
  mismatchLibrary.handle = dlopen(mismatchLibrary.frameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
  XCTAssertNotEqual(mismatchLibrary.handle, nullptr);
  XCTAssertFalse(miumNativeCEFTestLoadRequiredCefSymbols(mismatchLibrary.handle));
  miumNativeCEFTestResetState();

  FakeCefLibrary missingAPIHashLibrary = [self buildFakeCefLibraryVariant:@"missing-api-hash"];
  missingAPIHashLibrary.handle = dlopen(missingAPIHashLibrary.frameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
  XCTAssertNotEqual(missingAPIHashLibrary.handle, nullptr);
  XCTAssertFalse(miumNativeCEFTestLoadRequiredCefSymbols(missingAPIHashLibrary.handle));
  miumNativeCEFTestResetState();

  FakeCefLibrary missingUTF16ClearLibrary = [self buildFakeCefLibraryVariant:@"missing-utf16-clear"];
  missingUTF16ClearLibrary.handle = dlopen(missingUTF16ClearLibrary.frameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
  XCTAssertNotEqual(missingUTF16ClearLibrary.handle, nullptr);
  XCTAssertFalse(miumNativeCEFTestLoadRequiredCefSymbols(missingUTF16ClearLibrary.handle));
  miumNativeCEFTestResetState();

  FakeCefLibrary missingUTF8Library = [self buildFakeCefLibraryVariant:@"missing-utf8-to-utf16"];
  missingUTF8Library.handle = dlopen(missingUTF8Library.frameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
  XCTAssertNotEqual(missingUTF8Library.handle, nullptr);
  XCTAssertFalse(miumNativeCEFTestLoadRequiredCefSymbols(missingUTF8Library.handle));
  miumNativeCEFTestResetState();

  FakeCefLibrary versionInfoLibrary = [self buildFakeCefLibraryVariant:@"default"];
  versionInfoLibrary.handle = dlopen(versionInfoLibrary.frameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
  XCTAssertNotEqual(versionInfoLibrary.handle, nullptr);
  XCTAssertTrue(miumNativeCEFTestLoadRequiredCefSymbols(versionInfoLibrary.handle));
  void* mallocSymbol = nullptr;
  XCTAssertTrue(miumNativeCEFTestLoadSymbol(RTLD_DEFAULT, "malloc", &mallocSymbol));
  XCTAssertNotEqual(mallocSymbol, nullptr);
  XCTAssertFalse(miumNativeCEFTestLoadSymbol(nullptr, "malloc", &mallocSymbol));
  XCTAssertFalse(miumNativeCEFTestVerifyCefApiCompatibility(nullptr, "hash"));
  XCTAssertFalse(miumNativeCEFTestVerifyCefApiCompatibility("hash", nullptr));
  XCTAssertFalse(miumNativeCEFTestVerifyCefApiCompatibility("a", "b"));
  XCTAssertTrue(miumNativeCEFTestVerifyCefApiCompatibility(CEF_API_HASH_PLATFORM, CEF_API_HASH_PLATFORM));
  miumNativeCEFTestResetState();

  FakeCefLibrary missingVersionInfoLibrary = [self buildFakeCefLibraryVariant:@"missing-version-info"];
  missingVersionInfoLibrary.handle = dlopen(missingVersionInfoLibrary.frameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
  XCTAssertNotEqual(missingVersionInfoLibrary.handle, nullptr);
  XCTAssertFalse(miumNativeCEFTestLoadRequiredCefSymbols(missingVersionInfoLibrary.handle));
  miumNativeCEFTestResetState();

  FakeCefLibrary missingAPIVersionLibrary = [self buildFakeCefLibraryVariant:@"missing-api-version"];
  missingAPIVersionLibrary.handle = dlopen(missingAPIVersionLibrary.frameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
  XCTAssertNotEqual(missingAPIVersionLibrary.handle, nullptr);
  XCTAssertTrue(miumNativeCEFTestLoadRequiredCefSymbols(missingAPIVersionLibrary.handle));
  miumNativeCEFTestResetState();

  FakeCefLibrary missingStringListSizeLibrary = [self buildFakeCefLibraryVariant:@"missing-string-list-size"];
  missingStringListSizeLibrary.handle = dlopen(missingStringListSizeLibrary.frameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
  XCTAssertNotEqual(missingStringListSizeLibrary.handle, nullptr);
  XCTAssertTrue(miumNativeCEFTestLoadRequiredCefSymbols(missingStringListSizeLibrary.handle));
  miumNativeCEFTestResetState();

  FakeCefLibrary missingStringListValueLibrary = [self buildFakeCefLibraryVariant:@"missing-string-list-value"];
  missingStringListValueLibrary.handle = dlopen(missingStringListValueLibrary.frameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
  XCTAssertNotEqual(missingStringListValueLibrary.handle, nullptr);
  XCTAssertTrue(miumNativeCEFTestLoadRequiredCefSymbols(missingStringListValueLibrary.handle));
  miumNativeCEFTestResetState();

  FakeCefLibrary missingExecuteProcessLibrary = [self buildFakeCefLibraryVariant:@"missing-execute-process"];
  missingExecuteProcessLibrary.handle = dlopen(missingExecuteProcessLibrary.frameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
  XCTAssertNotEqual(missingExecuteProcessLibrary.handle, nullptr);
  XCTAssertTrue(miumNativeCEFTestLoadRequiredCefSymbols(missingExecuteProcessLibrary.handle));
  miumNativeCEFTestResetState();

  FakeCefLibrary missingInitializeLibrary = [self buildFakeCefLibraryVariant:@"missing-initialize"];
  missingInitializeLibrary.handle = dlopen(missingInitializeLibrary.frameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
  XCTAssertNotEqual(missingInitializeLibrary.handle, nullptr);
  XCTAssertFalse(miumNativeCEFTestLoadRequiredCefSymbols(missingInitializeLibrary.handle));
  miumNativeCEFTestResetState();

  FakeCefLibrary missingShutdownLibrary = [self buildFakeCefLibraryVariant:@"missing-shutdown"];
  missingShutdownLibrary.handle = dlopen(missingShutdownLibrary.frameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
  XCTAssertNotEqual(missingShutdownLibrary.handle, nullptr);
  XCTAssertFalse(miumNativeCEFTestLoadRequiredCefSymbols(missingShutdownLibrary.handle));
  miumNativeCEFTestResetState();

  FakeCefLibrary missingMessageLoopLibrary = [self buildFakeCefLibraryVariant:@"missing-do-message-loop-work"];
  missingMessageLoopLibrary.handle = dlopen(missingMessageLoopLibrary.frameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
  XCTAssertNotEqual(missingMessageLoopLibrary.handle, nullptr);
  XCTAssertFalse(miumNativeCEFTestLoadRequiredCefSymbols(missingMessageLoopLibrary.handle));
  miumNativeCEFTestResetState();

  FakeCefLibrary missingCreateBrowserSyncLibrary = [self buildFakeCefLibraryVariant:@"missing-create-browser-sync"];
  missingCreateBrowserSyncLibrary.handle = dlopen(missingCreateBrowserSyncLibrary.frameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
  XCTAssertNotEqual(missingCreateBrowserSyncLibrary.handle, nullptr);
  XCTAssertFalse(miumNativeCEFTestLoadRequiredCefSymbols(missingCreateBrowserSyncLibrary.handle));
  miumNativeCEFTestResetState();

  FakeCefLibrary missingProcessMessageLibrary = [self buildFakeCefLibraryVariant:@"missing-process-message-create"];
  missingProcessMessageLibrary.handle = dlopen(missingProcessMessageLibrary.frameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
  XCTAssertNotEqual(missingProcessMessageLibrary.handle, nullptr);
  XCTAssertTrue(miumNativeCEFTestLoadRequiredCefSymbols(missingProcessMessageLibrary.handle));
  miumNativeCEFTestResetState();

  miumNativeCEFTestSetFrameworkFallbackCandidates({
    std::string(missingAPIHashLibrary.frameworkPath.UTF8String)
  });
  XCTAssertFalse(miumNativeCEFTestOpenFrameworkIfNeeded({}));
  miumNativeCEFTestSetFrameworkFallbackCandidates({});
  miumNativeCEFTestResetState();

  FakeCefLibrary recoverableFailureLibrary = [self buildFakeCefLibraryVariant:@"missing-api-hash"];
  FakeCefLibrary recoverableSuccessLibrary = [self buildFakeCefLibraryVariant:@"default"];
  XCTAssertTrue(
    miumNativeCEFTestOpenFrameworkIfNeeded({
      std::string(recoverableFailureLibrary.frameworkPath.UTF8String),
      std::string(recoverableSuccessLibrary.frameworkPath.UTF8String)
    })
  );
  miumNativeCEFTestResetState();

  FakeCefLibrary runtimeLibrary = [self buildFakeCefLibraryVariant:@"default"];
  CallbackProbe firstInitializeProbe;
  firstInitializeProbe.expectation = [self expectationWithDescription:@"first initialize"];
  MiumCEFRuntimeHandle firstRuntime = nullptr;
  XCTAssertEqual(
    miumNativeCEFInitialize(runtimeLibrary.runtimeRoot.UTF8String, runtimeLibrary.metadataPath.UTF8String, testNativeCallback, &firstInitializeProbe, &firstRuntime),
    MiumCEFResultOK
  );

  CallbackProbe secondInitializeProbe;
  secondInitializeProbe.expectation = [self expectationWithDescription:@"second initialize"];
  MiumCEFRuntimeHandle secondRuntime = nullptr;
  XCTAssertEqual(
    miumNativeCEFInitialize(runtimeLibrary.runtimeRoot.UTF8String, runtimeLibrary.metadataPath.UTF8String, testNativeCallback, &secondInitializeProbe, &secondRuntime),
    MiumCEFResultOK
  );
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertNotEqual(firstRuntime, nullptr);
  XCTAssertNotEqual(secondRuntime, nullptr);
  XCTAssertTrue(miumNativeCEFIsLoaded());
  XCTAssertEqual(miumNativeCEFDoMessageLoopWork(), MiumCEFResultOK);

  runtimeLibrary.handle = dlopen(runtimeLibrary.frameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
  XCTAssertNotEqual(runtimeLibrary.handle, nullptr);
  auto initializeCalls = reinterpret_cast<IntGetterFn>([self symbolNamed:"mium_test_get_initialize_calls" inHandle:runtimeLibrary.handle]);
  auto shutdownCalls = reinterpret_cast<IntGetterFn>([self symbolNamed:"mium_test_get_shutdown_calls" inHandle:runtimeLibrary.handle]);
  auto subprocessPath = reinterpret_cast<CStringGetterFn>([self symbolNamed:"mium_test_get_browser_subprocess_path" inHandle:runtimeLibrary.handle]);
  auto resourcesPath = reinterpret_cast<CStringGetterFn>([self symbolNamed:"mium_test_get_resources_dir_path" inHandle:runtimeLibrary.handle]);
  auto localesPath = reinterpret_cast<CStringGetterFn>([self symbolNamed:"mium_test_get_locales_dir_path" inHandle:runtimeLibrary.handle]);
  auto cachePath = reinterpret_cast<CStringGetterFn>([self symbolNamed:"mium_test_get_cache_path" inHandle:runtimeLibrary.handle]);
  auto rootCachePath = reinterpret_cast<CStringGetterFn>([self symbolNamed:"mium_test_get_root_cache_path" inHandle:runtimeLibrary.handle]);
  NSString* expectedHelperPath = [[[[runtimeLibrary.runtimeRoot stringByAppendingPathComponent:@"Contents/Frameworks/Navigator Helper.app/Contents"] stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:@"Navigator Helper"] stringByStandardizingPath];
  XCTAssertEqual(initializeCalls(), 1);
  XCTAssertEqualObjects(stringFromCString(subprocessPath()), expectedHelperPath);
  XCTAssertFalse(stringFromCString(resourcesPath()).length == 0);
  XCTAssertFalse(stringFromCString(localesPath()).length == 0);
  XCTAssertFalse(stringFromCString(cachePath()).length == 0);
  XCTAssertFalse(stringFromCString(rootCachePath()).length == 0);

  XCTAssertEqual(miumNativeCEFShutdown(firstRuntime), MiumCEFResultOK);
  XCTAssertEqual(shutdownCalls(), 0);
  XCTAssertTrue(miumNativeCEFIsLoaded());
  XCTAssertEqual(miumNativeCEFShutdown(firstRuntime), MiumCEFResultNotInitialized);

  const MiumCEFRuntimeHandle inactiveRuntime = miumNativeCEFTestInsertRuntime(
    runtimeLibrary.runtimeRoot.UTF8String,
    runtimeLibrary.metadataPath.UTF8String,
    false
  );
  XCTAssertEqual(miumNativeCEFShutdown(inactiveRuntime), MiumCEFResultAlreadyShutdown);

  XCTAssertEqual(miumNativeCEFShutdown(secondRuntime), MiumCEFResultOK);
  XCTAssertEqual(shutdownCalls(), 1);
  XCTAssertFalse(miumNativeCEFIsLoaded());
}

@end
