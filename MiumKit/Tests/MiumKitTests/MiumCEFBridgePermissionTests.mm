#import "MiumCEFBridgeNativeTestSupport.h"

#include "../../Sources/MiumKit/MiumCEFBridgePermissions.h"

using namespace MiumCEFBridgeNativeTestSupport;

namespace {

template <typename T>
struct ScopedCefRef {
  T* value = nullptr;

  ScopedCefRef() = default;
  explicit ScopedCefRef(T* rawValue) : value(rawValue) {}

  ScopedCefRef(const ScopedCefRef&) = delete;
  ScopedCefRef& operator=(const ScopedCefRef&) = delete;

  ScopedCefRef(ScopedCefRef&& other) noexcept : value(other.value) {
    other.value = nullptr;
  }

  ScopedCefRef& operator=(ScopedCefRef&& other) noexcept {
    if (this == &other) {
      return *this;
    }
    reset();
    value = other.value;
    other.value = nullptr;
    return *this;
  }

  ~ScopedCefRef() {
    reset();
  }

  void reset(T* rawValue = nullptr) {
    if (value != nullptr && value->base.release != nullptr) {
      value->base.release(&value->base);
    }
    value = rawValue;
  }

  T* get() const {
    return value;
  }

  T* operator->() const {
    return value;
  }

  explicit operator bool() const {
    return value != nullptr;
  }
};

struct ScopedCEFString {
  cef_string_t value{};

  explicit ScopedCEFString(const char* utf8) {
    if (utf8 != nullptr) {
      fakeUTF8ToUTF16(utf8, std::strlen(utf8), &value);
    }
  }

  ~ScopedCEFString() {
    fakeUTF16Clear(&value);
  }

  const cef_string_t* ref() const {
    return &value;
  }
};

struct PermissionRequestRecord {
  MiumCEFPermissionSessionID sessionID = 0;
  uint64_t browserID = 0;
  uint64_t promptID = 0;
  std::string frameIdentifier;
  bool frameIdentifierWasNull = false;
  uint32_t permissionFlags = 0;
  uint32_t source = 0;
  std::string requestingOrigin;
  bool requestingOriginWasNull = false;
  std::string topLevelOrigin;
  bool topLevelOriginWasNull = false;
};

struct PermissionRequestProbe {
  mutable std::mutex mutex;
  std::vector<PermissionRequestRecord> requests;
};

struct PermissionDismissedRecord {
  MiumCEFPermissionSessionID sessionID = 0;
  uint32_t reason = 0;
};

struct PermissionDismissedProbe {
  mutable std::mutex mutex;
  std::vector<PermissionDismissedRecord> dismissals;
};

struct FakeRequestState {
  cef_request_t request{};
  FakeRefCountedLifetime lifetime{};
  std::string url;

  explicit FakeRequestState(const char* requestURL) : url(requestURL == nullptr ? "" : requestURL) {
    std::memset(&request, 0, sizeof(request));
    initializeRefCountedBase(request.base, sizeof(request));
    request.base.add_ref = fakeAddRef<FakeRequestState>;
    request.base.release = fakeRelease<FakeRequestState>;
    request.base.has_one_ref = fakeHasOneRef<FakeRequestState>;
    request.base.has_at_least_one_ref = fakeHasAtLeastOneRef<FakeRequestState>;
    request.get_url = fakeRequestGetURL;
  }

  static cef_string_userfree_t CEF_CALLBACK fakeRequestGetURL(cef_request_t* self) {
    auto* state = reinterpret_cast<FakeRequestState*>(self);
    return state == nullptr ? nullptr : fakeUserFreeString(state->url);
  }

  cef_request_t* requestRef() {
    return &request;
  }
};

struct PermissionTestHarness {
  MiumCEFRuntimeHandle runtimeHandle = nullptr;
  MiumCEFBrowserHandle browserHandle = nullptr;
  FakeBrowserHarness browser;
  cef_client_t* client = nullptr;
};

static void permissionRequestCallback(void* context, const MiumCEFPermissionRequest* request) {
  auto* probe = static_cast<PermissionRequestProbe*>(context);
  if (probe == nullptr || request == nullptr) {
    return;
  }

  PermissionRequestRecord record;
  record.sessionID = request->sessionID;
  record.browserID = request->browserID;
  record.promptID = request->promptID;
  record.frameIdentifierWasNull = request->frameIdentifier == nullptr;
  record.frameIdentifier = request->frameIdentifier == nullptr ? std::string() : std::string(request->frameIdentifier);
  record.permissionFlags = request->permissionFlags;
  record.source = request->source;
  record.requestingOriginWasNull = request->requestingOrigin == nullptr;
  record.requestingOrigin =
    request->requestingOrigin == nullptr ? std::string() : std::string(request->requestingOrigin);
  record.topLevelOriginWasNull = request->topLevelOrigin == nullptr;
  record.topLevelOrigin =
    request->topLevelOrigin == nullptr ? std::string() : std::string(request->topLevelOrigin);

  std::lock_guard<std::mutex> lock(probe->mutex);
  probe->requests.push_back(std::move(record));
}

static void permissionSessionDismissedCallback(
  void* context,
  MiumCEFPermissionSessionID sessionID,
  uint32_t reason
) {
  auto* probe = static_cast<PermissionDismissedProbe*>(context);
  if (probe == nullptr) {
    return;
  }

  std::lock_guard<std::mutex> lock(probe->mutex);
  probe->dismissals.push_back(PermissionDismissedRecord{sessionID, reason});
}

static void bridgePermissionRequestCallback(
  void* context,
  const CEFBridgePermissionRequest* request
) {
  auto* probe = static_cast<PermissionRequestProbe*>(context);
  if (probe == nullptr || request == nullptr) {
    return;
  }

  PermissionRequestRecord record;
  record.sessionID = request->session_id;
  record.browserID = request->browser_id;
  record.promptID = request->prompt_id;
  record.frameIdentifierWasNull = request->frame_identifier == nullptr;
  record.frameIdentifier =
    request->frame_identifier == nullptr ? std::string() : std::string(request->frame_identifier);
  record.permissionFlags = request->permission_flags;
  record.source = request->source;
  record.requestingOriginWasNull = request->requesting_origin == nullptr;
  record.requestingOrigin =
    request->requesting_origin == nullptr ? std::string() : std::string(request->requesting_origin);
  record.topLevelOriginWasNull = request->top_level_origin == nullptr;
  record.topLevelOrigin =
    request->top_level_origin == nullptr ? std::string() : std::string(request->top_level_origin);

  std::lock_guard<std::mutex> lock(probe->mutex);
  probe->requests.push_back(std::move(record));
}

static void bridgePermissionSessionDismissedCallback(
  void* context,
  CEFBridgePermissionSessionID sessionID,
  uint32_t reason
) {
  auto* probe = static_cast<PermissionDismissedProbe*>(context);
  if (probe == nullptr) {
    return;
  }

  std::lock_guard<std::mutex> lock(probe->mutex);
  probe->dismissals.push_back(PermissionDismissedRecord{sessionID, reason});
}

static PermissionTestHarness makePermissionHarness(
  MiumCEFBridgeNativeTestCase* testCase,
  const char* topLevelURL
) {
  PermissionTestHarness harness;
  [testCase installBasicAPI];
  harness.runtimeHandle = [testCase seedRuntime];
  harness.browserHandle = [testCase createBrowserForRuntime:harness.runtimeHandle];
  harness.browser.frame->currentURL = topLevelURL == nullptr ? "https://navigator.test" : topLevelURL;
  harness.client = miumNativeCEFTestCreateBrowserClient();
  return harness;
}

static ScopedCefRef<cef_permission_handler_t> permissionHandlerForBrowser(
  const PermissionTestHarness& harness
) {
  if (harness.client == nullptr) {
    return ScopedCefRef<cef_permission_handler_t>();
  }
  return ScopedCefRef<cef_permission_handler_t>(harness.client->get_permission_handler(harness.client));
}

static ScopedCefRef<cef_request_handler_t> requestHandlerForBrowser(
  const PermissionTestHarness& harness
) {
  if (harness.client == nullptr) {
    return ScopedCefRef<cef_request_handler_t>();
  }
  return ScopedCefRef<cef_request_handler_t>(harness.client->get_request_handler(harness.client));
}

static int requestMediaAccess(
  cef_permission_handler_t* handler,
  FakeBrowserHarness& browser,
  const char* requestingOrigin,
  uint32_t requestedPermissions,
  FakeMediaAccessCallbackHarness& callback
) {
  XCTAssertNotEqual(callback.callbackRef()->base.add_ref, nullptr);
  XCTAssertNotEqual(callback.callbackRef()->base.release, nullptr);
  ScopedCEFString requestingOriginString(requestingOrigin);
  return handler->on_request_media_access_permission(
    handler,
    browser.browserRef(),
    &browser.frame->frame,
    requestingOriginString.ref(),
    requestedPermissions,
    callback.callbackRef()
  );
}

static int showPermissionPrompt(
  cef_permission_handler_t* handler,
  FakeBrowserHarness& browser,
  uint64_t promptID,
  const char* requestingOrigin,
  uint32_t requestedPermissions,
  FakePermissionPromptCallbackHarness& callback
) {
  XCTAssertNotEqual(callback.callbackRef()->base.add_ref, nullptr);
  XCTAssertNotEqual(callback.callbackRef()->base.release, nullptr);
  ScopedCEFString requestingOriginString(requestingOrigin);
  return handler->on_show_permission_prompt(
    handler,
    browser.browserRef(),
    promptID,
    requestingOriginString.ref(),
    requestedPermissions,
    callback.callbackRef()
  );
}

static int beginMainFrameNavigation(
  cef_request_handler_t* handler,
  FakeBrowserHarness& browser,
  const char* nextURL,
  int userGesture = 0,
  int isRedirect = 0
) {
  FakeRequestState request(nextURL);
  return handler->on_before_browse(
    handler,
    browser.browserRef(),
    &browser.frame->frame,
    request.requestRef(),
    userGesture,
    isRedirect
  );
}

static std::vector<PermissionRequestRecord> copyRequests(const PermissionRequestProbe& probe) {
  std::lock_guard<std::mutex> lock(probe.mutex);
  return probe.requests;
}

static std::vector<PermissionDismissedRecord> copyDismissals(const PermissionDismissedProbe& probe) {
  std::lock_guard<std::mutex> lock(probe.mutex);
  return probe.dismissals;
}

} // namespace

