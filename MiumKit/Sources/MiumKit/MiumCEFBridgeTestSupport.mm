#if defined(MIUM_CEF_BRIDGE_TESTING)

#include "MiumCEFBridgeNative+Testing.h"

#include <algorithm>
#include <unordered_set>

#include "MiumCEFBridgeAuxiliaryState.h"
#include "MiumCEFBridgeBrowserRegistry.h"
#include "MiumCEFBridgeCallbackQueue.h"
#include "MiumCEFBridgeClient.h"
#include "MiumCEFBridgeHostView.h"
#include "MiumCEFBridgeInternalAdapters.h"
#include "MiumCEFBridgeInternalPermissionAdapters.h"
#include "MiumCEFBridgeInternalRendererMessageAdapters.h"
#include "MiumCEFBridgeInternalBrowserMessagingSupport.h"
#include "MiumCEFBridgeInternalBrowserPayloadSupport.h"
#include "MiumCEFBridgeInternalPopupSupport.h"
#include "MiumCEFBridgeInternalRendererCameraSupport.h"
#include "MiumCEFBridgeInternalRuntimeBootstrapSupport.h"
#include "MiumCEFBridgeInternalRuntimeExecutionSupport.h"
#include "MiumCEFBridgeInternalState.h"
#include "MiumCEFBridgePaths.h"
#include "MiumCEFBridgeShutdown.h"

namespace {

void releaseOwnedTestClient(cef_client_t* client) {
  CefRef<cef_client_t>::adopt(client).reset();
}

template <typename Map>
uint64_t nextTestIdFromMap(uint64_t& nextID, const Map& map) {
  if (nextID == 0) {
    nextID = 1;
  }
  while (map.find(nextID) != map.end()) {
    ++nextID;
    if (nextID == 0) {
      nextID = 1;
    }
  }
  return nextID++;
}

MiumCEFSnapshotOptions snapshotOptionsFromTestOptions(
  const MiumCEFBridgeTestSnapshotOptions* options
) {
  MiumCEFSnapshotOptions snapshotOptions;
  if (options == nullptr) {
    return snapshotOptions;
  }
  snapshotOptions.bitmapFileType = static_cast<NSBitmapImageFileType>(options->bitmapFileType);
  snapshotOptions.jpegCompressionFactor = static_cast<CGFloat>(options->jpegCompressionFactor);
  snapshotOptions.usesJPEGCompressionFactor = options->usesJPEGCompressionFactor;
  snapshotOptions.captureAsPDF = options->captureAsPDF;
  snapshotOptions.hasClipRect = options->hasClipRect;
  snapshotOptions.clipRect = NSMakeRect(
    static_cast<CGFloat>(options->clipX),
    static_cast<CGFloat>(options->clipY),
    static_cast<CGFloat>(options->clipWidth),
    static_cast<CGFloat>(options->clipHeight)
  );
  return snapshotOptions;
}

} // namespace

