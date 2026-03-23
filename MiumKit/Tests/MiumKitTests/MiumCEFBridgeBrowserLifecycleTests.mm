#import "MiumCEFBridgeNativeTestSupport.h"

using namespace MiumCEFBridgeNativeTestSupport;

@interface MiumCEFBridgeBrowserLifecycleTests : MiumCEFBridgeNativeTestCase
@end

static NSDictionary<NSString*, id>* bridgePayloadDictionary(const std::string& message) {
  NSData* payloadData = [NSData dataWithBytes:message.data() length:message.size()];
  return [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:nil];
}

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

struct LifecycleFakeRequestState {
  cef_request_t request{};
  FakeRefCountedLifetime lifetime{};
  std::string url;

  explicit LifecycleFakeRequestState(const char* requestURL) : url(requestURL == nullptr ? "" : requestURL) {
    std::memset(&request, 0, sizeof(request));
    initializeRefCountedBase(request.base, sizeof(request));
    request.base.add_ref = fakeAddRef<LifecycleFakeRequestState>;
    request.base.release = fakeRelease<LifecycleFakeRequestState>;
    request.base.has_one_ref = fakeHasOneRef<LifecycleFakeRequestState>;
    request.base.has_at_least_one_ref = fakeHasAtLeastOneRef<LifecycleFakeRequestState>;
    request.get_url = fakeGetURL;
  }

  static cef_string_userfree_t CEF_CALLBACK fakeGetURL(cef_request_t* self) {
    auto* state = reinterpret_cast<LifecycleFakeRequestState*>(self);
    return state == nullptr ? nullptr : fakeUserFreeString(state->url);
  }

  cef_request_t* requestRef() {
    return &request;
  }
};

struct LifecycleFakeResponseState {
  cef_response_t response{};
  FakeRefCountedLifetime lifetime{};
  std::string mimeType;

  explicit LifecycleFakeResponseState(const char* rawMIMEType)
    : mimeType(rawMIMEType == nullptr ? "" : rawMIMEType) {
    std::memset(&response, 0, sizeof(response));
    initializeRefCountedBase(response.base, sizeof(response));
    response.base.add_ref = fakeAddRef<LifecycleFakeResponseState>;
    response.base.release = fakeRelease<LifecycleFakeResponseState>;
    response.base.has_one_ref = fakeHasOneRef<LifecycleFakeResponseState>;
    response.base.has_at_least_one_ref = fakeHasAtLeastOneRef<LifecycleFakeResponseState>;
    response.get_mime_type = fakeGetMIMEType;
  }

  static cef_string_userfree_t CEF_CALLBACK fakeGetMIMEType(cef_response_t* self) {
    auto* state = reinterpret_cast<LifecycleFakeResponseState*>(self);
    return state == nullptr ? nullptr : fakeUserFreeString(state->mimeType);
  }

  cef_response_t* responseRef() {
    return &response;
  }
};

@implementation MiumCEFBridgeBrowserLifecycleTests

- (void)testCreateBrowserRequiresActiveRuntime {
  MiumCEFBrowserHandle browserHandle = reinterpret_cast<MiumCEFBrowserHandle>(0x55);

  XCTAssertEqual(
    miumNativeCEFCreateBrowser(reinterpret_cast<MiumCEFRuntimeHandle>(0x1234), &browserHandle),
    MiumCEFResultNotInitialized
  );
  XCTAssertEqual(browserHandle, nullptr);
}

- (void)testBrowserAndHostViewLifecycleWithoutNativeBrowser {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle hostViewHandle = nullptr;

  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &hostViewHandle), MiumCEFResultOK);
  XCTAssertNotEqual(hostViewHandle, nullptr);
  XCTAssertEqual(miumNativeCEFDetachBrowserFromHostView(browserHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFDestroyBrowserHostView(hostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFDestroyBrowser(browserHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFShutdown(runtimeHandle), MiumCEFResultOK);

  XCTAssertEqual(miumNativeCEFDestroyBrowser(browserHandle), MiumCEFResultNotInitialized);
  MiumCEFBrowserHandle nextBrowserHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowser(runtimeHandle, &nextBrowserHandle), MiumCEFResultNotInitialized);
}

- (void)testCreateBrowserHostViewForNSViewCleansUpOnNativeCreationFailure {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle hostViewHandle = reinterpret_cast<MiumCEFHostViewHandle>(0x66);
  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];

  const MiumCEFResultCode result = miumNativeCEFCreateBrowserHostViewForNSView(browserHandle, (__bridge void*)hostView, &hostViewHandle);

  XCTAssertEqual(result, MiumCEFResultNotInitialized);
  XCTAssertEqual(hostViewHandle, nullptr);
}

- (void)testCreateBrowserHostViewZeroesOutHandleOnFailure {
  MiumCEFHostViewHandle hostViewHandle = reinterpret_cast<MiumCEFHostViewHandle>(0x77);

  XCTAssertEqual(
    miumNativeCEFCreateBrowserHostView(reinterpret_cast<MiumCEFBrowserHandle>(0x1234), &hostViewHandle),
    MiumCEFResultNotInitialized
  );
  XCTAssertEqual(hostViewHandle, nullptr);
}

- (void)testCreateBrowserHostViewForNSViewCreatesNativeBrowser {
  [self installBasicAPI];
  FakeCreateBrowserFactory factory;
  gCreateBrowserFactory = &factory;

  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 144, 96)];
  MiumCEFHostViewHandle hostViewHandle = nullptr;

  const MiumCEFResultCode result = miumNativeCEFCreateBrowserHostViewForNSView(browserHandle, (__bridge void*)hostView, &hostViewHandle);

  XCTAssertEqual(result, MiumCEFResultOK);
  XCTAssertEqual(factory.callCount, 1);
  XCTAssertEqual(factory.lastParentView, (__bridge void*)embeddedParentViewForHostView(hostView));
  XCTAssertEqual(factory.lastWidth, 144);
  XCTAssertEqual(factory.lastHeight, 96);
  XCTAssertEqual(factory.lastURL, "about:blank");
  XCTAssertEqual(miumNativeCEFGoBack(browserHandle), MiumCEFResultOK);
  XCTAssertEqual(factory.createdBrowsers.back()->browser->goBackCalls, 1);
}

- (void)testCreateBrowserHostViewForNSViewFailurePreservesExistingHostBinding {
  [self installBasicAPI];
  FakeCreateBrowserFactory factory;
  gCreateBrowserFactory = &factory;

  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  NSView* initialHostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];
  MiumCEFHostViewHandle initialHostViewHandle = nullptr;

  XCTAssertEqual(
    miumNativeCEFCreateBrowserHostViewForNSView(browserHandle, (__bridge void*)initialHostView, &initialHostViewHandle),
    MiumCEFResultOK
  );
  XCTAssertEqual(miumNativeCEFTestHostViewHandleForBrowser(browserHandle), initialHostViewHandle);
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(initialHostViewHandle), browserHandle);

  gCreateBrowserFactory = nullptr;

  NSView* replacementHostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 144, 96)];
  MiumCEFHostViewHandle replacementHostViewHandle = nullptr;
  XCTAssertEqual(
    miumNativeCEFCreateBrowserHostViewForNSView(browserHandle, (__bridge void*)replacementHostView, &replacementHostViewHandle),
    MiumCEFResultError
  );
  XCTAssertEqual(replacementHostViewHandle, nullptr);
  XCTAssertEqual(miumNativeCEFTestHostViewHandleForBrowser(browserHandle), initialHostViewHandle);
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(initialHostViewHandle), browserHandle);
}

- (void)testCreateBrowserHostViewForNSViewReplacementClearsOldReverseBinding {
  [self installBasicAPI];
  FakeCreateBrowserFactory factory;
  gCreateBrowserFactory = &factory;

  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  NSView* initialHostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];
  MiumCEFHostViewHandle initialHostViewHandle = nullptr;

  XCTAssertEqual(
    miumNativeCEFCreateBrowserHostViewForNSView(browserHandle, (__bridge void*)initialHostView, &initialHostViewHandle),
    MiumCEFResultOK
  );

  NSView* replacementHostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 144, 96)];
  MiumCEFHostViewHandle replacementHostViewHandle = nullptr;
  XCTAssertEqual(
    miumNativeCEFCreateBrowserHostViewForNSView(browserHandle, (__bridge void*)replacementHostView, &replacementHostViewHandle),
    MiumCEFResultOK
  );

  XCTAssertEqual(miumNativeCEFTestHostViewHandleForBrowser(browserHandle), replacementHostViewHandle);
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(replacementHostViewHandle), browserHandle);
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(initialHostViewHandle), nullptr);

  XCTAssertEqual(miumNativeCEFDestroyBrowserHostView(initialHostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFTestHostViewHandleForBrowser(browserHandle), replacementHostViewHandle);
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(replacementHostViewHandle), browserHandle);
}