@interface MiumCEFBridgePermissionTests : MiumCEFBridgeNativeTestCase
@end

@implementation MiumCEFBridgePermissionTests

- (void)testMediaAccessPermissionRequestDeliversNormalizedRequestMetadata {
  auto harness = makePermissionHarness(self, "https://top.example/account?flow=1");
  XCTAssertNotEqual(harness.client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(harness.browserHandle, harness.browser.browserRef(), harness.client));
  XCTAssertEqual(miumNativeCEFTestGetNativeClient(harness.browserHandle), harness.client);

  PermissionRequestProbe requestProbe;
  XCTAssertEqual(
    miumNativeCEFSetPermissionRequestHandler(harness.browserHandle, &requestProbe, permissionRequestCallback),
    MiumCEFResultOK
  );

  ScopedCefRef<cef_permission_handler_t> permissionHandler = permissionHandlerForBrowser(harness);
  XCTAssertTrue(permissionHandler);

  FakeMediaAccessCallbackHarness mediaCallback;
  harness.browser.frame->identifier = "subframe-7";
  const uint32_t requestedPermissions =
    CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE | CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE;

  XCTAssertEqual(
    requestMediaAccess(
      permissionHandler.get(),
      harness.browser,
      "https://Sub.Example:8443/path?query=1",
      requestedPermissions,
      mediaCallback
    ),
    1
  );

  const auto requests = copyRequests(requestProbe);
  XCTAssertEqual(requests.size(), static_cast<size_t>(1));
  XCTAssertEqual(miumNativeCEFTestActivePermissionSessionCount(), static_cast<size_t>(1));
  XCTAssertTrue(miumNativeCEFTestHasActivePermissionSession(requests[0].sessionID));
  XCTAssertEqual(requests[0].browserID, reinterpret_cast<uint64_t>(harness.browserHandle));
  XCTAssertEqual(requests[0].promptID, static_cast<uint64_t>(0));
  XCTAssertEqual(requests[0].frameIdentifier, "subframe-7");
  XCTAssertEqual(
    requests[0].permissionFlags,
    static_cast<uint32_t>(MiumCEFPermissionKindFlags::camera)
      | static_cast<uint32_t>(MiumCEFPermissionKindFlags::microphone)
  );
  XCTAssertEqual(requests[0].source, static_cast<uint32_t>(MiumCEFPermissionRequestSource::mediaAccess));
  XCTAssertEqual(requests[0].requestingOrigin, "https://sub.example:8443");
  XCTAssertEqual(requests[0].topLevelOrigin, "https://top.example");
  XCTAssertEqual(mediaCallback.state->continueCalls, 0);
  XCTAssertEqual(mediaCallback.state->cancelCalls, 0);
}

- (void)testUnsupportedPermissionRequestsDenyImmediatelyWithoutCreatingSessions {
  auto harness = makePermissionHarness(self, "https://top.example/start");
  XCTAssertNotEqual(harness.client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(harness.browserHandle, harness.browser.browserRef(), harness.client));

  PermissionRequestProbe requestProbe;
  XCTAssertEqual(
    miumNativeCEFSetPermissionRequestHandler(harness.browserHandle, &requestProbe, permissionRequestCallback),
    MiumCEFResultOK
  );

  ScopedCefRef<cef_permission_handler_t> permissionHandler = permissionHandlerForBrowser(harness);
  XCTAssertTrue(permissionHandler);

  FakeMediaAccessCallbackHarness mediaCallback;
  XCTAssertEqual(
    requestMediaAccess(
      permissionHandler.get(),
      harness.browser,
      "https://unsupported.example",
      CEF_MEDIA_PERMISSION_DESKTOP_AUDIO_CAPTURE,
      mediaCallback
    ),
    1
  );
  XCTAssertEqual(mediaCallback.state->continueCalls, 1);
  XCTAssertEqual(mediaCallback.state->lastAllowedPermissions, static_cast<uint32_t>(0));
  XCTAssertEqual(mediaCallback.state->cancelCalls, 0);

  FakePermissionPromptCallbackHarness promptCallback;
  XCTAssertEqual(
    showPermissionPrompt(
      permissionHandler.get(),
      harness.browser,
      55,
      "https://unsupported.example",
      CEF_PERMISSION_TYPE_NOTIFICATIONS,
      promptCallback
    ),
    1
  );
  XCTAssertEqual(promptCallback.state->continueCalls, 1);
  XCTAssertEqual(promptCallback.state->lastResult, CEF_PERMISSION_RESULT_DENY);

  XCTAssertEqual(copyRequests(requestProbe).size(), static_cast<size_t>(0));
  XCTAssertEqual(miumNativeCEFTestActivePermissionSessionCount(), static_cast<size_t>(0));
}

- (void)testMixedSupportedAndUnsupportedPermissionRequestsDenyImmediately {
  auto harness = makePermissionHarness(self, "https://top.example/mixed");
  XCTAssertNotEqual(harness.client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(harness.browserHandle, harness.browser.browserRef(), harness.client));

  PermissionRequestProbe requestProbe;
  XCTAssertEqual(
    miumNativeCEFSetPermissionRequestHandler(harness.browserHandle, &requestProbe, permissionRequestCallback),
    MiumCEFResultOK
  );

  ScopedCefRef<cef_permission_handler_t> permissionHandler = permissionHandlerForBrowser(harness);
  XCTAssertTrue(permissionHandler);

  FakeMediaAccessCallbackHarness mediaCallback;
  XCTAssertEqual(
    requestMediaAccess(
      permissionHandler.get(),
      harness.browser,
      "https://mixed.example",
      CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE | CEF_MEDIA_PERMISSION_DESKTOP_AUDIO_CAPTURE,
      mediaCallback
    ),
    1
  );
  XCTAssertEqual(mediaCallback.state->continueCalls, 1);
  XCTAssertEqual(mediaCallback.state->lastAllowedPermissions, static_cast<uint32_t>(0));

  FakePermissionPromptCallbackHarness promptCallback;
  XCTAssertEqual(
    showPermissionPrompt(
      permissionHandler.get(),
      harness.browser,
      56,
      "https://mixed.example",
      CEF_PERMISSION_TYPE_CAMERA_STREAM | CEF_PERMISSION_TYPE_NOTIFICATIONS,
      promptCallback
    ),
    1
  );
  XCTAssertEqual(promptCallback.state->continueCalls, 1);
  XCTAssertEqual(promptCallback.state->lastResult, CEF_PERMISSION_RESULT_DENY);
  XCTAssertEqual(copyRequests(requestProbe).size(), static_cast<size_t>(0));
  XCTAssertEqual(miumNativeCEFTestActivePermissionSessionCount(), static_cast<size_t>(0));
}

