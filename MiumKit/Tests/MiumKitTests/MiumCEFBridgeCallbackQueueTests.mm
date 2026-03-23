#import "MiumCEFBridgeNativeTestSupport.h"

using namespace MiumCEFBridgeNativeTestSupport;

@interface MiumCEFBridgeCallbackQueueTests : MiumCEFBridgeNativeTestCase
@end

@implementation MiumCEFBridgeCallbackQueueTests

- (void)testBackgroundQueueDispatchesSubprocessAndSnapshotWorkToMainThread {
  MiumCEFBridgeTestAPI api{};
  api.executeProcess = fakeExecuteProcess;
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  gExecuteProcessReturnCode = 23;
  const char* arguments[] = { "navigator", "--type=renderer" };
  const char* const* argumentsPointer = arguments;
  __block int subprocessResult = -1;
  [self runOnBackgroundQueueAndWait:^{
    subprocessResult = miumNativeCEFMaybeRunSubprocess(2, argumentsPointer);
  }];
  XCTAssertEqual(subprocessResult, 23);
  XCTAssertEqual(gExecuteProcessCalls, 1);
  XCTAssertEqual(gExecuteProcessLastArgc, 2);
  XCTAssertTrue(gExecuteProcessLastHadApplication);
  XCTAssertFalse(gExecuteProcessLastAppHasBrowserProcessHandler);
  XCTAssertFalse(gExecuteProcessLastAppHasScheduleMessagePumpWork);
  XCTAssertTrue(gExecuteProcessLastAppHasRenderProcessHandler);
  XCTAssertTrue(gExecuteProcessLastAppHasProcessMessageReceivedHandler);

  FakeCreateBrowserFactory factory;
  gCreateBrowserFactory = &factory;
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle hostViewHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &hostViewHandle), MiumCEFResultOK);

  TestSnapshotView* hostView = [[TestSnapshotView alloc] initWithFrame:NSMakeRect(0, 0, 70, 50)];
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(hostViewHandle, (__bridge void*)hostView));
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(browserHandle, hostViewHandle), MiumCEFResultOK);

  NSString* outputPath = [[self temporaryDirectory] stringByAppendingPathComponent:@"background.png"];
  CallbackProbe probe;
  CallbackProbe* probePointer = &probe;
  probe.expectation = [self expectationWithDescription:@"background snapshot completed"];
  __block MiumCEFResultCode snapshotResult = MiumCEFResultError;
  [self runOnBackgroundQueueAndWait:^{
    snapshotResult = miumNativeCEFRequestSnapshot(browserHandle, outputPath.UTF8String, nullptr, probePointer, testNativeCallback);
  }];
  XCTAssertEqual(snapshotResult, MiumCEFResultOK);
  [self waitForExpectations:@[ probe.expectation ] timeout:kCallbackTimeout];
  XCTAssertEqual(probe.code, MiumCEFResultOK, @"%s", probe.message.c_str());
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:outputPath]);
}

- (void)testOffMainThreadDispatchRunsMessageLoopWork {
  MiumCEFBridgeTestAPI api{};
  api.doMessageLoopWork = fakeDoMessageLoopWork;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  __block MessageLoopWorkContext messageLoopContext;
  [self runOnBackgroundQueueAndWait:^{
    runMessageLoopWork(&messageLoopContext);
  }];
  XCTAssertEqual(messageLoopContext.result, MiumCEFResultOK);
  XCTAssertEqual(gMessageLoopWorkCalls, 1);
}

- (void)testOffMainThreadDispatchRunsSnapshotRequest {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  FakeCreateBrowserFactory factory;
  gCreateBrowserFactory = &factory;
  const MiumCEFRuntimeHandle snapshotRuntime = [self seedRuntime];
  const MiumCEFBrowserHandle snapshotBrowser = [self createBrowserForRuntime:snapshotRuntime];
  MiumCEFHostViewHandle snapshotHostViewHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(snapshotBrowser, &snapshotHostViewHandle), MiumCEFResultOK);
  TestSnapshotView* snapshotView = [[TestSnapshotView alloc] initWithFrame:NSMakeRect(0, 0, 72, 48)];
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(snapshotHostViewHandle, (__bridge void*)snapshotView));
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(snapshotBrowser, snapshotHostViewHandle), MiumCEFResultOK);

  NSString* outputPath = [[self temporaryDirectory] stringByAppendingPathComponent:@"off-main-snapshot.png"];
  CallbackProbe snapshotProbe;
  snapshotProbe.expectation = [self expectationWithDescription:@"off-main snapshot"];
  __block SnapshotRequestContext snapshotContext;
  snapshotContext.browserHandle = snapshotBrowser;
  snapshotContext.outputPath = outputPath.UTF8String;
  snapshotContext.probe = &snapshotProbe;

  [self runOnBackgroundQueueAndWait:^{
    runSnapshotRequest(&snapshotContext);
  }];

  XCTAssertEqual(snapshotContext.result, MiumCEFResultOK);
  [self waitForExpectations:@[ snapshotProbe.expectation ] timeout:kCallbackTimeout];
  XCTAssertEqual(snapshotProbe.code, MiumCEFResultOK, @"%s", snapshotProbe.message.c_str());
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:outputPath]);
}

- (void)testShutdownFromBackgroundQueueClearsBufferedCallbacks {
  MiumCEFBridgeTestAPI api{};
  api.shutdown = fakeShutdown;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);
  const MiumCEFRuntimeHandle shutdownRuntime = [self seedRuntime];
  const MiumCEFBrowserHandle shutdownBrowser = [self createBrowserForRuntime:shutdownRuntime];
  const uint64_t shutdownBrowserId = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(shutdownBrowser));
  miumNativeCEFTestEnqueueCallbackPayload(
    recordingNativeCallback,
    MiumCEFResultOK,
    "stale",
    nullptr,
    shutdownBrowserId,
    MiumCEFBridgeTestCallbackRoute::nonUI
  );

  __block ShutdownContext shutdownContext;
  shutdownContext.runtimeHandle = shutdownRuntime;
  [self runOnBackgroundQueueAndDrain:^{
    runShutdown(&shutdownContext);
  }];

  XCTAssertEqual(shutdownContext.result, MiumCEFResultOK);
  XCTAssertEqual(gShutdownCalls, 1);
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI), static_cast<size_t>(0));
}

- (void)testFinalShutdownMarksRuntimeUnavailableBeforeResetCompletes {
  ShutdownSnapshotState shutdownSnapshot;
  gShutdownSnapshotState = &shutdownSnapshot;

  MiumCEFBridgeTestAPI api{};
  api.shutdown = fakeShutdownCapturingState;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];

  XCTAssertEqual(miumNativeCEFShutdown(runtimeHandle), MiumCEFResultOK);
  XCTAssertEqual(gShutdownCalls, 1);
  XCTAssertFalse(shutdownSnapshot.initialized);
  XCTAssertTrue(shutdownSnapshot.shutdownExecuting);
  XCTAssertFalse(shutdownSnapshot.frameworkLoaded);
}

- (void)testRegisterAndEmitMessageHandlerDeliversMessage {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  CallbackProbe probe;
  probe.expectation = [self expectationWithDescription:@"message delivered"];

  XCTAssertEqual(
    miumNativeCEFRegisterMessageHandler(browserHandle, "channel", &probe, testNativeCallback),
    MiumCEFResultOK
  );
  XCTAssertEqual(miumNativeCEFEmitMessage(browserHandle, "channel", "hello"), MiumCEFResultOK);

  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(probe.code, MiumCEFResultOK);
  XCTAssertEqual(probe.message, "hello");
  XCTAssertEqual(probe.callbackContext, &probe);
  XCTAssertEqual(probe.invocationCount, 1);
}

- (void)testRegisterMessageHandlerRemovalPreventsFurtherDelivery {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  CallbackProbe probe;

  XCTAssertEqual(
    miumNativeCEFRegisterMessageHandler(browserHandle, "channel", &probe, testNativeCallback),
    MiumCEFResultOK
  );
  XCTAssertEqual(
    miumNativeCEFRegisterMessageHandler(browserHandle, "channel", nullptr, nullptr),
    MiumCEFResultOK
  );
  XCTAssertEqual(miumNativeCEFEmitMessage(browserHandle, "channel", "hello"), MiumCEFResultError);
}