- (void)testAttachBrowserToHostViewCreatesNativeBrowser {
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
  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 90, 60)];
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &hostViewHandle), MiumCEFResultOK);
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(hostViewHandle, (__bridge void*)hostView));

  const MiumCEFResultCode result = miumNativeCEFAttachBrowserToHostView(browserHandle, hostViewHandle);

  XCTAssertEqual(result, MiumCEFResultOK);
  XCTAssertEqual(factory.callCount, 1);
  XCTAssertEqual(miumNativeCEFGoForward(browserHandle), MiumCEFResultOK);
  XCTAssertEqual(factory.createdBrowsers.back()->browser->goForwardCalls, 1);
  XCTAssertEqual(miumNativeCEFDetachBrowserFromHostView(browserHandle), MiumCEFResultOK);
}

- (void)testDetachBrowserFromHostViewRemovesManagedSubviews {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];
  NSView* overlaySubview = [[NSView alloc] initWithFrame:NSMakeRect(8, 7, 6, 5)];
  [hostView addSubview:overlaySubview];

  NSView* managedSubview = nil;
  FakeCreateBrowserFactory factory;
  factory.onCreate = [&] {
    NSView* parentView = (__bridge NSView*)factory.lastParentView;
    managedSubview = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 20, 10)];
    [parentView addSubview:managedSubview];
  };
  gCreateBrowserFactory = &factory;

  MiumCEFHostViewHandle hostViewHandle = nullptr;
  XCTAssertEqual(
    miumNativeCEFCreateBrowserHostViewForNSView(browserHandle, (__bridge void*)hostView, &hostViewHandle),
    MiumCEFResultOK
  );
  XCTAssertEqual(managedSubview.superview, embeddedParentViewForHostView(hostView));
  XCTAssertEqual(overlaySubview.superview, hostView);
  XCTAssertEqual(hostView.subviews.count, static_cast<NSUInteger>(2));

  XCTAssertEqual(miumNativeCEFDetachBrowserFromHostView(browserHandle), MiumCEFResultOK);
  XCTAssertNil(managedSubview.superview);
  XCTAssertEqual(overlaySubview.superview, hostView);
  XCTAssertEqual(hostView.subviews.count, static_cast<NSUInteger>(1));
  gCreateBrowserFactory = nullptr;
}

- (void)testCreateBrowserHostViewForNSViewFailureRemovesInsertedManagedSubviews {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];
  NSView* overlaySubview = [[NSView alloc] initWithFrame:NSMakeRect(2, 3, 4, 5)];
  [hostView addSubview:overlaySubview];

  NSView* managedSubview = nil;
  FakeCreateBrowserFactory factory;
  factory.onCreate = [&] {
    NSView* parentView = (__bridge NSView*)factory.lastParentView;
    managedSubview = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
    [parentView addSubview:managedSubview];
    miumNativeCEFTestSetInitialized(false, 0);
  };
  gCreateBrowserFactory = &factory;

  MiumCEFHostViewHandle hostViewHandle = reinterpret_cast<MiumCEFHostViewHandle>(0x88);
  XCTAssertEqual(
    miumNativeCEFCreateBrowserHostViewForNSView(browserHandle, (__bridge void*)hostView, &hostViewHandle),
    MiumCEFResultNotInitialized
  );
  XCTAssertEqual(hostViewHandle, nullptr);
  XCTAssertNil(managedSubview.superview);
  XCTAssertEqual(overlaySubview.superview, hostView);
  XCTAssertEqual(hostView.subviews.count, static_cast<NSUInteger>(1));
  gCreateBrowserFactory = nullptr;
}

- (void)testNavigationAndStateQueriesUseNativeBrowser {
  [self installBasicAPI];
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness fakeBrowser;
  fakeBrowser.browser->canGoBackResult = 1;
  fakeBrowser.browser->canGoForwardResult = 0;
  fakeBrowser.browser->isLoadingResult = 1;

  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), nullptr));

  XCTAssertEqual(miumNativeCEFGoBack(browserHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFGoForward(browserHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFReload(browserHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFStopLoad(browserHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFCanGoBack(browserHandle), 1);
  XCTAssertEqual(miumNativeCEFCanGoForward(browserHandle), 0);
  XCTAssertEqual(miumNativeCEFIsLoading(browserHandle), 1);
  XCTAssertEqual(fakeBrowser.browser->goBackCalls, 1);
  XCTAssertEqual(fakeBrowser.browser->goForwardCalls, 1);
  XCTAssertEqual(fakeBrowser.browser->reloadCalls, 1);
  XCTAssertEqual(fakeBrowser.browser->stopLoadCalls, 1);
}

- (void)testLoadURLDefaultsToAboutBlankAndCompletes {
  [self installBasicAPI];
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness fakeBrowser;
  CallbackProbe probe;
  probe.expectation = [self expectationWithDescription:@"load completed"];

  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), nullptr));

  const MiumCEFResultCode result = miumNativeCEFLoadURL(browserHandle, nullptr, &probe, testNativeCallback);

  XCTAssertEqual(result, MiumCEFResultOK);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(fakeBrowser.frame->lastLoadedURL, "about:blank");
  XCTAssertEqual(probe.code, MiumCEFResultOK);
  XCTAssertEqual(probe.message, "about:blank");
}

- (void)testBrowserLifeSpanHandlerRedirectsImagePopupIntoSourceBrowser {
  [self installBasicAPI];
  FakeBrowserHarness fakeBrowser;
  cef_client_t* client = miumNativeCEFTestCreateBrowserClient();
  XCTAssertNotEqual(client, nullptr);
  cef_life_span_handler_t* lifeSpanHandler = client->get_life_span_handler(client);
  XCTAssertNotEqual(lifeSpanHandler, nullptr);

  static const char* targetURLCString = "https://navigator.test/popup-image.png";
  cef_string_t targetURL{};
  XCTAssertTrue(fakeUTF8ToUTF16(targetURLCString, strlen(targetURLCString), &targetURL));
  cef_window_info_t windowInfo{};
  cef_browser_settings_t settings{};
  cef_client_t* popupClient = nullptr;
  cef_dictionary_value_t* extraInfo = nullptr;
  int noJavaScriptAccess = 0;

  const int result = lifeSpanHandler->on_before_popup(
    lifeSpanHandler,
    fakeBrowser.browserRef(),
    &fakeBrowser.frame->frame,
    11,
    &targetURL,
    nullptr,
    CEF_WOD_NEW_POPUP,
    1,
    nullptr,
    &windowInfo,
    &popupClient,
    &settings,
    &extraInfo,
    &noJavaScriptAccess
  );

  XCTAssertEqual(result, 1);
  XCTAssertEqual(fakeBrowser.frame->lastLoadedURL, targetURLCString);

  fakeUTF16Clear(&targetURL);
  lifeSpanHandler->base.release(&lifeSpanHandler->base);
  client->base.release(&client->base);
}

- (void)testBrowserLifeSpanHandlerAllowsNonImagePopupCreation {
  [self installBasicAPI];
  FakeBrowserHarness fakeBrowser;
  cef_client_t* client = miumNativeCEFTestCreateBrowserClient();
  XCTAssertNotEqual(client, nullptr);
  cef_life_span_handler_t* lifeSpanHandler = client->get_life_span_handler(client);
  XCTAssertNotEqual(lifeSpanHandler, nullptr);

  static const char* targetURLCString = "https://navigator.test/document";
  cef_string_t targetURL{};
  XCTAssertTrue(fakeUTF8ToUTF16(targetURLCString, strlen(targetURLCString), &targetURL));
  cef_window_info_t windowInfo{};
  cef_browser_settings_t settings{};
  cef_client_t* popupClient = nullptr;
  cef_dictionary_value_t* extraInfo = nullptr;
  int noJavaScriptAccess = 0;

  const int result = lifeSpanHandler->on_before_popup(
    lifeSpanHandler,
    fakeBrowser.browserRef(),
    &fakeBrowser.frame->frame,
    12,
    &targetURL,
    nullptr,
    CEF_WOD_NEW_POPUP,
    1,
    nullptr,
    &windowInfo,
    &popupClient,
    &settings,
    &extraInfo,
    &noJavaScriptAccess
  );

  XCTAssertEqual(result, 0);
  XCTAssertTrue(fakeBrowser.frame->lastLoadedURL.empty());

  fakeUTF16Clear(&targetURL);
  lifeSpanHandler->base.release(&lifeSpanHandler->base);
  client->base.release(&client->base);
}