- (void)testPermissionRequestsDenyImmediatelyWhenNoSwiftHandlerIsRegistered {
  auto harness = makePermissionHarness(self, "https://top.example/no-handler");
  XCTAssertNotEqual(harness.client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(harness.browserHandle, harness.browser.browserRef(), harness.client));

  ScopedCefRef<cef_permission_handler_t> permissionHandler = permissionHandlerForBrowser(harness);
  XCTAssertTrue(permissionHandler);

  FakeMediaAccessCallbackHarness mediaCallback;
  XCTAssertEqual(
    requestMediaAccess(
      permissionHandler.get(),
      harness.browser,
      "https://no-handler.example",
      CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE,
      mediaCallback
    ),
    1
  );

  XCTAssertEqual(mediaCallback.state->continueCalls, 1);
  XCTAssertEqual(mediaCallback.state->lastAllowedPermissions, static_cast<uint32_t>(0));
  XCTAssertEqual(miumNativeCEFTestActivePermissionSessionCount(), static_cast<size_t>(0));
}

- (void)testDeduplicatesMatchingMediaRequestsAndResolvesAllAttachedCallbacks {
  auto harness = makePermissionHarness(self, "https://top.example/root");
  XCTAssertNotEqual(harness.client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(harness.browserHandle, harness.browser.browserRef(), harness.client));

  PermissionRequestProbe requestProbe;
  XCTAssertEqual(
    miumNativeCEFSetPermissionRequestHandler(harness.browserHandle, &requestProbe, permissionRequestCallback),
    MiumCEFResultOK
  );

  ScopedCefRef<cef_permission_handler_t> permissionHandler = permissionHandlerForBrowser(harness);
  XCTAssertTrue(permissionHandler);

  FakeMediaAccessCallbackHarness firstCallback;
  FakeMediaAccessCallbackHarness secondCallback;
  const uint32_t requestedPermissions =
    CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE | CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE;

  XCTAssertEqual(
    requestMediaAccess(
      permissionHandler.get(),
      harness.browser,
      "https://camera.example/room",
      requestedPermissions,
      firstCallback
    ),
    1
  );
  const auto firstRequests = copyRequests(requestProbe);
  XCTAssertEqual(firstRequests.size(), static_cast<size_t>(1));
  const MiumCEFPermissionSessionID sessionID = firstRequests[0].sessionID;

  XCTAssertEqual(
    requestMediaAccess(
      permissionHandler.get(),
      harness.browser,
      "https://camera.example/room?second=1",
      requestedPermissions,
      secondCallback
    ),
    1
  );

  XCTAssertEqual(copyRequests(requestProbe).size(), static_cast<size_t>(1));
  XCTAssertEqual(miumNativeCEFTestActivePermissionSessionCount(), static_cast<size_t>(1));
  XCTAssertTrue(miumNativeCEFTestHasActivePermissionSession(sessionID));

  XCTAssertEqual(
    miumNativeCEFResolvePermissionRequest(
      sessionID,
      static_cast<uint32_t>(MiumCEFPermissionResolution::allow)
    ),
    MiumCEFResultOK
  );
  [self drainPendingAsyncWork];

  XCTAssertEqual(firstCallback.state->continueCalls, 1);
  XCTAssertEqual(firstCallback.state->lastAllowedPermissions, requestedPermissions);
  XCTAssertEqual(secondCallback.state->continueCalls, 1);
  XCTAssertEqual(secondCallback.state->lastAllowedPermissions, requestedPermissions);
  XCTAssertEqual(firstCallback.state->cancelCalls, 0);
  XCTAssertEqual(secondCallback.state->cancelCalls, 0);
  XCTAssertEqual(miumNativeCEFTestActivePermissionSessionCount(), static_cast<size_t>(0));
  XCTAssertFalse(miumNativeCEFTestHasActivePermissionSession(sessionID));
}

- (void)testDeduplicatesAcrossMediaAndPromptSources {
  auto harness = makePermissionHarness(self, "https://top.example/shared");
  XCTAssertNotEqual(harness.client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(harness.browserHandle, harness.browser.browserRef(), harness.client));

  PermissionRequestProbe requestProbe;
  XCTAssertEqual(
    miumNativeCEFSetPermissionRequestHandler(harness.browserHandle, &requestProbe, permissionRequestCallback),
    MiumCEFResultOK
  );

  ScopedCefRef<cef_permission_handler_t> permissionHandler = permissionHandlerForBrowser(harness);
  XCTAssertTrue(permissionHandler);

  FakeMediaAccessCallbackHarness mediaCallback;
  XCTAssertEqual(
    requestMediaAccess(
      permissionHandler.get(),
      harness.browser,
      "https://shared.example/device",
      CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE,
      mediaCallback
    ),
    1
  );

  const auto requests = copyRequests(requestProbe);
  XCTAssertEqual(requests.size(), static_cast<size_t>(1));

  FakePermissionPromptCallbackHarness promptCallback;
  XCTAssertEqual(
    showPermissionPrompt(
      permissionHandler.get(),
      harness.browser,
      313,
      "https://shared.example/device?prompt=1",
      CEF_PERMISSION_TYPE_CAMERA_STREAM,
      promptCallback
    ),
    1
  );

  XCTAssertEqual(copyRequests(requestProbe).size(), static_cast<size_t>(1));
  XCTAssertEqual(miumNativeCEFTestActivePermissionSessionCount(), static_cast<size_t>(1));

  XCTAssertEqual(
    miumNativeCEFResolvePermissionRequest(
      requests[0].sessionID,
      static_cast<uint32_t>(MiumCEFPermissionResolution::allow)
    ),
    MiumCEFResultOK
  );
  [self drainPendingAsyncWork];

  XCTAssertEqual(mediaCallback.state->continueCalls, 1);
  XCTAssertEqual(mediaCallback.state->lastAllowedPermissions, CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE);
  XCTAssertEqual(promptCallback.state->continueCalls, 1);
  XCTAssertEqual(promptCallback.state->lastResult, CEF_PERMISSION_RESULT_ACCEPT);
  XCTAssertEqual(miumNativeCEFTestActivePermissionSessionCount(), static_cast<size_t>(0));
}

- (void)testMediaStreamOverrideBypassesPermissionServiceForMediaAndPromptRequests {
  ScopedEnvironmentVariable mediaStreamOverride("MIUM_CEF_ENABLE_MEDIA_STREAM", "1");
  auto harness = makePermissionHarness(self, "https://top.example/override");
  XCTAssertNotEqual(harness.client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(harness.browserHandle, harness.browser.browserRef(), harness.client));

  PermissionRequestProbe requestProbe;
  XCTAssertEqual(
    miumNativeCEFSetPermissionRequestHandler(harness.browserHandle, &requestProbe, permissionRequestCallback),
    MiumCEFResultOK
  );

  ScopedCefRef<cef_permission_handler_t> permissionHandler = permissionHandlerForBrowser(harness);
  XCTAssertTrue(permissionHandler);

  FakeMediaAccessCallbackHarness mediaCallback;
  XCTAssertEqual(
    requestMediaAccess(
      permissionHandler.get(),
      harness.browser,
      "https://override.example",
      CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE | CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE,
      mediaCallback
    ),
    1
  );
  XCTAssertEqual(mediaCallback.state->continueCalls, 1);
  XCTAssertEqual(
    mediaCallback.state->lastAllowedPermissions,
    static_cast<uint32_t>(
      CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE | CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE
    )
  );

  FakePermissionPromptCallbackHarness promptCallback;
  XCTAssertEqual(
    showPermissionPrompt(
      permissionHandler.get(),
      harness.browser,
      404,
      "https://override.example",
      CEF_PERMISSION_TYPE_CAMERA_STREAM | CEF_PERMISSION_TYPE_MIC_STREAM,
      promptCallback
    ),
    1
  );
  XCTAssertEqual(promptCallback.state->continueCalls, 1);
  XCTAssertEqual(promptCallback.state->lastResult, CEF_PERMISSION_RESULT_ACCEPT);
  XCTAssertEqual(copyRequests(requestProbe).size(), static_cast<size_t>(0));
  XCTAssertEqual(miumNativeCEFTestActivePermissionSessionCount(), static_cast<size_t>(0));
}