- (void)testQueuedMessageHandlerReplacementDropsStaleDelivery {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  CallbackProbe firstProbe;
  CallbackProbe secondProbe;
  secondProbe.expectation = [self expectationWithDescription:@"replacement handler delivered"];

  miumNativeCEFTestSetCallbackQueueDraining(MiumCEFBridgeTestCallbackRoute::nonUI, true);
  XCTAssertEqual(
    miumNativeCEFRegisterMessageHandler(browserHandle, "channel", &firstProbe, testNativeCallback),
    MiumCEFResultOK
  );
  XCTAssertEqual(miumNativeCEFEmitMessage(browserHandle, "channel", "first"), MiumCEFResultOK);
  XCTAssertEqual(
    miumNativeCEFRegisterMessageHandler(browserHandle, "channel", &secondProbe, testNativeCallback),
    MiumCEFResultOK
  );
  XCTAssertEqual(miumNativeCEFEmitMessage(browserHandle, "channel", "second"), MiumCEFResultOK);

  miumNativeCEFTestSetCallbackQueueDraining(MiumCEFBridgeTestCallbackRoute::nonUI, false);
  RecordingProbe drainProbe;
  drainProbe.expectation = [self expectationWithDescription:@"replacement queue drain trigger"];
  miumNativeCEFTestEnqueueCallbackPayload(
    recordingNativeCallback,
    MiumCEFResultOK,
    "drain",
    &drainProbe,
    0,
    MiumCEFBridgeTestCallbackRoute::nonUI
  );
  [self waitForExpectations:@[ secondProbe.expectation, drainProbe.expectation ] timeout:kCallbackTimeout];
  [self waitUntil:^BOOL {
    return miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI) == 0;
  } description:@"replacement queue drained"];

  XCTAssertEqual(firstProbe.invocationCount, 0);
  XCTAssertEqual(secondProbe.invocationCount, 1);
  XCTAssertEqual(secondProbe.message, "second");
  XCTAssertEqual(secondProbe.callbackContext, &secondProbe);
}

- (void)testQueuedMessageHandlerRegistrationInactiveBeforeDrainDropsDelivery {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  CallbackProbe probe;
  probe.expectation = [self expectationWithDescription:@"inactive registration drops queued delivery"];
  probe.expectation.inverted = YES;

  auto registration = std::make_shared<MiumCEFCallbackRegistration>();
  miumNativeCEFTestSetCallbackQueueDraining(MiumCEFBridgeTestCallbackRoute::nonUI, true);
  XCTAssertEqual(
    miumNativeCEFRegisterMessageHandlerWithRegistration(
      browserHandle,
      "channel",
      registration,
      &probe,
      testNativeCallback
    ),
    MiumCEFResultOK
  );
  XCTAssertEqual(miumNativeCEFEmitMessage(browserHandle, "channel", "queued"), MiumCEFResultOK);

  registration->active.store(false, std::memory_order_release);

  miumNativeCEFTestSetCallbackQueueDraining(MiumCEFBridgeTestCallbackRoute::nonUI, false);
  RecordingProbe drainProbe;
  drainProbe.expectation = [self expectationWithDescription:@"inactive registration queue drain"];
  miumNativeCEFTestEnqueueCallbackPayload(
    recordingNativeCallback,
    MiumCEFResultOK,
    "drain",
    &drainProbe,
    0,
    MiumCEFBridgeTestCallbackRoute::nonUI
  );

  [self waitForExpectations:@[ probe.expectation, drainProbe.expectation ] timeout:kCallbackTimeout];
  [self waitUntil:^BOOL {
    return miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI) == static_cast<size_t>(0);
  } description:@"inactive registration queue drained"];

  XCTAssertEqual(probe.invocationCount, 0);
}

- (void)testQueuedMessageHandlerUsesRegistrationOwnedContextInsteadOfRawPayloadContext {
  CallbackProbe expectedProbe;
  expectedProbe.expectation = [self expectationWithDescription:@"registration-owned context delivered"];
  CallbackProbe staleProbe;
  auto registration = std::make_shared<MiumCEFCallbackRegistration>();
  registration->userContext = &expectedProbe;

  miumNativeCEFTestRunOnMessageQueueForHandlerWithRegistration(
    testNativeCallback,
    MiumCEFResultOK,
    "registered",
    registration,
    &staleProbe,
    0,
    nullptr,
    0
  );

  [self waitForExpectations:@[ expectedProbe.expectation ] timeout:kCallbackTimeout];

  XCTAssertEqual(expectedProbe.invocationCount, 1);
  XCTAssertEqual(expectedProbe.message, "registered");
  XCTAssertEqual(expectedProbe.callbackContext, &expectedProbe);
  XCTAssertEqual(staleProbe.invocationCount, 0);
}

- (void)testDirectQueuedHandlerPayloadUsesGenerationFilter {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  const uint64_t browserId = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(browserHandle));
  CallbackProbe staleProbe;
  staleProbe.expectation = [self expectationWithDescription:@"stale queued handler dropped"];
  staleProbe.expectation.inverted = YES;

  XCTAssertEqual(
    miumNativeCEFRegisterMessageHandler(browserHandle, "channel", &staleProbe, testNativeCallback),
    MiumCEFResultOK
  );
  const uint64_t staleGeneration = miumNativeCEFTestMessageHandlerGeneration(browserHandle, "channel");
  XCTAssertGreaterThan(staleGeneration, static_cast<uint64_t>(0));

  XCTAssertEqual(
    miumNativeCEFRegisterMessageHandler(browserHandle, "channel", nullptr, nullptr),
    MiumCEFResultOK
  );

  miumNativeCEFTestRunOnMessageQueueForHandler(
    testNativeCallback,
    MiumCEFResultOK,
    "stale",
    &staleProbe,
    browserId,
    "channel",
    staleGeneration
  );
  [self waitForExpectations:@[ staleProbe.expectation ] timeout:0.2];
  XCTAssertEqual(staleProbe.invocationCount, 0);
}

- (void)testEmitMessageNormalizesNilPayloadToEmptyString {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  CallbackProbe probe;
  probe.expectation = [self expectationWithDescription:@"empty payload delivered"];

  XCTAssertEqual(
    miumNativeCEFRegisterMessageHandler(browserHandle, "channel", &probe, testNativeCallback),
    MiumCEFResultOK
  );
  XCTAssertEqual(miumNativeCEFEmitMessage(browserHandle, "channel", nullptr), MiumCEFResultOK);

  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(probe.message, "");
}

- (void)testShutdownClosesPendingBrowsersAndResetsLoadedState {
  MiumCEFBridgeTestAPI api{};
  api.shutdown = fakeShutdown;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetFrameworkLoaded(true);
  miumNativeCEFTestSetInitialized(true, 1);

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness fakeBrowser;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), nullptr));

  const MiumCEFResultCode result = miumNativeCEFShutdown(runtimeHandle);

  XCTAssertEqual(result, MiumCEFResultOK);
  XCTAssertEqual(fakeBrowser.host->closeBrowserCalls, 1);
  XCTAssertEqual(gShutdownCalls, 1);
  XCTAssertFalse(miumNativeCEFIsLoaded());
  MiumCEFBrowserHandle nextBrowserHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowser(runtimeHandle, &nextBrowserHandle), MiumCEFResultNotInitialized);
}