extern "C" {

bool miumNativeCEFTestHandleRendererExecuteJavaScriptMessage(
  cef_frame_t* frame,
  const char* channel,
  const char* script
) {
  return miumCEFNativeHandleRendererExecuteJavaScriptRequestMessage(frame, channel, "1", script);
}

bool miumNativeCEFTestHandleRendererExecuteJavaScriptRequestMessage(
  cef_frame_t* frame,
  const char* channel,
  const char* requestID,
  const char* script
) {
  return miumCEFNativeHandleRendererExecuteJavaScriptRequestMessage(frame, channel, requestID, script);
}

bool miumNativeCEFTestHandleRendererManagedCameraFrameMessage(
  cef_frame_t* frame,
  const char* channel,
  const char* payload
) {
  return miumCEFNativeHandleRendererManagedCameraFrameMessage(frame, channel, payload);
}

bool miumNativeCEFTestHandleRendererManagedCameraConfigMessage(
  cef_frame_t* frame,
  const char* channel,
  const char* payload
) {
  return miumCEFNativeHandleRendererManagedCameraConfigMessage(frame, channel, payload);
}

bool miumNativeCEFTestInstallRendererCameraRoutingEventBridge(
  cef_frame_t* frame,
  cef_v8_context_t* context
) {
  return miumCEFNativeInstallRendererCameraRoutingEventBridge(frame, context);
}

bool miumNativeCEFTestHandleRendererExecuteJavaScriptResultMessage(
  cef_browser_t* browser,
  const char* channel,
  const char* requestID,
  const char* result,
  const char* error
) {
  return miumCEFNativeHandleRendererExecuteJavaScriptResultMessage(browser, channel, requestID, result, error);
}

void miumNativeCEFTestTriggerRenderProcessTerminated(
  cef_browser_t* browser,
  int status,
  int errorCode,
  const char* errorString
) {
  cef_string_t errorStringValue{};
  const cef_string_t* errorStringPointer = nullptr;
  if (errorString != nullptr && miumCEFNativeUTF16FromUTF8(errorString, errorStringValue, nullptr)) {
    errorStringPointer = &errorStringValue;
  }
  miumCEFNativeRequestHandlerOnRenderProcessTerminated(
    nullptr,
    browser,
    static_cast<cef_termination_status_t>(status),
    errorCode,
    errorStringPointer
  );
  if (errorStringPointer != nullptr) {
    miumCEFNativeClearUTF16String(errorStringValue);
  }
}

void miumNativeCEFTestResetState(void) {
  std::vector<cef_browser_t*> browsersToRelease;
  std::vector<cef_client_t*> clientsToRelease;
  MiumCEFDetachedFrameworkArtifacts detachedArtifacts;
  NSMutableArray<MiumCEFHostResourceState*>* hostResourcesToCleanup = [NSMutableArray array];

  miumNativeCEFTestResetCallbackQueues();

  {
    CefStateLockGuard lock;

    for (auto& browserPair : gBrowsers) {
      auto* browser = browserPair.second.get();
      if (browser->nativeBrowser != nullptr) {
        browsersToRelease.push_back(browser->nativeBrowser.leak());
      }
      if (browser->nativeClient != nullptr) {
        clientsToRelease.push_back(browser->nativeClient.leak());
      }
    }
    for (const auto& hostPair : gHostViews) {
      auto* hostViewState = hostPair.second.get();
      if (hostViewState != nullptr && hostViewState->resources != nil) {
        [hostResourcesToCleanup addObject:hostViewState->resources];
      }
    }

    detachedArtifacts = miumCEFDetachFrameworkArtifactsLocked();
    miumCEFResetRuntimeStateLocked();
    gCEFInitializing = false;
    gPendingTeardownBrowserCloseCount = 0;
    gPendingReplacementBrowserCloseCount = 0;
    gNextRuntimeId = 1;
    gNextBrowserId = 1;
    gNextHostViewId = 1;
    gNextRendererJavaScriptRequestId = 1;
    gRuntimes.clear();
    gBrowsers.clear();
    gHostViews.clear();
    gBrowserIdByNativeBrowser.clear();
    gBrowserIdByNativeBrowserIdentifier.clear();
    gRendererJavaScriptRequests.clear();
    gLastCandidatePaths.clear();
    gTestWindowSnapshotMode = MiumCEFBridgeTestWindowSnapshotMode::live;
    gTestSubprocessFrameworkCandidates.clear();
    gTestFrameworkFallbackCandidates.clear();
    gTestBundlePathNil = false;
    gTestBundleExecutablePathOverride.clear();
    gTestBundleExecutablePathNil = false;
    gTestBundleIdentifierOverride.clear();
    gTestBundleIdentifierNil = false;
    gTestCachesDirectoryOverride.clear();
    gTestCachesDirectoriesEmpty = false;
    gTestRendererJavaScriptRequestTimeoutSeconds = -1.0;
    gTestMediaStreamOverrideDevelopmentEligibility = -1;
    gTestProcessExitCallback = nullptr;
    gTestInterceptProcessExit = false;
    gTestInterceptedProcessExitCode = -1;
    gTestCreateBrowserClientReturnsNull = false;
    gTestNextBrowserClientMissingDisplayHandler = false;
    gTestOnePixelImageFailureMode = MiumCEFBridgeTestOnePixelImageFailureMode::none;
    gStateCondition.notify_all();
  }
  miumCEFPermissionResetState();

  miumCEFNativeRunOnCefMainThread([hostResourcesToCleanup] {
    for (MiumCEFHostResourceState* resources in hostResourcesToCleanup) {
      if (resources == nil) {
        continue;
      }
      NSView* hostView = resources.hostView;
      if (hostView != nil) {
        removeManagedBrowserSubviewsForHostView(hostView);
      } else if (resources.containerView != nil) {
        NSArray<NSView*>* subviews = [resources.containerView.subviews copy];
        for (NSView* subview in subviews) {
          [subview removeFromSuperview];
        }
        [resources.containerView removeFromSuperview];
      }
      resources.containerView = nil;
    }
    removeAllManagedBrowserSubviews();
  });

  for (cef_browser_t* browser : browsersToRelease) {
    miumCEFNativeReleaseBrowserOnCefMainThread(browser);
  }
  for (cef_client_t* client : clientsToRelease) {
    releaseOwnedTestClient(client);
  }
  miumCEFReleaseDetachedFrameworkArtifactsAndResetApiState(detachedArtifacts);
}

void miumNativeCEFTestInstallAPI(const MiumCEFBridgeTestAPI* api) {
  MiumCEFDetachedFrameworkArtifacts detachedArtifacts;

  {
    CefStateLockGuard lock;
    detachedArtifacts = miumCEFDetachFrameworkArtifactsLocked();
    miumCEFResetRuntimeStateLocked();
    gCEFInitializing = false;
  }

  miumCEFReleaseDetachedFrameworkArtifactsAndResetApiState(detachedArtifacts);
  {
    CefStateLockGuard lock;
    if (api != nullptr) {
      gCefApi.utf8ToUTF16 = api->utf8ToUTF16;
      gCefApi.utf16Clear = api->utf16Clear;
      gCefApi.userfreeFree = api->userfreeFree;
      gCefApi.stringListSize = api->stringListSize;
      gCefApi.stringListValue = api->stringListValue;
      gCefApi.initialize = api->initialize;
      gCefApi.executeProcess = api->executeProcess;
      gCefApi.shutdown = api->shutdown;
      gCefApi.doMessageLoopWork = api->doMessageLoopWork;
      gCefApi.createBrowserSync = api->createBrowserSync;
      gCefApi.createProcessMessage = api->createProcessMessage;
      gCefApi.createV8Function = api->createV8Function;
      gCefApi.currentV8Context = api->currentV8Context;
      gCefApi.loaded =
        gCefApi.utf8ToUTF16 != nullptr ||
        gCefApi.utf16Clear != nullptr ||
        gCefApi.userfreeFree != nullptr ||
        gCefApi.stringListSize != nullptr ||
        gCefApi.stringListValue != nullptr ||
        gCefApi.initialize != nullptr ||
        gCefApi.executeProcess != nullptr ||
        gCefApi.shutdown != nullptr ||
        gCefApi.doMessageLoopWork != nullptr ||
        gCefApi.createBrowserSync != nullptr ||
        gCefApi.createProcessMessage != nullptr ||
        gCefApi.createV8Function != nullptr ||
        gCefApi.currentV8Context != nullptr;
    }
  }
}

void miumNativeCEFTestSetFrameworkLoaded(bool loaded) {
  CefStateLockGuard lock;
  gFrameworkLoaded = loaded;
}

void miumNativeCEFTestSetFrameworkHandle(void* frameworkHandle) {
  CefStateLockGuard lock;
  gCefApi.frameworkHandle = frameworkHandle;
}

void miumNativeCEFTestSetInitialized(bool initialized, int initializeCount) {
  CefStateLockGuard lock;
  gCEFInitialized = initialized;
  gCEFInitializeCount = std::max(0, initializeCount);
  if (initialized) {
    if (gCefApi.loaded && gCefApi.frameworkHandle == nullptr) {
      gCefApi.frameworkHandle = miumCEFTestInjectedFrameworkHandleSentinel();
      gFrameworkLoaded = true;
    }
  } else if (gCefApi.frameworkHandle == miumCEFTestInjectedFrameworkHandleSentinel()) {
    gCefApi.frameworkHandle = nullptr;
    gFrameworkLoaded = false;
  }
  if (!initialized) {
    gCEFShutdownPending = false;
    gPendingShutdownPumpScheduled = false;
  }
}

void miumNativeCEFTestSetShutdownExecuting(bool shutdownExecuting) {
  CefStateLockGuard lock;
  gCEFShutdownExecuting = shutdownExecuting;
}

bool miumNativeCEFTestIsInitialized(void) {
  CefStateLockGuard lock;
  return gCEFInitialized;
}

bool miumNativeCEFTestIsShutdownExecuting(void) {
  CefStateLockGuard lock;
  return gCEFShutdownExecuting;
}

MiumCEFRuntimeHandle miumNativeCEFTestInsertRuntime(
  const char* runtimeRootPath,
  const char* runtimeMetadataPath,
  bool active
) {
  CefStateLockGuard lock;

  auto runtime = std::make_unique<MiumCEFRuntimeState>();
  runtime->id = nextTestIdFromMap(gNextRuntimeId, gRuntimes);
  runtime->runtimeRoot = runtimeRootPath == nullptr ? std::string() : std::string(runtimeRootPath);
  runtime->metadataPath = runtimeMetadataPath == nullptr ? std::string() : std::string(runtimeMetadataPath);
  runtime->active = active;

  const uint64_t runtimeId = runtime->id;
  gRuntimes[runtimeId] = std::move(runtime);
  return static_cast<MiumCEFRuntimeHandle>(miumCEFIdToHandle(runtimeId));
}

bool miumNativeCEFTestSetHostViewPointer(MiumCEFHostViewHandle hostViewHandle, void* hostView) {
  if (hostViewHandle == nullptr) {
    return false;
  }

  CefStateLockGuard lock;
  auto hostIter = gHostViews.find(miumCEFNativeHandleToId(hostViewHandle));
  if (hostIter == gHostViews.end() || hostIter->second == nullptr || !hostIter->second->active) {
    return false;
  }

  ensureHostResources(hostIter->second.get()).hostView = (__bridge NSView*)hostView;
  return true;
}

void* miumNativeCEFTestGetHostViewPointer(MiumCEFHostViewHandle hostViewHandle) {
  if (hostViewHandle == nullptr) {
    return nullptr;
  }

  CefStateLockGuard lock;
  auto hostIter = gHostViews.find(miumCEFNativeHandleToId(hostViewHandle));
  if (hostIter == gHostViews.end() || hostIter->second == nullptr || !hostIter->second->active) {
    return nullptr;
  }

  return (__bridge void*)resolvedHostViewForState(hostIter->second.get());
}

uint64_t miumNativeCEFTestGetBrowserHostViewId(MiumCEFBrowserHandle browserHandle) {
  if (browserHandle == nullptr) {
    return 0;
  }

  CefStateLockGuard lock;
  auto browserIter = gBrowsers.find(miumCEFNativeHandleToId(browserHandle));
  if (browserIter == gBrowsers.end() || browserIter->second == nullptr || !browserIter->second->active) {
    return 0;
  }

  return browserIter->second->hostViewId;
}

cef_client_t* miumNativeCEFTestGetNativeClient(MiumCEFBrowserHandle browserHandle) {
  if (browserHandle == nullptr) {
    return nullptr;
  }

  CefStateLockGuard lock;
  auto* browserState = activeBrowserStateLocked(miumCEFNativeHandleToId(browserHandle));
  return browserState == nullptr ? nullptr : browserState->nativeClient.get();
}

size_t miumNativeCEFTestActivePermissionSessionCount(void) {
  return miumCEFPermissionActiveSessionCount();
}

bool miumNativeCEFTestHasActivePermissionSession(MiumCEFPermissionSessionID sessionID) {
  return miumCEFPermissionHasActiveSession(sessionID);
}

bool miumNativeCEFTestAttachNativeBrowser(
  MiumCEFBrowserHandle browserHandle,
  cef_browser_t* browser,
  cef_client_t* client
) {
  if (browserHandle == nullptr) {
    return false;
  }

  cef_browser_t* previousBrowser = nullptr;
  cef_client_t* previousClient = nullptr;

  {
    CefStateLockGuard lock;
    auto browserIter = gBrowsers.find(miumCEFNativeHandleToId(browserHandle));
    if (browserIter == gBrowsers.end() || browserIter->second == nullptr || !browserIter->second->active) {
      return false;
    }

    auto& browserState = *browserIter->second;
    previousBrowser = browserState.nativeBrowser.leak();
    previousClient = browserState.nativeClient.leak();
    browserState.nativeBrowser = CefRef<cef_browser_t>::retain(browser);
    browserState.nativeClient = CefRef<cef_client_t>::retain(client);
    browserState.hostViewBound = (browser != nullptr && browserState.hostViewId != 0);
    bindNativeBrowserIdForBrowser(browserState.id, previousBrowser, browser);
    assertBrowserStateConsistencyLocked(&browserState);
  }
  if (previousBrowser != nullptr && previousBrowser != browser) {
    miumCEFNativeReleaseBrowserOnCefMainThread(previousBrowser);
  }
  if (previousClient != nullptr && previousClient != client) {
    releaseOwnedTestClient(previousClient);
  }

  return true;
}

MiumCEFHostViewHandle miumNativeCEFTestHostViewHandleForBrowser(MiumCEFBrowserHandle browserHandle) {
  if (browserHandle == nullptr) {
    return nullptr;
  }

  CefStateLockGuard lock;
  auto* browserState = activeBrowserStateLocked(miumCEFNativeHandleToId(browserHandle));
  if (browserState == nullptr || browserState->hostViewId == 0) {
    return nullptr;
  }

  auto hostIter = gHostViews.find(browserState->hostViewId);
  if (hostIter == gHostViews.end() || hostIter->second == nullptr || !hostIter->second->active) {
    return nullptr;
  }

  return static_cast<MiumCEFHostViewHandle>(miumCEFIdToHandle(browserState->hostViewId));
}

MiumCEFBrowserHandle miumNativeCEFTestBrowserHandleForHostView(MiumCEFHostViewHandle hostViewHandle) {
  if (hostViewHandle == nullptr) {
    return nullptr;
  }

  CefStateLockGuard lock;
  auto hostIter = gHostViews.find(miumCEFNativeHandleToId(hostViewHandle));
  if (hostIter == gHostViews.end() || hostIter->second == nullptr || !hostIter->second->active) {
    return nullptr;
  }

  const uint64_t browserId = hostIter->second->browserId;
  if (browserId == 0) {
    return nullptr;
  }

  auto browserIter = gBrowsers.find(browserId);
  if (browserIter == gBrowsers.end() || browserIter->second == nullptr || !browserIter->second->active) {
    return nullptr;
  }

  return static_cast<MiumCEFBrowserHandle>(miumCEFIdToHandle(browserId));
}

void miumNativeCEFTestRunOnMainThread(void* context, MiumCEFBridgeTestVoidCallback callback) {
  if (callback == nullptr) {
    return;
  }
  miumCEFNativeRunOnCefMainThread([context, callback] {
    callback(context);
  });
}

void miumNativeCEFTestRunOffMainThread(void* context, MiumCEFBridgeTestVoidCallback callback) {
  if (callback == nullptr) {
    return;
  }
  if (![NSThread isMainThread]) {
    callback(context);
    return;
  }

  dispatch_semaphore_t completion = dispatch_semaphore_create(0);
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    callback(context);
    dispatch_semaphore_signal(completion);
  });
  dispatch_semaphore_wait(completion, DISPATCH_TIME_FOREVER);
}