- (void)testMediaStreamOverrideDoesNotBypassPermissionServiceWhenDevelopmentEligibilityIsDisabled {
  ScopedEnvironmentVariable mediaStreamOverride("MIUM_CEF_ENABLE_MEDIA_STREAM", "1");
  miumNativeCEFTestSetMediaStreamOverrideDevelopmentEligible(false);
  auto harness = makePermissionHarness(self, "https://top.example/override-disabled");
  XCTAssertNotEqual(harness.client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(harness.browserHandle, harness.browser.browserRef(), harness.client));

  PermissionRequestProbe requestProbe;
  XCTAssertEqual(
    miumNativeCEFSetPermissionRequestHandler(harness.browserHandle, &requestProbe, permissionRequestCallback),
    MiumCEFResultOK
  );

  ScopedCefRef<cef_permission_handler_t> permissionHandler = permissionHandlerForBrowser(harness);
  XCTAssertTrue(permissionHandler);

  FakeMediaAccessCallbackHarness mediaCallback;
  XCTAssertEqual(
    requestMediaAccess(
      permissionHandler.get(),
      harness.browser,
      "https://override-disabled.example",
      CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE,
      mediaCallback
    ),
    1
  );

  const auto requests = copyRequests(requestProbe);
  XCTAssertEqual(requests.size(), static_cast<size_t>(1));
  XCTAssertEqual(mediaCallback.state->continueCalls, 0);
  XCTAssertEqual(miumNativeCEFTestActivePermissionSessionCount(), static_cast<size_t>(1));
  XCTAssertEqual(
    miumNativeCEFResolvePermissionRequest(
      requests[0].sessionID,
      static_cast<uint32_t>(MiumCEFPermissionResolution::allow)
    ),
    MiumCEFResultOK
  );
  [self drainPendingAsyncWork];

  XCTAssertEqual(mediaCallback.state->continueCalls, 1);
  XCTAssertEqual(
    mediaCallback.state->lastAllowedPermissions,
    static_cast<uint32_t>(CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE)
  );
  XCTAssertEqual(miumNativeCEFTestActivePermissionSessionCount(), static_cast<size_t>(0));
  miumNativeCEFTestResetMediaStreamOverrideDevelopmentEligibility();
}

- (void)testResolvePermissionRequestAllowAcceptsPromptCallback {
  auto harness = makePermissionHarness(self, "https://top.example/allow");
  XCTAssertNotEqual(harness.client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(harness.browserHandle, harness.browser.browserRef(), harness.client));

  PermissionRequestProbe requestProbe;
  PermissionDismissedProbe dismissedProbe;
  XCTAssertEqual(
    miumNativeCEFSetPermissionRequestHandler(harness.browserHandle, &requestProbe, permissionRequestCallback),
    MiumCEFResultOK
  );
  XCTAssertEqual(
    miumNativeCEFSetPermissionSessionDismissedHandler(
      harness.browserHandle,
      &dismissedProbe,
      permissionSessionDismissedCallback
    ),
    MiumCEFResultOK
  );

  ScopedCefRef<cef_permission_handler_t> permissionHandler = permissionHandlerForBrowser(harness);
  XCTAssertTrue(permissionHandler);

  FakePermissionPromptCallbackHarness promptCallback;
  XCTAssertEqual(
    showPermissionPrompt(
      permissionHandler.get(),
      harness.browser,
      91,
      "https://geo.example/path",
      CEF_PERMISSION_TYPE_CAMERA_STREAM | CEF_PERMISSION_TYPE_GEOLOCATION,
      promptCallback
    ),
    1
  );

  const auto requests = copyRequests(requestProbe);
  XCTAssertEqual(requests.size(), static_cast<size_t>(1));
  XCTAssertEqual(requests[0].promptID, static_cast<uint64_t>(91));
  XCTAssertTrue(requests[0].frameIdentifier.empty());
  XCTAssertEqual(requests[0].source, static_cast<uint32_t>(MiumCEFPermissionRequestSource::permissionPrompt));
  XCTAssertEqual(
    requests[0].permissionFlags,
    static_cast<uint32_t>(MiumCEFPermissionKindFlags::camera)
      | static_cast<uint32_t>(MiumCEFPermissionKindFlags::geolocation)
  );
  XCTAssertEqual(requests[0].requestingOrigin, "https://geo.example");
  XCTAssertEqual(requests[0].topLevelOrigin, "https://top.example");

  XCTAssertEqual(
    miumNativeCEFResolvePermissionRequest(
      requests[0].sessionID,
      static_cast<uint32_t>(MiumCEFPermissionResolution::allow)
    ),
    MiumCEFResultOK
  );
  [self drainPendingAsyncWork];

  XCTAssertEqual(promptCallback.state->continueCalls, 1);
  XCTAssertEqual(promptCallback.state->lastResult, CEF_PERMISSION_RESULT_ACCEPT);
  XCTAssertEqual(copyDismissals(dismissedProbe).size(), static_cast<size_t>(0));
  XCTAssertEqual(miumNativeCEFTestActivePermissionSessionCount(), static_cast<size_t>(0));
}

- (void)testResolvePermissionRequestDenyReturnsZeroPermissionsToMediaAccessCallback {
  auto harness = makePermissionHarness(self, "https://top.example/deny");
  XCTAssertNotEqual(harness.client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(harness.browserHandle, harness.browser.browserRef(), harness.client));

  PermissionRequestProbe requestProbe;
  PermissionDismissedProbe dismissedProbe;
  XCTAssertEqual(
    miumNativeCEFSetPermissionRequestHandler(harness.browserHandle, &requestProbe, permissionRequestCallback),
    MiumCEFResultOK
  );
  XCTAssertEqual(
    miumNativeCEFSetPermissionSessionDismissedHandler(
      harness.browserHandle,
      &dismissedProbe,
      permissionSessionDismissedCallback
    ),
    MiumCEFResultOK
  );

  ScopedCefRef<cef_permission_handler_t> permissionHandler = permissionHandlerForBrowser(harness);
  XCTAssertTrue(permissionHandler);

  FakeMediaAccessCallbackHarness mediaCallback;
  XCTAssertEqual(
    requestMediaAccess(
      permissionHandler.get(),
      harness.browser,
      "https://camera.example/deny",
      CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE,
      mediaCallback
    ),
    1
  );

  const auto requests = copyRequests(requestProbe);
  XCTAssertEqual(requests.size(), static_cast<size_t>(1));
  XCTAssertEqual(
    miumNativeCEFResolvePermissionRequest(
      requests[0].sessionID,
      static_cast<uint32_t>(MiumCEFPermissionResolution::deny)
    ),
    MiumCEFResultOK
  );
  [self drainPendingAsyncWork];

  XCTAssertEqual(mediaCallback.state->continueCalls, 1);
  XCTAssertEqual(mediaCallback.state->lastAllowedPermissions, static_cast<uint32_t>(0));
  XCTAssertEqual(mediaCallback.state->cancelCalls, 0);
  XCTAssertEqual(copyDismissals(dismissedProbe).size(), static_cast<size_t>(0));
  XCTAssertEqual(miumNativeCEFTestActivePermissionSessionCount(), static_cast<size_t>(0));
}