- (void)testBrowserClientAddressChangeAndRefCounting {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness mappedBrowser;
  FakeBrowserHarness unmappedBrowser;
  unmappedBrowser.browser->identifier = 7331;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, mappedBrowser.browserRef(), nullptr));

  CallbackProbe probe;
  probe.expectation = [self expectationWithDescription:@"address change delivered"];
  XCTAssertEqual(
    miumNativeCEFRegisterMessageHandler(browserHandle, "__addressChange__", &probe, testNativeCallback),
    MiumCEFResultOK
  );
  CallbackProbe faviconProbe;
  faviconProbe.expectation = [self expectationWithDescription:@"favicon change delivered"];
  XCTAssertEqual(
    miumNativeCEFRegisterMessageHandler(browserHandle, "__faviconURLChange__", &faviconProbe, testNativeCallback),
    MiumCEFResultOK
  );
  CallbackProbe titleProbe;
  titleProbe.expectation = [self expectationWithDescription:@"title change delivered"];
  XCTAssertEqual(
    miumNativeCEFRegisterMessageHandler(browserHandle, "__titleChange__", &titleProbe, testNativeCallback),
    MiumCEFResultOK
  );

  cef_client_t* client = miumNativeCEFTestCreateBrowserClient();
  XCTAssertNotEqual(client, nullptr);
  XCTAssertEqual(client->base.has_one_ref(nullptr), 0);
  XCTAssertEqual(client->base.has_at_least_one_ref(nullptr), 0);
  client->base.add_ref(nullptr);
  XCTAssertEqual(client->base.has_one_ref(&client->base), 1);
  client->base.add_ref(&client->base);
  XCTAssertEqual(client->base.has_one_ref(&client->base), 0);
  XCTAssertEqual(client->base.has_at_least_one_ref(&client->base), 1);

  cef_display_handler_t* handler = client->get_display_handler(client);
  XCTAssertNotEqual(handler, nullptr);
  XCTAssertEqual(handler->base.has_one_ref(nullptr), 0);
  XCTAssertEqual(handler->base.has_one_ref(&handler->base), 0);
  XCTAssertEqual(handler->base.has_at_least_one_ref(nullptr), 0);
  handler->base.add_ref(nullptr);
  handler->base.add_ref(&handler->base);
  XCTAssertEqual(handler->base.has_at_least_one_ref(&handler->base), 1);

  const char* urlBytes = "https://example.com/path";
  cef_string_t url{};
  XCTAssertEqual(fakeUTF8ToUTF16(urlBytes, std::strlen(urlBytes), &url), 1);
  const char* titleBytes = "Example Page";
  cef_string_t title{};
  XCTAssertEqual(fakeUTF8ToUTF16(titleBytes, std::strlen(titleBytes), &title), 1);

  handler->on_address_change(handler, nullptr, nullptr, &url);
  handler->on_title_change(handler, nullptr, nullptr);
  handler->on_address_change(handler, unmappedBrowser.browserRef(), nullptr, nullptr);
  handler->on_title_change(handler, unmappedBrowser.browserRef(), nullptr);
  handler->on_title_change(handler, mappedBrowser.browserRef(), &title);
  handler->on_address_change(handler, mappedBrowser.browserRef(), nullptr, &url);
  miumNativeCEFTestEmitDisplayHandlerFaviconURLChange(
    mappedBrowser.browserRef(),
    "https://example.com/favicon.ico"
  );

  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(probe.code, MiumCEFResultOK);
  XCTAssertEqual(probe.message, "https://example.com/path");
  XCTAssertEqual(titleProbe.code, MiumCEFResultOK);
  XCTAssertEqual(titleProbe.message, "Example Page");
  XCTAssertEqual(faviconProbe.code, MiumCEFResultOK);
  XCTAssertEqual(faviconProbe.message, "https://example.com/favicon.ico");

  fakeUTF16Clear(&url);
  fakeUTF16Clear(&title);
  XCTAssertEqual(handler->base.release(nullptr), 0);
  XCTAssertEqual(handler->base.release(&handler->base), 0);
  XCTAssertEqual(handler->base.release(&handler->base), 0);
  XCTAssertEqual(client->base.release(nullptr), 0);
  XCTAssertEqual(client->base.release(&client->base), 0);
  XCTAssertEqual(client->base.release(&client->base), 1);
}

- (void)testLateDisplayHandlerMessagesAreDroppedOnceBrowserCloseBegins {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness fakeBrowser;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), nullptr));

  CallbackProbe probe;
  probe.expectation = [self expectationWithDescription:@"late favicon callback not delivered"];
  probe.expectation.inverted = YES;
  XCTAssertEqual(
    miumNativeCEFRegisterMessageHandler(browserHandle, "__faviconURLChange__", &probe, testNativeCallback),
    MiumCEFResultOK
  );

  cef_browser_t* detachedBrowser = nullptr;
  cef_client_t* detachedClient = nullptr;
  XCTAssertEqual(
    miumNativeCEFTestBeginClosingNativeBrowser(
      browserHandle,
      false,
      true,
      nullptr,
      &detachedBrowser,
      &detachedClient
    ),
    MiumCEFBridgeTestBrowserCloseDisposition::closePending
  );

  miumNativeCEFTestEmitDisplayHandlerFaviconURLChange(fakeBrowser.browserRef(), "https://navigator.test/favicon.ico");
  [self waitForExpectations:@[ probe.expectation ] timeout:0.2];
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI), static_cast<size_t>(0));
  XCTAssertEqual(probe.invocationCount, 0);

  if (detachedBrowser != nullptr && detachedBrowser->base.release != nullptr) {
    detachedBrowser->base.release(&detachedBrowser->base);
  }
  if (detachedClient != nullptr && detachedClient->base.release != nullptr) {
    detachedClient->base.release(&detachedClient->base);
  }
  miumNativeCEFTestFinalizeClosedBrowserState(browserHandle, runtimeHandle);
}

- (void)testBrowserClientFaviconHandlerCoversStringListPaths {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.stringListSize = fakeStringListSize;
  api.stringListValue = fakeStringListValue;
  miumNativeCEFTestInstallAPI(&api);

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness mappedBrowser;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, mappedBrowser.browserRef(), nullptr));

  RecordingProbe probe;
  probe.expectation = [self expectationWithDescription:@"favicon messages delivered"];
  probe.expectation.expectedFulfillmentCount = 4;
  XCTAssertEqual(
    miumNativeCEFRegisterMessageHandler(browserHandle, "__faviconURLChange__", &probe, recordingNativeCallback),
    MiumCEFResultOK
  );

  cef_client_t* client = miumNativeCEFTestCreateBrowserClient();
  XCTAssertNotEqual(client, nullptr);
  cef_display_handler_t* handler = client->get_display_handler(client);
  XCTAssertNotEqual(handler, nullptr);

  FakeStringListState emptyList;
  FakeStringListState failingList;
  failingList.values = { "https://navigator.test/failing.ico" };
  failingList.failValueLookup = true;
  FakeStringListState successList;
  successList.values = { "https://navigator.test/favicon.ico" };

  handler->on_favicon_urlchange(handler, mappedBrowser.browserRef(), nullptr);
  handler->on_favicon_urlchange(
    handler,
    mappedBrowser.browserRef(),
    reinterpret_cast<cef_string_list_t>(&emptyList)
  );
  handler->on_favicon_urlchange(
    handler,
    mappedBrowser.browserRef(),
    reinterpret_cast<cef_string_list_t>(&failingList)
  );
  handler->on_favicon_urlchange(
    handler,
    mappedBrowser.browserRef(),
    reinterpret_cast<cef_string_list_t>(&successList)
  );

  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  std::lock_guard<std::mutex> lock(probe.mutex);
  XCTAssertEqual(probe.messages.size(), static_cast<size_t>(4));
  XCTAssertEqual(probe.messages[0], "");
  XCTAssertEqual(probe.messages[1], "");
  XCTAssertEqual(probe.messages[2], "");
  XCTAssertEqual(probe.messages[3], "https://navigator.test/favicon.ico");

  XCTAssertEqual(handler->base.release(&handler->base), 0);
  XCTAssertEqual(client->base.release(&client->base), 1);
}