- (void)testBrowserLifeSpanHandlerEmitsCmdClickTargetAsTabOpenRequest {
  [self installBasicAPI];
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  const CEFBridgeBrowserRef browserRef = reinterpret_cast<CEFBridgeBrowserRef>(browserHandle);
  FakeBrowserHarness fakeBrowser;
  cef_client_t* client = miumNativeCEFTestCreateBrowserClient();
  XCTAssertNotEqual(client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), client));
  cef_life_span_handler_t* lifeSpanHandler = client->get_life_span_handler(client);
  XCTAssertNotEqual(lifeSpanHandler, nullptr);

  BridgeMessageProbe probe;
  probe.expectation = [self expectationWithDescription:@"cmd click tab open request"];
  CEFBridge_SetOpenURLInTabHandler(browserRef, bridgeMessageCallback, &probe);

  static const char* targetURLCString = "https://navigator.test/cmd-click";
  cef_string_t targetURL{};
  XCTAssertTrue(fakeUTF8ToUTF16(targetURLCString, strlen(targetURLCString), &targetURL));
  cef_window_info_t windowInfo{};
  cef_browser_settings_t settings{};
  cef_client_t* popupClient = nullptr;
  cef_dictionary_value_t* extraInfo = nullptr;
  int noJavaScriptAccess = 0;

  const int result = lifeSpanHandler->on_before_popup(
    lifeSpanHandler,
    fakeBrowser.browserRef(),
    &fakeBrowser.frame->frame,
    13,
    &targetURL,
    nullptr,
    CEF_WOD_NEW_BACKGROUND_TAB,
    1,
    nullptr,
    &windowInfo,
    &popupClient,
    &settings,
    &extraInfo,
    &noJavaScriptAccess
  );

  XCTAssertEqual(result, 1);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(probe.messages.size(), static_cast<size_t>(1));
  NSDictionary<NSString*, id>* payload = bridgePayloadDictionary(probe.messages[0]);
  XCTAssertEqualObjects(payload[@"url"], @"https://navigator.test/cmd-click");
  XCTAssertEqualObjects(payload[@"activatesTab"], @NO);

  CEFBridge_SetOpenURLInTabHandler(browserRef, nullptr, nullptr);
  fakeUTF16Clear(&targetURL);
  lifeSpanHandler->base.release(&lifeSpanHandler->base);
  client->base.release(&client->base);
}

- (void)testBrowserLifeSpanHandlerEmitsForegroundTabOpenRequest {
  [self installBasicAPI];
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  const CEFBridgeBrowserRef browserRef = reinterpret_cast<CEFBridgeBrowserRef>(browserHandle);
  FakeBrowserHarness fakeBrowser;
  cef_client_t* client = miumNativeCEFTestCreateBrowserClient();
  XCTAssertNotEqual(client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), client));
  cef_life_span_handler_t* lifeSpanHandler = client->get_life_span_handler(client);
  XCTAssertNotEqual(lifeSpanHandler, nullptr);

  BridgeMessageProbe probe;
  probe.expectation = [self expectationWithDescription:@"foreground popup tab open request"];
  CEFBridge_SetOpenURLInTabHandler(browserRef, bridgeMessageCallback, &probe);

  static const char* targetURLCString = "https://navigator.test/foreground-popup-tab";
  cef_string_t targetURL{};
  XCTAssertTrue(fakeUTF8ToUTF16(targetURLCString, strlen(targetURLCString), &targetURL));
  cef_window_info_t windowInfo{};
  cef_browser_settings_t settings{};
  cef_client_t* popupClient = nullptr;
  cef_dictionary_value_t* extraInfo = nullptr;
  int noJavaScriptAccess = 0;

  const int result = lifeSpanHandler->on_before_popup(
    lifeSpanHandler,
    fakeBrowser.browserRef(),
    &fakeBrowser.frame->frame,
    14,
    &targetURL,
    nullptr,
    CEF_WOD_NEW_FOREGROUND_TAB,
    1,
    nullptr,
    &windowInfo,
    &popupClient,
    &settings,
    &extraInfo,
    &noJavaScriptAccess
  );

  XCTAssertEqual(result, 1);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(probe.messages.size(), static_cast<size_t>(1));
  NSDictionary<NSString*, id>* payload = bridgePayloadDictionary(probe.messages[0]);
  XCTAssertEqualObjects(payload[@"url"], @"https://navigator.test/foreground-popup-tab");
  XCTAssertEqualObjects(payload[@"activatesTab"], @YES);
  XCTAssertTrue(fakeBrowser.frame->lastLoadedURL.empty());

  CEFBridge_SetOpenURLInTabHandler(browserRef, nullptr, nullptr);
  fakeUTF16Clear(&targetURL);
  lifeSpanHandler->base.release(&lifeSpanHandler->base);
  client->base.release(&client->base);
}

- (void)testBrowserLifeSpanHandlerIgnoresNonTabDispositionWithoutEmittingTabOpenRequest {
  [self installBasicAPI];
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  const CEFBridgeBrowserRef browserRef = reinterpret_cast<CEFBridgeBrowserRef>(browserHandle);
  FakeBrowserHarness fakeBrowser;
  cef_client_t* client = miumNativeCEFTestCreateBrowserClient();
  XCTAssertNotEqual(client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), client));
  cef_life_span_handler_t* lifeSpanHandler = client->get_life_span_handler(client);
  XCTAssertNotEqual(lifeSpanHandler, nullptr);

  BridgeMessageProbe probe;
  probe.expectation = [self expectationWithDescription:@"non-tab popup should not emit tab open request"];
  probe.expectation.inverted = YES;
  CEFBridge_SetOpenURLInTabHandler(browserRef, bridgeMessageCallback, &probe);

  static const char* targetURLCString = "https://navigator.test/non-tab-popup";
  cef_string_t targetURL{};
  XCTAssertTrue(fakeUTF8ToUTF16(targetURLCString, strlen(targetURLCString), &targetURL));
  cef_window_info_t windowInfo{};
  cef_browser_settings_t settings{};
  cef_client_t* popupClient = nullptr;
  cef_dictionary_value_t* extraInfo = nullptr;
  int noJavaScriptAccess = 0;

  const int result = lifeSpanHandler->on_before_popup(
    lifeSpanHandler,
    fakeBrowser.browserRef(),
    &fakeBrowser.frame->frame,
    15,
    &targetURL,
    nullptr,
    CEF_WOD_NEW_POPUP,
    1,
    nullptr,
    &windowInfo,
    &popupClient,
    &settings,
    &extraInfo,
    &noJavaScriptAccess
  );

  XCTAssertEqual(result, 0);
  [self waitForExpectationsWithTimeout:0.1 handler:nil];
  XCTAssertTrue(probe.messages.empty());
  XCTAssertTrue(fakeBrowser.frame->lastLoadedURL.empty());

  CEFBridge_SetOpenURLInTabHandler(browserRef, nullptr, nullptr);
  fakeUTF16Clear(&targetURL);
  lifeSpanHandler->base.release(&lifeSpanHandler->base);
  client->base.release(&client->base);
}

- (void)testBrowserLifeSpanHandlerRedirectsImageTabDispositionWithoutEmittingTabOpenRequest {
  [self installBasicAPI];
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  const CEFBridgeBrowserRef browserRef = reinterpret_cast<CEFBridgeBrowserRef>(browserHandle);
  FakeBrowserHarness fakeBrowser;
  cef_client_t* client = miumNativeCEFTestCreateBrowserClient();
  XCTAssertNotEqual(client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), client));
  cef_life_span_handler_t* lifeSpanHandler = client->get_life_span_handler(client);
  XCTAssertNotEqual(lifeSpanHandler, nullptr);

  BridgeMessageProbe probe;
  probe.expectation = [self expectationWithDescription:@"image popup should not emit tab open request"];
  probe.expectation.inverted = YES;
  CEFBridge_SetOpenURLInTabHandler(browserRef, bridgeMessageCallback, &probe);

  static const char* targetURLCString = "https://navigator.test/image-in-tab.png";
  cef_string_t targetURL{};
  XCTAssertTrue(fakeUTF8ToUTF16(targetURLCString, strlen(targetURLCString), &targetURL));
  cef_window_info_t windowInfo{};
  cef_browser_settings_t settings{};
  cef_client_t* popupClient = nullptr;
  cef_dictionary_value_t* extraInfo = nullptr;
  int noJavaScriptAccess = 0;

  const int result = lifeSpanHandler->on_before_popup(
    lifeSpanHandler,
    fakeBrowser.browserRef(),
    &fakeBrowser.frame->frame,
    16,
    &targetURL,
    nullptr,
    CEF_WOD_NEW_BACKGROUND_TAB,
    1,
    nullptr,
    &windowInfo,
    &popupClient,
    &settings,
    &extraInfo,
    &noJavaScriptAccess
  );

  XCTAssertEqual(result, 1);
  [self waitForExpectationsWithTimeout:0.1 handler:nil];
  XCTAssertTrue(probe.messages.empty());
  XCTAssertEqual(fakeBrowser.frame->lastLoadedURL, targetURLCString);

  CEFBridge_SetOpenURLInTabHandler(browserRef, nullptr, nullptr);
  fakeUTF16Clear(&targetURL);
  lifeSpanHandler->base.release(&lifeSpanHandler->base);
  client->base.release(&client->base);
}

- (void)testBrowserLifeSpanHandlerReturnsZeroWithoutBrowserForTabDisposition {
  [self installBasicAPI];
  cef_client_t* client = miumNativeCEFTestCreateBrowserClient();
  XCTAssertNotEqual(client, nullptr);
  cef_life_span_handler_t* lifeSpanHandler = client->get_life_span_handler(client);
  XCTAssertNotEqual(lifeSpanHandler, nullptr);

  static const char* targetURLCString = "https://navigator.test/missing-popup-browser";
  cef_string_t targetURL{};
  XCTAssertTrue(fakeUTF8ToUTF16(targetURLCString, strlen(targetURLCString), &targetURL));
  cef_window_info_t windowInfo{};
  cef_browser_settings_t settings{};
  cef_client_t* popupClient = nullptr;
  cef_dictionary_value_t* extraInfo = nullptr;
  int noJavaScriptAccess = 0;

  const int result = lifeSpanHandler->on_before_popup(
    lifeSpanHandler,
    nullptr,
    nullptr,
    17,
    &targetURL,
    nullptr,
    CEF_WOD_NEW_BACKGROUND_TAB,
    1,
    nullptr,
    &windowInfo,
    &popupClient,
    &settings,
    &extraInfo,
    &noJavaScriptAccess
  );

  XCTAssertEqual(result, 0);

  fakeUTF16Clear(&targetURL);
  lifeSpanHandler->base.release(&lifeSpanHandler->base);
  client->base.release(&client->base);
}