void miumNativeCEFTestRunOnMessageQueue(
  MiumCEFEventCallback callback,
  MiumCEFResultCode code,
  const char* message,
  void* context,
  uint64_t browserId
) {
  runOnMessageQueue(callback, code, message, context, browserId);
}

void miumNativeCEFTestRunOnMessageQueueForHandler(
  MiumCEFEventCallback callback,
  MiumCEFResultCode code,
  const char* message,
  void* context,
  uint64_t browserId,
  const char* channel,
  uint64_t handlerGeneration
) {
  runOnMessageQueue(callback, code, message, context, browserId, channel, handlerGeneration);
}

void miumNativeCEFTestRunOnMessageQueueForHandlerWithRegistration(
  MiumCEFEventCallback callback,
  MiumCEFResultCode code,
  const char* message,
  const MiumCEFCallbackRegistrationRef& registration,
  void* context,
  uint64_t browserId,
  const char* channel,
  uint64_t handlerGeneration
) {
  runOnMessageQueue(
    callback,
    code,
    message,
    context,
    browserId,
    channel,
    handlerGeneration,
    ensureNativeCallbackRegistrationContext(registration, context)
  );
}

void miumNativeCEFTestSetBundleExecutablePathOverride(const char* path) {
  gTestBundleExecutablePathOverride = path == nullptr ? std::string() : std::string(path);
}