- (void)testBrowserClientPictureInPictureHandlersInjectAndEmitBridgeMessages {
  [self installBasicAPI];

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness mappedBrowser;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, mappedBrowser.browserRef(), nullptr));

  CallbackProbe probe;
  probe.expectation = [self expectationWithDescription:@"picture in picture message delivered"];
  XCTAssertEqual(
    miumNativeCEFRegisterMessageHandler(
      browserHandle,
      MiumCEFPictureInPictureStateChangeChannel,
      &probe,
      testNativeCallback
    ),
    MiumCEFResultOK
  );

  cef_client_t* client = miumNativeCEFTestCreateBrowserClient();
  XCTAssertNotEqual(client, nullptr);

  cef_load_handler_t* loadHandler = client->get_load_handler(client);
  XCTAssertNotEqual(loadHandler, nullptr);
  mappedBrowser.frame->isMainResult = 0;
  loadHandler->on_load_end(loadHandler, mappedBrowser.browserRef(), &mappedBrowser.frame->frame, 204);
  XCTAssertEqual(mappedBrowser.frame->lastExecutedScript, "");

  mappedBrowser.frame->isMainResult = 1;
  loadHandler->on_load_end(loadHandler, mappedBrowser.browserRef(), &mappedBrowser.frame->frame, 200);
  XCTAssertTrue(mappedBrowser.frame->lastExecutedScript.find("__miumPictureInPictureStateChange__") != std::string::npos);
  XCTAssertTrue(mappedBrowser.frame->lastExecutedScript.find("sequenceNumber") != std::string::npos);
  XCTAssertTrue(mappedBrowser.frame->lastExecutedScript.find("reason") != std::string::npos);
  XCTAssertTrue(mappedBrowser.frame->lastExecutedScript.find("leavepictureinpicture") != std::string::npos);

  cef_jsdialog_handler_t* jsDialogHandler = client->get_jsdialog_handler(client);
  XCTAssertNotEqual(jsDialogHandler, nullptr);

  const char* payloadBytes =
    "{\"sequenceNumber\":3,\"event\":\"video-enter\",\"location\":\"https://navigator.test/player\","
    "\"isCurrentWindowPictureInPicture\":true,\"isVideoPictureInPictureActive\":true,"
    "\"isVideoPictureInPictureSupported\":true,\"isDocumentPictureInPictureSupported\":true,"
    "\"isDocumentPictureInPictureWindowOpen\":false,\"currentWindowInnerWidth\":480,"
    "\"currentWindowInnerHeight\":270,\"videoPictureInPictureWindowWidth\":480,"
    "\"videoPictureInPictureWindowHeight\":270,\"documentPictureInPictureWindowWidth\":null,"
    "\"documentPictureInPictureWindowHeight\":null,\"activeVideo\":null,\"videoElementCount\":1,"
    "\"errorDescription\":null}";
  cef_string_t originURL{};
  cef_string_t messageText{};
  cef_string_t payloadText{};
  XCTAssertEqual(fakeUTF8ToUTF16("https://navigator.test/player", std::strlen("https://navigator.test/player"), &originURL), 1);
  XCTAssertEqual(
    fakeUTF8ToUTF16("__miumPictureInPictureStateChange__", std::strlen("__miumPictureInPictureStateChange__"), &messageText),
    1
  );
  XCTAssertEqual(fakeUTF8ToUTF16(payloadBytes, std::strlen(payloadBytes), &payloadText), 1);

  int suppressMessage = 0;
  XCTAssertEqual(
    jsDialogHandler->on_jsdialog(
      jsDialogHandler,
      mappedBrowser.browserRef(),
      &originURL,
      JSDIALOGTYPE_PROMPT,
      &messageText,
      &payloadText,
      nullptr,
      &suppressMessage
    ),
    0
  );

  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(suppressMessage, 1);
  XCTAssertEqual(probe.code, MiumCEFResultOK);
  XCTAssertEqual(probe.message, payloadBytes);
  XCTAssertEqual(probe.invocationCount, 1);

  cef_string_t ignoredMessage{};
  XCTAssertEqual(fakeUTF8ToUTF16("__ignored__", std::strlen("__ignored__"), &ignoredMessage), 1);
  suppressMessage = 0;
  XCTAssertEqual(
    jsDialogHandler->on_jsdialog(
      jsDialogHandler,
      mappedBrowser.browserRef(),
      &originURL,
      JSDIALOGTYPE_PROMPT,
      &ignoredMessage,
      &payloadText,
      nullptr,
      &suppressMessage
    ),
    0
  );
  XCTAssertEqual(suppressMessage, 0);
  XCTAssertEqual(probe.invocationCount, 1);

  CallbackProbe cameraProbe;
  cameraProbe.expectation = [self expectationWithDescription:@"camera routing message delivered"];
  XCTAssertEqual(
    miumNativeCEFRegisterMessageHandler(
      browserHandle,
      MiumCEFCameraRoutingEventChannel,
      &cameraProbe,
      testNativeCallback
    ),
    MiumCEFResultOK
  );

  const char* cameraPayloadBytes =
    "{\"event\":\"track-started\",\"activeManagedTrackCount\":1,\"managedTrackID\":\"track-1\","
    "\"managedDeviceID\":\"navigator-camera-managed-output\",\"preferredFilterPreset\":\"folia\"}";
  cef_string_t cameraMessageText{};
  cef_string_t cameraPayloadText{};
  XCTAssertEqual(
    fakeUTF8ToUTF16(
      MiumCEFCameraRoutingPromptMessage,
      std::strlen(MiumCEFCameraRoutingPromptMessage),
      &cameraMessageText
    ),
    1
  );
  XCTAssertEqual(
    fakeUTF8ToUTF16(cameraPayloadBytes, std::strlen(cameraPayloadBytes), &cameraPayloadText),
    1
  );

  suppressMessage = 0;
  XCTAssertEqual(
    jsDialogHandler->on_jsdialog(
      jsDialogHandler,
      mappedBrowser.browserRef(),
      &originURL,
      JSDIALOGTYPE_PROMPT,
      &cameraMessageText,
      &cameraPayloadText,
      nullptr,
      &suppressMessage
    ),
    0
  );

  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(suppressMessage, 1);
  XCTAssertEqual(cameraProbe.code, MiumCEFResultOK);
  XCTAssertEqual(cameraProbe.message, cameraPayloadBytes);
  XCTAssertEqual(cameraProbe.invocationCount, 1);

  fakeUTF16Clear(&originURL);
  fakeUTF16Clear(&messageText);
  fakeUTF16Clear(&payloadText);
  fakeUTF16Clear(&ignoredMessage);
  fakeUTF16Clear(&cameraMessageText);
  fakeUTF16Clear(&cameraPayloadText);
  XCTAssertEqual(loadHandler->base.release(&loadHandler->base), 0);
  XCTAssertEqual(jsDialogHandler->base.release(&jsDialogHandler->base), 0);
  XCTAssertEqual(client->base.release(&client->base), 1);
}