- (void)testBrowserRequestHandlerEmitsCmdClickTargetAsTabOpenRequest {
  [self installBasicAPI];
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  const CEFBridgeBrowserRef browserRef = reinterpret_cast<CEFBridgeBrowserRef>(browserHandle);
  FakeBrowserHarness fakeBrowser;
  cef_client_t* client = miumNativeCEFTestCreateBrowserClient();
  XCTAssertNotEqual(client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), client));
  cef_request_handler_t* requestHandler = client->get_request_handler(client);
  XCTAssertNotEqual(requestHandler, nullptr);

  BridgeMessageProbe probe;
  probe.expectation = [self expectationWithDescription:@"request handler cmd click tab open request"];
  CEFBridge_SetOpenURLInTabHandler(browserRef, bridgeMessageCallback, &probe);

  static const char* targetURLCString = "https://navigator.test/cmd-click-request";
  cef_string_t targetURL{};
  XCTAssertTrue(fakeUTF8ToUTF16(targetURLCString, strlen(targetURLCString), &targetURL));

  const int result = requestHandler->on_open_urlfrom_tab(
    requestHandler,
    fakeBrowser.browserRef(),
    &fakeBrowser.frame->frame,
    &targetURL,
    CEF_WOD_NEW_BACKGROUND_TAB,
    1
  );

  XCTAssertEqual(result, 1);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(probe.messages.size(), static_cast<size_t>(1));
  NSDictionary<NSString*, id>* payload = bridgePayloadDictionary(probe.messages[0]);
  XCTAssertEqualObjects(payload[@"url"], @"https://navigator.test/cmd-click-request");
  XCTAssertEqualObjects(payload[@"activatesTab"], @NO);

  CEFBridge_SetOpenURLInTabHandler(browserRef, nullptr, nullptr);
  fakeUTF16Clear(&targetURL);
  requestHandler->base.release(&requestHandler->base);
  client->base.release(&client->base);
}

- (void)testBrowserRequestHandlerEmitsForegroundTabOpenRequest {
  [self installBasicAPI];
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  const CEFBridgeBrowserRef browserRef = reinterpret_cast<CEFBridgeBrowserRef>(browserHandle);
  FakeBrowserHarness fakeBrowser;
  cef_client_t* client = miumNativeCEFTestCreateBrowserClient();
  XCTAssertNotEqual(client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), client));
  cef_request_handler_t* requestHandler = client->get_request_handler(client);
  XCTAssertNotEqual(requestHandler, nullptr);

  BridgeMessageProbe probe;
  probe.expectation = [self expectationWithDescription:@"foreground request tab open request"];
  CEFBridge_SetOpenURLInTabHandler(browserRef, bridgeMessageCallback, &probe);

  static const char* targetURLCString = "https://navigator.test/foreground-request-tab";
  cef_string_t targetURL{};
  XCTAssertTrue(fakeUTF8ToUTF16(targetURLCString, strlen(targetURLCString), &targetURL));

  const int result = requestHandler->on_open_urlfrom_tab(
    requestHandler,
    fakeBrowser.browserRef(),
    &fakeBrowser.frame->frame,
    &targetURL,
    CEF_WOD_NEW_FOREGROUND_TAB,
    1
  );

  XCTAssertEqual(result, 1);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(probe.messages.size(), static_cast<size_t>(1));
  NSDictionary<NSString*, id>* payload = bridgePayloadDictionary(probe.messages[0]);
  XCTAssertEqualObjects(payload[@"url"], @"https://navigator.test/foreground-request-tab");
  XCTAssertEqualObjects(payload[@"activatesTab"], @YES);

  CEFBridge_SetOpenURLInTabHandler(browserRef, nullptr, nullptr);
  fakeUTF16Clear(&targetURL);
  requestHandler->base.release(&requestHandler->base);
  client->base.release(&client->base);
}

- (void)testBrowserRequestHandlerIgnoresNonTabDisposition {
  [self installBasicAPI];
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  const CEFBridgeBrowserRef browserRef = reinterpret_cast<CEFBridgeBrowserRef>(browserHandle);
  FakeBrowserHarness fakeBrowser;
  cef_client_t* client = miumNativeCEFTestCreateBrowserClient();
  XCTAssertNotEqual(client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), client));
  cef_request_handler_t* requestHandler = client->get_request_handler(client);
  XCTAssertNotEqual(requestHandler, nullptr);

  BridgeMessageProbe probe;
  probe.expectation = [self expectationWithDescription:@"non-tab request should not emit tab open request"];
  probe.expectation.inverted = YES;
  CEFBridge_SetOpenURLInTabHandler(browserRef, bridgeMessageCallback, &probe);

  static const char* targetURLCString = "https://navigator.test/request-non-tab";
  cef_string_t targetURL{};
  XCTAssertTrue(fakeUTF8ToUTF16(targetURLCString, strlen(targetURLCString), &targetURL));

  const int result = requestHandler->on_open_urlfrom_tab(
    requestHandler,
    fakeBrowser.browserRef(),
    &fakeBrowser.frame->frame,
    &targetURL,
    CEF_WOD_CURRENT_TAB,
    1
  );

  XCTAssertEqual(result, 0);
  [self waitForExpectationsWithTimeout:0.1 handler:nil];
  XCTAssertTrue(probe.messages.empty());

  CEFBridge_SetOpenURLInTabHandler(browserRef, nullptr, nullptr);
  fakeUTF16Clear(&targetURL);
  requestHandler->base.release(&requestHandler->base);
  client->base.release(&client->base);
}

- (void)testBrowserRequestHandlerReturnsZeroWithoutBrowserForTabDisposition {
  [self installBasicAPI];
  cef_client_t* client = miumNativeCEFTestCreateBrowserClient();
  XCTAssertNotEqual(client, nullptr);
  cef_request_handler_t* requestHandler = client->get_request_handler(client);
  XCTAssertNotEqual(requestHandler, nullptr);

  static const char* targetURLCString = "https://navigator.test/missing-request-browser";
  cef_string_t targetURL{};
  XCTAssertTrue(fakeUTF8ToUTF16(targetURLCString, strlen(targetURLCString), &targetURL));

  const int result = requestHandler->on_open_urlfrom_tab(
    requestHandler,
    nullptr,
    nullptr,
    &targetURL,
    CEF_WOD_NEW_BACKGROUND_TAB,
    1
  );

  XCTAssertEqual(result, 0);

  fakeUTF16Clear(&targetURL);
  requestHandler->base.release(&requestHandler->base);
  client->base.release(&client->base);
}

- (void)testBrowserResourceRequestHandlerEmitsTopLevelImageContentForExtensionlessQueryURL {
  [self installBasicAPI];
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  const CEFBridgeBrowserRef browserRef = reinterpret_cast<CEFBridgeBrowserRef>(browserHandle);
  FakeBrowserHarness fakeBrowser;
  cef_client_t* client = miumNativeCEFTestCreateBrowserClient();
  XCTAssertNotEqual(client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), client));
  cef_request_handler_t* requestHandler = client->get_request_handler(client);
  XCTAssertNotEqual(requestHandler, nullptr);

  LifecycleFakeRequestState request("https://navigator.test/asset?token=abc123");
  cef_resource_request_handler_t* resourceHandler = requestHandler->get_resource_request_handler(
    requestHandler,
    fakeBrowser.browserRef(),
    &fakeBrowser.frame->frame,
    request.requestRef(),
    1,
    0,
    nullptr,
    nullptr
  );
  XCTAssertNotEqual(resourceHandler, nullptr);

  BridgeMessageProbe probe;
  probe.expectation = [self expectationWithDescription:@"extensionless query image native content"];
  CEFBridge_SetTopLevelNativeContentHandler(browserRef, bridgeMessageCallback, &probe);

  LifecycleFakeResponseState response("image/png");
  const int result = resourceHandler->on_resource_response(
    resourceHandler,
    fakeBrowser.browserRef(),
    &fakeBrowser.frame->frame,
    request.requestRef(),
    response.responseRef()
  );

  XCTAssertEqual(result, 0);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(probe.messages.size(), static_cast<size_t>(1));
  NSDictionary<NSString*, id>* payload = bridgePayloadDictionary(probe.messages[0]);
  XCTAssertEqualObjects(payload[@"kind"], @"image");
  XCTAssertEqualObjects(payload[@"url"], @"https://navigator.test/asset?token=abc123");
  XCTAssertNil(payload[@"pathExtension"]);
  XCTAssertEqualObjects(payload[@"uniformTypeIdentifier"], @"public.png");

  CEFBridge_SetTopLevelNativeContentHandler(browserRef, nullptr, nullptr);
  resourceHandler->base.release(&resourceHandler->base);
  requestHandler->base.release(&requestHandler->base);
  client->base.release(&client->base);
}