void miumNativeCEFTestSetBundleExecutablePathNil(bool enabled) {
  gTestBundleExecutablePathNil = enabled;
}

void miumNativeCEFTestSetBundlePathNil(bool enabled) {
  gTestBundlePathNil = enabled;
}

void miumNativeCEFTestSetBundleIdentifierOverride(const char* bundleIdentifier) {
  gTestBundleIdentifierOverride = bundleIdentifier == nullptr ? std::string() : std::string(bundleIdentifier);
}

void miumNativeCEFTestSetBundleIdentifierNil(bool enabled) {
  gTestBundleIdentifierNil = enabled;
}

void miumNativeCEFTestSetCachesDirectoryOverride(const char* cachesDirectory) {
  gTestCachesDirectoryOverride = cachesDirectory == nullptr ? std::string() : std::string(cachesDirectory);
}

void miumNativeCEFTestSetCachesDirectoriesEmpty(bool enabled) {
  gTestCachesDirectoriesEmpty = enabled;
}

void miumNativeCEFTestSetRendererJavaScriptRequestTimeoutSeconds(double timeoutSeconds) {
  gTestRendererJavaScriptRequestTimeoutSeconds = timeoutSeconds;
}

void miumNativeCEFTestSetMediaStreamOverrideDevelopmentEligible(bool enabled) {
  gTestMediaStreamOverrideDevelopmentEligibility = enabled ? 1 : 0;
}

void miumNativeCEFTestResetMediaStreamOverrideDevelopmentEligibility(void) {
  gTestMediaStreamOverrideDevelopmentEligibility = -1;
}

void miumNativeCEFTestSetProcessExitCallback(MiumCEFBridgeTestProcessExitCallback callback) {
  gTestProcessExitCallback = callback;
}

void miumNativeCEFTestSetInterceptProcessExit(bool enabled) {
  gTestInterceptProcessExit = enabled;
  if (!enabled) {
    gTestInterceptedProcessExitCode = -1;
  }
}

int miumNativeCEFTestLastInterceptedProcessExitCode(void) {
  return gTestInterceptedProcessExitCode;
}

void miumNativeCEFTestSetCreateBrowserClientReturnsNull(bool enabled) {
  gTestCreateBrowserClientReturnsNull = enabled;
}

void miumNativeCEFTestSetNextBrowserClientMissingDisplayHandler(bool enabled) {
  gTestNextBrowserClientMissingDisplayHandler = enabled;
}

void miumNativeCEFTestSetNextIds(uint64_t runtimeId, uint64_t browserId, uint64_t hostViewId) {
  CefStateLockGuard lock;
  gNextRuntimeId = runtimeId;
  gNextBrowserId = browserId;
  gNextHostViewId = hostViewId;
}

} // extern "C"

std::string miumNativeCEFTestNormalizePath(const char* path) {
  return normalizePath(path);
}