- (void)testCallbackQueuePoliciesAndClearingAreDeterministic {
  miumNativeCEFTestSetCallbackQueueDraining(MiumCEFBridgeTestCallbackRoute::nonUI, true);
  miumNativeCEFTestSetCallbackQueueOverflowPolicy(
    MiumCEFBridgeTestCallbackRoute::nonUI,
    MiumCEFBridgeTestCallbackOverflowPolicy::dropOldest,
    2
  );
  miumNativeCEFTestEnqueueCallbackPayload(recordingNativeCallback, MiumCEFResultOK, "one", nullptr, 11, MiumCEFBridgeTestCallbackRoute::nonUI);
  miumNativeCEFTestEnqueueCallbackPayload(recordingNativeCallback, MiumCEFResultOK, "two", nullptr, 22, MiumCEFBridgeTestCallbackRoute::nonUI);
  miumNativeCEFTestEnqueueCallbackPayload(recordingNativeCallback, MiumCEFResultOK, "three", nullptr, 33, MiumCEFBridgeTestCallbackRoute::nonUI);
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI), static_cast<size_t>(2));
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackMessages(MiumCEFBridgeTestCallbackRoute::nonUI)[0], "two");

  miumNativeCEFTestClearCallbackPayloadsForBrowser(22);
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI), static_cast<size_t>(1));
  miumNativeCEFTestClearCallbackPayloadsForBrowsers({ 33 });
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI), static_cast<size_t>(0));

  miumNativeCEFTestSetCallbackQueueOverflowPolicy(
    MiumCEFBridgeTestCallbackRoute::nonUI,
    MiumCEFBridgeTestCallbackOverflowPolicy::latest,
    4
  );
  miumNativeCEFTestEnqueueCallbackPayload(recordingNativeCallback, MiumCEFResultOK, "alpha", nullptr, 0, MiumCEFBridgeTestCallbackRoute::nonUI);
  miumNativeCEFTestEnqueueCallbackPayload(recordingNativeCallback, MiumCEFResultOK, "beta", nullptr, 0, MiumCEFBridgeTestCallbackRoute::nonUI);
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI), static_cast<size_t>(1));
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackMessages(MiumCEFBridgeTestCallbackRoute::nonUI)[0], "beta");

  miumNativeCEFTestSetCallbackQueueOverflowPolicy(
    MiumCEFBridgeTestCallbackRoute::nonUI,
    MiumCEFBridgeTestCallbackOverflowPolicy::coalesce,
    4
  );
  miumNativeCEFTestEnqueueCallbackPayload(recordingNativeCallback, MiumCEFResultOK, "beta", nullptr, 0, MiumCEFBridgeTestCallbackRoute::nonUI);
  miumNativeCEFTestEnqueueCallbackPayload(recordingNativeCallback, MiumCEFResultOK, "beta", nullptr, 0, MiumCEFBridgeTestCallbackRoute::nonUI);
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI), static_cast<size_t>(1));

  miumNativeCEFTestClearCallbackPayloadsForBrowsers({ 0 });
  miumNativeCEFTestEnqueueCallbackPayload(recordingNativeCallback, MiumCEFResultOK, "same", nullptr, 41, MiumCEFBridgeTestCallbackRoute::nonUI);
  miumNativeCEFTestEnqueueCallbackPayload(recordingNativeCallback, MiumCEFResultOK, "same", nullptr, 42, MiumCEFBridgeTestCallbackRoute::nonUI);
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI), static_cast<size_t>(2));
  miumNativeCEFTestClearCallbackPayloadsForBrowsers({ 41, 42 });

  miumNativeCEFTestSetCallbackQueueOverflowPolicy(
    MiumCEFBridgeTestCallbackRoute::nonUI,
    MiumCEFBridgeTestCallbackOverflowPolicy::coalesce,
    1
  );
  miumNativeCEFTestEnqueueCallbackPayload(recordingNativeCallback, MiumCEFResultOK, "delta", nullptr, 0, MiumCEFBridgeTestCallbackRoute::nonUI);
  miumNativeCEFTestEnqueueCallbackPayload(recordingNativeCallback, MiumCEFResultOK, "epsilon", nullptr, 0, MiumCEFBridgeTestCallbackRoute::nonUI);
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI), static_cast<size_t>(1));
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackMessages(MiumCEFBridgeTestCallbackRoute::nonUI)[0], "epsilon");

  miumNativeCEFTestSetCallbackQueueOverflowPolicy(
    MiumCEFBridgeTestCallbackRoute::nonUI,
    MiumCEFBridgeTestCallbackOverflowPolicy::coalesce,
    4
  );
  miumNativeCEFTestClearCallbackPayloadsForBrowsers({ 0 });

  miumNativeCEFTestSetCallbackQueueOverflowPolicy(
    MiumCEFBridgeTestCallbackRoute::ui,
    MiumCEFBridgeTestCallbackOverflowPolicy::dropOldest,
    4
  );
  miumNativeCEFTestSetCallbackQueueDraining(MiumCEFBridgeTestCallbackRoute::ui, true);
  miumNativeCEFTestEnqueueCallbackPayload(recordingNativeCallback, MiumCEFResultOK, "ui-one", nullptr, 101, MiumCEFBridgeTestCallbackRoute::ui);
  miumNativeCEFTestEnqueueCallbackPayload(recordingNativeCallback, MiumCEFResultOK, "ui-two", nullptr, 202, MiumCEFBridgeTestCallbackRoute::ui);
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::ui), static_cast<size_t>(2));
  miumNativeCEFTestClearCallbackPayloadsForBrowser(101);
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::ui), static_cast<size_t>(1));
  miumNativeCEFTestClearCallbackPayloadsForBrowsers({ 202 });
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::ui), static_cast<size_t>(0));

  RecordingProbe probe;
  probe.expectation = [self expectationWithDescription:@"non-ui callbacks drained"];
  probe.expectation.expectedFulfillmentCount = 2;
  miumNativeCEFTestSetCallbackQueueDraining(MiumCEFBridgeTestCallbackRoute::nonUI, false);
  miumNativeCEFTestEnqueueCallbackPayload(recordingNativeCallback, MiumCEFResultOK, "beta", &probe, 0, MiumCEFBridgeTestCallbackRoute::nonUI);
  miumNativeCEFTestEnqueueCallbackPayload(recordingNativeCallback, MiumCEFResultOK, "gamma", &probe, 0, MiumCEFBridgeTestCallbackRoute::nonUI);

  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  std::lock_guard<std::mutex> lock(probe.mutex);
  XCTAssertEqual(probe.messages.size(), static_cast<size_t>(2));
  XCTAssertEqual(probe.messages[0], "beta");
  XCTAssertEqual(probe.messages[1], "gamma");

  CallbackProbe inactiveProbe;
  miumNativeCEFTestEnqueueCallbackPayload(nullptr, MiumCEFResultOK, "ignored", nullptr, 0, MiumCEFBridgeTestCallbackRoute::nonUI);
  miumNativeCEFTestEnqueueCallbackPayload(testNativeCallback, MiumCEFResultOK, "inactive", &inactiveProbe, 9999, MiumCEFBridgeTestCallbackRoute::nonUI);
  RecordingProbe inactiveDrainProbe;
  inactiveDrainProbe.expectation = [self expectationWithDescription:@"non-ui inactive payload drained"];
  miumNativeCEFTestEnqueueCallbackPayload(
    recordingNativeCallback,
    MiumCEFResultOK,
    "drain",
    &inactiveDrainProbe,
    0,
    MiumCEFBridgeTestCallbackRoute::nonUI
  );
  [self waitForExpectations:@[ inactiveDrainProbe.expectation ] timeout:kCallbackTimeout];
  XCTAssertEqual(inactiveProbe.invocationCount, 0);
}

- (void)testPendingBrowserCloseHelpersAndShutdownPump {
  MiumCEFBridgeTestAPI api{};
  api.doMessageLoopWork = fakeDoMessageLoopWork;
  api.shutdown = fakeShutdown;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 0);
  miumNativeCEFTestSetShutdownState(true, false);

  XCTAssertEqual(miumNativeCEFHasPendingBrowserClose(), 0);
  miumNativeCEFTestRegisterPendingBrowserClose(MiumCEFBridgeTestCloseKind::teardown);
  XCTAssertEqual(miumNativeCEFHasPendingBrowserClose(), 1);
  XCTAssertEqual(miumNativeCEFTestPendingNativeBrowserCloseCount(), static_cast<size_t>(1));
  miumNativeCEFTestSchedulePendingShutdownPumpIfNeeded();
  XCTAssertTrue(miumNativeCEFTestIsShutdownPumpScheduled());
  miumNativeCEFTestFinishPendingBrowserClose(MiumCEFBridgeTestCloseKind::teardown);
  [self waitUntil:^BOOL {
    return gShutdownCalls == 1 && miumNativeCEFHasPendingBrowserClose() == 0 && !miumNativeCEFTestIsShutdownPumpScheduled();
  } description:@"pending shutdown pump drained"];

  XCTAssertEqual(gMessageLoopWorkCalls, 0);
  XCTAssertEqual(gShutdownCalls, 1);
  XCTAssertEqual(miumNativeCEFHasPendingBrowserClose(), 0);
  XCTAssertFalse(miumNativeCEFTestIsShutdownPumpScheduled());

  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 0);
  miumNativeCEFTestSetShutdownState(true, true);
  miumNativeCEFTestPumpPendingShutdownMessageLoop();
  XCTAssertEqual(gShutdownCalls, 2);
}

- (void)testBrowserOperationsRejectWorkDuringShutdownExecution {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createProcessMessage = fakeCreateProcessMessage;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  FakeProcessMessageFactory messageFactory;
  gProcessMessageFactory = &messageFactory;

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness fakeBrowser;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), nullptr));

  miumNativeCEFTestSetFrameworkHandle(nullptr);
  miumNativeCEFTestSetFrameworkLoaded(false);
  miumNativeCEFTestSetShutdownExecuting(true);

  CallbackProbe loadProbe;
  loadProbe.expectation = [self expectationWithDescription:@"shutdown load rejected"];
  CallbackProbe scriptProbe;
  scriptProbe.expectation = [self expectationWithDescription:@"shutdown script rejected"];
  CallbackProbe sendProbe;
  sendProbe.expectation = [self expectationWithDescription:@"shutdown send rejected"];

  XCTAssertEqual(miumNativeCEFGoBack(browserHandle), MiumCEFResultNotInitialized);
  XCTAssertEqual(miumNativeCEFGoForward(browserHandle), MiumCEFResultNotInitialized);
  XCTAssertEqual(miumNativeCEFReload(browserHandle), MiumCEFResultNotInitialized);
  XCTAssertEqual(miumNativeCEFStopLoad(browserHandle), MiumCEFResultNotInitialized);
  XCTAssertEqual(miumNativeCEFCanGoBack(browserHandle), 0);
  XCTAssertEqual(miumNativeCEFCanGoForward(browserHandle), 0);
  XCTAssertEqual(miumNativeCEFIsLoading(browserHandle), 0);
  XCTAssertEqual(
    miumNativeCEFLoadURL(browserHandle, "https://example.com", &loadProbe, testNativeCallback),
    MiumCEFResultNotInitialized
  );
  XCTAssertEqual(
    miumNativeCEFEvaluateJavaScript(browserHandle, "window.test()", &scriptProbe, testNativeCallback),
    MiumCEFResultNotInitialized
  );
  XCTAssertEqual(
    miumNativeCEFSendMessage(browserHandle, "bridge", "{}", &sendProbe, testNativeCallback),
    MiumCEFResultNotInitialized
  );

  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];

  XCTAssertEqual(loadProbe.code, MiumCEFResultNotInitialized);
  XCTAssertEqual(loadProbe.message, kRuntimeUnavailableMessage);
  XCTAssertEqual(scriptProbe.code, MiumCEFResultNotInitialized);
  XCTAssertEqual(scriptProbe.message, kRuntimeUnavailableMessage);
  XCTAssertEqual(sendProbe.code, MiumCEFResultNotInitialized);
  XCTAssertEqual(sendProbe.message, kRuntimeUnavailableMessage);
  XCTAssertEqual(fakeBrowser.browser->goBackCalls, 0);
  XCTAssertEqual(fakeBrowser.browser->goForwardCalls, 0);
  XCTAssertEqual(fakeBrowser.browser->reloadCalls, 0);
  XCTAssertEqual(fakeBrowser.browser->stopLoadCalls, 0);
  XCTAssertTrue(fakeBrowser.frame->lastLoadedURL.empty());
  XCTAssertTrue(fakeBrowser.frame->lastExecutedScript.empty());
  XCTAssertEqual(fakeBrowser.frame->sendProcessMessageCalls, 0);
  XCTAssertEqual(messageFactory.messages.size(), static_cast<size_t>(0));
}