- (void)testBrowserResourceRequestHandlerIgnoresNonImageMimeTypeForExtensionlessQueryURL {
  [self installBasicAPI];
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  const CEFBridgeBrowserRef browserRef = reinterpret_cast<CEFBridgeBrowserRef>(browserHandle);
  FakeBrowserHarness fakeBrowser;
  cef_client_t* client = miumNativeCEFTestCreateBrowserClient();
  XCTAssertNotEqual(client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), client));
  cef_request_handler_t* requestHandler = client->get_request_handler(client);
  XCTAssertNotEqual(requestHandler, nullptr);

  LifecycleFakeRequestState request("https://navigator.test/asset?token=abc123");
  cef_resource_request_handler_t* resourceHandler = requestHandler->get_resource_request_handler(
    requestHandler,
    fakeBrowser.browserRef(),
    &fakeBrowser.frame->frame,
    request.requestRef(),
    1,
    0,
    nullptr,
    nullptr
  );
  XCTAssertNotEqual(resourceHandler, nullptr);

  BridgeMessageProbe probe;
  probe.expectation = [self expectationWithDescription:@"non-image mime type should not emit native content"];
  probe.expectation.inverted = YES;
  CEFBridge_SetTopLevelNativeContentHandler(browserRef, bridgeMessageCallback, &probe);

  LifecycleFakeResponseState response("text/html");
  const int result = resourceHandler->on_resource_response(
    resourceHandler,
    fakeBrowser.browserRef(),
    &fakeBrowser.frame->frame,
    request.requestRef(),
    response.responseRef()
  );

  XCTAssertEqual(result, 0);
  [self waitForExpectationsWithTimeout:0.1 handler:nil];
  XCTAssertTrue(probe.messages.empty());

  CEFBridge_SetTopLevelNativeContentHandler(browserRef, nullptr, nullptr);
  resourceHandler->base.release(&resourceHandler->base);
  requestHandler->base.release(&requestHandler->base);
  client->base.release(&client->base);
}

- (void)testEvaluateJavaScriptExecutesScriptAndCompletes {
  [self installBasicAPI];
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness fakeBrowser;
  CallbackProbe probe;
  probe.expectation = [self expectationWithDescription:@"script completed"];

  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), nullptr));

  const MiumCEFResultCode result = miumNativeCEFEvaluateJavaScript(browserHandle, "window.test()", &probe, testNativeCallback);

  XCTAssertEqual(result, MiumCEFResultOK);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(fakeBrowser.frame->lastExecutedScript, "window.test()");
  XCTAssertEqual(probe.code, MiumCEFResultOK);
  XCTAssertEqual(probe.message, "{\"dispatched\":true}");
}

- (void)testSendMessageBuildsRendererProcessMessage {
  [self installBasicAPI];
  FakeProcessMessageFactory messageFactory;
  gProcessMessageFactory = &messageFactory;

  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createProcessMessage = fakeCreateProcessMessage;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness fakeBrowser;
  CallbackProbe probe;
  probe.expectation = [self expectationWithDescription:@"send completed"];

  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), nullptr));

  const MiumCEFResultCode result = miumNativeCEFSendMessage(browserHandle, "bridge", "{\"ok\":true}", &probe, testNativeCallback);

  XCTAssertEqual(result, MiumCEFResultOK);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  if (probe.code != MiumCEFResultOK) {
    NSLog(@"PNG snapshot failure: %s", probe.message.c_str());
  }
  XCTAssertEqual(probe.code, MiumCEFResultOK);
  XCTAssertEqual(probe.message, "{\"acknowledged\":true}");
  XCTAssertEqual(messageFactory.lastCreatedName, "bridge");
  XCTAssertEqual(fakeBrowser.frame->sendProcessMessageCalls, 1);
  XCTAssertEqual(fakeBrowser.frame->lastProcessId, 1);
  XCTAssertNotEqual(fakeBrowser.frame->lastMessage, nullptr);
  XCTAssertEqual(fakeBrowser.frame->lastMessage->arguments.values.size(), static_cast<size_t>(1));
  XCTAssertEqual(fakeBrowser.frame->lastMessage->arguments.values[0], "{\"ok\":true}");
}

- (void)testSendMessageFailsWithoutProcessMessageFactory {
  [self installBasicAPI];
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness fakeBrowser;
  CallbackProbe probe;
  probe.expectation = [self expectationWithDescription:@"send failure delivered"];

  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), nullptr));

  const MiumCEFResultCode result = miumNativeCEFSendMessage(browserHandle, "bridge", "{}", &probe, testNativeCallback);

  XCTAssertEqual(result, MiumCEFResultError);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(probe.code, MiumCEFResultError);
  XCTAssertTrue(probe.message.find("process messaging unavailable") != std::string::npos);
}

- (void)testResizeBrowserRejectsNonPositiveDimensions {
  [self installBasicAPI];
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness fakeBrowser;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), nullptr));

  XCTAssertEqual(miumNativeCEFResizeBrowser(browserHandle, 0, 100), MiumCEFResultError);
  XCTAssertEqual(miumNativeCEFResizeBrowser(browserHandle, 100, -10), MiumCEFResultError);
  XCTAssertEqual(fakeBrowser.host->notifyMoveOrResizeStartedCalls, 0);
  XCTAssertEqual(fakeBrowser.host->wasResizedCalls, 0);
}

- (void)testResizeBrowserNotifiesBrowserHost {
  [self installBasicAPI];
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness fakeBrowser;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), nullptr));

  XCTAssertEqual(miumNativeCEFResizeBrowser(browserHandle, 320, 180), MiumCEFResultOK);
  XCTAssertEqual(fakeBrowser.host->notifyMoveOrResizeStartedCalls, 1);
  XCTAssertEqual(fakeBrowser.host->wasResizedCalls, 1);
}

- (void)testBackgroundQueueDispatchesResizeAndMessageLoopWork {
  MiumCEFBridgeTestAPI api{};
  api.doMessageLoopWork = fakeDoMessageLoopWork;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness fakeBrowser;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), nullptr));

  __block MiumCEFResultCode loopResult = MiumCEFResultError;
  [self runOnBackgroundQueueAndWait:^{
    loopResult = miumNativeCEFDoMessageLoopWork();
  }];
  XCTAssertEqual(loopResult, MiumCEFResultOK);
  XCTAssertEqual(gMessageLoopWorkCalls, 1);

  __block MiumCEFResultCode resizeResult = MiumCEFResultError;
  [self runOnBackgroundQueueAndWait:^{
    resizeResult = miumNativeCEFResizeBrowser(browserHandle, 320, 180);
  }];
  XCTAssertEqual(resizeResult, MiumCEFResultOK);
  XCTAssertEqual(fakeBrowser.host->notifyMoveOrResizeStartedCalls, 1);
  XCTAssertEqual(fakeBrowser.host->wasResizedCalls, 1);
}

- (void)testDestroyBrowserWithNativeBrowserClosesAndInvalidatesHandle {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness fakeBrowser;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), nullptr));

  CallbackProbe probe;
  XCTAssertEqual(
    miumNativeCEFRegisterMessageHandler(browserHandle, "channel", &probe, testNativeCallback),
    MiumCEFResultOK
  );

  XCTAssertEqual(miumNativeCEFDestroyBrowser(browserHandle), MiumCEFResultOK);
  XCTAssertEqual(fakeBrowser.host->closeBrowserCalls, 1);
  XCTAssertEqual(miumNativeCEFEmitMessage(browserHandle, "channel", "hello"), MiumCEFResultNotInitialized);
  XCTAssertEqual(miumNativeCEFGoBack(browserHandle), MiumCEFResultNotInitialized);
}