bool miumNativeCEFTestSetCefSettingPath(const char* value, std::string* errorOut) {
  cef_string_t setting{};
  const bool configured = miumCEFNativeSetCefSettingPath(
    setting,
    value == nullptr ? std::string() : std::string(value),
    errorOut
  );
  miumCEFNativeClearUTF16String(setting);
  return configured;
}

std::vector<std::string> miumNativeCEFTestCandidatePaths(
  const char* runtimeRootPath,
  const char* runtimeMetadataPath
) {
  return miumCEFNativeCandidatePathsFor(
    runtimeRootPath == nullptr ? std::string() : std::string(runtimeRootPath),
    runtimeMetadataPath == nullptr ? std::string() : std::string(runtimeMetadataPath)
  );
}

std::string miumNativeCEFTestTrimWhitespaceInString(const char* value) {
  return trimWhitespaceInString(value == nullptr ? std::string() : std::string(value));
}

std::string miumNativeCEFTestMakePathFromRootAndRelative(
  const char* rootPath,
  const char* relativePath
) {
  return makePathFromRootAndRelative(
    rootPath == nullptr ? std::string() : std::string(rootPath),
    relativePath == nullptr ? std::string() : std::string(relativePath)
  );
}

bool miumNativeCEFTestDirectoryContainsCefLocaleResources(const char* directoryPath) {
  NSString* path = directoryPath == nullptr ? nil : [NSString stringWithUTF8String:directoryPath];
  return directoryContainsCefLocaleResources(path);
}

std::string miumNativeCEFTestNormalizeChromiumLocalesPathCandidate(const char* candidatePath) {
  return normalizeChromiumLocalesPathCandidate(
    candidatePath == nullptr ? std::string() : std::string(candidatePath)
  );
}

std::string miumNativeCEFTestResolveChromiumLocalesPath(const char* runtimeRootPath) {
  return miumCEFNativeResolveChromiumLocalesPath(
    runtimeRootPath == nullptr ? std::string() : std::string(runtimeRootPath)
  );
}

MiumCEFBridgeTestRuntimeLayout miumNativeCEFTestResolveRuntimeLayoutConfig(
  const char* runtimeRootPath,
  const char* runtimeMetadataPath
) {
  const RuntimeLayoutConfig layout = miumCEFNativeResolveRuntimeLayoutConfig(
    runtimeRootPath == nullptr ? std::string() : std::string(runtimeRootPath),
    runtimeMetadataPath == nullptr ? std::string() : std::string(runtimeMetadataPath)
  );
  return {
    .resourcesDir = layout.resourcesDir,
    .localesDir = layout.localesDir,
    .helpersDir = layout.helpersDir,
  };
}

std::string miumNativeCEFTestHostExecutableBasename(void) {
  return hostExecutableBasename();
}

bool miumNativeCEFTestPathExistsAndIsDirectory(const char* path, bool mustBeDirectory) {
  const std::string normalizedPath = path == nullptr ? std::string() : std::string(path);
  return mustBeDirectory ? miumCEFNativePathExistsAsDirectory(normalizedPath) : pathExists(normalizedPath);
}

bool miumNativeCEFTestPathExistsAsFile(const char* path) {
  return pathExistsAsFile(path == nullptr ? std::string() : std::string(path));
}

std::string miumNativeCEFTestResolveHelperBundlePath(const char* helpersDirPath) {
  return resolveHelperBundlePath(helpersDirPath == nullptr ? std::string() : std::string(helpersDirPath));
}

std::string miumNativeCEFTestResolveHelperSubprocessPath(
  const char* runtimeRootPath,
  const char* runtimeMetadataPath
) {
  return miumCEFNativeResolveHelperSubprocessPath(
    runtimeRootPath == nullptr ? std::string() : std::string(runtimeRootPath),
    runtimeMetadataPath == nullptr ? std::string() : std::string(runtimeMetadataPath)
  );
}

std::string miumNativeCEFTestDescribeFrameworkCandidateFailure(
  const std::vector<std::string>& candidates
) {
  return miumCEFNativeDescribeFrameworkCandidateFailure(candidates);
}

bool miumNativeCEFTestVerifyCefApiCompatibility(const char* runtimeHash, const char* expectedHash) {
  return miumCEFNativeVerifyCefApiCompatibility(runtimeHash, expectedHash);
}

bool miumNativeCEFTestLoadSymbol(void* handle, const char* symbolName, void** destination) {
  return miumCEFNativeLoadSymbol(handle, symbolName, destination);
}

bool miumNativeCEFTestLoadRequiredCefSymbols(void* frameworkHandle) {
  CefApi loadedApi;
  const bool didLoad = miumCEFNativeLoadRequiredCefSymbols(frameworkHandle, &loadedApi);

  CefStateLockGuard lock;
  gCefApi.reset();
  gFrameworkLoaded = false;
  if (didLoad) {
    gCefApi = loadedApi;
    gFrameworkLoaded = true;
  }
  return didLoad;
}

bool miumNativeCEFTestOpenFrameworkIfNeeded(const std::vector<std::string>& candidates) {
  {
    CefStateLockGuard lock;
    gLastCandidatePaths = candidates;
  }
  return miumCEFNativeOpenFrameworkIfNeeded(candidates);
}

bool miumNativeCEFTestEnsureCefInitialized(
  const char* runtimeRootPath,
  const char* runtimeMetadataPath,
  std::string* failureReason
) {
  return miumCEFNativeEnsureCefInitialized(
    runtimeRootPath == nullptr ? std::string() : std::string(runtimeRootPath),
    runtimeMetadataPath == nullptr ? std::string() : std::string(runtimeMetadataPath),
    failureReason
  );
}

bool miumNativeCEFTestParseBooleanEnvironmentFlag(const char* name) {
  return parseBooleanEnvironmentFlag(name);
}

bool miumNativeCEFTestHasEnvironmentValue(const char* name) {
  return miumCEFNativeHasEnvironmentValue(name);
}