- (void)testShutdownSweepsInactiveBrowsersHostBindingsAndBufferedCallbacks {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle hostViewHandle = nullptr;
  MiumCEFHostViewHandle unboundHostViewHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &hostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &unboundHostViewHandle), MiumCEFResultOK);

  const uint64_t browserId = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(browserHandle));
  XCTAssertTrue(miumNativeCEFTestSetHostViewBrowserId(hostViewHandle, browserId + 99));
  miumNativeCEFTestSetCallbackQueueDraining(MiumCEFBridgeTestCallbackRoute::nonUI, true);
  miumNativeCEFTestEnqueueCallbackPayload(
    testNativeCallback,
    MiumCEFResultOK,
    "pending",
    nullptr,
    browserId,
    MiumCEFBridgeTestCallbackRoute::nonUI
  );
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI), static_cast<size_t>(1));

  miumNativeCEFTestSetBrowserStateFlags(browserHandle, false, false);
  XCTAssertEqual(miumNativeCEFShutdown(runtimeHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI), static_cast<size_t>(0));
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(hostViewHandle), nullptr);
  XCTAssertEqual(miumNativeCEFTestGetBrowserHostViewId(browserHandle), static_cast<uint64_t>(0));

  miumNativeCEFTestFinalizeClosedBrowserState(browserHandle, nullptr);
}

- (void)testBridgeMessageHandlerReentersMainThreadNativeAPIsWithoutDeadlock {
  [self installBasicAPI];

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness fakeBrowser;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), nullptr));

  ReentrantBridgeMessageContext context;
  context.browserHandle = browserHandle;
  context.browserRef = reinterpret_cast<CEFBridgeBrowserRef>(browserHandle);
  context.messageExpectation = [self expectationWithDescription:@"reentrant bridge message"];
  context.loadProbe.expectation = [self expectationWithDescription:@"reentrant load completion"];
  context.scriptProbe.expectation = [self expectationWithDescription:@"reentrant script completion"];

  CEFBridge_SetMessageHandler(context.browserRef, reentrantBridgeLoadEvalResizeCallback, &context);
  XCTAssertEqual(
    miumNativeCEFEmitMessage(browserHandle, MiumCEFAddressChangeChannel, "https://callback.example"),
    MiumCEFResultOK
  );

  [self waitForExpectations:@[
    context.messageExpectation,
    context.loadProbe.expectation,
    context.scriptProbe.expectation
  ] timeout:kCallbackTimeout];

  XCTAssertEqual(context.invocationCount, 1);
  XCTAssertEqual(context.messages.size(), static_cast<size_t>(1));
  XCTAssertEqual(context.messages[0], "https://callback.example");
  XCTAssertEqual(context.loadResult, MiumCEFResultOK);
  XCTAssertEqual(context.scriptResult, MiumCEFResultOK);
  XCTAssertEqual(context.resizeResult, MiumCEFResultOK);
  XCTAssertEqual(context.loadProbe.code, MiumCEFResultOK);
  XCTAssertEqual(context.scriptProbe.code, MiumCEFResultOK);
  XCTAssertEqual(fakeBrowser.frame->lastLoadedURL, "https://reentrant.load");
  XCTAssertEqual(fakeBrowser.frame->lastExecutedScript, "window.reentrant()");
  XCTAssertGreaterThanOrEqual(fakeBrowser.host->notifyMoveOrResizeStartedCalls, 1);
  XCTAssertGreaterThanOrEqual(fakeBrowser.host->wasResizedCalls, 1);
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI), static_cast<size_t>(0));
}

- (void)testLoadURLCompletionReentersReloadAndStopLoadWithoutDeadlock {
  [self installBasicAPI];

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness fakeBrowser;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), nullptr));

  ReentrantCompletionContext context;
  context.browserHandle = browserHandle;
  context.expectation = [self expectationWithDescription:@"reentrant completion"];

  XCTAssertEqual(
    miumNativeCEFLoadURL(browserHandle, "https://completion.example", &context, reentrantLoadCompletionCallback),
    MiumCEFResultOK
  );
  [self waitForExpectations:@[ context.expectation ] timeout:kCallbackTimeout];

  XCTAssertEqual(context.invocationCount, 1);
  XCTAssertEqual(context.code, MiumCEFResultOK);
  XCTAssertEqual(context.message, "https://completion.example");
  XCTAssertEqual(context.reloadResult, MiumCEFResultOK);
  XCTAssertEqual(context.stopLoadResult, MiumCEFResultOK);
  XCTAssertEqual(fakeBrowser.frame->lastLoadedURL, "https://completion.example");
  XCTAssertEqual(fakeBrowser.browser->reloadCalls, 1);
  XCTAssertEqual(fakeBrowser.browser->stopLoadCalls, 1);
}

- (void)testBridgeMessageHandlerCanRemoveItselfDuringDelivery {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  const CEFBridgeBrowserRef browserRef = reinterpret_cast<CEFBridgeBrowserRef>(browserHandle);

  SelfRemovingBridgeMessageContext context;
  context.browserRef = browserRef;
  context.expectation = [self expectationWithDescription:@"self removing bridge callback"];

  CEFBridge_SetMessageHandler(browserRef, selfRemovingBridgeMessageCallback, &context);
  XCTAssertEqual(
    miumNativeCEFEmitMessage(browserHandle, MiumCEFAddressChangeChannel, "first"),
    MiumCEFResultOK
  );
  [self waitForExpectations:@[ context.expectation ] timeout:kCallbackTimeout];

  XCTAssertEqual(
    miumNativeCEFEmitMessage(browserHandle, MiumCEFAddressChangeChannel, "second"),
    MiumCEFResultError
  );

  XCTAssertEqual(context.invocationCount, 1);
  XCTAssertEqual(context.messages.size(), static_cast<size_t>(1));
  XCTAssertEqual(context.messages[0], "first");
}

- (void)testBridgeDestroyingBrowserBeforeQueueDrainPrunesQueuedBrowserScopedCallbacks {
  [self installBasicAPI];

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness fakeBrowser;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), nullptr));

  const CEFBridgeBrowserRef browserRef = reinterpret_cast<CEFBridgeBrowserRef>(browserHandle);
  BridgeMessageProbe messageProbe;
  CEFBridge_SetMessageHandler(browserRef, bridgeMessageCallback, &messageProbe);
  miumNativeCEFTestSetCallbackQueueDraining(MiumCEFBridgeTestCallbackRoute::nonUI, true);
  XCTAssertEqual(miumNativeCEFEmitMessage(browserHandle, MiumCEFAddressChangeChannel, "first"), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFEmitMessage(browserHandle, MiumCEFAddressChangeChannel, "second"), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI), static_cast<size_t>(2));
  XCTAssertEqual(miumNativeCEFDestroyBrowser(browserHandle), MiumCEFResultOK);

  miumNativeCEFTestSetCallbackQueueDraining(MiumCEFBridgeTestCallbackRoute::nonUI, false);
  RecordingProbe drainProbe;
  drainProbe.expectation = [self expectationWithDescription:@"pruned queue drain trigger"];
  miumNativeCEFTestEnqueueCallbackPayload(
    recordingNativeCallback,
    MiumCEFResultOK,
    "drain",
    &drainProbe,
    0,
    MiumCEFBridgeTestCallbackRoute::nonUI
  );
  [self waitForExpectations:@[ drainProbe.expectation ] timeout:kCallbackTimeout];

  XCTAssertEqual(messageProbe.messages.size(), static_cast<size_t>(0));
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI), static_cast<size_t>(0));
  XCTAssertEqual(miumNativeCEFReload(browserHandle), MiumCEFResultNotInitialized);
}

