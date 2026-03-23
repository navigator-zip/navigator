#include "CEFBridge.h"

#include <Foundation/Foundation.h>

#include <algorithm>
#include <atomic>
#include <cstdarg>
#include <cstring>
#include <cstdint>
#include <cstdlib>
#include <memory>
#include <unordered_map>
#include <mutex>
#include <string>
#include <utility>

#include "MiumCEFBridgeNative.h"
#include "Tracing.h"
#if defined(MIUM_CEF_BRIDGE_TESTING)
#include "CEFBridge+Testing.h"
#endif

namespace {

static bool shouldEmitWrapperDiagnostics() {
#if defined(MIUM_CEF_BRIDGE_TESTING)
  return miumCefTracingEnabled();
#else
  return true;
#endif
}

static void wrapperDiagnostic(const char* format, ...) {
  if (!shouldEmitWrapperDiagnostics()) {
    return;
  }
  va_list args;
  va_start(args, format);
  if (miumCefTracingEnabled()) {
    miumCefTraceV("wrapper", format, args);
  } else {
    std::fprintf(stderr, "[MiumCEFBridge] ");
    std::vfprintf(stderr, format, args);
  }
  va_end(args);
}

static std::mutex g_runtime_mutex;
static std::atomic<MiumCEFRuntimeHandle> g_runtime{nullptr};
static std::mutex g_bridge_message_handler_mutex;
static std::mutex g_bridge_permission_handler_mutex;
struct BridgeMessageRegistration : MiumCEFCallbackRegistration {
  CEFBridgeBrowserRef browserRef = nullptr;
  std::string channel;
  CEFBridgeMessageCallback callback = nullptr;
  void* userData = nullptr;
};

struct BridgePermissionRequestRegistration : MiumCEFCallbackRegistration {
  CEFBridgeBrowserRef browserRef = nullptr;
  CEFBridgePermissionRequestCallback callback = nullptr;
  void* userData = nullptr;
};

struct BridgePermissionSessionDismissedRegistration : MiumCEFCallbackRegistration {
  CEFBridgeBrowserRef browserRef = nullptr;
  CEFBridgePermissionSessionDismissedCallback callback = nullptr;
  void* userData = nullptr;
};

static std::unordered_map<CEFBridgeBrowserRef, std::unordered_map<std::string, std::shared_ptr<BridgeMessageRegistration>>> g_bridge_message_handlers;
static std::unordered_map<CEFBridgeBrowserRef, std::shared_ptr<BridgePermissionRequestRegistration>> g_bridge_permission_request_handlers;
static std::unordered_map<CEFBridgeBrowserRef, std::shared_ptr<BridgePermissionSessionDismissedRegistration>> g_bridge_permission_dismissed_handlers;
static MiumCEFBrowserHandle HandleFromRef(CEFBridgeBrowserRef ref);
#if defined(MIUM_CEF_BRIDGE_TESTING)
static CEFBridgeTestFailureMode g_test_failure_mode = CEFBridgeTestFailureMode::none;
#endif

static void browserBridgeMessageHandler(
  MiumCEFResultCode code,
  const char* message,
  void* context
) {
  auto* registration = static_cast<BridgeMessageRegistration*>(context);
  if (registration == nullptr || !registration->active.load(std::memory_order_acquire)) {
    return;
  }

  if (registration->callback != nullptr && code == MiumCEFResultOK) {
    registration->callback(registration->userData, message == nullptr ? "" : message);
  }
}

static void setBrowserBridgeMessageHandler(
  CEFBridgeBrowserRef browserRef,
  const char* channel,
  CEFBridgeMessageCallback callback,
  void* userData
) {
  if (browserRef == nullptr || channel == nullptr) {
    return;
  }
  const std::string channelString(channel);

  if (callback == nullptr) {
    {
      std::lock_guard<std::mutex> lock(g_bridge_message_handler_mutex);
      if (auto browserIt = g_bridge_message_handlers.find(browserRef); browserIt != g_bridge_message_handlers.end()) {
        if (auto channelIt = browserIt->second.find(channelString); channelIt != browserIt->second.end()) {
          channelIt->second->active.store(false, std::memory_order_release);
        }
        browserIt->second.erase(channelString);
        if (browserIt->second.empty()) {
          g_bridge_message_handlers.erase(browserIt);
        }
      }
    }
    (void)miumNativeCEFRegisterMessageHandlerWithRegistration(
      HandleFromRef(browserRef),
      channel,
      {},
      nullptr,
      nullptr
    );
    return;
  }

  std::shared_ptr<BridgeMessageRegistration> registration;
  {
    std::lock_guard<std::mutex> lock(g_bridge_message_handler_mutex);
    auto& browserRegistrations = g_bridge_message_handlers[browserRef];
    if (auto existingIt = browserRegistrations.find(channelString); existingIt != browserRegistrations.end()) {
      existingIt->second->active.store(false, std::memory_order_release);
    }

    registration = std::make_shared<BridgeMessageRegistration>();
    registration->browserRef = browserRef;
    registration->channel = channelString;
    registration->callback = callback;
    registration->userData = userData;
    browserRegistrations[channelString] = registration;
  }
  (void)miumNativeCEFRegisterMessageHandlerWithRegistration(
    HandleFromRef(browserRef),
    channel,
    std::static_pointer_cast<MiumCEFCallbackRegistration>(registration),
    registration.get(),
    browserBridgeMessageHandler
  );
}

static void clearAllBrowserBridgeMessageHandlers(CEFBridgeBrowserRef browserRef) {
  static constexpr const char* kBridgeMessageChannels[] = {
    MiumCEFAddressChangeChannel,
    MiumCEFTitleChangeChannel,
    MiumCEFFaviconURLChangeChannel,
    MiumCEFPictureInPictureStateChangeChannel,
    MiumCEFTopLevelNativeContentChannel,
    MiumCEFRenderProcessTerminationChannel,
    MiumCEFMainFrameNavigationChannel,
    MiumCEFOpenURLInTabChannel,
    MiumCEFCameraRoutingEventChannel,
  };

  for (const char* channel : kBridgeMessageChannels) {
    setBrowserBridgeMessageHandler(browserRef, channel, nullptr, nullptr);
  }
}

static void browserPermissionRequestHandler(void* context, const MiumCEFPermissionRequest* request) {
  auto* registration = static_cast<BridgePermissionRequestRegistration*>(context);
  if (registration == nullptr || request == nullptr || !registration->active.load(std::memory_order_acquire)) {
    return;
  }

  const CEFBridgePermissionRequest bridgedRequest{
    .session_id = request->sessionID,
    .browser_id = request->browserID,
    .prompt_id = request->promptID,
    .frame_identifier = request->frameIdentifier,
    .permission_flags = request->permissionFlags,
    .source = request->source,
    .requesting_origin = request->requestingOrigin,
    .top_level_origin = request->topLevelOrigin,
  };
  if (registration->callback != nullptr) {
    registration->callback(registration->userData, &bridgedRequest);
  }
}

static void browserPermissionSessionDismissedHandler(
  void* context,
  MiumCEFPermissionSessionID sessionID,
  uint32_t reason
) {
  auto* registration = static_cast<BridgePermissionSessionDismissedRegistration*>(context);
  if (registration != nullptr
      && registration->active.load(std::memory_order_acquire)
      && registration->callback != nullptr) {
    registration->callback(registration->userData, sessionID, reason);
  }
}

static NSString* StandardizedPathString(const char* path) {
  if (path == nullptr || path[0] == '\0') {
    return nil;
  }
  NSString* normalized = [NSString stringWithUTF8String:path];
  if (normalized == nil || normalized.length == 0) {
    return nil;
  }
#if defined(MIUM_CEF_BRIDGE_TESTING)
  if (g_test_failure_mode == CEFBridgeTestFailureMode::normalizeStandardizeReturnsNil) {
    normalized = nil;
  } else {
    normalized = [normalized stringByStandardizingPath];
  }
#else
  normalized = [normalized stringByStandardizingPath];
#endif
  if (normalized == nil || normalized.length == 0) {
    return nil;
  }
  return normalized;
}

static std::string NormalizeCPath(const char* path) {
  NSString* normalized = StandardizedPathString(path);
  if (normalized == nil) {
    return {};
  }
#if defined(MIUM_CEF_BRIDGE_TESTING)
  const char* normalized_bytes =
    g_test_failure_mode == CEFBridgeTestFailureMode::normalizeUTF8ReturnsNull
      ? nullptr
      : normalized.UTF8String;
#else
  const char* normalized_bytes = normalized.UTF8String;
#endif
  if (normalized_bytes == nullptr) {
    return {};
  }
  return normalized_bytes;
}

static std::string ResolveRuntimeRoot(const char* resources_path) {
  if (resources_path != nullptr && resources_path[0] != '\0') {
    NSString* normalized = StandardizedPathString(resources_path);
    if (normalized != nil) {
      if ([normalized hasSuffix:@"/Contents/Resources"]) {
        normalized = [[normalized stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
      }
      if (normalized.length == 0) {
        return {};
      }
      const char* runtime_root = normalized.UTF8String;
#if defined(MIUM_CEF_BRIDGE_TESTING)
      if (g_test_failure_mode == CEFBridgeTestFailureMode::resourcesFileSystemRepresentationReturnsNull) {
        runtime_root = nullptr;
      } else if (g_test_failure_mode == CEFBridgeTestFailureMode::resourcesFileSystemRepresentationReturnsEmpty) {
        runtime_root = "";
      }
#endif
      if (runtime_root != nullptr && runtime_root[0] != '\0') {
        return NormalizeCPath(runtime_root);
      }
    }
  }

  NSString* bundle_path = nil;
#if defined(MIUM_CEF_BRIDGE_TESTING)
  if (g_test_failure_mode != CEFBridgeTestFailureMode::bundlePathReturnsNil) {
    bundle_path = [[NSBundle mainBundle] bundlePath];
  }
#else
  bundle_path = [[NSBundle mainBundle] bundlePath];
#endif
  if (bundle_path == nil || bundle_path.length == 0) {
    return {};
  }
#if defined(MIUM_CEF_BRIDGE_TESTING)
  const char* bundle_root =
    g_test_failure_mode == CEFBridgeTestFailureMode::bundleFileSystemRepresentationReturnsNull
      ? nullptr
      : bundle_path.UTF8String;
  if (g_test_failure_mode == CEFBridgeTestFailureMode::bundleFileSystemRepresentationReturnsEmpty) {
    bundle_root = "";
  }
#else
  const char* bundle_root = bundle_path.UTF8String;
#endif
  if (bundle_root == nullptr || bundle_root[0] == '\0') {
    return {};
  }
  return NormalizeCPath(bundle_root);
}

static std::string ResolveMetadataPath(const char* resources_path) {
  if (resources_path != nullptr && resources_path[0] != '\0') {
    return NormalizeCPath(resources_path);
  }
  return {};
}

static MiumCEFBrowserHandle HandleFromRef(CEFBridgeBrowserRef ref) {
  return reinterpret_cast<MiumCEFBrowserHandle>(ref);
}

struct JavaScriptResultContext {
  CEFBridgeJavaScriptResultCallback callback;
  void* user_data;
};

static void ForwardJavaScriptResult(MiumCEFResultCode code, const char* result, void* user_data) {
  auto* context = static_cast<JavaScriptResultContext*>(user_data);
  if (context == nullptr) {
    return;
  }
  if (context->callback != nullptr) {
    if (code == MiumCEFResultOK) {
      context->callback(context->user_data, result != nullptr ? result : "", "");
    } else {
      context->callback(context->user_data, "", result != nullptr ? result : "cef execute javascript failed");
    }
  }
  delete context;
}

}  // namespace

static bool isCefSubprocessArgv(int argc, const char* const* argv) {
  if (argc <= 0 || argv == nullptr) {
    return false;
  }

  for (int index = 0; index < argc; ++index) {
    const char* arg = argv[index];
    if (arg == nullptr) {
      continue;
    }
    if (std::strncmp(arg, "--type=", 7) == 0) {
      return true;
    }
  }

  return false;
}

int CEFBridge_MaybeRunSubprocess(int argc, const void* argv) {
  if (argc <= 0 || argv == nullptr) {
    return -1;
  }

  const auto* argv_values = static_cast<const char* const*>(argv);
  if (!isCefSubprocessArgv(argc, static_cast<const char* const*>(argv_values))) {
    return -1;
  }

  return miumNativeCEFMaybeRunSubprocess(argc, argv_values);
}

int CEFBridge_Initialize(const char* resources_path,
                         const char* locales_path,
                         const char* cache_path,
                         const char* subprocess_path) {
  // locales_path is currently derived from runtime_layout.json inside the native
  // runtime bootstrap. This argument is preserved for ABI compatibility.
  (void)locales_path;

  if (cache_path != nullptr && cache_path[0] != '\0') {
    setenv("MIUM_CEF_ROOT_CACHE_PATH", cache_path, 1);
  } else {
    unsetenv("MIUM_CEF_ROOT_CACHE_PATH");
  }

  if (subprocess_path != nullptr && subprocess_path[0] != '\0') {
    setenv("MIUM_CEF_BROWSER_SUBPROCESS_PATH", subprocess_path, 1);
  } else {
    unsetenv("MIUM_CEF_BROWSER_SUBPROCESS_PATH");
  }

  std::lock_guard<std::mutex> lock(g_runtime_mutex);
  if (g_runtime.load(std::memory_order_acquire) != nullptr) {
    return 1;
  }

  const std::string metadata_path = ResolveMetadataPath(resources_path);
  if (metadata_path.empty()) {
    return 0;
  }

  const std::string runtime_root = ResolveRuntimeRoot(resources_path);
  if (runtime_root.empty()) {
    return 0;
  }

  MiumCEFRuntimeHandle runtime = nullptr;
  const MiumCEFResultCode result = miumNativeCEFInitialize(
    runtime_root.c_str(),
    metadata_path.c_str(),
    nullptr,
    nullptr,
    &runtime
  );
#if defined(MIUM_CEF_BRIDGE_TESTING)
  if (g_test_failure_mode == CEFBridgeTestFailureMode::initializeReturnsOKWithNullRuntime) {
    if (result == MiumCEFResultOK) {
      (void)miumNativeCEFShutdown(runtime);
      runtime = nullptr;
    }
  }
#endif
  if (result != MiumCEFResultOK || runtime == nullptr) {
    return 0;
  }

  g_runtime.store(runtime, std::memory_order_release);
  return 1;
}

void CEFBridge_Shutdown(void) {
  std::lock_guard<std::mutex> lock(g_runtime_mutex);
  MiumCEFRuntimeHandle runtime = g_runtime.load(std::memory_order_acquire);
  if (runtime == nullptr) {
    return;
  }
  miumNativeCEFShutdown(runtime);
  g_runtime.store(nullptr, std::memory_order_release);
}

void CEFBridge_DoMessageLoopWork(void) {
  if (g_runtime.load(std::memory_order_acquire) == nullptr) {
    return;
  }
  // Bridge runtime relies on host-driven manual message loop pumping.
  (void)miumNativeCEFDoMessageLoopWork();
}

int CEFBridge_HasPendingBrowserClose(void) {
  return miumNativeCEFHasPendingBrowserClose();
}

CEFBridgeBrowserRef CEFBridge_CreateBrowser(void* parent_view,
                                           const char* initial_url,
                                           int width,
                                           int height,
                                           double backing_scale_factor) {
  (void)backing_scale_factor;
  const MiumCEFRuntimeHandle runtime = g_runtime.load(std::memory_order_acquire);
  if (runtime == nullptr || parent_view == nullptr || width <= 0 || height <= 0) {
    return nullptr;
  }

  MiumCEFBrowserHandle browser_handle = nullptr;
  const MiumCEFResultCode browser_result = miumNativeCEFCreateBrowser(runtime, &browser_handle);
#if defined(MIUM_CEF_BRIDGE_TESTING)
  if (g_test_failure_mode == CEFBridgeTestFailureMode::createBrowserReturnsOKWithNullHandle) {
    if (browser_result == MiumCEFResultOK) {
      (void)miumNativeCEFDestroyBrowser(browser_handle);
      browser_handle = nullptr;
    }
  }
#endif
  if (browser_result != MiumCEFResultOK || browser_handle == nullptr) {
    wrapperDiagnostic("CreateBrowser: native browser creation failed\n");
    return nullptr;
  }

  MiumCEFHostViewHandle host_view_handle = nullptr;
  const MiumCEFResultCode host_result = miumNativeCEFCreateBrowserHostViewForNSView(
    browser_handle,
    parent_view,
    &host_view_handle
  );
#if defined(MIUM_CEF_BRIDGE_TESTING)
  if (g_test_failure_mode == CEFBridgeTestFailureMode::createHostViewReturnsOKWithNullHandle) {
    if (host_result == MiumCEFResultOK) {
      (void)miumNativeCEFDestroyBrowserHostView(host_view_handle);
      host_view_handle = nullptr;
    }
  }
#endif
  if (host_result != MiumCEFResultOK || host_view_handle == nullptr) {
    wrapperDiagnostic(
      "CreateBrowser: host view creation failed code=%u\n",
      static_cast<unsigned int>(host_result)
    );
    miumNativeCEFDestroyBrowser(browser_handle);
    return nullptr;
  }
  return reinterpret_cast<CEFBridgeBrowserRef>(browser_handle);
}

void CEFBridge_ResizeBrowser(CEFBridgeBrowserRef browser_ref,
                            int width,
                            int height,
                            double backing_scale_factor) {
  (void)backing_scale_factor;
  if (width <= 0 || height <= 0) {
    return;
  }

  miumNativeCEFResizeBrowser(HandleFromRef(browser_ref), width, height);
}

void CEFBridge_LoadUrl(CEFBridgeBrowserRef browser_ref, const char* url) {
  miumNativeCEFLoadURL(HandleFromRef(browser_ref), url, nullptr, nullptr);
}

void CEFBridge_StopLoad(CEFBridgeBrowserRef browser_ref) {
  miumNativeCEFStopLoad(HandleFromRef(browser_ref));
}

void CEFBridge_GoBack(CEFBridgeBrowserRef browser_ref) {
  miumNativeCEFGoBack(HandleFromRef(browser_ref));
}

void CEFBridge_GoForward(CEFBridgeBrowserRef browser_ref) {
  miumNativeCEFGoForward(HandleFromRef(browser_ref));
}

void CEFBridge_Reload(CEFBridgeBrowserRef browser_ref) {
  miumNativeCEFReload(HandleFromRef(browser_ref));
}

void CEFBridge_CloseBrowser(CEFBridgeBrowserRef browser_ref) {
  clearAllBrowserBridgeMessageHandlers(browser_ref);
  CEFBridge_SetPermissionRequestHandler(browser_ref, nullptr, nullptr);
  CEFBridge_SetPermissionSessionDismissedHandler(browser_ref, nullptr, nullptr);
  MiumCEFHostViewHandle host_view_handle = miumNativeCEFHostViewHandleForBrowser(HandleFromRef(browser_ref));
  if (host_view_handle != nullptr) {
    miumNativeCEFDestroyBrowser(HandleFromRef(browser_ref));
    miumNativeCEFDestroyBrowserHostView(host_view_handle);
    return;
  }
  miumNativeCEFDestroyBrowser(HandleFromRef(browser_ref));
}

int CEFBridge_CanGoBack(CEFBridgeBrowserRef browser_ref) {
  return miumNativeCEFCanGoBack(HandleFromRef(browser_ref));
}

int CEFBridge_CanGoForward(CEFBridgeBrowserRef browser_ref) {
  return miumNativeCEFCanGoForward(HandleFromRef(browser_ref));
}

int CEFBridge_IsLoading(CEFBridgeBrowserRef browser_ref) {
  return miumNativeCEFIsLoading(HandleFromRef(browser_ref));
}

void CEFBridge_ExecuteJavaScript(CEFBridgeBrowserRef browser_ref, const char* script) {
  miumNativeCEFEvaluateJavaScript(HandleFromRef(browser_ref), script, nullptr, nullptr);
}

void CEFBridge_SetMessageHandler(CEFBridgeBrowserRef browser_ref,
                                CEFBridgeMessageCallback callback,
                                void* user_data) {
  if (callback == nullptr) {
    setBrowserBridgeMessageHandler(browser_ref, MiumCEFAddressChangeChannel, nullptr, nullptr);
    return;
  }
  setBrowserBridgeMessageHandler(browser_ref, MiumCEFAddressChangeChannel, callback, user_data);
}

void CEFBridge_SetTitleChangeHandler(CEFBridgeBrowserRef browser_ref,
                                    CEFBridgeMessageCallback callback,
                                    void* user_data) {
  if (callback == nullptr) {
    setBrowserBridgeMessageHandler(browser_ref, MiumCEFTitleChangeChannel, nullptr, nullptr);
    return;
  }
  setBrowserBridgeMessageHandler(browser_ref, MiumCEFTitleChangeChannel, callback, user_data);
}

void CEFBridge_SetFaviconURLChangeHandler(CEFBridgeBrowserRef browser_ref,
                                         CEFBridgeMessageCallback callback,
                                         void* user_data) {
  if (callback == nullptr) {
    setBrowserBridgeMessageHandler(browser_ref, MiumCEFFaviconURLChangeChannel, nullptr, nullptr);
    return;
  }
  setBrowserBridgeMessageHandler(browser_ref, MiumCEFFaviconURLChangeChannel, callback, user_data);
}

void CEFBridge_SetPictureInPictureStateChangeHandler(CEFBridgeBrowserRef browser_ref,
                                                    CEFBridgeMessageCallback callback,
                                                    void* user_data) {
  if (callback == nullptr) {
    setBrowserBridgeMessageHandler(browser_ref, MiumCEFPictureInPictureStateChangeChannel, nullptr, nullptr);
    return;
  }
  setBrowserBridgeMessageHandler(browser_ref, MiumCEFPictureInPictureStateChangeChannel, callback, user_data);
}

void CEFBridge_SetTopLevelNativeContentHandler(CEFBridgeBrowserRef browser_ref,
                                              CEFBridgeMessageCallback callback,
                                              void* user_data) {
  if (callback == nullptr) {
    setBrowserBridgeMessageHandler(browser_ref, MiumCEFTopLevelNativeContentChannel, nullptr, nullptr);
    return;
  }
  setBrowserBridgeMessageHandler(browser_ref, MiumCEFTopLevelNativeContentChannel, callback, user_data);
}

void CEFBridge_SetRenderProcessTerminationHandler(CEFBridgeBrowserRef browser_ref,
                                                  CEFBridgeMessageCallback callback,
                                                  void* user_data) {
  if (callback == nullptr) {
    setBrowserBridgeMessageHandler(browser_ref, MiumCEFRenderProcessTerminationChannel, nullptr, nullptr);
    return;
  }
  setBrowserBridgeMessageHandler(browser_ref, MiumCEFRenderProcessTerminationChannel, callback, user_data);
}

void CEFBridge_SetMainFrameNavigationHandler(CEFBridgeBrowserRef browser_ref,
                                             CEFBridgeMessageCallback callback,
                                             void* user_data) {
  if (callback == nullptr) {
    setBrowserBridgeMessageHandler(browser_ref, MiumCEFMainFrameNavigationChannel, nullptr, nullptr);
    return;
  }
  setBrowserBridgeMessageHandler(browser_ref, MiumCEFMainFrameNavigationChannel, callback, user_data);
}

void CEFBridge_SetOpenURLInTabHandler(CEFBridgeBrowserRef browser_ref,
                                      CEFBridgeMessageCallback callback,
                                      void* user_data) {
  if (callback == nullptr) {
    setBrowserBridgeMessageHandler(browser_ref, MiumCEFOpenURLInTabChannel, nullptr, nullptr);
    return;
  }
  setBrowserBridgeMessageHandler(browser_ref, MiumCEFOpenURLInTabChannel, callback, user_data);
}

void CEFBridge_SetCameraRoutingEventHandler(CEFBridgeBrowserRef browser_ref,
                                            CEFBridgeMessageCallback callback,
                                            void* user_data) {
  if (callback == nullptr) {
    setBrowserBridgeMessageHandler(browser_ref, MiumCEFCameraRoutingEventChannel, nullptr, nullptr);
    return;
  }
  setBrowserBridgeMessageHandler(browser_ref, MiumCEFCameraRoutingEventChannel, callback, user_data);
}

void CEFBridge_SetPermissionRequestHandler(CEFBridgeBrowserRef browser_ref,
                                           CEFBridgePermissionRequestCallback callback,
                                           void* user_data) {
  if (browser_ref == nullptr) {
    return;
  }

  if (callback == nullptr) {
    {
      std::lock_guard<std::mutex> lock(g_bridge_permission_handler_mutex);
      if (auto handlerIt = g_bridge_permission_request_handlers.find(browser_ref);
          handlerIt != g_bridge_permission_request_handlers.end()) {
        handlerIt->second->active.store(false, std::memory_order_release);
        g_bridge_permission_request_handlers.erase(handlerIt);
      }
    }
    (void)miumNativeCEFSetPermissionRequestHandlerWithRegistration(
      HandleFromRef(browser_ref),
      {},
      nullptr,
      nullptr
    );
    return;
  }

  std::shared_ptr<BridgePermissionRequestRegistration> registration;
  {
    std::lock_guard<std::mutex> lock(g_bridge_permission_handler_mutex);
    if (auto existingIt = g_bridge_permission_request_handlers.find(browser_ref);
        existingIt != g_bridge_permission_request_handlers.end()) {
      existingIt->second->active.store(false, std::memory_order_release);
    }
    registration = std::make_shared<BridgePermissionRequestRegistration>();
    registration->browserRef = browser_ref;
    registration->callback = callback;
    registration->userData = user_data;
    g_bridge_permission_request_handlers[browser_ref] = registration;
  }

  (void)miumNativeCEFSetPermissionRequestHandlerWithRegistration(
    HandleFromRef(browser_ref),
    std::static_pointer_cast<MiumCEFCallbackRegistration>(registration),
    registration.get(),
    browserPermissionRequestHandler
  );
}

void CEFBridge_SetPermissionSessionDismissedHandler(
  CEFBridgeBrowserRef browser_ref,
  CEFBridgePermissionSessionDismissedCallback callback,
  void* user_data
) {
  if (browser_ref == nullptr) {
    return;
  }

  if (callback == nullptr) {
    {
      std::lock_guard<std::mutex> lock(g_bridge_permission_handler_mutex);
      if (auto handlerIt = g_bridge_permission_dismissed_handlers.find(browser_ref);
          handlerIt != g_bridge_permission_dismissed_handlers.end()) {
        handlerIt->second->active.store(false, std::memory_order_release);
        g_bridge_permission_dismissed_handlers.erase(handlerIt);
      }
    }
    (void)miumNativeCEFSetPermissionSessionDismissedHandlerWithRegistration(
      HandleFromRef(browser_ref),
      {},
      nullptr,
      nullptr
    );
    return;
  }

  std::shared_ptr<BridgePermissionSessionDismissedRegistration> registration;
  {
    std::lock_guard<std::mutex> lock(g_bridge_permission_handler_mutex);
    if (auto existingIt = g_bridge_permission_dismissed_handlers.find(browser_ref);
        existingIt != g_bridge_permission_dismissed_handlers.end()) {
      existingIt->second->active.store(false, std::memory_order_release);
    }
    registration = std::make_shared<BridgePermissionSessionDismissedRegistration>();
    registration->browserRef = browser_ref;
    registration->callback = callback;
    registration->userData = user_data;
    g_bridge_permission_dismissed_handlers[browser_ref] = registration;
  }

  (void)miumNativeCEFSetPermissionSessionDismissedHandlerWithRegistration(
    HandleFromRef(browser_ref),
    std::static_pointer_cast<MiumCEFCallbackRegistration>(registration),
    registration.get(),
    browserPermissionSessionDismissedHandler
  );
}

int CEFBridge_ResolvePermissionRequest(CEFBridgePermissionSessionID session_id, uint32_t resolution) {
  return miumNativeCEFResolvePermissionRequest(session_id, resolution) == MiumCEFResultOK ? 1 : 0;
}

void CEFBridge_ExecuteJavaScriptWithResult(CEFBridgeBrowserRef browser_ref,
                                          const char* script,
                                          CEFBridgeJavaScriptResultCallback callback,
                                          void* user_data) {
  (void)browser_ref;
  if (callback == nullptr) {
    return;
  }
  auto* context = new JavaScriptResultContext{callback, user_data};
  miumNativeCEFEvaluateJavaScript(
    HandleFromRef(browser_ref),
    script,
    context,
    ForwardJavaScriptResult
  );
}

void CEFBridge_ExecuteJavaScriptInRendererWithResult(
  CEFBridgeBrowserRef browser_ref,
  const char* script,
  CEFBridgeJavaScriptResultCallback callback,
  void* user_data
) {
  (void)browser_ref;
  if (callback == nullptr) {
    return;
  }
  auto* context = new JavaScriptResultContext{callback, user_data};
  miumNativeCEFExecuteJavaScriptInRendererWithResult(
    HandleFromRef(browser_ref),
    script,
    context,
    ForwardJavaScriptResult
  );
}

#if defined(MIUM_CEF_BRIDGE_TESTING)

bool CEFBridgeTestIsCefSubprocessArgv(int argc, const char* const* argv) {
  return isCefSubprocessArgv(argc, argv);
}

std::string CEFBridgeTestNormalizeCPath(const char* path) {
  return NormalizeCPath(path);
}

std::string CEFBridgeTestResolveRuntimeRoot(const char* resourcesPath) {
  return ResolveRuntimeRoot(resourcesPath);
}

std::string CEFBridgeTestResolveMetadataPath(const char* resourcesPath) {
  return ResolveMetadataPath(resourcesPath);
}

void CEFBridgeTestResetState(void) {
  {
    std::lock_guard<std::mutex> lock(g_runtime_mutex);
    g_runtime.store(nullptr, std::memory_order_release);
  }
  {
    std::lock_guard<std::mutex> lock(g_bridge_message_handler_mutex);
    g_bridge_message_handlers.clear();
  }
  {
    std::lock_guard<std::mutex> lock(g_bridge_permission_handler_mutex);
    g_bridge_permission_request_handlers.clear();
    g_bridge_permission_dismissed_handlers.clear();
  }
  g_test_failure_mode = CEFBridgeTestFailureMode::none;
}

void CEFBridgeTestSetBridgeRuntimeState(MiumCEFRuntimeHandle runtime, bool initialized) {
  std::lock_guard<std::mutex> lock(g_runtime_mutex);
  g_runtime.store(initialized ? runtime : nullptr, std::memory_order_release);
}

void CEFBridgeTestBrowserBridgeMessageHandler(MiumCEFResultCode code, const char* message, void* context) {
  browserBridgeMessageHandler(code, message, context);
}

void CEFBridgeTestBrowserBridgeMessageHandlerForBrowser(
  CEFBridgeBrowserRef browserRef,
  const char* channel,
  MiumCEFResultCode code,
  const char* message
) {
  std::shared_ptr<BridgeMessageRegistration> registration;
  {
    std::lock_guard<std::mutex> lock(g_bridge_message_handler_mutex);
    const auto browserIt = g_bridge_message_handlers.find(browserRef);
    if (browserIt != g_bridge_message_handlers.end() && channel != nullptr) {
      const auto channelIt = browserIt->second.find(channel);
      if (channelIt != browserIt->second.end()) {
        registration = channelIt->second;
      }
    }
  }
  if (registration == nullptr) {
    registration = std::make_shared<BridgeMessageRegistration>();
    registration->browserRef = browserRef;
    registration->channel = channel == nullptr ? std::string() : std::string(channel);
  }
  browserBridgeMessageHandler(code, message, registration.get());
}

void CEFBridgeTestSetBrowserBridgeMessageHandler(
  CEFBridgeBrowserRef browserRef,
  const char* channel,
  CEFBridgeMessageCallback callback,
  void* userData
) {
  setBrowserBridgeMessageHandler(browserRef, channel, callback, userData);
}

void CEFBridgeTestBrowserPermissionRequestHandler(
  void* context,
  const MiumCEFPermissionRequest* request
) {
  browserPermissionRequestHandler(context, request);
}

void CEFBridgeTestBrowserPermissionRequestHandlerForBrowser(
  CEFBridgeBrowserRef browserRef,
  const MiumCEFPermissionRequest* request
) {
  std::shared_ptr<BridgePermissionRequestRegistration> registration;
  {
    std::lock_guard<std::mutex> lock(g_bridge_permission_handler_mutex);
    const auto registrationIt = g_bridge_permission_request_handlers.find(browserRef);
    if (registrationIt != g_bridge_permission_request_handlers.end()) {
      registration = registrationIt->second;
    }
  }
  if (registration == nullptr) {
    registration = std::make_shared<BridgePermissionRequestRegistration>();
    registration->browserRef = browserRef;
  }
  browserPermissionRequestHandler(registration.get(), request);
}

void CEFBridgeTestInstallRawPermissionRequestHandlerState(
  CEFBridgeBrowserRef browserRef,
  CEFBridgePermissionRequestCallback callback,
  void* userData
) {
  if (browserRef == nullptr) {
    return;
  }

  std::lock_guard<std::mutex> lock(g_bridge_permission_handler_mutex);
  auto registration = std::make_shared<BridgePermissionRequestRegistration>();
  registration->browserRef = browserRef;
  registration->callback = callback;
  registration->userData = userData;
  g_bridge_permission_request_handlers[browserRef] = std::move(registration);
}

void CEFBridgeTestBrowserPermissionSessionDismissedHandler(
  void* context,
  MiumCEFPermissionSessionID sessionID,
  uint32_t reason
) {
  browserPermissionSessionDismissedHandler(context, sessionID, reason);
}

void CEFBridgeTestBrowserPermissionSessionDismissedHandlerForBrowser(
  CEFBridgeBrowserRef browserRef,
  MiumCEFPermissionSessionID sessionID,
  uint32_t reason
) {
  std::shared_ptr<BridgePermissionSessionDismissedRegistration> registration;
  {
    std::lock_guard<std::mutex> lock(g_bridge_permission_handler_mutex);
    const auto registrationIt = g_bridge_permission_dismissed_handlers.find(browserRef);
    if (registrationIt != g_bridge_permission_dismissed_handlers.end()) {
      registration = registrationIt->second;
    }
  }
  if (registration == nullptr) {
    registration = std::make_shared<BridgePermissionSessionDismissedRegistration>();
    registration->browserRef = browserRef;
  }
  browserPermissionSessionDismissedHandler(registration.get(), sessionID, reason);
}

void CEFBridgeTestInstallRawPermissionDismissedHandlerState(
  CEFBridgeBrowserRef browserRef,
  CEFBridgePermissionSessionDismissedCallback callback,
  void* userData
) {
  if (browserRef == nullptr) {
    return;
  }

  std::lock_guard<std::mutex> lock(g_bridge_permission_handler_mutex);
  auto registration = std::make_shared<BridgePermissionSessionDismissedRegistration>();
  registration->browserRef = browserRef;
  registration->callback = callback;
  registration->userData = userData;
  g_bridge_permission_dismissed_handlers[browserRef] = std::move(registration);
}

void CEFBridgeTestInstallRawMessageHandlerState(
  CEFBridgeBrowserRef browserRef,
  const char* channel,
  CEFBridgeMessageCallback callback,
  void* userData
) {
  if (browserRef == nullptr || channel == nullptr) {
    return;
  }

  const std::string channelString(channel);
  std::lock_guard<std::mutex> lock(g_bridge_message_handler_mutex);
  auto registration = std::make_shared<BridgeMessageRegistration>();
  registration->browserRef = browserRef;
  registration->channel = channelString;
  registration->callback = callback;
  registration->userData = userData;
  g_bridge_message_handlers[browserRef][channelString] = std::move(registration);
}

void CEFBridgeTestForwardJavaScriptResult(
  MiumCEFResultCode code,
  const char* result,
  CEFBridgeJavaScriptResultCallback callback,
  void* userData,
  bool useNullContext
) {
  if (useNullContext) {
    ForwardJavaScriptResult(code, result, nullptr);
    return;
  }

  auto* context = new JavaScriptResultContext{callback, userData};
  ForwardJavaScriptResult(code, result, context);
}

void CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode mode) {
  g_test_failure_mode = mode;
}

#endif