bool miumNativeCEFTestShouldDisableCEFChildProcessSandbox(void) {
  return miumCEFNativeShouldDisableCEFChildProcessSandbox();
}

bool miumNativeCEFTestShouldInterceptProcessExitCode(int exitCode) {
  return miumCEFNativeInterceptProcessExitCodeIfTesting(exitCode);
}

int miumNativeCEFTestSingletonOwnerPIDFromLockDestination(const char* destinationPath) {
  NSString* path = destinationPath == nullptr ? nil : [NSString stringWithUTF8String:destinationPath];
  return static_cast<int>(singletonOwnerPIDFromLockDestination(path));
}

bool miumNativeCEFTestIsLiveNavigatorProcess(int pid) {
  return isLiveNavigatorProcess(static_cast<pid_t>(pid));
}

void miumNativeCEFTestRemoveStaleSingletonArtifacts(const char* candidatePath) {
  NSString* path = candidatePath == nullptr ? nil : [NSString stringWithUTF8String:candidatePath];
  removeStaleSingletonArtifacts(path);
}

std::string miumNativeCEFTestResolveCEFUserDataDirectory(void) {
  return miumCEFNativeResolveCEFUserDataDirectory();
}

bool miumNativeCEFTestCanBindBrowserToHostView(
  MiumCEFBrowserHandle browserHandle,
  MiumCEFHostViewHandle hostViewHandle,
  void* hostView
) {
  if (browserHandle == nullptr) {
    return false;
  }

  CefStateLockGuard lock;
  return canBindBrowserToHostViewLocked(
    activeBrowserStateLocked(miumCEFNativeHandleToId(browserHandle)),
    hostViewHandle == nullptr ? 0 : miumCEFNativeHandleToId(hostViewHandle),
    hostView
  );
}

bool miumNativeCEFTestBindBrowserToHostView(
  MiumCEFBrowserHandle browserHandle,
  MiumCEFHostViewHandle hostViewHandle,
  void* hostView
) {
  if (browserHandle == nullptr) {
    return false;
  }

  CefStateLockGuard lock;
  return bindBrowserToHostViewLocked(
    activeBrowserStateLocked(miumCEFNativeHandleToId(browserHandle)),
    hostViewHandle == nullptr ? 0 : miumCEFNativeHandleToId(hostViewHandle),
    hostView
  );
}

void miumNativeCEFTestClearBrowserHostViewBinding(MiumCEFBrowserHandle browserHandle) {
  if (browserHandle == nullptr) {
    return;
  }

  CefStateLockGuard lock;
  auto browserIter = gBrowsers.find(miumCEFNativeHandleToId(browserHandle));
  if (browserIter == gBrowsers.end() || browserIter->second == nullptr) {
    return;
  }
  clearBrowserHostViewBindingLocked(browserIter->second.get());
}

bool miumNativeCEFTestIsBrowserHandleAvailableForCallbacks(uint64_t browserId) {
  if (browserId == 0) {
    return true;
  }

  CefStateLockGuard lock;
  auto browserIter = gBrowsers.find(browserId);
  return browserIter != gBrowsers.end() && shouldTrackBrowserForNativeCallbacksLocked(browserIter->second.get());
}

uint64_t miumNativeCEFTestMessageHandlerGeneration(
  MiumCEFBrowserHandle browserHandle,
  const char* channel
) {
  if (browserHandle == nullptr || channel == nullptr) {
    return 0;
  }

  CefStateLockGuard lock;
  auto browserIter = gBrowsers.find(miumCEFNativeHandleToId(browserHandle));
  if (browserIter == gBrowsers.end() || browserIter->second == nullptr) {
    return 0;
  }

  auto handlerIter = browserIter->second->handlers.find(channel);
  if (handlerIter == browserIter->second->handlers.end()) {
    return 0;
  }

  return handlerIter->second.generation;
}

bool miumNativeCEFTestParseSnapshotOptions(
  const char* jsonOptions,
  const char* outputPath,
  MiumCEFBridgeTestSnapshotOptions* outOptions,
  std::string* errorOut
) {
  NSString* output = outputPath == nullptr ? nil : [NSString stringWithUTF8String:outputPath];
  MiumCEFSnapshotOptions parsedOptions;
  NSString* error = nil;
  const bool parsed = parseSnapshotOptions(jsonOptions, output, &parsedOptions, &error);
  if (outOptions != nullptr) {
    outOptions->bitmapFileType = static_cast<long>(parsedOptions.bitmapFileType);
    outOptions->jpegCompressionFactor = parsedOptions.jpegCompressionFactor;
    outOptions->usesJPEGCompressionFactor = parsedOptions.usesJPEGCompressionFactor;
    outOptions->captureAsPDF = parsedOptions.captureAsPDF;
    outOptions->hasClipRect = parsedOptions.hasClipRect;
    outOptions->clipX = parsedOptions.clipRect.origin.x;
    outOptions->clipY = parsedOptions.clipRect.origin.y;
    outOptions->clipWidth = parsedOptions.clipRect.size.width;
    outOptions->clipHeight = parsedOptions.clipRect.size.height;
  }
  if (errorOut != nullptr) {
    *errorOut = error == nil ? std::string() : std::string(error.UTF8String == nullptr ? "" : error.UTF8String);
  }
  return parsed;
}

bool miumNativeCEFTestConfigureSnapshotFormat(
  const char* format,
  MiumCEFBridgeTestSnapshotOptions* outOptions,
  std::string* errorOut
) {
  MiumCEFSnapshotOptions options;
  MiumCEFSnapshotOptions* internalOptions = outOptions == nullptr ? nullptr : &options;
  NSString* error = nil;
  const bool configured = configureSnapshotFormat(
    format == nullptr ? nil : [NSString stringWithUTF8String:format],
    internalOptions,
    &error
  );
  if (outOptions != nullptr) {
    outOptions->bitmapFileType = static_cast<long>(options.bitmapFileType);
    outOptions->jpegCompressionFactor = options.jpegCompressionFactor;
    outOptions->usesJPEGCompressionFactor = options.usesJPEGCompressionFactor;
    outOptions->captureAsPDF = options.captureAsPDF;
    outOptions->hasClipRect = options.hasClipRect;
    outOptions->clipX = options.clipRect.origin.x;
    outOptions->clipY = options.clipRect.origin.y;
    outOptions->clipWidth = options.clipRect.size.width;
    outOptions->clipHeight = options.clipRect.size.height;
  }
  if (errorOut != nullptr) {
    *errorOut = error == nil ? std::string() : std::string(error.UTF8String == nullptr ? "" : error.UTF8String);
  }
  return configured;
}