- (void)testResolvePermissionRequestCancelCancelsMediaAccessCallbackAndNotifiesDismissal {
  auto harness = makePermissionHarness(self, "https://top.example/cancel");
  XCTAssertNotEqual(harness.client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(harness.browserHandle, harness.browser.browserRef(), harness.client));

  PermissionRequestProbe requestProbe;
  PermissionDismissedProbe dismissedProbe;
  XCTAssertEqual(
    miumNativeCEFSetPermissionRequestHandler(harness.browserHandle, &requestProbe, permissionRequestCallback),
    MiumCEFResultOK
  );
  XCTAssertEqual(
    miumNativeCEFSetPermissionSessionDismissedHandler(
      harness.browserHandle,
      &dismissedProbe,
      permissionSessionDismissedCallback
    ),
    MiumCEFResultOK
  );

  ScopedCefRef<cef_permission_handler_t> permissionHandler = permissionHandlerForBrowser(harness);
  XCTAssertTrue(permissionHandler);

  FakeMediaAccessCallbackHarness mediaCallback;
  XCTAssertEqual(
    requestMediaAccess(
      permissionHandler.get(),
      harness.browser,
      "https://camera.example/cancel",
      CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE,
      mediaCallback
    ),
    1
  );

  const auto requests = copyRequests(requestProbe);
  XCTAssertEqual(requests.size(), static_cast<size_t>(1));
  XCTAssertEqual(
    miumNativeCEFResolvePermissionRequest(
      requests[0].sessionID,
      static_cast<uint32_t>(MiumCEFPermissionResolution::cancel)
    ),
    MiumCEFResultOK
  );
  [self drainPendingAsyncWork];

  const auto dismissals = copyDismissals(dismissedProbe);
  XCTAssertEqual(mediaCallback.state->continueCalls, 0);
  XCTAssertEqual(mediaCallback.state->cancelCalls, 1);
  XCTAssertEqual(dismissals.size(), static_cast<size_t>(1));
  XCTAssertEqual(dismissals[0].sessionID, requests[0].sessionID);
  XCTAssertEqual(
    dismissals[0].reason,
    static_cast<uint32_t>(MiumCEFPermissionSessionDismissReason::explicitCancel)
  );
  XCTAssertEqual(miumNativeCEFTestActivePermissionSessionCount(), static_cast<size_t>(0));
}

- (void)testPromptDismissalFinalizesSessionWithoutResolvingPromptCallback {
  auto harness = makePermissionHarness(self, "https://top.example/dismiss");
  XCTAssertNotEqual(harness.client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(harness.browserHandle, harness.browser.browserRef(), harness.client));

  PermissionRequestProbe requestProbe;
  PermissionDismissedProbe dismissedProbe;
  XCTAssertEqual(
    miumNativeCEFSetPermissionRequestHandler(harness.browserHandle, &requestProbe, permissionRequestCallback),
    MiumCEFResultOK
  );
  XCTAssertEqual(
    miumNativeCEFSetPermissionSessionDismissedHandler(
      harness.browserHandle,
      &dismissedProbe,
      permissionSessionDismissedCallback
    ),
    MiumCEFResultOK
  );

  ScopedCefRef<cef_permission_handler_t> permissionHandler = permissionHandlerForBrowser(harness);
  XCTAssertTrue(permissionHandler);

  FakePermissionPromptCallbackHarness promptCallback;
  XCTAssertEqual(
    showPermissionPrompt(
      permissionHandler.get(),
      harness.browser,
      120,
      "https://prompt.example/start",
      CEF_PERMISSION_TYPE_MIC_STREAM,
      promptCallback
    ),
    1
  );

  const auto requests = copyRequests(requestProbe);
  XCTAssertEqual(requests.size(), static_cast<size_t>(1));
  const MiumCEFPermissionSessionID sessionID = requests[0].sessionID;
  XCTAssertTrue(miumNativeCEFTestHasActivePermissionSession(sessionID));

  permissionHandler->on_dismiss_permission_prompt(
    permissionHandler.get(),
    harness.browser.browserRef(),
    120,
    CEF_PERMISSION_RESULT_DISMISS
  );
  [self drainPendingAsyncWork];

  const auto dismissals = copyDismissals(dismissedProbe);
  XCTAssertEqual(promptCallback.state->continueCalls, 0);
  XCTAssertEqual(dismissals.size(), static_cast<size_t>(1));
  XCTAssertEqual(dismissals[0].sessionID, sessionID);
  XCTAssertEqual(
    dismissals[0].reason,
    static_cast<uint32_t>(MiumCEFPermissionSessionDismissReason::promptDismissed)
  );
  XCTAssertFalse(miumNativeCEFTestHasActivePermissionSession(sessionID));
}

- (void)testDestroyBrowserCancelsActivePermissionSession {
  auto harness = makePermissionHarness(self, "https://top.example/close");
  XCTAssertNotEqual(harness.client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(harness.browserHandle, harness.browser.browserRef(), harness.client));

  PermissionRequestProbe requestProbe;
  PermissionDismissedProbe dismissedProbe;
  XCTAssertEqual(
    miumNativeCEFSetPermissionRequestHandler(harness.browserHandle, &requestProbe, permissionRequestCallback),
    MiumCEFResultOK
  );
  XCTAssertEqual(
    miumNativeCEFSetPermissionSessionDismissedHandler(
      harness.browserHandle,
      &dismissedProbe,
      permissionSessionDismissedCallback
    ),
    MiumCEFResultOK
  );

  ScopedCefRef<cef_permission_handler_t> permissionHandler = permissionHandlerForBrowser(harness);
  XCTAssertTrue(permissionHandler);

  FakeMediaAccessCallbackHarness mediaCallback;
  XCTAssertEqual(
    requestMediaAccess(
      permissionHandler.get(),
      harness.browser,
      "https://close.example/camera",
      CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE,
      mediaCallback
    ),
    1
  );

  const auto requests = copyRequests(requestProbe);
  XCTAssertEqual(requests.size(), static_cast<size_t>(1));
  const MiumCEFPermissionSessionID sessionID = requests[0].sessionID;

  XCTAssertEqual(miumNativeCEFDestroyBrowser(harness.browserHandle), MiumCEFResultOK);
  [self drainPendingAsyncWork];

  const auto dismissals = copyDismissals(dismissedProbe);
  XCTAssertEqual(mediaCallback.state->cancelCalls, 1);
  XCTAssertEqual(dismissals.size(), static_cast<size_t>(1));
  XCTAssertEqual(dismissals[0].sessionID, sessionID);
  XCTAssertEqual(
    dismissals[0].reason,
    static_cast<uint32_t>(MiumCEFPermissionSessionDismissReason::browserClosed)
  );
  XCTAssertFalse(miumNativeCEFTestHasActivePermissionSession(sessionID));
}

- (void)testRenderTerminationCancelsPromptSessionAndNotifiesDismissal {
  auto harness = makePermissionHarness(self, "https://top.example/render");
  XCTAssertNotEqual(harness.client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(harness.browserHandle, harness.browser.browserRef(), harness.client));

  PermissionRequestProbe requestProbe;
  PermissionDismissedProbe dismissedProbe;
  XCTAssertEqual(
    miumNativeCEFSetPermissionRequestHandler(harness.browserHandle, &requestProbe, permissionRequestCallback),
    MiumCEFResultOK
  );
  XCTAssertEqual(
    miumNativeCEFSetPermissionSessionDismissedHandler(
      harness.browserHandle,
      &dismissedProbe,
      permissionSessionDismissedCallback
    ),
    MiumCEFResultOK
  );

  ScopedCefRef<cef_permission_handler_t> permissionHandler = permissionHandlerForBrowser(harness);
  ScopedCefRef<cef_request_handler_t> requestHandler = requestHandlerForBrowser(harness);
  XCTAssertTrue(permissionHandler);
  XCTAssertTrue(requestHandler);

  FakePermissionPromptCallbackHarness promptCallback;
  XCTAssertEqual(
    showPermissionPrompt(
      permissionHandler.get(),
      harness.browser,
      212,
      "https://render.example/mic",
      CEF_PERMISSION_TYPE_MIC_STREAM,
      promptCallback
    ),
    1
  );

  const auto requests = copyRequests(requestProbe);
  XCTAssertEqual(requests.size(), static_cast<size_t>(1));
  const MiumCEFPermissionSessionID sessionID = requests[0].sessionID;
  ScopedCEFString errorString("renderer crashed");

  requestHandler->on_render_process_terminated(
    requestHandler.get(),
    harness.browser.browserRef(),
    TS_PROCESS_CRASHED,
    9,
    errorString.ref()
  );
  [self drainPendingAsyncWork];

  const auto dismissals = copyDismissals(dismissedProbe);
  XCTAssertEqual(promptCallback.state->continueCalls, 1);
  XCTAssertEqual(promptCallback.state->lastResult, CEF_PERMISSION_RESULT_DISMISS);
  XCTAssertEqual(dismissals.size(), static_cast<size_t>(1));
  XCTAssertEqual(dismissals[0].sessionID, sessionID);
  XCTAssertEqual(
    dismissals[0].reason,
    static_cast<uint32_t>(MiumCEFPermissionSessionDismissReason::renderProcessTerminated)
  );
  XCTAssertFalse(miumNativeCEFTestHasActivePermissionSession(sessionID));
}

