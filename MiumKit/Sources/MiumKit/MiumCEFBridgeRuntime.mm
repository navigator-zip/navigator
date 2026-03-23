#import <Foundation/Foundation.h>

#include <dlfcn.h>
#include <unordered_set>
#include <cstdarg>
#include <cstdio>
#include <memory>
#include <string>
#include <vector>

#include "CefThreadGate.h"
#include "CefRef.h"
#include "MiumCEFBridgeAuxiliaryState.h"
#include "MiumCEFBridgeBrowserRegistry.h"
#include "MiumCEFBridgeCallbackQueue.h"
#include "MiumCEFBridgeInternalAdapters.h"
#include "MiumCEFBridgeInternalPermissionAdapters.h"
#include "MiumCEFBridgeInternalRendererMessageAdapters.h"
#include "MiumCEFBridgeInternalBrowserPayloadSupport.h"
#include "MiumCEFBridgeInternalRendererCameraSupport.h"
#include "MiumCEFBridgeInternalRuntimeBootstrapSupport.h"
#include "MiumCEFBridgeInternalRuntimeExecutionSupport.h"
#include "MiumCEFBridgeShutdown.h"
#include "MiumCEFBridgePermissions.h"
#include "MiumCEFBridgeRuntimeAppState.h"
#include "MiumCEFBridgeRuntime.h"
#include "MiumCEFBridgeThreading.h"
#include "Tracing.h"

template <typename Fn>
static void runOnRuntimeCefMainThread(Fn fn) {
  auto task = std::make_shared<Fn>(std::move(fn));
  if (miumCefIsOnMainThread()) {
    (*task)();
    return;
  }
  miumCefDispatchSyncOnMainThread([task] {
    (*task)();
  });
}

static bool shouldEmitRuntimeDiagnostics() {
#if defined(MIUM_CEF_BRIDGE_TESTING)
  return miumCefTracingEnabled();
#else
  return true;
#endif
}

static void runtimeTrace(const char* format, ...) {
  if (!miumCefTracingEnabled()) {
    return;
  }
  va_list args;
  va_start(args, format);
  miumCefTraceV("runtime", format, args);
  va_end(args);
}

static void runtimeDiagnostic(const char* format, ...) {
  if (!shouldEmitRuntimeDiagnostics()) {
    return;
  }
  va_list args;
  va_start(args, format);
  vfprintf(stderr, format, args);
  va_end(args);
}

static std::string runtimeNormalizePath(const char* path) {
  if (path == nullptr) {
    return {};
  }

  NSString* rawPath = [NSString stringWithUTF8String:path];
  if (rawPath == nil) {
    return {};
  }

  NSString* normalized = [rawPath stringByStandardizingPath];
  if (normalized == nil) {
    return {};
  }
  const char* bytes = normalized.fileSystemRepresentation;
  return bytes == nullptr ? std::string() : std::string(bytes);
}

static std::string runtimeMakePathFromRootAndRelative(
  const std::string& rootPath,
  const std::string& relativePath
) {
  if (rootPath.empty() || relativePath.empty()) {
    return {};
  }

  NSString* root = [NSString stringWithUTF8String:rootPath.c_str()];
  NSString* relative = [NSString stringWithUTF8String:relativePath.c_str()];
  if (root == nil || relative == nil) {
    return {};
  }

  NSString* candidate = [[root stringByAppendingPathComponent:relative] stringByStandardizingPath];
  const char* bytes = candidate.fileSystemRepresentation;
  return bytes == nullptr ? std::string() : std::string(bytes);
}