bool miumNativeCEFTestSnapshotBoundsForHostView(
  void* hostView,
  const MiumCEFBridgeTestSnapshotOptions* options,
  std::string* errorOut
) {
  NSString* error = nil;
  const NSRect bounds = snapshotBoundsForHostView(
    (__bridge NSView*)hostView,
    snapshotOptionsFromTestOptions(options),
    &error
  );
  if (errorOut != nullptr) {
    *errorOut = error == nil ? std::string() : std::string(error.UTF8String == nullptr ? "" : error.UTF8String);
  }
  return NSWidth(bounds) > 0.0 && NSHeight(bounds) > 0.0;
}

bool miumNativeCEFTestSnapshotBitmapRepForHostViewFromWindow(
  void* hostView,
  double x,
  double y,
  double width,
  double height
) {
  NSBitmapImageRep* bitmap = snapshotBitmapRepForHostViewFromWindow(
    (__bridge NSView*)hostView,
    NSMakeRect(
      static_cast<CGFloat>(x),
      static_cast<CGFloat>(y),
      static_cast<CGFloat>(width),
      static_cast<CGFloat>(height)
    )
  );
  return bitmap != nil;
}

void miumNativeCEFTestSetWindowSnapshotMode(MiumCEFBridgeTestWindowSnapshotMode mode) {
  gTestWindowSnapshotMode = mode;
}

void miumNativeCEFTestSetOnePixelImageFailureMode(MiumCEFBridgeTestOnePixelImageFailureMode mode) {
  gTestOnePixelImageFailureMode = mode;
}

void miumNativeCEFTestSetSubprocessFrameworkCandidates(
  const std::vector<std::string>& candidates
) {
  gTestSubprocessFrameworkCandidates = candidates;
}

void miumNativeCEFTestSetFrameworkFallbackCandidates(
  const std::vector<std::string>& candidates
) {
  gTestFrameworkFallbackCandidates = candidates;
}

void miumNativeCEFTestResizeEmbeddedBrowserHostView(void* hostView, int pixelWidth, int pixelHeight) {
  resizeEmbeddedBrowserHostView((__bridge NSView*)hostView, pixelWidth, pixelHeight);
}

double miumNativeCEFTestBackingScaleFactorForHostView(void* hostView) {
  return backingScaleFactorForHostView((__bridge NSView*)hostView);
}

cef_client_t* miumNativeCEFTestCreateBrowserClient(void) {
  return createBrowserClient();
}

bool miumNativeCEFTestCreateBrowserWithWindowInfo(
  void* hostView,
  cef_browser_t** outBrowser,
  cef_client_t** outClient
) {
  return createBrowserWithWindowInfo(hostView, outBrowser, outClient, nullptr);
}

uint64_t miumNativeCEFTestBrowserIdFromNativeBrowser(cef_browser_t* browser) {
  return miumCEFNativeBrowserIdFromNativeBrowser(browser);
}

uint64_t miumNativeCEFTestBrowserIdFromNativeBrowserPointerMapping(cef_browser_t* browser) {
  if (browser == nullptr) {
    return 0;
  }

  CefStateLockGuard lock;
  auto nativeIter = gBrowserIdByNativeBrowser.find(browser);
  return nativeIter == gBrowserIdByNativeBrowser.end() ? 0 : nativeIter->second;
}

void miumNativeCEFTestEraseNativeBrowserPointerMapping(cef_browser_t* browser) {
  CefStateLockGuard lock;
  gBrowserIdByNativeBrowser.erase(browser);
}

void miumNativeCEFTestEraseNativeBrowserIdentifierMapping(int64_t browserIdentifier) {
  CefStateLockGuard lock;
  gBrowserIdByNativeBrowserIdentifier.erase(browserIdentifier);
}

void miumNativeCEFTestBindNativeBrowserMappings(
  MiumCEFBrowserHandle browserHandle,
  cef_browser_t* previousBrowser,
  cef_browser_t* nextBrowser
) {
  if (browserHandle == nullptr) {
    return;
  }

  CefStateLockGuard lock;
  auto browserIter = gBrowsers.find(miumCEFNativeHandleToId(browserHandle));
  if (browserIter == gBrowsers.end() || browserIter->second == nullptr) {
    return;
  }
  bindNativeBrowserIdForBrowser(browserIter->second->id, previousBrowser, nextBrowser);
}

void miumNativeCEFTestSetBrowserStateFlags(
  MiumCEFBrowserHandle browserHandle,
  bool active,
  bool closing
) {
  if (browserHandle == nullptr) {
    return;
  }

  CefStateLockGuard lock;
  auto browserIter = gBrowsers.find(miumCEFNativeHandleToId(browserHandle));
  if (browserIter == gBrowsers.end() || browserIter->second == nullptr) {
    return;
  }
  browserIter->second->active = active;
  browserIter->second->closing = closing;
}

bool miumNativeCEFTestSetHostViewBrowserId(
  MiumCEFHostViewHandle hostViewHandle,
  uint64_t browserId
) {
  if (hostViewHandle == nullptr) {
    return false;
  }

  CefStateLockGuard lock;
  auto hostIter = gHostViews.find(miumCEFNativeHandleToId(hostViewHandle));
  if (hostIter == gHostViews.end() || hostIter->second == nullptr) {
    return false;
  }
  hostIter->second->browserId = browserId;
  return true;
}