- (void)testManagedBrowserSubviewsResizeAndReplacementRemovesStaleSubviews {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle hostViewHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &hostViewHandle), MiumCEFResultOK);

  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 50)];
  NSView* overlaySubview = [[NSView alloc] initWithFrame:NSMakeRect(12, 11, 9, 8)];
  [hostView addSubview:overlaySubview];
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(hostViewHandle, (__bridge void*)hostView));

  NSView* firstManagedSubview = nil;
  NSView* secondManagedSubview = nil;
  FakeCreateBrowserFactory factory;
  factory.onCreate = [&] {
    NSView* parentView = (__bridge NSView*)factory.lastParentView;
    NSView* createdSubview = [[NSView alloc] initWithFrame:NSMakeRect(4, 3, 2, 1)];
    [parentView addSubview:createdSubview];
    if (firstManagedSubview == nil) {
      firstManagedSubview = createdSubview;
    } else {
      secondManagedSubview = createdSubview;
    }
  };
  gCreateBrowserFactory = &factory;

  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(browserHandle, hostViewHandle), MiumCEFResultOK);
  XCTAssertNotNil(firstManagedSubview);
  XCTAssertEqual(miumNativeCEFResizeBrowser(browserHandle, 320, 180), MiumCEFResultOK);
  XCTAssertEqualWithAccuracy(firstManagedSubview.frame.origin.x, 0.0, 0.001);
  XCTAssertEqualWithAccuracy(firstManagedSubview.frame.origin.y, 0.0, 0.001);
  XCTAssertEqualWithAccuracy(firstManagedSubview.frame.size.width, 160.0, 0.001);
  XCTAssertEqualWithAccuracy(firstManagedSubview.frame.size.height, 90.0, 0.001);
  XCTAssertEqualWithAccuracy(overlaySubview.frame.origin.x, 12.0, 0.001);
  XCTAssertEqualWithAccuracy(overlaySubview.frame.origin.y, 11.0, 0.001);
  XCTAssertEqualWithAccuracy(overlaySubview.frame.size.width, 9.0, 0.001);
  XCTAssertEqualWithAccuracy(overlaySubview.frame.size.height, 8.0, 0.001);

  XCTAssertEqual(miumNativeCEFDetachBrowserFromHostView(browserHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(browserHandle, hostViewHandle), MiumCEFResultOK);
  XCTAssertNotNil(secondManagedSubview);
  XCTAssertNil(firstManagedSubview.superview);
  XCTAssertEqual(secondManagedSubview.superview, embeddedParentViewForHostView(hostView));
  XCTAssertEqual(overlaySubview.superview, hostView);
  XCTAssertEqual(hostView.subviews.count, static_cast<NSUInteger>(2));
  gCreateBrowserFactory = nullptr;
}

- (void)testResetStateRemovesManagedBrowserSubviewsAcrossHostViews {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle firstBrowserHandle = [self createBrowserForRuntime:runtimeHandle];
  const MiumCEFBrowserHandle secondBrowserHandle = [self createBrowserForRuntime:runtimeHandle];

  MiumCEFHostViewHandle firstHostViewHandle = nullptr;
  MiumCEFHostViewHandle secondHostViewHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(firstBrowserHandle, &firstHostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(secondBrowserHandle, &secondHostViewHandle), MiumCEFResultOK);

  NSView* firstHostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 50)];
  NSView* secondHostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 60)];
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(firstHostViewHandle, (__bridge void*)firstHostView));
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(secondHostViewHandle, (__bridge void*)secondHostView));

  NSView* firstManagedSubview = nil;
  NSView* secondManagedSubview = nil;
  FakeCreateBrowserFactory factory;
  factory.onCreate = [&] {
    NSView* parentView = (__bridge NSView*)factory.lastParentView;
    NSView* createdSubview = [[NSView alloc] initWithFrame:NSMakeRect(1, 2, 3, 4)];
    [parentView addSubview:createdSubview];
    if (firstManagedSubview == nil) {
      firstManagedSubview = createdSubview;
    } else {
      secondManagedSubview = createdSubview;
    }
  };
  gCreateBrowserFactory = &factory;

  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(firstBrowserHandle, firstHostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(secondBrowserHandle, secondHostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(firstManagedSubview.superview, embeddedParentViewForHostView(firstHostView));
  XCTAssertEqual(secondManagedSubview.superview, embeddedParentViewForHostView(secondHostView));

  miumNativeCEFTestResetState();

  XCTAssertEqual(embeddedParentViewForHostView(firstHostView), firstHostView);
  XCTAssertEqual(embeddedParentViewForHostView(secondHostView), secondHostView);
  XCTAssertFalse([firstManagedSubview isDescendantOf:firstHostView]);
  XCTAssertFalse([secondManagedSubview isDescendantOf:secondHostView]);
  gCreateBrowserFactory = nullptr;
}

- (void)testPublicAPINegativeBranches {
  CallbackProbe loadProbe;
  loadProbe.expectation = [self expectationWithDescription:@"load invalid argument"];
  XCTAssertEqual(miumNativeCEFLoadURL(nullptr, "https://example.com", &loadProbe, testNativeCallback), MiumCEFResultInvalidArgument);
  [self waitForExpectations:@[ loadProbe.expectation ] timeout:kCallbackTimeout];
  XCTAssertEqual(loadProbe.message, "Invalid browser handle");

  CallbackProbe scriptProbe;
  scriptProbe.expectation = [self expectationWithDescription:@"script invalid argument"];
  XCTAssertEqual(miumNativeCEFEvaluateJavaScript(nullptr, "1+1", &scriptProbe, testNativeCallback), MiumCEFResultInvalidArgument);
  CallbackProbe sendProbe;
  sendProbe.expectation = [self expectationWithDescription:@"send invalid argument"];
  XCTAssertEqual(miumNativeCEFSendMessage(nullptr, nullptr, "{}", &sendProbe, testNativeCallback), MiumCEFResultInvalidArgument);
  CallbackProbe snapshotProbe;
  snapshotProbe.expectation = [self expectationWithDescription:@"snapshot invalid argument"];
  XCTAssertEqual(miumNativeCEFRequestSnapshot(nullptr, "/tmp/out.png", nullptr, &snapshotProbe, testNativeCallback), MiumCEFResultInvalidArgument);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];

  XCTAssertEqual(miumNativeCEFGoBack(nullptr), MiumCEFResultInvalidArgument);
  XCTAssertEqual(miumNativeCEFGoForward(nullptr), MiumCEFResultInvalidArgument);
  XCTAssertEqual(miumNativeCEFReload(nullptr), MiumCEFResultInvalidArgument);
  XCTAssertEqual(miumNativeCEFStopLoad(nullptr), MiumCEFResultInvalidArgument);
  XCTAssertEqual(miumNativeCEFResizeBrowser(nullptr, 10, 10), MiumCEFResultInvalidArgument);
  XCTAssertEqual(miumNativeCEFCanGoBack(nullptr), 0);
  XCTAssertEqual(miumNativeCEFCanGoForward(nullptr), 0);
  XCTAssertEqual(miumNativeCEFIsLoading(nullptr), 0);
  XCTAssertEqual(miumNativeCEFRegisterMessageHandler(nullptr, "channel", nullptr, testNativeCallback), MiumCEFResultInvalidArgument);
  XCTAssertEqual(miumNativeCEFEmitMessage(nullptr, "channel", "message"), MiumCEFResultInvalidArgument);

  MiumCEFBrowserHandle browserHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowser(nullptr, &browserHandle), MiumCEFResultInvalidArgument);
  XCTAssertEqual(miumNativeCEFCreateBrowser(reinterpret_cast<MiumCEFRuntimeHandle>(0x99), nullptr), MiumCEFResultInvalidArgument);
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(nullptr, nullptr), MiumCEFResultInvalidArgument);
  XCTAssertEqual(miumNativeCEFCreateBrowserHostViewForNSView(reinterpret_cast<MiumCEFBrowserHandle>(0x44), nullptr, &browserHandle), MiumCEFResultInvalidArgument);
  XCTAssertEqual(miumNativeCEFDestroyBrowser(nullptr), MiumCEFResultInvalidArgument);
  XCTAssertEqual(miumNativeCEFDestroyBrowserHostView(nullptr), MiumCEFResultInvalidArgument);
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(nullptr, nullptr), MiumCEFResultInvalidArgument);
  XCTAssertEqual(miumNativeCEFDetachBrowserFromHostView(nullptr), MiumCEFResultInvalidArgument);
  XCTAssertEqual(miumNativeCEFShutdown(nullptr), MiumCEFResultInvalidArgument);
}

- (void)testInactiveBrowserHandleSweepCoversRemainingPublicBranches {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createProcessMessage = fakeCreateProcessMessage;
  miumNativeCEFTestInstallAPI(&api);
  FakeProcessMessageFactory messageFactory;
  gProcessMessageFactory = &messageFactory;

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness fakeBrowser;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), nullptr));

  CallbackProbe emptyOutputProbe;
  emptyOutputProbe.expectation = [self expectationWithDescription:@"snapshot empty output"];
  XCTAssertEqual(
    miumNativeCEFRequestSnapshot(browserHandle, "", nullptr, &emptyOutputProbe, testNativeCallback),
    MiumCEFResultInvalidArgument
  );
  [self waitForExpectations:@[ emptyOutputProbe.expectation ] timeout:kCallbackTimeout];
  XCTAssertEqual(emptyOutputProbe.message, "Output path is required");

  XCTAssertEqual(miumNativeCEFDestroyBrowser(browserHandle), MiumCEFResultOK);
  [self drainPendingAsyncWork];
  XCTAssertEqual(miumNativeCEFGoBack(browserHandle), MiumCEFResultNotInitialized);
  XCTAssertEqual(miumNativeCEFGoForward(browserHandle), MiumCEFResultNotInitialized);
  XCTAssertEqual(miumNativeCEFReload(browserHandle), MiumCEFResultNotInitialized);
  XCTAssertEqual(miumNativeCEFStopLoad(browserHandle), MiumCEFResultNotInitialized);
  XCTAssertEqual(miumNativeCEFCanGoBack(browserHandle), 0);
  XCTAssertEqual(miumNativeCEFCanGoForward(browserHandle), 0);
  XCTAssertEqual(miumNativeCEFIsLoading(browserHandle), 0);

  CallbackProbe loadProbe;
  CallbackProbe scriptProbe;
  CallbackProbe snapshotProbe;
  CallbackProbe sendProbe;

  XCTAssertEqual(
    miumNativeCEFLoadURL(browserHandle, "https://stale.example", &loadProbe, testNativeCallback),
    MiumCEFResultNotInitialized
  );
  XCTAssertEqual(
    miumNativeCEFEvaluateJavaScript(browserHandle, "1 + 1", &scriptProbe, testNativeCallback),
    MiumCEFResultNotInitialized
  );
  XCTAssertEqual(
    miumNativeCEFRequestSnapshot(browserHandle, "/tmp/stale.png", nullptr, &snapshotProbe, testNativeCallback),
    MiumCEFResultNotInitialized
  );
  XCTAssertEqual(
    miumNativeCEFSendMessage(browserHandle, "bridge", "{}", &sendProbe, testNativeCallback),
    MiumCEFResultNotInitialized
  );
  XCTAssertEqual(loadProbe.invocationCount, 0);
  XCTAssertEqual(scriptProbe.invocationCount, 0);
  XCTAssertEqual(snapshotProbe.invocationCount, 0);
  XCTAssertEqual(sendProbe.invocationCount, 0);
}