- (void)testBridgeMessageHandlerDestroyingBrowserAfterFirstDeliveryPrunesLaterCallbacks {
  [self installBasicAPI];

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness fakeBrowser;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), nullptr));

  CoordinatedDestroyBridgeMessageContext context;
  context.browserHandle = browserHandle;
  context.startedExpectation = [self expectationWithDescription:@"destroy callback started"];
  context.finishedExpectation = [self expectationWithDescription:@"destroy callback finished"];
  context.continueSemaphore = dispatch_semaphore_create(0);

  CEFBridge_SetMessageHandler(
    reinterpret_cast<CEFBridgeBrowserRef>(browserHandle),
    coordinatedDestroyBridgeMessageCallback,
    &context
  );

  XCTAssertEqual(miumNativeCEFEmitMessage(browserHandle, MiumCEFAddressChangeChannel, "one"), MiumCEFResultOK);
  [self waitForExpectations:@[ context.startedExpectation ] timeout:kCallbackTimeout];

  XCTAssertEqual(miumNativeCEFEmitMessage(browserHandle, MiumCEFAddressChangeChannel, "two"), MiumCEFResultOK);
  dispatch_semaphore_signal(context.continueSemaphore);
  [self waitForExpectations:@[ context.finishedExpectation ] timeout:kCallbackTimeout];
  [self waitUntil:^BOOL {
    return miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI) == 0;
  } description:@"later queued callback pruned"];

  XCTAssertEqual(context.destroyResult, MiumCEFResultOK);
  XCTAssertEqual(context.invocationCount, 1);
  XCTAssertEqual(context.messages.size(), static_cast<size_t>(1));
  if (context.messages.size() > 0) {
    XCTAssertEqual(context.messages[0], "one");
  }
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI), static_cast<size_t>(0));
  XCTAssertEqual(miumNativeCEFReload(browserHandle), MiumCEFResultNotInitialized);
}

- (void)testBridgeQueuedHandlerReplacementDropsStaleDelivery {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  const CEFBridgeBrowserRef browserRef = reinterpret_cast<CEFBridgeBrowserRef>(browserHandle);

  BridgeMessageProbe firstProbe;
  BridgeMessageProbe secondProbe;
  secondProbe.expectation = [self expectationWithDescription:@"replacement bridge handler delivered"];

  miumNativeCEFTestSetCallbackQueueDraining(MiumCEFBridgeTestCallbackRoute::nonUI, true);
  CEFBridge_SetMessageHandler(browserRef, bridgeMessageCallback, &firstProbe);
  XCTAssertEqual(miumNativeCEFEmitMessage(browserHandle, MiumCEFAddressChangeChannel, "first"), MiumCEFResultOK);

  CEFBridge_SetMessageHandler(browserRef, bridgeMessageCallback, &secondProbe);
  XCTAssertEqual(miumNativeCEFEmitMessage(browserHandle, MiumCEFAddressChangeChannel, "second"), MiumCEFResultOK);

  miumNativeCEFTestSetCallbackQueueDraining(MiumCEFBridgeTestCallbackRoute::nonUI, false);
  RecordingProbe drainProbe;
  drainProbe.expectation = [self expectationWithDescription:@"bridge replacement queue drain"];
  miumNativeCEFTestEnqueueCallbackPayload(
    recordingNativeCallback,
    MiumCEFResultOK,
    "drain",
    &drainProbe,
    0,
    MiumCEFBridgeTestCallbackRoute::nonUI
  );

  [self waitForExpectations:@[ secondProbe.expectation, drainProbe.expectation ] timeout:kCallbackTimeout];
  [self waitUntil:^BOOL {
    return miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI) == static_cast<size_t>(0);
  } description:@"bridge replacement queue drained"];

  XCTAssertEqual(firstProbe.messages.size(), static_cast<size_t>(0));
  XCTAssertEqual(secondProbe.messages.size(), static_cast<size_t>(1));
  if (secondProbe.messages.size() > 0) {
    XCTAssertEqual(secondProbe.messages[0], "second");
  }
}

- (void)testBridgeMessageHandlerShutdownDropsQueuedBrowserCallbacks {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.shutdown = fakeShutdown;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness fakeBrowser;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), nullptr));

  ReentrantBridgeMessageContext context;
  context.browserHandle = browserHandle;
  context.runtimeHandle = runtimeHandle;
  context.browserRef = reinterpret_cast<CEFBridgeBrowserRef>(browserHandle);
  context.messageExpectation = [self expectationWithDescription:@"shutdown callback"];

  CEFBridge_SetMessageHandler(context.browserRef, shutdownRuntimeFromBridgeMessageCallback, &context);
  miumNativeCEFTestSetCallbackQueueDraining(MiumCEFBridgeTestCallbackRoute::nonUI, true);
  XCTAssertEqual(miumNativeCEFEmitMessage(browserHandle, MiumCEFAddressChangeChannel, "first"), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFEmitMessage(browserHandle, MiumCEFAddressChangeChannel, "second"), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI), static_cast<size_t>(2));

  miumNativeCEFTestSetCallbackQueueDraining(MiumCEFBridgeTestCallbackRoute::nonUI, false);
  XCTAssertEqual(miumNativeCEFEmitMessage(browserHandle, MiumCEFAddressChangeChannel, "trigger"), MiumCEFResultOK);
  [self waitForExpectations:@[ context.messageExpectation ] timeout:kCallbackTimeout];
  [self waitUntil:^BOOL {
    return gShutdownCalls == 1 && miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI) == 0;
  } description:@"shutdown callback drain"];

  XCTAssertEqual(context.shutdownResult, MiumCEFResultOK);
  XCTAssertEqual(context.invocationCount, 1);
  XCTAssertEqual(context.messages.size(), static_cast<size_t>(1));
  XCTAssertEqual(context.messages[0], "first");
  XCTAssertEqual(gShutdownCalls, 1);
  XCTAssertEqual(miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute::nonUI), static_cast<size_t>(0));
  XCTAssertEqual(miumNativeCEFReload(browserHandle), MiumCEFResultNotInitialized);
}

- (void)testAttachBrowserReplacementKeepsPendingReplacementCloseUntilOldBrowserInvalidates {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  FakeCreateBrowserFactory factory;
  factory.onCreate = [&] {
    if (factory.createdBrowsers.size() == 1) {
      factory.createdBrowsers.back()->host->invalidatesOwnerOnClose = false;
    }
  };
  gCreateBrowserFactory = &factory;

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  const uint64_t browserId = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(browserHandle));
  MiumCEFHostViewHandle firstHostViewHandle = nullptr;
  MiumCEFHostViewHandle secondHostViewHandle = nullptr;
  NSView* firstHostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];
  NSView* secondHostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 140, 90)];

  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &firstHostViewHandle), MiumCEFResultOK);
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(firstHostViewHandle, (__bridge void*)firstHostView));
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(browserHandle, firstHostViewHandle), MiumCEFResultOK);

  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &secondHostViewHandle), MiumCEFResultOK);
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(secondHostViewHandle, (__bridge void*)secondHostView));
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(browserHandle, secondHostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(factory.callCount, 2);
  XCTAssertEqual(miumNativeCEFTestPendingReplacementBrowserCloseCount(), static_cast<size_t>(1));
  XCTAssertEqual(miumNativeCEFTestPendingNativeBrowserCloseCount(), static_cast<size_t>(1));
  XCTAssertEqual(factory.createdBrowsers[0]->host->closeBrowserCalls, 1);
  XCTAssertEqual(miumNativeCEFTestHostViewHandleForBrowser(browserHandle), secondHostViewHandle);
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(firstHostViewHandle), nullptr);
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(secondHostViewHandle), browserHandle);
  XCTAssertEqual(
    miumNativeCEFTestBrowserIdFromNativeBrowserPointerMapping(factory.createdBrowsers[0]->browserRef()),
    static_cast<uint64_t>(0)
  );
  XCTAssertEqual(miumNativeCEFTestBrowserIdFromNativeBrowser(factory.createdBrowsers[1]->browserRef()), browserId);

  factory.createdBrowsers[0]->browser->isValid = false;
  [self waitUntil:^BOOL {
    return miumNativeCEFTestPendingReplacementBrowserCloseCount() == 0
      && miumNativeCEFTestPendingNativeBrowserCloseCount() == 0;
  } description:@"replacement close drain"];

  XCTAssertEqual(miumNativeCEFTestPendingReplacementBrowserCloseCount(), static_cast<size_t>(0));
  XCTAssertEqual(miumNativeCEFTestPendingNativeBrowserCloseCount(), static_cast<size_t>(0));
  XCTAssertEqual(
    miumNativeCEFTestBrowserIdFromNativeBrowserPointerMapping(factory.createdBrowsers[0]->browserRef()),
    static_cast<uint64_t>(0)
  );
}