bool miumNativeCEFTestEnsureNativeBrowser(
  MiumCEFBrowserHandle browserHandle,
  MiumCEFHostViewHandle hostViewHandle
) {
  if (browserHandle == nullptr) {
    return false;
  }

  uint64_t hostViewId = 0;
  void* hostView = nullptr;
  if (hostViewHandle != nullptr) {
    hostViewId = miumCEFNativeHandleToId(hostViewHandle);
    CefStateLockGuard lock;
    auto hostIter = gHostViews.find(hostViewId);
    if (hostIter != gHostViews.end() && hostIter->second != nullptr) {
      hostView = (__bridge void*)resolvedHostViewForState(hostIter->second.get());
    }
  }

  return ensureNativeBrowser(miumCEFNativeHandleToId(browserHandle), hostViewId, hostView);
}

void miumNativeCEFTestCloseBrowserDirect(
  cef_browser_t* browser,
  cef_client_t* client,
  MiumCEFBridgeTestCloseKind kind,
  void* context,
  MiumCEFBridgeTestVoidCallback callback
) {
  miumCEFNativeCloseBrowser(
    browser,
    client,
    kind == MiumCEFBridgeTestCloseKind::replacement
      ? MiumCEFNativeBrowserCloseKind::replacement
      : MiumCEFNativeBrowserCloseKind::teardown,
    false,
    nil,
    callback == nullptr
      ? std::function<void()>{}
      : std::function<void()>([context, callback] {
          callback(context);
        })
  );
}

MiumCEFBridgeTestBrowserCloseDisposition miumNativeCEFTestBeginClosingNativeBrowser(
  MiumCEFBrowserHandle browserHandle,
  bool trackRuntimePendingClose,
  bool returnClient,
  uint64_t* outRuntimeId,
  cef_browser_t** outBrowser,
  cef_client_t** outClient
) {
  if (browserHandle == nullptr) {
    return MiumCEFBridgeTestBrowserCloseDisposition::failed;
  }

  CefStateLockGuard lock;
  cef_client_t** clientOut = returnClient ? outClient : nullptr;
  const MiumCEFBrowserCloseDisposition disposition = beginClosingNativeBrowserForIdLocked(
    miumCEFNativeHandleToId(browserHandle),
    outBrowser,
    clientOut,
    outRuntimeId,
    trackRuntimePendingClose
  );
  switch (disposition) {
    case MiumCEFBrowserCloseDisposition::completedSynchronously:
      return MiumCEFBridgeTestBrowserCloseDisposition::completedSynchronously;
    case MiumCEFBrowserCloseDisposition::closePending:
      return MiumCEFBridgeTestBrowserCloseDisposition::closePending;
    case MiumCEFBrowserCloseDisposition::failed:
    default:
      return MiumCEFBridgeTestBrowserCloseDisposition::failed;
  }
}

void miumNativeCEFTestFinalizeClosedBrowserState(
  MiumCEFBrowserHandle browserHandle,
  MiumCEFRuntimeHandle runtimeHandle
) {
  finalizeClosedBrowserState(
    browserHandle == nullptr ? 0 : miumCEFNativeHandleToId(browserHandle),
    runtimeHandle == nullptr ? 0 : miumCEFNativeHandleToId(runtimeHandle)
  );
}

void miumNativeCEFTestMaybeCompletePendingCefShutdown(void) {
  miumCEFMaybeCompletePendingCefShutdown();
}

void miumNativeCEFTestEmitDisplayHandlerFaviconURLChange(cef_browser_t* browser, const char* url) {
  miumCEFNativeEmitBrowserMessageForMappedBrowser(
    browser,
    MiumCEFFaviconURLChangeChannel,
    url == nullptr ? "" : url
  );
}

void miumNativeCEFTestRegisterPendingBrowserClose(MiumCEFBridgeTestCloseKind kind) {
  CefStateLockGuard lock;
  registerPendingBrowserCloseLocked(
    kind == MiumCEFBridgeTestCloseKind::replacement
      ? MiumCEFNativeBrowserCloseKind::replacement
      : MiumCEFNativeBrowserCloseKind::teardown
  );
}

void miumNativeCEFTestFinishPendingBrowserClose(MiumCEFBridgeTestCloseKind kind) {
  miumCEFFinishPendingBrowserClose(
    kind == MiumCEFBridgeTestCloseKind::replacement
      ? MiumCEFNativeBrowserCloseKind::replacement
      : MiumCEFNativeBrowserCloseKind::teardown
  );
}

size_t miumNativeCEFTestPendingNativeBrowserCloseCount(void) {
  CefStateLockGuard lock;
  return miumCEFPendingNativeBrowserCloseCountLocked();
}

size_t miumNativeCEFTestPendingTeardownBrowserCloseCount(void) {
  CefStateLockGuard lock;
  return gPendingTeardownBrowserCloseCount;
}

size_t miumNativeCEFTestPendingReplacementBrowserCloseCount(void) {
  CefStateLockGuard lock;
  return gPendingReplacementBrowserCloseCount;
}

void miumNativeCEFTestPumpPendingShutdownMessageLoop(void) {
  miumCEFPumpPendingShutdownMessageLoop();
}

void miumNativeCEFTestSchedulePendingShutdownPumpIfNeeded(void) {
  miumCEFSchedulePendingShutdownPumpIfNeeded();
}

void miumNativeCEFTestClearCallbackPayloadsForBrowser(uint64_t browserId) {
  clearNativeCallbackPayloadsForBrowser(browserId);
}

void miumNativeCEFTestClearCallbackPayloadsForBrowsers(const std::vector<uint64_t>& browserIds) {
  const std::unordered_set<uint64_t> ids(browserIds.begin(), browserIds.end());
  clearNativeCallbackPayloadsForBrowsers(ids);
}

void miumNativeCEFTestSetShutdownState(bool shutdownPending, bool pumpScheduled) {
  CefStateLockGuard lock;
  gCEFShutdownPending = shutdownPending;
  gPendingShutdownPumpScheduled = pumpScheduled;
}

bool miumNativeCEFTestIsShutdownPumpScheduled(void) {
  CefStateLockGuard lock;
  return gPendingShutdownPumpScheduled;
}

#endif