static std::string normalizedCEFLocaleIdentifier(NSString* identifier) {
  if (identifier == nil) {
    return {};
  }

  NSString* trimmed = [identifier stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (trimmed.length == 0) {
    return {};
  }

  NSString* normalized = [trimmed stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
  const char* bytes = normalized.UTF8String;
  return bytes == nullptr ? std::string() : std::string(bytes);
}

static std::string preferredCEFLocaleIdentifier() {
  for (NSString* identifier in NSLocale.preferredLanguages) {
    const std::string normalized = normalizedCEFLocaleIdentifier(identifier);
    if (!normalized.empty()) {
      return normalized;
    }
  }
  return "en-US";
}

static std::string preferredCEFAcceptLanguageList() {
  NSMutableOrderedSet<NSString*>* orderedIdentifiers = [NSMutableOrderedSet orderedSet];
  for (NSString* identifier in NSLocale.preferredLanguages) {
    const std::string normalized = normalizedCEFLocaleIdentifier(identifier);
    if (normalized.empty()) {
      continue;
    }

    NSString* normalizedIdentifier = [NSString stringWithUTF8String:normalized.c_str()];
    if (normalizedIdentifier == nil || normalizedIdentifier.length == 0) {
      continue;
    }

    [orderedIdentifiers addObject:normalizedIdentifier];
    NSRange separatorRange = [normalizedIdentifier rangeOfString:@"-"];
    if (separatorRange.location != NSNotFound && separatorRange.location > 0) {
      NSString* baseLanguage = [normalizedIdentifier substringToIndex:separatorRange.location];
      if (baseLanguage.length > 0) {
        [orderedIdentifiers addObject:baseLanguage];
      }
    }
  }

  if (orderedIdentifiers.count == 0) {
    return "en-US,en";
  }

  NSString* joined = [orderedIdentifiers.array componentsJoinedByString:@","];
  const char* bytes = joined.UTF8String;
  return bytes == nullptr ? std::string() : std::string(bytes);
}

static bool hasLoadedFrameworkArtifactsLocked() {
  return gFrameworkLoaded && gCefApi.frameworkHandle != nullptr && gCefApi.loaded;
}

static void CEF_CALLBACK miumCEFAppAddRef(cef_base_ref_counted_t* base) {
  auto* state = miumCEFStateFromRefCountedBase<MiumExternalBrowserProcessAppState>(base);
  if (state != nullptr) {
    state->refCount.fetch_add(1, std::memory_order_relaxed);
  }
}

static int CEF_CALLBACK miumCEFAppRelease(cef_base_ref_counted_t* base) {
  auto* state = miumCEFStateFromRefCountedBase<MiumExternalBrowserProcessAppState>(base);
  if (state == nullptr) {
    return 1;
  }
  const int previousCount = state->refCount.fetch_sub(1, std::memory_order_acq_rel);
  if (previousCount == 1) {
    if (state->browserProcessHandler != nullptr && state->browserProcessHandler->handler.base.release != nullptr) {
      releaseCefBase(&state->browserProcessHandler->handler.base);
    }
    if (state->renderProcessHandler != nullptr && state->renderProcessHandler->handler.base.release != nullptr) {
      releaseCefBase(&state->renderProcessHandler->handler.base);
    }
    delete state;
    return 1;
  }
  return 0;
}

static int CEF_CALLBACK miumCEFAppHasOneRef(cef_base_ref_counted_t* base) {
  auto* state = miumCEFStateFromRefCountedBase<MiumExternalBrowserProcessAppState>(base);
  return state != nullptr && state->refCount.load(std::memory_order_acquire) == 1;
}

static int CEF_CALLBACK miumCEFAppHasAtLeastOneRef(cef_base_ref_counted_t* base) {
  auto* state = miumCEFStateFromRefCountedBase<MiumExternalBrowserProcessAppState>(base);
  return state != nullptr && state->refCount.load(std::memory_order_acquire) >= 1;
}

static void CEF_CALLBACK miumCEFBrowserProcessHandlerAddRef(cef_base_ref_counted_t* base) {
  auto* state = miumCEFStateFromRefCountedBase<MiumExternalBrowserProcessHandlerState>(base);
  if (state != nullptr) {
    state->refCount.fetch_add(1, std::memory_order_relaxed);
  }
}

static int CEF_CALLBACK miumCEFBrowserProcessHandlerRelease(cef_base_ref_counted_t* base) {
  auto* state = miumCEFStateFromRefCountedBase<MiumExternalBrowserProcessHandlerState>(base);
  if (state == nullptr) {
    return 1;
  }
  const int previousCount = state->refCount.fetch_sub(1, std::memory_order_acq_rel);
  if (previousCount == 1) {
    delete state;
    return 1;
  }
  return 0;
}

static int CEF_CALLBACK miumCEFBrowserProcessHandlerHasOneRef(cef_base_ref_counted_t* base) {
  auto* state = miumCEFStateFromRefCountedBase<MiumExternalBrowserProcessHandlerState>(base);
  return state != nullptr && state->refCount.load(std::memory_order_acquire) == 1;
}

static int CEF_CALLBACK miumCEFBrowserProcessHandlerHasAtLeastOneRef(cef_base_ref_counted_t* base) {
  auto* state = miumCEFStateFromRefCountedBase<MiumExternalBrowserProcessHandlerState>(base);
  return state != nullptr && state->refCount.load(std::memory_order_acquire) >= 1;
}

static void CEF_CALLBACK miumCEFRenderProcessHandlerAddRef(cef_base_ref_counted_t* base) {
  auto* state = miumCEFStateFromRefCountedBase<MiumExternalRenderProcessHandlerState>(base);
  if (state != nullptr) {
    state->refCount.fetch_add(1, std::memory_order_relaxed);
  }
}

static int CEF_CALLBACK miumCEFRenderProcessHandlerRelease(cef_base_ref_counted_t* base) {
  auto* state = miumCEFStateFromRefCountedBase<MiumExternalRenderProcessHandlerState>(base);
  if (state == nullptr) {
    return 1;
  }
  const int previousCount = state->refCount.fetch_sub(1, std::memory_order_acq_rel);
  if (previousCount == 1) {
    delete state;
    return 1;
  }
  return 0;
}

static int CEF_CALLBACK miumCEFRenderProcessHandlerHasOneRef(cef_base_ref_counted_t* base) {
  auto* state = miumCEFStateFromRefCountedBase<MiumExternalRenderProcessHandlerState>(base);
  return state != nullptr && state->refCount.load(std::memory_order_acquire) == 1;
}

static int CEF_CALLBACK miumCEFRenderProcessHandlerHasAtLeastOneRef(cef_base_ref_counted_t* base) {
  auto* state = miumCEFStateFromRefCountedBase<MiumExternalRenderProcessHandlerState>(base);
  return state != nullptr && state->refCount.load(std::memory_order_acquire) >= 1;
}

static cef_browser_process_handler_t* CEF_CALLBACK miumCEFAppGetBrowserProcessHandler(cef_app_t* self) {
  auto* state = reinterpret_cast<MiumExternalBrowserProcessAppState*>(self);
  if (state == nullptr || state->browserProcessHandler == nullptr) {
    return nullptr;
  }
  return reinterpret_cast<cef_browser_process_handler_t*>(
    retainCefBase(&state->browserProcessHandler->handler.base)
  );
}

static cef_render_process_handler_t* CEF_CALLBACK miumCEFAppGetRenderProcessHandler(cef_app_t* self) {
  auto* state = reinterpret_cast<MiumExternalBrowserProcessAppState*>(self);
  if (state == nullptr || state->renderProcessHandler == nullptr) {
    return nullptr;
  }
  return reinterpret_cast<cef_render_process_handler_t*>(
    retainCefBase(&state->renderProcessHandler->handler.base)
  );
}

static void CEF_CALLBACK miumCEFBrowserProcessHandlerOnScheduleMessagePumpWork(
  cef_browser_process_handler_t*,
  int64_t delay_ms
) {
  miumCEFNativeScheduleExternalMessagePumpWork(delay_ms);
}

static void CEF_CALLBACK miumCEFRenderProcessHandlerOnContextCreated(
  cef_render_process_handler_t*,
  cef_browser_t*,
  cef_frame_t* frame,
  cef_v8_context_t* context
) {
  (void)miumCEFNativeInstallRendererCameraRoutingEventBridge(frame, context);
}

static int CEF_CALLBACK miumCEFRenderProcessHandlerOnProcessMessageReceived(
  cef_render_process_handler_t*,
  cef_browser_t*,
  cef_frame_t* frame,
  cef_process_id_t source_process,
  cef_process_message_t* message
) {
  if (source_process != PID_BROWSER) {
    return 0;
  }

  const std::string channel = miumCEFNativeProcessMessageName(message);
  if (channel == MiumCEFCameraFrameDeliveryChannel || channel == MiumCEFCameraFrameClearChannel) {
    const std::string payload = miumCEFNativeProcessMessageArgumentString(message, 0);
    return miumCEFNativeHandleRendererManagedCameraFrameMessage(
      frame,
      channel.c_str(),
      payload.c_str()
    ) ? 1 : 0;
  }
  if (channel == MiumCEFCameraRoutingConfigUpdateChannel) {
    const std::string payload = miumCEFNativeProcessMessageArgumentString(message, 0);
    return miumCEFNativeHandleRendererManagedCameraConfigMessage(
      frame,
      channel.c_str(),
      payload.c_str()
    ) ? 1 : 0;
  }
  const std::string requestID = miumCEFNativeProcessMessageArgumentString(message, 0);
  const std::string script = miumCEFNativeProcessMessageArgumentString(message, 1);
  return miumCEFNativeHandleRendererExecuteJavaScriptRequestMessage(
    frame,
    channel.c_str(),
    requestID.c_str(),
    script.c_str()
  ) ? 1 : 0;
}

static cef_app_t* createBrowserProcessApp() {
  auto* appState = new MiumExternalBrowserProcessAppState{};
  appState->app.base.size = sizeof(cef_app_t);
  appState->app.base.add_ref = miumCEFAppAddRef;
  appState->app.base.release = miumCEFAppRelease;
  appState->app.base.has_one_ref = miumCEFAppHasOneRef;
  appState->app.base.has_at_least_one_ref = miumCEFAppHasAtLeastOneRef;
  appState->app.get_browser_process_handler = miumCEFAppGetBrowserProcessHandler;
  appState->app.get_render_process_handler = miumCEFAppGetRenderProcessHandler;

  auto* handlerState = new MiumExternalBrowserProcessHandlerState{};
  handlerState->handler.base.size = sizeof(cef_browser_process_handler_t);
  handlerState->handler.base.add_ref = miumCEFBrowserProcessHandlerAddRef;
  handlerState->handler.base.release = miumCEFBrowserProcessHandlerRelease;
  handlerState->handler.base.has_one_ref = miumCEFBrowserProcessHandlerHasOneRef;
  handlerState->handler.base.has_at_least_one_ref = miumCEFBrowserProcessHandlerHasAtLeastOneRef;
  handlerState->handler.on_schedule_message_pump_work = miumCEFBrowserProcessHandlerOnScheduleMessagePumpWork;

  appState->browserProcessHandler = handlerState;
  return &appState->app;
}

static cef_app_t* createSubprocessApp(void) {
  auto* appState = new MiumExternalBrowserProcessAppState{};
  appState->app.base.size = sizeof(cef_app_t);
  appState->app.base.add_ref = miumCEFAppAddRef;
  appState->app.base.release = miumCEFAppRelease;
  appState->app.base.has_one_ref = miumCEFAppHasOneRef;
  appState->app.base.has_at_least_one_ref = miumCEFAppHasAtLeastOneRef;
  appState->app.get_browser_process_handler = miumCEFAppGetBrowserProcessHandler;
  appState->app.get_render_process_handler = miumCEFAppGetRenderProcessHandler;

  auto* handlerState = new MiumExternalRenderProcessHandlerState{};
  handlerState->handler.base.size = sizeof(cef_render_process_handler_t);
  handlerState->handler.base.add_ref = miumCEFRenderProcessHandlerAddRef;
  handlerState->handler.base.release = miumCEFRenderProcessHandlerRelease;
  handlerState->handler.base.has_one_ref = miumCEFRenderProcessHandlerHasOneRef;
  handlerState->handler.base.has_at_least_one_ref = miumCEFRenderProcessHandlerHasAtLeastOneRef;
  handlerState->handler.on_context_created = miumCEFRenderProcessHandlerOnContextCreated;
  handlerState->handler.on_process_message_received = miumCEFRenderProcessHandlerOnProcessMessageReceived;

  appState->renderProcessHandler = handlerState;
  return &appState->app;
}

bool loadRequiredCefSymbols(void* frameworkHandle, CefApi* apiOut) {
  if (frameworkHandle == nullptr || apiOut == nullptr) {
    return false;
  }

  CefApi loadedApi;
  loadedApi.frameworkHandle = frameworkHandle;
  void* symbol = nullptr;
  if (!miumCEFNativeLoadSymbol(frameworkHandle, "cef_api_hash", &symbol)) {
    runtimeDiagnostic("CEF ABI check failed: cef_api_hash is required\n");
    return false;
  }
  loadedApi.apiHash = reinterpret_cast<CefApiHashFn>(symbol);
  if (!miumCEFNativeVerifyCefApiCompatibility(loadedApi.apiHash(CEF_API_VERSION, 0), CEF_API_HASH_PLATFORM)) {
    return false;
  }

  if (miumCEFNativeLoadSymbol(frameworkHandle, "cef_api_version", &symbol)) {
    loadedApi.apiVersion = reinterpret_cast<CefApiVersionFn>(symbol);
    const int runtimeVersion = loadedApi.apiVersion();
    runtimeTrace(
      "CEF runtime API version: %d (headers: %d)\n",
      runtimeVersion,
      static_cast<int>(CEF_API_VERSION)
    );
  } else {
    runtimeDiagnostic("CEF ABI warning: cef_api_version is unavailable\n");
  }

  // `cef_get_version` is intentionally not required here. We do not call it elsewhere and
  // `cef_version_info` has an exact vendored declaration we can validate/load safely.
  if (!miumCEFNativeLoadSymbol(frameworkHandle, "cef_version_info", &symbol)) {
    runtimeDiagnostic("CEF ABI check failed: cef_version_info is required\n");
    return false;
  }
  loadedApi.versionInfo = reinterpret_cast<CefVersionInfoFn>(symbol);
  runtimeDiagnostic("CEF runtime version info: major=%d\n", loadedApi.versionInfo(0));

  if (!miumCEFNativeLoadSymbol(frameworkHandle, "cef_string_utf8_to_utf16", &symbol)) {
    return false;
  }
  loadedApi.utf8ToUTF16 = reinterpret_cast<CefStringUTF8ToUTF16>(symbol);

  if (!miumCEFNativeLoadSymbol(frameworkHandle, "cef_string_utf16_clear", &symbol)) {
    runtimeDiagnostic("CEF ABI check failed: cef_string_utf16_clear is required\n");
    return false;
  }
  loadedApi.utf16Clear = reinterpret_cast<CefStringUTF16Clear>(symbol);

  if (!miumCEFNativeLoadSymbol(frameworkHandle, "cef_string_userfree_utf16_free", &symbol)) {
    runtimeDiagnostic("CEF ABI check failed: cef_string_userfree_utf16_free is required\n");
    return false;
  }
  loadedApi.userfreeFree = reinterpret_cast<CefStringUserFreeUTF16Free>(symbol);

  if (miumCEFNativeLoadSymbol(frameworkHandle, "cef_string_list_size", &symbol)) {
    loadedApi.stringListSize = reinterpret_cast<CefStringListSizeFn>(symbol);
  } else {
    runtimeDiagnostic("CEF ABI warning: cef_string_list_size is unavailable\n");
  }

  if (miumCEFNativeLoadSymbol(frameworkHandle, "cef_string_list_value", &symbol)) {
    loadedApi.stringListValue = reinterpret_cast<CefStringListValueFn>(symbol);
  } else {
    runtimeDiagnostic("CEF ABI warning: cef_string_list_value is unavailable\n");
  }

  if (miumCEFNativeLoadSymbol(frameworkHandle, "cef_execute_process", &symbol)) {
    loadedApi.executeProcess = reinterpret_cast<CefExecuteProcessFn>(symbol);
  } else {
    runtimeDiagnostic("CEF ABI warning: cef_execute_process is unavailable\n");
  }

  if (!miumCEFNativeLoadSymbol(frameworkHandle, "cef_initialize", &symbol)) {
    return false;
  }
  loadedApi.initialize = reinterpret_cast<CefInitializeFn>(symbol);

  if (!miumCEFNativeLoadSymbol(frameworkHandle, "cef_shutdown", &symbol)) {
    return false;
  }
  loadedApi.shutdown = reinterpret_cast<CefShutdownFn>(symbol);

  if (!miumCEFNativeLoadSymbol(frameworkHandle, "cef_do_message_loop_work", &symbol)) {
    runtimeDiagnostic("CEF ABI check failed: cef_do_message_loop_work is required\n");
    return false;
  }
  loadedApi.doMessageLoopWork = reinterpret_cast<CefDoMessageLoopWorkFn>(symbol);

  if (!miumCEFNativeLoadSymbol(frameworkHandle, "cef_browser_host_create_browser_sync", &symbol)) {
    return false;
  }
  loadedApi.createBrowserSync = reinterpret_cast<CefBrowserCreateBrowserSyncFn>(symbol);

  if (!miumCEFNativeLoadSymbol(frameworkHandle, "cef_process_message_create", &symbol)) {
    runtimeDiagnostic("CEF symbol not loaded: cef_process_message_create\n");
  } else {
    loadedApi.createProcessMessage = reinterpret_cast<CefProcessMessageCreateFn>(symbol);
  }

  if (miumCEFNativeLoadSymbol(frameworkHandle, "cef_v8_value_create_function", &symbol)) {
    loadedApi.createV8Function = reinterpret_cast<CefV8ValueCreateFunctionFn>(symbol);
  } else {
    runtimeDiagnostic("CEF ABI warning: cef_v8_value_create_function is unavailable\n");
  }

  if (miumCEFNativeLoadSymbol(frameworkHandle, "cef_v8_context_get_current_context", &symbol)) {
    loadedApi.currentV8Context = reinterpret_cast<CefV8ContextGetCurrentContextFn>(symbol);
  } else {
    runtimeDiagnostic("CEF ABI warning: cef_v8_context_get_current_context is unavailable\n");
  }

  loadedApi.loaded = true;
  *apiOut = loadedApi;
  return true;
}

static bool tryLoadFrameworkAtPath(
  const std::string& candidate,
  bool isFallback,
  CefApi* loadedApiOut
) {
  if (loadedApiOut == nullptr) {
    return false;
  }

  void* handle = dlopen(candidate.c_str(), RTLD_NOW | RTLD_LOCAL);
  if (handle == nullptr) {
    runtimeDiagnostic("cefopen failed: %s -> %s\n", candidate.c_str(), dlerror());
    return false;
  }
  runtimeTrace(isFallback ? "cefopen succeeded (fallback): %s\n" : "cefopen succeeded: %s\n", candidate.c_str());

  CefApi loadedApi;
  if (!loadRequiredCefSymbols(handle, &loadedApi)) {
    runtimeDiagnostic(
      isFallback ? "CEF symbol check failed for fallback: %s\n" : "CEF symbol check failed for candidate: %s\n",
      candidate.c_str()
    );
    dlclose(handle);
    return false;
  }

  *loadedApiOut = loadedApi;
  return true;
}

static bool commitLoadedFrameworkIfAbsent(const CefApi& loadedApi) {
  CefStateLockGuard lock;
  if (hasLoadedFrameworkArtifactsLocked()) {
    return false;
  }
  gCefApi = loadedApi;
  gFrameworkLoaded = true;
  return true;
}

static bool tryOpenFrameworkCandidateSet(
  const std::vector<std::string>& candidatePaths,
  bool isFallback
) {
  for (const auto& candidate : candidatePaths) {
    CefApi loadedApi;
    if (!tryLoadFrameworkAtPath(candidate, isFallback, &loadedApi)) {
      continue;
    }
    if (!commitLoadedFrameworkIfAbsent(loadedApi)) {
      miumCEFNativeCloseUncommittedFrameworkHandle(loadedApi.frameworkHandle);
    }
    return true;
  }
  return false;
}

bool openFrameworkIfNeeded(const std::vector<std::string>& candidates) {
  {
    CefStateLockGuard lock;
    if (hasLoadedFrameworkArtifactsLocked()) {
      return true;
    }
  }

  std::lock_guard<std::mutex> loaderLock(gFrameworkLoadLock);
  {
    CefStateLockGuard lock;
    if (hasLoadedFrameworkArtifactsLocked()) {
      return true;
    }
  }

  if (tryOpenFrameworkCandidateSet(candidates, /*isFallback=*/false)) {
    return true;
  }

  const std::vector<std::string> fallbackCandidates = miumCEFNativeFrameworkFallbackCandidates();
  if (tryOpenFrameworkCandidateSet(fallbackCandidates, /*isFallback=*/true)) {
    return true;
  }

  CefStateLockGuard lock;
  if (hasLoadedFrameworkArtifactsLocked()) {
    return true;
  }
  gFrameworkLoaded = false;
  gCefApi.reset();
  return false;
}

bool ensureCefInitialized(
  const std::string& runtimeRootPath,
  const std::string& runtimeMetadataPath,
  std::string* failureReason
) {
  const RuntimeLayoutConfig layoutConfig =
    miumCEFNativeResolveRuntimeLayoutConfig(runtimeRootPath, runtimeMetadataPath);
  const std::string helperExecutable =
    miumCEFNativeResolveHelperSubprocessPath(runtimeRootPath, runtimeMetadataPath);
  const std::string userDataDirectory = miumCEFNativeResolveCEFUserDataDirectory();

  std::vector<std::string> argValues;
  const bool autoplayByPolicy = !miumCEFNativeHasEnvironmentValue("MIUM_CEF_REQUIRE_USER_GESTURE_AUTOPLAY");
  NSString* executablePath = miumCEFNativeMainBundleExecutablePath();
  if (executablePath != nil) {
    argValues.emplace_back(executablePath.UTF8String == nullptr ? "Navigator" : executablePath.UTF8String);
  } else {
    argValues.emplace_back("Navigator");
  }
  if (autoplayByPolicy) {
    argValues.emplace_back("--autoplay-policy=no-user-gesture-required");
  }
  argValues.emplace_back("--use-mock-keychain");
  if (miumCEFNativeShouldEnableMediaStreamOverride()) {
    argValues.emplace_back("--enable-media-stream");
  }

  const bool disableSandbox = miumCEFNativeShouldDisableCEFChildProcessSandbox();

  std::vector<std::vector<char>> argvStorage;
  std::vector<char*> argv;
  argvStorage.reserve(argValues.size());
  argv.reserve(argValues.size());
  for (const auto& value : argValues) {
    std::vector<char> valueBuffer(value.begin(), value.end());
    valueBuffer.push_back('\0');
    argvStorage.push_back(std::move(valueBuffer));
    argv.push_back(argvStorage.back().data());
  }

  cef_main_args_t args{};
  args.argc = static_cast<int>(argv.size());
  args.argv = argv.empty() ? nullptr : argv.data();

  runtimeTrace(
    "ensureCefInitialized: noSandbox=%s argc=%d\n",
    disableSandbox ? "true" : "false",
    static_cast<int>(argv.size())
  );

  for (size_t index = 0; index < argv.size(); ++index) {
    runtimeTrace("ensureCefInitialized argv[%zu]=%s\n", index, argv[index]);
  }

  if (!userDataDirectory.empty()) {
    runtimeTrace("ensureCefInitialized userDataDir=%s\n", userDataDirectory.c_str());
  }

  CefExecuteProcessFn executeProcess = nullptr;
  CefInitializeFn initialize = nullptr;
  {
    CefStateLockGuard lock;
    executeProcess = gCefApi.executeProcess;
    initialize = gCefApi.initialize;
  }
  if (initialize == nullptr) {
    if (failureReason != nullptr) {
      *failureReason = "cef_initialize API unavailable";
    }
    return false;
  }

  int processExitCode = -1;
  if (executeProcess != nullptr) {
    runtimeTrace("before cef_execute_process with null app wrapper\n");
    runOnRuntimeCefMainThread([&] {
      runtimeTrace("cef_execute_process lane=%s\n", miumCEFThreadLaneLabel());
      processExitCode = executeProcess(&args, nullptr, nullptr);
    });
  }
  if (processExitCode >= 0) {
    runtimeDiagnostic(
      "[MiumCEFBridge] CefExecuteProcess requested process termination with code %d\n",
      processExitCode
    );
    if (miumCEFNativeInterceptProcessExitCodeIfTesting(processExitCode)) {
      if (failureReason != nullptr) {
        *failureReason = "CEF subprocess execution requested process termination";
      }
      return false;
    }
    miumCEFNativeTerminateProcessAfterCEFExecuteProcess(processExitCode);
    if (failureReason != nullptr) {
      *failureReason = "CEF subprocess execution requested process termination";
    }
    return false;
  }

  const bool useExternalMessagePump = miumCEFNativeBridgeExternalMessagePumpEnabled();
  cef_settings_t settings{};
  cef_string_t browserSubprocessPath{};
  cef_string_t resourcesDirPath{};
  cef_string_t localesDirPath{};
  cef_string_t cachePath{};
  cef_string_t rootCachePath{};
  cef_string_t locale{};
  cef_string_t acceptLanguageList{};
  settings.size = sizeof(settings);
  settings.multi_threaded_message_loop = 0;
  settings.external_message_pump = useExternalMessagePump ? 1 : 0;
  settings.no_sandbox = disableSandbox ? 1 : 0;
  settings.persist_session_cookies = 1;
  settings.log_severity = miumCEFNativeBridgeLoggingEnabled() ? LOGSEVERITY_DEFAULT : LOGSEVERITY_DISABLE;
  auto clearSettingsStrings = [&] {
    miumCEFNativeClearUTF16String(browserSubprocessPath);
    miumCEFNativeClearUTF16String(resourcesDirPath);
    miumCEFNativeClearUTF16String(localesDirPath);
    miumCEFNativeClearUTF16String(cachePath);
    miumCEFNativeClearUTF16String(rootCachePath);
    miumCEFNativeClearUTF16String(locale);
    miumCEFNativeClearUTF16String(acceptLanguageList);
  };
  std::string conversionError;
  if (!miumCEFNativeSetCefSettingPath(browserSubprocessPath, helperExecutable, &conversionError)) {
    runtimeDiagnostic(
      "[MiumCEFBridge] Failed to set cef_settings.browser_subprocess_path: %s\n",
      conversionError.empty() ? "unknown error" : conversionError.c_str()
    );
    if (failureReason != nullptr) {
      *failureReason = conversionError;
    }
    clearSettingsStrings();
    return false;
  }
  if (!miumCEFNativeSetCefSettingPath(resourcesDirPath, layoutConfig.resourcesDir, &conversionError)) {
    runtimeDiagnostic(
      "[MiumCEFBridge] Failed to set cef_settings.resources_dir_path: %s\n",
      conversionError.empty() ? "unknown error" : conversionError.c_str()
    );
    if (failureReason != nullptr) {
      *failureReason = conversionError;
    }
    clearSettingsStrings();
    return false;
  }
  if (!miumCEFNativeSetCefSettingPath(localesDirPath, layoutConfig.localesDir, &conversionError)) {
    runtimeDiagnostic(
      "[MiumCEFBridge] Failed to set cef_settings.locales_dir_path: %s\n",
      conversionError.empty() ? "unknown error" : conversionError.c_str()
    );
    if (failureReason != nullptr) {
      *failureReason = conversionError;
    }
    clearSettingsStrings();
    return false;
  }
  if (!miumCEFNativeSetCefSettingPath(cachePath, userDataDirectory, &conversionError)) {
    runtimeDiagnostic(
      "[MiumCEFBridge] Failed to set cef_settings.cache_path: %s\n",
      conversionError.empty() ? "unknown error" : conversionError.c_str()
    );
    if (failureReason != nullptr) {
      *failureReason = conversionError;
    }
    clearSettingsStrings();
    return false;
  }
  if (!miumCEFNativeSetCefSettingPath(rootCachePath, userDataDirectory, &conversionError)) {
    runtimeDiagnostic(
      "[MiumCEFBridge] Failed to set cef_settings.root_cache_path: %s\n",
      conversionError.empty() ? "unknown error" : conversionError.c_str()
    );
    if (failureReason != nullptr) {
      *failureReason = conversionError;
    }
    clearSettingsStrings();
    return false;
  }
  const std::string browserLocale = preferredCEFLocaleIdentifier();
  if (!miumCEFNativeUTF16FromUTF8(browserLocale.c_str(), locale, &conversionError)) {
    runtimeDiagnostic(
      "[MiumCEFBridge] Failed to set cef_settings.locale: %s\n",
      conversionError.empty() ? "unknown error" : conversionError.c_str()
    );
    if (failureReason != nullptr) {
      *failureReason = conversionError;
    }
    clearSettingsStrings();
    return false;
  }
  const std::string browserAcceptLanguageList = preferredCEFAcceptLanguageList();
  if (!miumCEFNativeUTF16FromUTF8(browserAcceptLanguageList.c_str(), acceptLanguageList, &conversionError)) {
    runtimeDiagnostic(
      "[MiumCEFBridge] Failed to set cef_settings.accept_language_list: %s\n",
      conversionError.empty() ? "unknown error" : conversionError.c_str()
    );
    if (failureReason != nullptr) {
      *failureReason = conversionError;
    }
    clearSettingsStrings();
    return false;
  }
  settings.browser_subprocess_path = browserSubprocessPath;
  settings.resources_dir_path = resourcesDirPath;
  settings.locales_dir_path = localesDirPath;
  settings.cache_path = cachePath;
  settings.root_cache_path = rootCachePath;
  settings.locale = locale;
  settings.accept_language_list = acceptLanguageList;

  runtimeTrace(
    "ensureCefInitialized settings: size=%zu log_severity=%d\n",
    static_cast<size_t>(settings.size),
    static_cast<int>(settings.log_severity)
  );

  bool initialized = false;
  cef_app_t* app = useExternalMessagePump ? createBrowserProcessApp() : nullptr;
  runOnRuntimeCefMainThread([&] {
    runtimeTrace(
      "cef_initialize lane=%s external_message_pump=%d\n",
      miumCEFThreadLaneLabel(),
      settings.external_message_pump
    );
    if (initialize != nullptr) {
      initialized = initialize(&args, &settings, app, nullptr) != 0;
    }
  });

  clearSettingsStrings();

  if (!initialized) {
    releaseOwnedCefValue(app);
    if (failureReason != nullptr) {
      *failureReason = "cef_initialize() returned false";
    }
    return false;
  }

  {
    CefStateLockGuard lock;
    gExternalMessagePumpEnabled = useExternalMessagePump;
    gLastPerformedMessagePumpSequence = 0;
    gLastPerformedMessagePumpTime = 0.0;
    gBrowserProcessApp = app;
  }

  if (useExternalMessagePump) {
    miumCEFNativeScheduleExternalMessagePumpWork(0);
  }

  return true;
}

namespace {

template <typename Map>
uint64_t nextIdFromMap(uint64_t& nextId, const Map& map) {
  while (nextId == 0 || map.find(nextId) != map.end()) {
    ++nextId;
  }
  return nextId++;
}

void logRuntimeFailure(const std::string& message) {
  runtimeDiagnostic("%s\n", message.c_str());
}

}  // namespace

bool miumCEFRuntimeIsLoaded(void) {
  CefStateLockGuard lock;
  return gFrameworkLoaded;
}

int miumCEFRuntimeHasPendingBrowserClose(void) {
  CefStateLockGuard lock;
  return miumCEFPendingNativeBrowserCloseCountLocked() > 0 ? 1 : 0;
}

int miumCEFRuntimeMaybeRunSubprocess(int argc, const char* const* argv) {
  if (argc <= 0 || argv == nullptr) {
    return -1;
  }

  CefExecuteProcessFn executeProcess = nullptr;
  {
    CefStateLockGuard lock;
    executeProcess = gCefApi.executeProcess;
  }

  if (executeProcess == nullptr) {
#if defined(MIUM_CEF_BRIDGE_TESTING)
    const bool hasTestCandidates = !gTestSubprocessFrameworkCandidates.empty();
    if (hasTestCandidates) {
      if (!openFrameworkIfNeeded(gTestSubprocessFrameworkCandidates)) {
        return -1;
      }
    } else {
#endif
      NSString* bundlePath = [NSBundle mainBundle].bundlePath;
      if (bundlePath == nil) {
        return -1;
      }

      const std::string runtimeRoot = runtimeNormalizePath(bundlePath.fileSystemRepresentation);
      const std::string runtimeMetadataPath =
        runtimeRoot.empty() ? std::string() : runtimeMakePathFromRootAndRelative(runtimeRoot, "Contents/Resources");
      const std::vector<std::string> candidates =
        miumCEFNativeCandidatePathsFor(runtimeRoot, runtimeMetadataPath);
      if (!openFrameworkIfNeeded(candidates)) {
        return -1;
      }
#if defined(MIUM_CEF_BRIDGE_TESTING)
    }
#endif
  }

  {
    CefStateLockGuard lock;
    executeProcess = gCefApi.executeProcess;
  }
  if (executeProcess == nullptr) {
    return -1;
  }

  cef_main_args_t args{};
  args.argc = argc;
  args.argv = const_cast<char**>(argv);
  cef_app_t* app = createSubprocessApp();
  runtimeTrace("subprocess before cef_execute_process with subprocess app wrapper\n");
  int processExitCode = -1;

  runOnRuntimeCefMainThread([&] {
    runtimeTrace("subprocess cef_execute_process lane=%s\n", miumCEFThreadLaneLabel());
    processExitCode = executeProcess(&args, app, nullptr);
  });
  if (app != nullptr) {
    releaseCefBase(&app->base);
  }
  return processExitCode;
}

MiumCEFResultCode miumCEFRuntimeInitialize(
  const char* runtimeRootPath,
  const char* runtimeMetadataPath,
  MiumCEFEventCallback eventCallback,
  void* eventContext,
  MiumCEFRuntimeHandle* outRuntimeHandle
) {
  if (outRuntimeHandle == nullptr) {
    logRuntimeFailure("Runtime out pointer is nil");
    runOnEventQueue(eventCallback, MiumCEFResultInvalidArgument, "Runtime out pointer is nil", eventContext);
    return MiumCEFResultInvalidArgument;
  }
  *outRuntimeHandle = nullptr;

  const std::string runtimeRoot = runtimeNormalizePath(runtimeRootPath);
  const std::string runtimeMetadata = runtimeNormalizePath(runtimeMetadataPath);
  RuntimeLayoutConfig layoutConfig = miumCEFNativeResolveRuntimeLayoutConfig(runtimeRoot, runtimeMetadata);
  const std::string fallbackLocalesDir = miumCEFNativeResolveChromiumLocalesPath(runtimeRoot);
  if (!layoutConfig.localesDir.empty() && !miumCEFNativePathExistsAsDirectory(layoutConfig.localesDir)) {
    if (!fallbackLocalesDir.empty() && miumCEFNativePathExistsAsDirectory(fallbackLocalesDir)) {
      layoutConfig.localesDir = fallbackLocalesDir;
    }
  }

  const std::string helperExecutable = miumCEFNativeResolveHelperSubprocessPath(runtimeRoot, runtimeMetadata);
  runtimeTrace(
    "init paths: runtimeRoot=%s runtimeMetadata=%s resources=%s locales=%s helpers=%s\n",
    runtimeRoot.empty() ? "<empty>" : runtimeRoot.c_str(),
    runtimeMetadata.empty() ? "<empty>" : runtimeMetadata.c_str(),
    layoutConfig.resourcesDir.empty() ? "<missing>" : layoutConfig.resourcesDir.c_str(),
    layoutConfig.localesDir.empty() ? "<missing>" : layoutConfig.localesDir.c_str(),
    helperExecutable.empty() ? "<missing>" : helperExecutable.c_str()
  );
  if (helperExecutable.empty()) {
    const std::string reason =
      "CEF helper executable unresolved; expected a Chromium/Navigator helper app in the runtime helper search paths";
    logRuntimeFailure(reason);
    runOnEventQueue(eventCallback, MiumCEFResultNotInitialized, reason.c_str(), eventContext);
    return MiumCEFResultNotInitialized;
  }
  if (!layoutConfig.resourcesDir.empty() && !miumCEFNativePathExistsAsDirectory(layoutConfig.resourcesDir)) {
    const std::string reason = "CEF resources directory missing: " + layoutConfig.resourcesDir;
    logRuntimeFailure(reason);
    runOnEventQueue(eventCallback, MiumCEFResultNotInitialized, reason.c_str(), eventContext);
    return MiumCEFResultNotInitialized;
  }
  if (!layoutConfig.localesDir.empty() && !miumCEFNativePathExistsAsDirectory(layoutConfig.localesDir)) {
    const std::string reason = "CEF locales directory missing: " + layoutConfig.localesDir;
    logRuntimeFailure(reason);
    runOnEventQueue(eventCallback, MiumCEFResultNotInitialized, reason.c_str(), eventContext);
    return MiumCEFResultNotInitialized;
  }

  const auto candidates = miumCEFNativeCandidatePathsFor(runtimeRoot, runtimeMetadata);
  bool shouldInitialize = false;
  bool didInitialize = false;
  std::string initializeFailureReason;

  {
    CefStateUniqueLock lock;
    while (gCEFInitializing || gCEFShutdownExecuting) {
      lock.wait(gStateCondition);
    }
    gLastCandidatePaths = candidates;
  }

  if (!openFrameworkIfNeeded(candidates)) {
    const std::string candidateFailure = miumCEFNativeDescribeFrameworkCandidateFailure(candidates);
    logRuntimeFailure(candidateFailure);
    runOnEventQueue(eventCallback, MiumCEFResultNotInitialized, candidateFailure.c_str(), eventContext);
    return MiumCEFResultNotInitialized;
  }

  {
    CefStateUniqueLock lock;
    while (gCEFInitializing || gCEFShutdownExecuting) {
      lock.wait(gStateCondition);
    }

    if (!gCEFInitialized) {
      shouldInitialize = true;
      gCEFInitializing = true;
    } else {
      gCEFShutdownPending = false;
      gCEFInitializeCount += 1;
    }
  }
  if (shouldInitialize) {
    didInitialize = ensureCefInitialized(runtimeRoot, runtimeMetadata, &initializeFailureReason);

    {
      CefStateLockGuard lock;
      gCEFInitializing = false;
      if (!didInitialize) {
        miumCEFResetRuntimeStateLocked();
      } else {
        gCEFInitialized = true;
        gCEFShutdownPending = false;
        gCEFInitializeCount = 1;
      }
      gStateCondition.notify_all();
    }
  }

  if (shouldInitialize && !didInitialize) {
    miumCEFUnloadFrameworkArtifactsWithoutShutdown();
    std::string reason = "Failed to initialize CEF runtime";
    if (!initializeFailureReason.empty()) {
      reason += ". ";
      reason += initializeFailureReason;
    }
    logRuntimeFailure(reason);
    runOnEventQueue(eventCallback, MiumCEFResultNotInitialized, reason.c_str(), eventContext);
    return MiumCEFResultNotInitialized;
  }

  {
    CefStateLockGuard lock;
    auto runtime = std::make_unique<MiumCEFRuntimeState>();
    runtime->id = nextIdFromMap(gNextRuntimeId, gRuntimes);
    runtime->runtimeRoot = runtimeRoot;
    runtime->metadataPath = runtimeMetadata;

    const auto runtimeId = runtime->id;
    gRuntimes[runtimeId] = std::move(runtime);
    *outRuntimeHandle = static_cast<MiumCEFRuntimeHandle>(miumCEFIdToHandle(runtimeId));
  }

  runOnEventQueue(eventCallback, MiumCEFResultOK, "runtime initialized", eventContext);
  return MiumCEFResultOK;
}

MiumCEFResultCode miumCEFRuntimeShutdown(MiumCEFRuntimeHandle runtimeHandle) {
  if (runtimeHandle == nullptr) {
    return MiumCEFResultInvalidArgument;
  }

  const uint64_t runtimeId = miumCEFNativeHandleToId(runtimeHandle);
  struct PendingBrowserClose {
    uint64_t browserId = 0;
    uint64_t runtimeId = 0;
    cef_browser_t* nativeBrowser = nullptr;
    cef_client_t* nativeClient = nullptr;
  };

  bool shouldShutdownNow = false;
  bool shouldScheduleShutdownPump = false;
  MiumCEFFinalShutdown shutdownContext;
  std::unordered_set<uint64_t> browserIdsToClear;
  std::vector<PendingBrowserClose> nativeBrowsersToRelease;

  {
    CefStateLockGuard lock;
    auto runtimeIter = gRuntimes.find(runtimeId);
    if (runtimeIter == gRuntimes.end()) {
      return MiumCEFResultNotInitialized;
    }
    if (!runtimeIter->second->active) {
      return MiumCEFResultAlreadyShutdown;
    }
    browserIdsToClear = runtimeIter->second->browserIds;
  }

  for (const uint64_t browserId : browserIdsToClear) {
    std::vector<MiumCEFPermissionExecutionBatch> permissionBatches;
    miumCEFPermissionTakeBrowserDismissalBatches(
      browserId,
      MiumCEFPermissionSessionDismissReason::browserClosed,
      true,
      &permissionBatches
    );
    miumCEFNativeExecutePermissionBatchesOnCefMainThread(std::move(permissionBatches));
  }

  {
    CefStateLockGuard lock;
    auto runtimeIter = gRuntimes.find(runtimeId);
    if (runtimeIter == gRuntimes.end()) {
      return MiumCEFResultNotInitialized;
    }
    if (!runtimeIter->second->active) {
      return MiumCEFResultAlreadyShutdown;
    }

    auto& runtime = *runtimeIter->second;
    runtime.active = false;
    runtime.pendingBrowserCloseCount = 0;

    std::vector<uint64_t> runtimeBrowserIds(runtime.browserIds.begin(), runtime.browserIds.end());
    for (const auto browserId : runtimeBrowserIds) {
      cef_browser_t* nativeBrowser = nullptr;
      cef_client_t* nativeClient = nullptr;
      uint64_t closingRuntimeId = 0;
      const MiumCEFBrowserCloseDisposition closeDisposition =
        beginClosingNativeBrowserForIdLocked(
          browserId,
          &nativeBrowser,
          &nativeClient,
          &closingRuntimeId,
          /*trackRuntimePendingClose=*/true
        );
      if (closeDisposition == MiumCEFBrowserCloseDisposition::failed) {
        runtimeTrace("Shutdown failed to begin close for browserId=%llu\n", static_cast<unsigned long long>(browserId));
      }
      if (closeDisposition == MiumCEFBrowserCloseDisposition::completedSynchronously) {
        runtimeTrace(
          "Shutdown completed close synchronously for browserId=%llu\n",
          static_cast<unsigned long long>(browserId)
        );
      }
      if (closeDisposition != MiumCEFBrowserCloseDisposition::closePending) {
        continue;
      }

      nativeBrowsersToRelease.push_back({
        .browserId = browserId,
        .runtimeId = closingRuntimeId,
        .nativeBrowser = nativeBrowser,
        .nativeClient = nativeClient,
      });
    }

    runtime.browserIds.clear();

    for (auto hostIter = gHostViews.begin(); hostIter != gHostViews.end(); ++hostIter) {
      if (hostIter->second->browserId == 0) {
        continue;
      }

      auto browserIter = gBrowsers.find(hostIter->second->browserId);
      if (browserIter == gBrowsers.end()) {
        hostIter->second->browserId = 0;
      }
    }

    if (runtime.pendingBrowserCloseCount == 0) {
      gRuntimes.erase(runtimeIter);
    }
    if (gCEFInitializeCount > 0) {
      gCEFInitializeCount -= 1;
    }

    if (gCEFInitializeCount == 0) {
      if (miumCEFPendingNativeBrowserCloseCountLocked() == 0) {
        gCEFShutdownPending = false;
        gPendingShutdownPumpScheduled = false;
        shouldShutdownNow = miumCEFBeginFinalShutdownLocked(&shutdownContext);
      } else {
        gCEFShutdownPending = gCEFInitialized;
        shouldScheduleShutdownPump = gCEFShutdownPending;
      }
    }
  }
  if (!browserIdsToClear.empty()) {
    clearNativeCallbackPayloadsForBrowsers(browserIdsToClear);
  }

  for (const auto& nativeBrowser : nativeBrowsersToRelease) {
    miumCEFNativeCloseBrowser(
      nativeBrowser.nativeBrowser,
      nativeBrowser.nativeClient,
      MiumCEFNativeBrowserCloseKind::teardown,
      true,
      nil,
      [browserId = nativeBrowser.browserId, closeRuntimeId = nativeBrowser.runtimeId] {
        finalizeClosedBrowserState(browserId, closeRuntimeId);
      }
    );
  }

  if (shouldShutdownNow) {
    miumCEFShutdownAndUnloadFrameworkArtifacts(shutdownContext);
  } else if (shouldScheduleShutdownPump) {
    miumCEFNativeCancelExternalMessagePumpWork();
    miumCEFSchedulePendingShutdownPumpIfNeeded();
  }

  return MiumCEFResultOK;
}

MiumCEFResultCode miumCEFRuntimeDoMessageLoopWork(void) {
  {
    CefStateLockGuard lock;
    if (!miumCEFIsCefRuntimeUsableLocked() || gCefApi.doMessageLoopWork == nullptr) {
      return MiumCEFResultNotInitialized;
    }
  }

  runOnRuntimeCefMainThread([] {
    (void)miumCEFNativePerformCefMessageLoopWork("manual_bridge");
  });

  return MiumCEFResultOK;
}