- (void)testShutdownWithLogicalBrowserAndNoNativeBrowserCompletesSynchronously {
  MiumCEFBridgeTestAPI api{};
  api.shutdown = fakeShutdown;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];

  XCTAssertEqual(miumNativeCEFShutdown(runtimeHandle), MiumCEFResultOK);
  XCTAssertEqual(gShutdownCalls, 1);
  XCTAssertEqual(miumNativeCEFTestPendingNativeBrowserCloseCount(), static_cast<size_t>(0));
  XCTAssertEqual(miumNativeCEFReload(browserHandle), MiumCEFResultNotInitialized);
}

- (void)testShutdownWaitsForTeardownClosePollingBeforeCallingCefShutdown {
  MiumCEFBridgeTestAPI api{};
  api.shutdown = fakeShutdown;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness fakeBrowser;
  fakeBrowser.host->invalidatesOwnerOnClose = false;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), nullptr));

  XCTAssertEqual(miumNativeCEFShutdown(runtimeHandle), MiumCEFResultOK);
  XCTAssertEqual(gShutdownCalls, 0);
  XCTAssertEqual(miumNativeCEFTestPendingTeardownBrowserCloseCount(), static_cast<size_t>(1));

  fakeBrowser.browser->isValid = false;
  [self waitUntil:^BOOL {
    return gShutdownCalls == 1
      && miumNativeCEFTestPendingTeardownBrowserCloseCount() == 0
      && miumNativeCEFTestPendingNativeBrowserCloseCount() == 0;
  } description:@"teardown close drain"];

  XCTAssertEqual(gShutdownCalls, 1);
  XCTAssertEqual(miumNativeCEFTestPendingTeardownBrowserCloseCount(), static_cast<size_t>(0));
  XCTAssertEqual(miumNativeCEFTestPendingNativeBrowserCloseCount(), static_cast<size_t>(0));
}

- (void)testShutdownWaitsForPendingReplacementCloseBeforeFinalShutdown {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createBrowserSync = fakeCreateBrowserSync;
  api.shutdown = fakeShutdown;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  FakeCreateBrowserFactory factory;
  factory.onCreate = [&] {
    if (factory.createdBrowsers.size() == 1) {
      factory.createdBrowsers.back()->host->invalidatesOwnerOnClose = false;
    }
  };
  gCreateBrowserFactory = &factory;

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle firstHostViewHandle = nullptr;
  MiumCEFHostViewHandle secondHostViewHandle = nullptr;
  NSView* firstHostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];
  NSView* secondHostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 140, 90)];

  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &firstHostViewHandle), MiumCEFResultOK);
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(firstHostViewHandle, (__bridge void*)firstHostView));
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(browserHandle, firstHostViewHandle), MiumCEFResultOK);

  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &secondHostViewHandle), MiumCEFResultOK);
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(secondHostViewHandle, (__bridge void*)secondHostView));
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(browserHandle, secondHostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFTestPendingReplacementBrowserCloseCount(), static_cast<size_t>(1));

  XCTAssertEqual(miumNativeCEFShutdown(runtimeHandle), MiumCEFResultOK);
  XCTAssertEqual(gShutdownCalls, 0);
  XCTAssertEqual(miumNativeCEFTestPendingReplacementBrowserCloseCount(), static_cast<size_t>(1));

  factory.createdBrowsers[0]->browser->isValid = false;
  [self waitUntil:^BOOL {
    return gShutdownCalls == 1
      && miumNativeCEFTestPendingReplacementBrowserCloseCount() == 0
      && miumNativeCEFTestPendingNativeBrowserCloseCount() == 0;
  } description:@"replacement shutdown drain"];

  XCTAssertEqual(gShutdownCalls, 1);
  XCTAssertEqual(miumNativeCEFTestPendingReplacementBrowserCloseCount(), static_cast<size_t>(0));
  XCTAssertEqual(miumNativeCEFTestPendingNativeBrowserCloseCount(), static_cast<size_t>(0));
}

- (void)testClosingBrowserDropsCallbacksBeforeAndAfterFinalization {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  const uint64_t browserId = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(browserHandle));

  CallbackProbe closingProbe;
  closingProbe.expectation = [self expectationWithDescription:@"closing callback dropped"];
  closingProbe.expectation.inverted = YES;
  miumNativeCEFTestSetBrowserStateFlags(browserHandle, false, true);
  miumNativeCEFTestEnqueueCallbackPayload(
    testNativeCallback,
    MiumCEFResultOK,
    "closing",
    &closingProbe,
    browserId,
    MiumCEFBridgeTestCallbackRoute::nonUI
  );
  [self waitForExpectations:@[ closingProbe.expectation ] timeout:0.2];
  XCTAssertEqual(closingProbe.invocationCount, 0);

  miumNativeCEFTestFinalizeClosedBrowserState(browserHandle, runtimeHandle);
  CallbackProbe finalizedProbe;
  miumNativeCEFTestEnqueueCallbackPayload(
    testNativeCallback,
    MiumCEFResultOK,
    "finalized",
    &finalizedProbe,
    browserId,
    MiumCEFBridgeTestCallbackRoute::nonUI
  );
  RecordingProbe finalizedDrainProbe;
  finalizedDrainProbe.expectation = [self expectationWithDescription:@"finalized callback dropped"];
  miumNativeCEFTestEnqueueCallbackPayload(
    recordingNativeCallback,
    MiumCEFResultOK,
    "drain",
    &finalizedDrainProbe,
    0,
    MiumCEFBridgeTestCallbackRoute::nonUI
  );
  [self waitForExpectations:@[ finalizedDrainProbe.expectation ] timeout:kCallbackTimeout];
  XCTAssertEqual(finalizedProbe.invocationCount, 0);
}

- (void)testFinalizeClosedBrowserStateClearsMappingsBeforeIdentifierReuse {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle firstBrowserHandle = [self createBrowserForRuntime:runtimeHandle];
  const MiumCEFBrowserHandle secondBrowserHandle = [self createBrowserForRuntime:runtimeHandle];
  const uint64_t secondBrowserId = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(secondBrowserHandle));

  FakeBrowserHarness firstBrowser;
  firstBrowser.browser->identifier = 7001;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(firstBrowserHandle, firstBrowser.browserRef(), nullptr));
  XCTAssertGreaterThan(miumNativeCEFTestBrowserIdFromNativeBrowser(firstBrowser.browserRef()), static_cast<uint64_t>(0));

  miumNativeCEFTestFinalizeClosedBrowserState(firstBrowserHandle, runtimeHandle);
  XCTAssertEqual(miumNativeCEFTestBrowserIdFromNativeBrowserPointerMapping(firstBrowser.browserRef()), static_cast<uint64_t>(0));

  FakeBrowserHarness secondBrowser;
  secondBrowser.browser->identifier = 7001;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(secondBrowserHandle, secondBrowser.browserRef(), nullptr));
  XCTAssertEqual(miumNativeCEFTestBrowserIdFromNativeBrowser(secondBrowser.browserRef()), secondBrowserId);
  XCTAssertEqual(miumNativeCEFTestBrowserIdFromNativeBrowserPointerMapping(firstBrowser.browserRef()), static_cast<uint64_t>(0));
}

@end