- (void)testMainFrameNavigationKeepsSameOriginSessionAndCancelsAfterOriginChange {
  auto harness = makePermissionHarness(self, "https://top.example/start");
  XCTAssertNotEqual(harness.client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(harness.browserHandle, harness.browser.browserRef(), harness.client));

  PermissionRequestProbe requestProbe;
  PermissionDismissedProbe dismissedProbe;
  XCTAssertEqual(
    miumNativeCEFSetPermissionRequestHandler(harness.browserHandle, &requestProbe, permissionRequestCallback),
    MiumCEFResultOK
  );
  XCTAssertEqual(
    miumNativeCEFSetPermissionSessionDismissedHandler(
      harness.browserHandle,
      &dismissedProbe,
      permissionSessionDismissedCallback
    ),
    MiumCEFResultOK
  );

  ScopedCefRef<cef_permission_handler_t> permissionHandler = permissionHandlerForBrowser(harness);
  ScopedCefRef<cef_request_handler_t> requestHandler = requestHandlerForBrowser(harness);
  XCTAssertTrue(permissionHandler);
  XCTAssertTrue(requestHandler);

  FakeMediaAccessCallbackHarness mediaCallback;
  XCTAssertEqual(
    requestMediaAccess(
      permissionHandler.get(),
      harness.browser,
      "https://camera.example/device",
      CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE,
      mediaCallback
    ),
    1
  );

  const auto requests = copyRequests(requestProbe);
  XCTAssertEqual(requests.size(), static_cast<size_t>(1));
  const MiumCEFPermissionSessionID sessionID = requests[0].sessionID;

  XCTAssertEqual(
    beginMainFrameNavigation(
      requestHandler.get(),
      harness.browser,
      "https://top.example/other-path",
      0,
      0
    ),
    0
  );
  [self drainPendingAsyncWork];

  XCTAssertTrue(miumNativeCEFTestHasActivePermissionSession(sessionID));
  XCTAssertEqual(copyDismissals(dismissedProbe).size(), static_cast<size_t>(0));
  XCTAssertEqual(mediaCallback.state->cancelCalls, 0);

  XCTAssertEqual(
    beginMainFrameNavigation(
      requestHandler.get(),
      harness.browser,
      "https://different.example/landing",
      1,
      1
    ),
    0
  );
  [self drainPendingAsyncWork];

  const auto dismissals = copyDismissals(dismissedProbe);
  XCTAssertEqual(mediaCallback.state->cancelCalls, 1);
  XCTAssertEqual(dismissals.size(), static_cast<size_t>(1));
  XCTAssertEqual(dismissals[0].sessionID, sessionID);
  XCTAssertEqual(
    dismissals[0].reason,
    static_cast<uint32_t>(MiumCEFPermissionSessionDismissReason::mainFrameNavigation)
  );
  XCTAssertFalse(miumNativeCEFTestHasActivePermissionSession(sessionID));
}

- (void)testDirectPermissionPrimitivesRejectInvalidArgumentsAndMissingState {
  miumCEFPermissionResetState();

  XCTAssertEqual(
    miumCEFPermissionSetRequestHandler(0, nullptr, permissionRequestCallback),
    MiumCEFResultInvalidArgument
  );
  XCTAssertEqual(
    miumCEFPermissionSetSessionDismissedHandler(0, nullptr, permissionSessionDismissedCallback),
    MiumCEFResultInvalidArgument
  );
  XCTAssertEqual(
    miumCEFPermissionSetRequestHandler(404, nullptr, permissionRequestCallback),
    MiumCEFResultNotInitialized
  );
  XCTAssertEqual(
    miumCEFPermissionSetSessionDismissedHandler(404, nullptr, permissionSessionDismissedCallback),
    MiumCEFResultNotInitialized
  );

  miumCEFPermissionRegisterBrowser(0);
  XCTAssertEqual(miumCEFPermissionActiveSessionCount(), static_cast<size_t>(0));

  XCTAssertFalse(
    miumCEFPermissionHandleMediaAccessRequest(
      0,
      "https://invalid.example",
      "https://top.example",
      "frame-0",
      CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE,
      false,
      nullptr
    )
  );
  XCTAssertFalse(
    miumCEFPermissionHandleShowPromptRequest(
      0,
      "https://invalid.example",
      "https://top.example",
      9,
      CEF_PERMISSION_TYPE_CAMERA_STREAM,
      false,
      nullptr
    )
  );
  XCTAssertFalse(
    miumCEFPermissionHandleMediaAccessRequest(
      505,
      "https://missing-browser.example",
      "https://top.example",
      "frame-1",
      CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE,
      false,
      nullptr
    )
  );
  XCTAssertFalse(
    miumCEFPermissionHandleShowPromptRequest(
      505,
      "https://missing-browser.example",
      "https://top.example",
      10,
      CEF_PERMISSION_TYPE_CAMERA_STREAM,
      false,
      nullptr
    )
  );

  const uint64_t browserId = 77;
  miumCEFPermissionRegisterBrowser(browserId);
  miumCEFPermissionInjectDanglingBrowserSessionForTesting(999, 1);
  miumCEFPermissionInjectNullBrowserForTesting(1001);
  miumCEFPermissionInjectDanglingBrowserSessionForTesting(1001, 2);
  XCTAssertFalse(
    miumCEFPermissionHandleMediaAccessRequest(
      browserId,
      "https://unsupported.example",
      "https://top.example",
      "frame-2",
      CEF_MEDIA_PERMISSION_DESKTOP_AUDIO_CAPTURE,
      false,
      nullptr
    )
  );
  XCTAssertFalse(
    miumCEFPermissionHandleShowPromptRequest(
      browserId,
      "https://unsupported.example",
      "https://top.example",
      11,
      CEF_PERMISSION_TYPE_NOTIFICATIONS,
      false,
      nullptr
    )
  );
  XCTAssertFalse(
    miumCEFPermissionHandleMediaAccessRequest(
      browserId,
      "https://no-handler.example",
      "https://top.example",
      "frame-3",
      CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE,
      false,
      nullptr
    )
  );

  MiumCEFPermissionExecutionBatch batch{};
  XCTAssertFalse(
    miumCEFPermissionTakePromptDismissalBatch(
      browserId,
      12,
      MiumCEFPermissionSessionDismissReason::promptDismissed,
      nullptr
    )
  );
  XCTAssertFalse(
    miumCEFPermissionTakePromptDismissalBatch(
      909,
      12,
      MiumCEFPermissionSessionDismissReason::promptDismissed,
      &batch
    )
  );
  XCTAssertFalse(
    miumCEFPermissionTakeResolutionBatch(
      4040,
      MiumCEFPermissionResolution::allow,
      MiumCEFPermissionSessionDismissReason::unknown,
      true,
      nullptr
    )
  );
  XCTAssertFalse(
    miumCEFPermissionTakeResolutionBatch(
      4040,
      MiumCEFPermissionResolution::allow,
      MiumCEFPermissionSessionDismissReason::unknown,
      true,
      &batch
    )
  );

  std::vector<MiumCEFPermissionExecutionBatch> batches;
  miumCEFPermissionTakeBrowserDismissalBatches(
    browserId,
    MiumCEFPermissionSessionDismissReason::browserClosed,
    true,
    nullptr
  );
  miumCEFPermissionTakeBrowserDismissalBatches(
    909,
    MiumCEFPermissionSessionDismissReason::browserClosed,
    true,
    &batches
  );
  XCTAssertTrue(batches.empty());

  miumCEFPermissionTakeNavigationDismissalBatches(browserId, "https://top.example", nullptr);
  miumCEFPermissionTakeNavigationDismissalBatches(909, "https://top.example", &batches);
  XCTAssertTrue(batches.empty());

  miumCEFPermissionUnregisterBrowser(909);
  miumCEFPermissionExecuteBatch(nullptr);
}