- (void)testBrowserOperationsRequireUsableRuntimeBeforeReportingNativeImplementationErrors {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];

  XCTAssertEqual(miumNativeCEFGoForward(browserHandle), MiumCEFResultNotInitialized);
  XCTAssertEqual(miumNativeCEFReload(browserHandle), MiumCEFResultNotInitialized);
  XCTAssertEqual(miumNativeCEFStopLoad(browserHandle), MiumCEFResultNotInitialized);
  XCTAssertEqual(miumNativeCEFCanGoBack(browserHandle), 0);
  XCTAssertEqual(miumNativeCEFCanGoForward(browserHandle), 0);
  XCTAssertEqual(miumNativeCEFIsLoading(browserHandle), 0);
  XCTAssertEqual(miumNativeCEFResizeBrowser(browserHandle, 120, 80), MiumCEFResultNotInitialized);

  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  FakeBrowserHarness partialBrowser;
  partialBrowser.browser->browser.go_forward = nullptr;
  partialBrowser.browser->browser.reload = nullptr;
  partialBrowser.browser->browser.stop_load = nullptr;
  partialBrowser.browser->browser.can_go_back = nullptr;
  partialBrowser.browser->browser.can_go_forward = nullptr;
  partialBrowser.browser->browser.is_loading = nullptr;
  partialBrowser.frame->frame.load_url = nullptr;
  partialBrowser.frame->frame.execute_java_script = nullptr;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, partialBrowser.browserRef(), nullptr));

  CallbackProbe loadProbe;
  loadProbe.expectation = [self expectationWithDescription:@"load unavailable"];
  CallbackProbe scriptProbe;
  scriptProbe.expectation = [self expectationWithDescription:@"script unavailable"];

  XCTAssertEqual(miumNativeCEFLoadURL(browserHandle, "https://example.com", &loadProbe, testNativeCallback), MiumCEFResultError);
  XCTAssertEqual(miumNativeCEFEvaluateJavaScript(browserHandle, "window.test()", &scriptProbe, testNativeCallback), MiumCEFResultError);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];

  XCTAssertEqual(loadProbe.code, MiumCEFResultError);
  XCTAssertTrue(loadProbe.message.find("load_url unavailable") != std::string::npos);
  XCTAssertEqual(scriptProbe.code, MiumCEFResultError);
  XCTAssertEqual(scriptProbe.message, "CEF execute_java_script unavailable");
}

- (void)testDestroyBrowserAndHostViewRepeatedCallsReturnNotInitialized {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle hostViewHandle = nullptr;
  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 80, 40)];

  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &hostViewHandle), MiumCEFResultOK);
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(hostViewHandle, (__bridge void*)hostView));
  XCTAssertEqual(miumNativeCEFDestroyBrowserHostView(hostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFDestroyBrowserHostView(hostViewHandle), MiumCEFResultNotInitialized);

  XCTAssertEqual(miumNativeCEFDestroyBrowser(browserHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFDestroyBrowser(browserHandle), MiumCEFResultNotInitialized);
  XCTAssertEqual(miumNativeCEFDetachBrowserFromHostView(browserHandle), MiumCEFResultNotInitialized);
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(browserHandle, hostViewHandle), MiumCEFResultNotInitialized);
}

- (void)testAttachBrowserToHostViewCoversReattachReplacementAndFailures {
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
  MiumCEFHostViewHandle firstHostViewHandle = nullptr;
  MiumCEFHostViewHandle secondHostViewHandle = nullptr;
  NSView* firstHostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];
  NSView* secondHostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 140, 90)];

  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &firstHostViewHandle), MiumCEFResultOK);
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(firstHostViewHandle, (__bridge void*)firstHostView));
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(browserHandle, firstHostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(factory.callCount, 1);

  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(browserHandle, firstHostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(factory.callCount, 1);
  XCTAssertEqual(miumNativeCEFTestHostViewHandleForBrowser(browserHandle), firstHostViewHandle);

  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &secondHostViewHandle), MiumCEFResultOK);
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(secondHostViewHandle, (__bridge void*)secondHostView));
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(browserHandle, secondHostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(factory.callCount, 2);
  XCTAssertEqual(miumNativeCEFTestHostViewHandleForBrowser(browserHandle), secondHostViewHandle);
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(firstHostViewHandle), nullptr);
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(secondHostViewHandle), browserHandle);

  const MiumCEFBrowserHandle invalidBrowserHandle = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle missingPointerHostViewHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(invalidBrowserHandle, &missingPointerHostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(invalidBrowserHandle, missingPointerHostViewHandle), MiumCEFResultInvalidArgument);

  MiumCEFBridgeTestAPI missingCreateAPI{};
  missingCreateAPI.utf8ToUTF16 = fakeUTF8ToUTF16;
  missingCreateAPI.utf16Clear = fakeUTF16Clear;
  miumNativeCEFTestInstallAPI(&missingCreateAPI);
  miumNativeCEFTestSetInitialized(true, 1);
  const MiumCEFBrowserHandle browserWithoutCreator = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle hostWithoutCreator = nullptr;
  NSView* hostWithoutCreatorView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 80, 60)];
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserWithoutCreator, &hostWithoutCreator), MiumCEFResultOK);
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(hostWithoutCreator, (__bridge void*)hostWithoutCreatorView));
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(browserWithoutCreator, hostWithoutCreator), MiumCEFResultError);
}

- (void)testEvaluateJavaScriptAndSendMessageCoverAdditionalInputBranches {
  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  FakeBrowserHarness fakeBrowser;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), nullptr));

  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16MaybeFail;
  api.utf16Clear = fakeUTF16Clear;
  api.createProcessMessage = fakeCreateProcessMessage;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);
  FakeProcessMessageFactory messageFactory;
  gProcessMessageFactory = &messageFactory;

  CallbackProbe nilScriptProbe;
  nilScriptProbe.expectation = [self expectationWithDescription:@"nil script"];
  XCTAssertEqual(miumNativeCEFEvaluateJavaScript(browserHandle, nullptr, &nilScriptProbe, testNativeCallback), MiumCEFResultOK);

  CallbackProbe nilPayloadProbe;
  nilPayloadProbe.expectation = [self expectationWithDescription:@"nil payload"];
  XCTAssertEqual(miumNativeCEFSendMessage(browserHandle, "bridge", nullptr, &nilPayloadProbe, testNativeCallback), MiumCEFResultOK);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(nilScriptProbe.message, "{\"dispatched\":true}");
  XCTAssertEqual(fakeBrowser.frame->lastExecutedScript, "");
  XCTAssertEqual(nilPayloadProbe.message, "{\"acknowledged\":true}");
  XCTAssertNotEqual(fakeBrowser.frame->lastMessage, nullptr);
  XCTAssertEqual(fakeBrowser.frame->lastMessage->arguments.values[0], "");

  gUTF8ConversionFailureNeedle = "window.fail()";
  CallbackProbe scriptConversionProbe;
  scriptConversionProbe.expectation = [self expectationWithDescription:@"script conversion failure"];
  XCTAssertEqual(miumNativeCEFEvaluateJavaScript(browserHandle, "window.fail()", &scriptConversionProbe, testNativeCallback), MiumCEFResultError);

  gUTF8ConversionFailureNeedle = "{\"fail\":true}";
  CallbackProbe payloadConversionProbe;
  payloadConversionProbe.expectation = [self expectationWithDescription:@"payload conversion failure"];
  XCTAssertEqual(miumNativeCEFSendMessage(browserHandle, "bridge", "{\"fail\":true}", &payloadConversionProbe, testNativeCallback), MiumCEFResultError);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertTrue(scriptConversionProbe.message.find("convert UTF8 to UTF16") != std::string::npos);
  XCTAssertTrue(payloadConversionProbe.message.find("convert UTF8 to UTF16") != std::string::npos);

  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createProcessMessage = nullptr;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);
  CallbackProbe missingMessageAPIProbe;
  missingMessageAPIProbe.expectation = [self expectationWithDescription:@"missing process message api"];
  XCTAssertEqual(miumNativeCEFSendMessage(browserHandle, "bridge", "{}", &missingMessageAPIProbe, testNativeCallback), MiumCEFResultError);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertEqual(missingMessageAPIProbe.code, MiumCEFResultError);
  XCTAssertEqual(missingMessageAPIProbe.invocationCount, 1);

  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createProcessMessage = fakeCreateNullProcessMessage;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);
  CallbackProbe nullMessageProbe;
  nullMessageProbe.expectation = [self expectationWithDescription:@"null process message"];
  XCTAssertEqual(miumNativeCEFSendMessage(browserHandle, "bridge", "{}", &nullMessageProbe, testNativeCallback), MiumCEFResultError);
  [self waitForExpectationsWithTimeout:kCallbackTimeout handler:nil];
  XCTAssertTrue(nullMessageProbe.message.find("message delivery unavailable") != std::string::npos);
}