- (void)testDirectPermissionPrimitivesCoverWrappedSessionIDsAndCorruptedStateCleanup {
  miumCEFPermissionResetState();

  const uint64_t browserId = 88;
  PermissionRequestProbe requestProbe;
  miumCEFPermissionRegisterBrowser(browserId);
  XCTAssertEqual(
    miumCEFPermissionSetRequestHandler(browserId, &requestProbe, permissionRequestCallback),
    MiumCEFResultOK
  );

  miumCEFPermissionSetNextSessionIDForTesting(0);
  FakeMediaAccessCallbackHarness mediaCallback;
  XCTAssertTrue(
    miumCEFPermissionHandleMediaAccessRequest(
      browserId,
      "https://wrap.example/device",
      "https://top.example",
      "frame-7",
      CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE,
      false,
      mediaCallback.callbackRef()
    )
  );

  const auto requests = copyRequests(requestProbe);
  XCTAssertEqual(requests.size(), static_cast<size_t>(1));
  XCTAssertEqual(requests[0].sessionID, static_cast<uint64_t>(1));
  XCTAssertTrue(miumCEFPermissionHasActiveSession(requests[0].sessionID));

  miumCEFPermissionInjectDanglingBrowserSessionForTesting(browserId, 404);

  MiumCEFPermissionExecutionBatch promptBatch{};
  XCTAssertFalse(
    miumCEFPermissionTakePromptDismissalBatch(
      browserId,
      9999,
      MiumCEFPermissionSessionDismissReason::promptDismissed,
      &promptBatch
    )
  );

  std::vector<MiumCEFPermissionExecutionBatch> navigationBatches;
  miumCEFPermissionTakeNavigationDismissalBatches(browserId, "https://top.example", &navigationBatches);
  XCTAssertTrue(navigationBatches.empty());
  XCTAssertTrue(miumCEFPermissionHasActiveSession(requests[0].sessionID));

  miumCEFPermissionInjectNullSessionForTesting(5050);
  miumCEFPermissionResetState();

  XCTAssertEqual(mediaCallback.state->continueCalls, 0);
  XCTAssertEqual(mediaCallback.state->cancelCalls, 0);
  XCTAssertEqual(miumCEFPermissionActiveSessionCount(), static_cast<size_t>(0));
}

- (void)testDirectPermissionPrimitivesBridgeEmptyOriginsAsNullPointers {
  miumCEFPermissionResetState();

  const uint64_t browserId = 89;
  PermissionRequestProbe requestProbe;
  miumCEFPermissionRegisterBrowser(browserId);
  XCTAssertEqual(
    miumCEFPermissionSetRequestHandler(browserId, &requestProbe, permissionRequestCallback),
    MiumCEFResultOK
  );

  FakeMediaAccessCallbackHarness mediaCallback;
  XCTAssertTrue(
    miumCEFPermissionHandleMediaAccessRequest(
      browserId,
      "",
      "",
      "",
      CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE,
      false,
      mediaCallback.callbackRef()
    )
  );

  const auto requests = copyRequests(requestProbe);
  XCTAssertEqual(requests.size(), static_cast<size_t>(1));
  XCTAssertTrue(requests[0].frameIdentifier.empty());
  XCTAssertTrue(requests[0].frameIdentifierWasNull);
  XCTAssertTrue(requests[0].requestingOrigin.empty());
  XCTAssertTrue(requests[0].requestingOriginWasNull);
  XCTAssertTrue(requests[0].topLevelOrigin.empty());
  XCTAssertTrue(requests[0].topLevelOriginWasNull);
  XCTAssertEqual(miumCEFPermissionActiveSessionCount(), static_cast<size_t>(1));

  miumCEFPermissionResetState();

  XCTAssertEqual(mediaCallback.state->continueCalls, 0);
  XCTAssertEqual(mediaCallback.state->cancelCalls, 0);
  XCTAssertEqual(miumCEFPermissionActiveSessionCount(), static_cast<size_t>(0));
}

- (void)testDirectPermissionUnregisterBrowserFinalizesOrphanedSessionsWithoutResolution {
  miumCEFPermissionResetState();

  const uint64_t browserId = 101;
  PermissionRequestProbe requestProbe;
  miumCEFPermissionRegisterBrowser(browserId);
  XCTAssertEqual(
    miumCEFPermissionSetRequestHandler(browserId, &requestProbe, permissionRequestCallback),
    MiumCEFResultOK
  );

  FakeMediaAccessCallbackHarness mediaCallback;
  XCTAssertTrue(
    miumCEFPermissionHandleMediaAccessRequest(
      browserId,
      "https://orphaned.example/device",
      "https://top.example",
      "frame-9",
      CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE,
      false,
      mediaCallback.callbackRef()
    )
  );
  XCTAssertEqual(copyRequests(requestProbe).size(), static_cast<size_t>(1));
  XCTAssertEqual(miumCEFPermissionActiveSessionCount(), static_cast<size_t>(1));

  miumCEFPermissionUnregisterBrowser(browserId);

  XCTAssertEqual(mediaCallback.state->continueCalls, 0);
  XCTAssertEqual(mediaCallback.state->cancelCalls, 0);
  XCTAssertEqual(miumCEFPermissionActiveSessionCount(), static_cast<size_t>(0));
}

- (void)testDirectPermissionInactiveRequestRegistrationDeniesWithoutInvokingHandler {
  miumCEFPermissionResetState();

  const uint64_t browserId = 111;
  PermissionRequestProbe requestProbe;
  auto registration = std::make_shared<MiumCEFCallbackRegistration>();
  miumCEFPermissionRegisterBrowser(browserId);
  XCTAssertEqual(
    miumCEFPermissionSetRequestHandler(browserId, &requestProbe, registration, permissionRequestCallback),
    MiumCEFResultOK
  );

  registration->active.store(false, std::memory_order_release);

  FakeMediaAccessCallbackHarness mediaCallback;
  XCTAssertTrue(
    miumCEFPermissionHandleMediaAccessRequest(
      browserId,
      "https://inactive.example/device",
      "https://top.example",
      "frame-inactive",
      CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE,
      false,
      mediaCallback.callbackRef()
    )
  );

  XCTAssertTrue(copyRequests(requestProbe).empty());
  XCTAssertEqual(mediaCallback.state->continueCalls, 1);
  XCTAssertEqual(mediaCallback.state->lastAllowedPermissions, static_cast<uint32_t>(0));
  XCTAssertEqual(mediaCallback.state->cancelCalls, 0);
  XCTAssertEqual(miumCEFPermissionActiveSessionCount(), static_cast<size_t>(0));
}

- (void)testDirectPermissionExecuteBatchHandlesNullCallbacksAndPromptDenials {
  MiumCEFPermissionExecutionBatch nullBatch{};
  nullBatch.kind = MiumCEFPermissionExecutionKind::resolve;
  nullBatch.resolution = MiumCEFPermissionResolution::allow;

  MiumCEFPermissionAttachment nullMediaAttachment;
  nullMediaAttachment.source = MiumCEFPermissionAttachmentSource::mediaAccess;
  nullMediaAttachment.requestedPermissions = CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE;
  nullBatch.attachments.push_back(nullMediaAttachment);

  MiumCEFPermissionAttachment nullPromptAttachment;
  nullPromptAttachment.source = MiumCEFPermissionAttachmentSource::permissionPrompt;
  nullBatch.attachments.push_back(nullPromptAttachment);

  miumCEFPermissionExecuteBatch(&nullBatch);
  XCTAssertTrue(nullBatch.attachments.empty());

  FakePermissionPromptCallbackHarness promptCallback;
  auto* promptRef = promptCallback.callbackRef();
  promptRef->base.add_ref(&promptRef->base);

  MiumCEFPermissionExecutionBatch denyBatch{};
  denyBatch.kind = MiumCEFPermissionExecutionKind::resolve;
  denyBatch.resolution = MiumCEFPermissionResolution::deny;

  MiumCEFPermissionAttachment denyPromptAttachment;
  denyPromptAttachment.source = MiumCEFPermissionAttachmentSource::permissionPrompt;
  denyPromptAttachment.promptCallback = promptRef;
  denyBatch.attachments.push_back(denyPromptAttachment);

  miumCEFPermissionExecuteBatch(&denyBatch);

  XCTAssertEqual(promptCallback.state->continueCalls, 1);
  XCTAssertEqual(promptCallback.state->lastResult, CEF_PERMISSION_RESULT_DENY);
  XCTAssertTrue(denyBatch.attachments.empty());
}

- (void)testDirectPermissionExecuteBatchSkipsInactiveDismissedRegistration {
  PermissionDismissedProbe dismissedProbe;
  auto registration = std::make_shared<MiumCEFCallbackRegistration>();
  registration->active.store(false, std::memory_order_release);

  MiumCEFPermissionExecutionBatch batch{};
  batch.notifyDismissedHandler = true;
  batch.sessionID = 8080;
  batch.dismissalReason = MiumCEFPermissionSessionDismissReason::explicitCancel;
  batch.dismissedHandler.registration = registration;
  batch.dismissedHandler.context = &dismissedProbe;
  batch.dismissedHandler.callback = permissionSessionDismissedCallback;

  miumCEFPermissionExecuteBatch(&batch);

  XCTAssertTrue(copyDismissals(dismissedProbe).empty());
  XCTAssertTrue(batch.attachments.empty());
}

- (void)testCEFBridgePermissionWrappersForwardRequestsAndDismissals {
  auto harness = makePermissionHarness(self, "https://top.example/bridge");
  XCTAssertNotEqual(harness.client, nullptr);
  XCTAssertTrue(miumNativeCEFTestAttachNativeBrowser(harness.browserHandle, harness.browser.browserRef(), harness.client));

  const CEFBridgeBrowserRef browserRef = reinterpret_cast<CEFBridgeBrowserRef>(harness.browserHandle);
  PermissionRequestProbe requestProbe;
  PermissionDismissedProbe dismissedProbe;

  CEFBridge_SetPermissionRequestHandler(nullptr, bridgePermissionRequestCallback, &requestProbe);
  CEFBridge_SetPermissionSessionDismissedHandler(nullptr, bridgePermissionSessionDismissedCallback, &dismissedProbe);
  CEFBridge_SetPermissionRequestHandler(browserRef, bridgePermissionRequestCallback, &requestProbe);
  CEFBridge_SetPermissionSessionDismissedHandler(browserRef, bridgePermissionSessionDismissedCallback, &dismissedProbe);

  ScopedCefRef<cef_permission_handler_t> permissionHandler = permissionHandlerForBrowser(harness);
  XCTAssertTrue(permissionHandler);

  FakeMediaAccessCallbackHarness mediaCallback;
  XCTAssertEqual(
    requestMediaAccess(
      permissionHandler.get(),
      harness.browser,
      "https://bridge.example/mic",
      CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE,
      mediaCallback
    ),
    1
  );

  auto requests = copyRequests(requestProbe);
  XCTAssertEqual(requests.size(), static_cast<size_t>(1));
  XCTAssertEqual(requests[0].browserID, reinterpret_cast<uint64_t>(harness.browserHandle));
  XCTAssertEqual(requests[0].requestingOrigin, "https://bridge.example");
  XCTAssertEqual(requests[0].topLevelOrigin, "https://top.example");
  XCTAssertEqual(requests[0].permissionFlags, static_cast<uint32_t>(CEFBridgePermissionKindMicrophone));

  XCTAssertEqual(
    CEFBridge_ResolvePermissionRequest(requests[0].sessionID, CEFBridgePermissionResolutionAllow),
    1
  );
  [self drainPendingAsyncWork];

  XCTAssertEqual(mediaCallback.state->continueCalls, 1);
  XCTAssertEqual(mediaCallback.state->lastAllowedPermissions, CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE);

  FakePermissionPromptCallbackHarness promptCallback;
  XCTAssertEqual(
    showPermissionPrompt(
      permissionHandler.get(),
      harness.browser,
      144,
      "https://bridge.example/prompt",
      CEF_PERMISSION_TYPE_MIC_STREAM,
      promptCallback
    ),
    1
  );

  requests = copyRequests(requestProbe);
  XCTAssertEqual(requests.size(), static_cast<size_t>(2));
  const auto promptSessionID = requests[1].sessionID;
  XCTAssertEqual(requests[1].promptID, static_cast<uint64_t>(144));
  XCTAssertEqual(requests[1].source, static_cast<uint32_t>(CEFBridgePermissionRequestSourcePermissionPrompt));

  XCTAssertEqual(
    CEFBridge_ResolvePermissionRequest(promptSessionID, CEFBridgePermissionResolutionCancel),
    1
  );
  [self drainPendingAsyncWork];

  const auto dismissals = copyDismissals(dismissedProbe);
  XCTAssertEqual(promptCallback.state->continueCalls, 1);
  XCTAssertEqual(promptCallback.state->lastResult, CEF_PERMISSION_RESULT_DISMISS);
  XCTAssertEqual(dismissals.size(), static_cast<size_t>(1));
  XCTAssertEqual(dismissals[0].sessionID, promptSessionID);
  XCTAssertEqual(
    dismissals[0].reason,
    static_cast<uint32_t>(CEFBridgePermissionSessionDismissReasonExplicitCancel)
  );

  CEFBridge_SetPermissionRequestHandler(browserRef, nullptr, nullptr);
  CEFBridge_SetPermissionSessionDismissedHandler(browserRef, nullptr, nullptr);
  CEFBridge_SetPermissionSessionDismissedHandler(browserRef, bridgePermissionSessionDismissedCallback, &dismissedProbe);
  CEFBridge_SetPermissionSessionDismissedHandler(browserRef, nullptr, nullptr);
  CEFBridge_SetPermissionRequestHandler(browserRef, bridgePermissionRequestCallback, &requestProbe);
  CEFBridge_SetPermissionRequestHandler(browserRef, nullptr, nullptr);
  CEFBridge_StopLoad(browserRef);
  CEFBridgeTestInstallRawPermissionRequestHandlerState(nullptr, nullptr, nullptr);
  CEFBridgeTestInstallRawPermissionDismissedHandlerState(nullptr, nullptr, nullptr);

  MiumCEFPermissionRequest bridgeRequest{};
  bridgeRequest.sessionID = 9001;
  bridgeRequest.browserID = reinterpret_cast<uint64_t>(harness.browserHandle);
  bridgeRequest.promptID = 333;
  bridgeRequest.permissionFlags = static_cast<uint32_t>(CEFBridgePermissionKindCamera);
  bridgeRequest.source = static_cast<uint32_t>(CEFBridgePermissionRequestSourceMediaAccess);
  bridgeRequest.requestingOrigin = "https://bridge.example";
  bridgeRequest.topLevelOrigin = "https://top.example";
  const auto syntheticBrowserRef = reinterpret_cast<CEFBridgeBrowserRef>(static_cast<uintptr_t>(0xBEEF));

  CEFBridgeTestBrowserPermissionRequestHandler(nullptr, nullptr);
  CEFBridgeTestBrowserPermissionRequestHandlerForBrowser(browserRef, &bridgeRequest);
  CEFBridgeTestInstallRawPermissionRequestHandlerState(browserRef, nullptr, nullptr);
  CEFBridgeTestBrowserPermissionRequestHandlerForBrowser(browserRef, &bridgeRequest);
  CEFBridgeTestBrowserPermissionSessionDismissedHandler(nullptr, 9001, 0);
  CEFBridgeTestBrowserPermissionSessionDismissedHandlerForBrowser(browserRef, 9001, 0);
  CEFBridgeTestInstallRawPermissionDismissedHandlerState(
    syntheticBrowserRef,
    bridgePermissionSessionDismissedCallback,
    &dismissedProbe
  );
  CEFBridgeTestInstallRawPermissionDismissedHandlerState(browserRef, nullptr, nullptr);
  CEFBridgeTestBrowserPermissionSessionDismissedHandlerForBrowser(browserRef, 9001, 0);

  FakeMediaAccessCallbackHarness deniedCallback;
  XCTAssertEqual(
    requestMediaAccess(
      permissionHandler.get(),
      harness.browser,
      "https://bridge.example/removed",
      CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE,
      deniedCallback
    ),
    1
  );

  XCTAssertEqual(copyRequests(requestProbe).size(), static_cast<size_t>(2));
  XCTAssertEqual(deniedCallback.state->continueCalls, 1);
  XCTAssertEqual(deniedCallback.state->lastAllowedPermissions, static_cast<uint32_t>(0));
  XCTAssertEqual(
    CEFBridge_ResolvePermissionRequest(999999, CEFBridgePermissionResolutionAllow),
    0
  );
}

@end