- (void)testExecutorHelperCoversInlineExecutorRoutes {
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
  fakeBrowser.browser->canGoBackResult = 1;
  fakeBrowser.browser->canGoForwardResult = 1;
  fakeBrowser.browser->isLoadingResult = 1;
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(browserHandle, fakeBrowser.browserRef(), nullptr));

  CallbackProbe loadProbe;
  loadProbe.expectation = [self expectationWithDescription:@"executor load"];
  CallbackProbe scriptProbe;
  scriptProbe.expectation = [self expectationWithDescription:@"executor script"];
  CallbackProbe sendProbe;
  sendProbe.expectation = [self expectationWithDescription:@"executor send"];

  ExecutorCoverageContext context;
  context.browserHandle = browserHandle;
  context.loadProbe = &loadProbe;
  context.scriptProbe = &scriptProbe;
  context.sendProbe = &sendProbe;

  miumNativeCEFTestRunOnCefExecutor(&context, runExecutorCoverageActions);
  [self waitForExpectations:@[ loadProbe.expectation, scriptProbe.expectation, sendProbe.expectation ]
                    timeout:kCallbackTimeout];
  XCTAssertEqual(context.goBackResult, MiumCEFResultOK);
  XCTAssertEqual(context.goForwardResult, MiumCEFResultOK);
  XCTAssertEqual(context.reloadResult, MiumCEFResultOK);
  XCTAssertEqual(context.stopLoadResult, MiumCEFResultOK);
  XCTAssertEqual(context.resizeResult, MiumCEFResultOK);
  XCTAssertEqual(context.loadURLResult, MiumCEFResultOK);
  XCTAssertEqual(context.evaluateResult, MiumCEFResultOK);
  XCTAssertEqual(context.sendResult, MiumCEFResultOK);
  XCTAssertEqual(context.canGoBack, 1);
  XCTAssertEqual(context.canGoForward, 1);
  XCTAssertEqual(context.isLoading, 1);
  XCTAssertEqual(fakeBrowser.browser->goBackCalls, 1);
  XCTAssertEqual(fakeBrowser.browser->goForwardCalls, 1);
  XCTAssertEqual(fakeBrowser.browser->reloadCalls, 1);
  XCTAssertEqual(fakeBrowser.browser->stopLoadCalls, 1);
  XCTAssertEqual(fakeBrowser.host->notifyMoveOrResizeStartedCalls, 1);
  XCTAssertEqual(fakeBrowser.host->wasResizedCalls, 1);
  XCTAssertEqual(loadProbe.message, "https://executor.example");
  XCTAssertEqual(scriptProbe.message, "{\"dispatched\":true}");
  XCTAssertEqual(sendProbe.message, "{\"acknowledged\":true}");
}

- (void)testDestroyBrowserHostViewClearsBindingAndAllowsLaterReattach {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  NSView* firstManagedSubview = nil;
  FakeCreateBrowserFactory factory;
  factory.onCreate = [&] {
    if (firstManagedSubview == nil) {
      NSView* parentView = (__bridge NSView*)factory.lastParentView;
      firstManagedSubview = [[NSView alloc] initWithFrame:NSMakeRect(1, 1, 10, 10)];
      [parentView addSubview:firstManagedSubview];
    }
  };
  gCreateBrowserFactory = &factory;

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle firstHostViewHandle = nullptr;
  MiumCEFHostViewHandle secondHostViewHandle = nullptr;
  NSView* firstHostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 70)];
  NSView* secondHostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 110, 75)];

  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &firstHostViewHandle), MiumCEFResultOK);
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(firstHostViewHandle, (__bridge void*)firstHostView));
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(browserHandle, firstHostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(firstManagedSubview.superview, embeddedParentViewForHostView(firstHostView));

  XCTAssertEqual(miumNativeCEFDestroyBrowserHostView(firstHostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFTestHostViewHandleForBrowser(browserHandle), nullptr);
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(firstHostViewHandle), nullptr);
  XCTAssertNil(firstManagedSubview.superview);

  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &secondHostViewHandle), MiumCEFResultOK);
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(secondHostViewHandle, (__bridge void*)secondHostView));
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(browserHandle, secondHostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFTestHostViewHandleForBrowser(browserHandle), secondHostViewHandle);
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(secondHostViewHandle), browserHandle);
}

- (void)testDestroyBrowserClearsBoundHostViewAndManagedSubviews {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  NSView* managedSubview = nil;
  FakeCreateBrowserFactory factory;
  factory.onCreate = [&] {
    NSView* parentView = (__bridge NSView*)factory.lastParentView;
    managedSubview = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 12, 12)];
    [parentView addSubview:managedSubview];
  };
  gCreateBrowserFactory = &factory;

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle hostViewHandle = nullptr;
  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];

  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &hostViewHandle), MiumCEFResultOK);
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(hostViewHandle, (__bridge void*)hostView));
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(browserHandle, hostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(managedSubview.superview, embeddedParentViewForHostView(hostView));

  XCTAssertEqual(miumNativeCEFDestroyBrowser(browserHandle), MiumCEFResultOK);
  XCTAssertEqual(miumNativeCEFTestBrowserHandleForHostView(hostViewHandle), nullptr);
  XCTAssertEqual(miumNativeCEFTestGetBrowserHostViewId(browserHandle), static_cast<uint64_t>(0));
  XCTAssertNil(managedSubview.superview);
}

- (void)testAttachBrowserInRealWindowHierarchyEmbedsSubviewResizesAndCleansUp {
  MiumCEFBridgeTestAPI api{};
  api.utf8ToUTF16 = fakeUTF8ToUTF16;
  api.utf16Clear = fakeUTF16Clear;
  api.createBrowserSync = fakeCreateBrowserSync;
  miumNativeCEFTestInstallAPI(&api);
  miumNativeCEFTestSetInitialized(true, 1);

  NSView* embeddedSubview = nil;
  FakeCreateBrowserFactory factory;
  factory.onCreate = [&] {
    NSView* parentView = (__bridge NSView*)factory.lastParentView;
    embeddedSubview = [[NSView alloc] initWithFrame:NSMakeRect(2, 3, 20, 10)];
    [parentView addSubview:embeddedSubview];
  };
  gCreateBrowserFactory = &factory;
  FakeCreateBrowserFactory* factoryPtr = &factory;

  NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 180, 120)
                                                 styleMask:NSWindowStyleMaskBorderless
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
  NSView* hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)];
  [window.contentView addSubview:hostView];
  [window orderFrontRegardless];

  const MiumCEFRuntimeHandle runtimeHandle = [self seedRuntime];
  const MiumCEFBrowserHandle browserHandle = [self createBrowserForRuntime:runtimeHandle];
  MiumCEFHostViewHandle hostViewHandle = nullptr;
  XCTAssertEqual(miumNativeCEFCreateBrowserHostView(browserHandle, &hostViewHandle), MiumCEFResultOK);
  XCTAssertTrue(miumNativeCEFTestSetHostViewPointer(hostViewHandle, (__bridge void*)hostView));
  XCTAssertEqual(miumNativeCEFAttachBrowserToHostView(browserHandle, hostViewHandle), MiumCEFResultOK);
  XCTAssertEqual(embeddedSubview.superview, embeddedParentViewForHostView(hostView));
  XCTAssertEqual(factory.lastParentView, (__bridge void*)embeddedParentViewForHostView(hostView));

  XCTAssertEqual(miumNativeCEFResizeBrowser(browserHandle, 200, 120), MiumCEFResultOK);
  [self waitUntil:^BOOL {
    return factoryPtr->createdBrowsers.back()->host->notifyMoveOrResizeStartedCalls >= 1
      && factoryPtr->createdBrowsers.back()->host->wasResizedCalls >= 1;
  } description:@"real window resize drain"];
  XCTAssertGreaterThanOrEqual(factory.createdBrowsers.back()->host->notifyMoveOrResizeStartedCalls, 1);
  XCTAssertGreaterThanOrEqual(factory.createdBrowsers.back()->host->wasResizedCalls, 1);

  XCTAssertEqual(miumNativeCEFDestroyBrowser(browserHandle), MiumCEFResultOK);
  [self waitUntil:^BOOL {
    return embeddedSubview.superview == nil;
  } description:@"real window destroy cleanup"];
  XCTAssertNil(embeddedSubview.superview);
  [window orderOut:nil];
}

@end
