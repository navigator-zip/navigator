#include "MiumCEFBridgeBrowserRegistry.h"
#include "MiumCEFBridgeInternalAdapters.h"
#include "MiumCEFBridgeInternalRuntimeExecutionSupport.h"
#include "MiumCEFBridgeThreading.h"
#include "Tracing.h"

// Global CEF lifetime invariants:
// - subprocess entry uses a dedicated subprocess `cef_app_t` wrapper.
// - browser-process preflight still calls `cef_execute_process(..., nullptr, nullptr)`.
// - browser-process initialization may use an app wrapper when external message pump mode is enabled.
// - `gCEFInitializeCount` tracks active runtime handles, not whether CEF work is still draining.
// - final shutdown waits for both teardown closes and replacement closes to finish polling.
CefApi gCefApi;
std::mutex gStateLock;
std::mutex gFrameworkLoadLock;
std::condition_variable gStateCondition;
bool gCEFInitializing = false;
bool gCEFShutdownExecuting = false;
thread_local int gStateLockDepth = 0;
bool gFrameworkLoaded = false;
bool gCEFInitialized = false;
bool gCEFShutdownPending = false;
bool gPendingShutdownPumpScheduled = false;
bool gExternalMessagePumpEnabled = false;
MiumCEFRuntimeShutdownState gRuntimeShutdownState = MiumCEFRuntimeShutdownState::uninitialized;
int gCEFInitializeCount = 0;
size_t gPendingTeardownBrowserCloseCount = 0;
size_t gPendingReplacementBrowserCloseCount = 0;
uint64_t gNextRuntimeId = 1;
uint64_t gNextBrowserId = 1;
uint64_t gNextHostViewId = 1;
uint64_t gNextExternalMessagePumpScheduleId = 0;
uint64_t gActiveExternalMessagePumpScheduleId = 0;
uint64_t gLastPerformedMessagePumpSequence = 0;
CFAbsoluteTime gLastPerformedMessagePumpTime = 0.0;
uint64_t gNextRendererJavaScriptRequestId = 1;
cef_app_t* gBrowserProcessApp = nullptr;
std::unordered_map<uint64_t, std::unique_ptr<MiumCEFRuntimeState>> gRuntimes;
std::unordered_map<uint64_t, std::unique_ptr<MiumCEFBrowserState>> gBrowsers;
std::unordered_map<uint64_t, std::unique_ptr<MiumCEFHostViewState>> gHostViews;
std::unordered_map<cef_browser_t*, uint64_t> gBrowserIdByNativeBrowser;
std::unordered_map<int64_t, uint64_t> gBrowserIdByNativeBrowserIdentifier;
std::unordered_map<uint64_t, MiumCEFRendererJavaScriptRequestState> gRendererJavaScriptRequests;

static void assertHostViewStateConsistencyLocked(const MiumCEFHostViewState* hostViewState) {
#if !defined(NDEBUG)
  if (hostViewState == nullptr) {
    return;
  }

  if (hostViewState->browserId == 0) {
    return;
  }

  auto browserIter = gBrowsers.find(hostViewState->browserId);
  assert(browserIter != gBrowsers.end());
  assert(browserIter->second != nullptr);
  assert(browserIter->second->active);
  assert(browserIter->second->hostViewId == hostViewState->id);
  assert(browserIter->second->hostViewBound);
#else
  (void)hostViewState;
#endif
}

void assertBrowserStateConsistencyLocked(const MiumCEFBrowserState* browserState) {
#if !defined(NDEBUG)
  if (browserState == nullptr) {
    return;
  }

  assert(!browserState->hostViewBound || browserState->hostViewId != 0);
  assert(browserState->hostViewId != 0 || !browserState->attached);
  assert(!browserState->hostViewBound || browserState->attached);
  assert(!browserState->closing || !browserState->active);
  if (browserState->hostViewBound) {
    auto hostIter = gHostViews.find(browserState->hostViewId);
    if (hostIter != gHostViews.end()) {
      assert(hostIter->second != nullptr);
      assert(hostIter->second->active);
      assert(hostIter->second->browserId == browserState->id);
    }
  }
  if (browserState->nativeBrowser.get() != nullptr) {
    auto mappingIter = gBrowserIdByNativeBrowser.find(browserState->nativeBrowser.get());
    assert(mappingIter != gBrowserIdByNativeBrowser.end());
    assert(mappingIter->second == browserState->id);
    const int64_t nativeIdentifier =
      miumCEFBrowserIdentifierFromNativeBrowser(browserState->nativeBrowser.get());
    if (nativeIdentifier >= 0) {
      auto identifierIter = gBrowserIdByNativeBrowserIdentifier.find(nativeIdentifier);
      if (identifierIter != gBrowserIdByNativeBrowserIdentifier.end()) {
        assert(identifierIter->second == browserState->id);
      }
    }
  }
#else
  (void)browserState;
#endif
}

// Requires gStateLock to be held.
MiumCEFBrowserState* activeBrowserStateLocked(uint64_t browserId) {
  auto browserIter = gBrowsers.find(browserId);
  if (browserIter == gBrowsers.end() || browserIter->second == nullptr || !browserIter->second->active) {
    return nullptr;
  }
  assertBrowserStateConsistencyLocked(browserIter->second.get());
  return browserIter->second.get();
}

MiumCEFHostViewState* activeHostViewStateLocked(uint64_t hostViewId) {
  auto hostIter = gHostViews.find(hostViewId);
  if (hostIter == gHostViews.end() || hostIter->second == nullptr || !hostIter->second->active) {
    return nullptr;
  }
  assertHostViewStateConsistencyLocked(hostIter->second.get());
  return hostIter->second.get();
}

MiumCEFHostResourceState* ensureHostResources(MiumCEFHostViewState* hostViewState) {
  if (hostViewState == nullptr) {
    return nil;
  }
  if (hostViewState->resources == nil) {
    hostViewState->resources = [[MiumCEFHostResourceState alloc] init];
  }
  return hostViewState->resources;
}

NSView* resolvedHostViewForState(MiumCEFHostViewState* hostViewState) {
  return hostViewState == nullptr || hostViewState->resources == nil ? nil : hostViewState->resources.hostView;
}

MiumBrowserContainerView* resolvedContainerViewForState(MiumCEFHostViewState* hostViewState) {
  return hostViewState == nullptr || hostViewState->resources == nil
    ? nil
    : hostViewState->resources.containerView;
}

MiumCEFHostViewState* activeHostViewStateForViewLocked(NSView* hostView) {
  if (hostView == nil) {
    return nullptr;
  }

  for (auto& hostPair : gHostViews) {
    auto* hostViewState = hostPair.second.get();
    if (hostViewState == nullptr || !hostViewState->active) {
      continue;
    }
    if (resolvedHostViewForState(hostViewState) == hostView) {
      return hostViewState;
    }
  }
  return nullptr;
}

bool shouldTrackBrowserForNativeCallbacksLocked(const MiumCEFBrowserState* browserState) {
  return browserState != nullptr && browserState->active;
}

// Requires gStateLock to be held.
static void clearHostViewBindingsForBrowserLocked(uint64_t browserId, uint64_t exceptHostViewId = 0) {
  for (auto& hostPair : gHostViews) {
    auto* hostViewState = hostPair.second.get();
    if (hostPair.first == exceptHostViewId || hostViewState == nullptr || hostViewState->browserId != browserId) {
      continue;
    }
    hostViewState->browserId = 0;
  }
}

// Requires gStateLock to be held.
bool canBindBrowserToHostViewLocked(
  const MiumCEFBrowserState* browserState,
  uint64_t hostViewId,
  void* hostView
) {
  if (browserState == nullptr || hostViewId == 0 || hostView == nullptr) {
    return false;
  }

  auto hostIter = gHostViews.find(hostViewId);
  if (hostIter == gHostViews.end() || hostIter->second == nullptr || !hostIter->second->active) {
    return false;
  }

  auto* hostViewState = hostIter->second.get();
  return (__bridge void*)resolvedHostViewForState(hostViewState) == hostView
    && (hostViewState->browserId == 0 || hostViewState->browserId == browserState->id);
}

// Requires gStateLock to be held.
bool bindBrowserToHostViewLocked(
  MiumCEFBrowserState* browserState,
  uint64_t hostViewId,
  void* hostView
) {
  if (!canBindBrowserToHostViewLocked(browserState, hostViewId, hostView)) {
    return false;
  }

  auto hostIter = gHostViews.find(hostViewId);
  clearHostViewBindingsForBrowserLocked(browserState->id, hostViewId);
  hostIter->second->browserId = browserState->id;
  browserState->hostViewId = hostViewId;
  browserState->attached = true;
  browserState->hostViewBound = true;
  miumCefTrace(
    "browser-registry",
    "HostView bind browserId=%llu hostViewId=%llu hostView=%p lane=%s\n",
    static_cast<unsigned long long>(browserState->id),
    static_cast<unsigned long long>(hostViewId),
    hostView,
    miumCEFThreadLaneLabel()
  );
  assertBrowserStateConsistencyLocked(browserState);
  return true;
}

bool installNativeBrowserForHostViewLocked(
  uint64_t browserId,
  uint64_t hostViewId,
  void* hostView,
  cef_browser_t* createdBrowser,
  cef_client_t* createdClient,
  bool* releaseCreated,
  bool* shouldReplaceManagedSubviews,
  cef_browser_t** browserToClose,
  cef_client_t** browserToCloseClient
) {
  if (releaseCreated != nullptr) {
    *releaseCreated = true;
  }
  if (shouldReplaceManagedSubviews != nullptr) {
    *shouldReplaceManagedSubviews = false;
  }
  if (browserToClose != nullptr) {
    *browserToClose = nullptr;
  }
  if (browserToCloseClient != nullptr) {
    *browserToCloseClient = nullptr;
  }

  auto* browserState = activeBrowserStateLocked(browserId);
  if (browserState == nullptr || !miumCEFIsCefRuntimeUsableLocked()) {
    return false;
  }

  const bool targetHostBinding = hostView != nullptr;
  if (targetHostBinding && !canBindBrowserToHostViewLocked(browserState, hostViewId, hostView)) {
    return false;
  }

  if (browserState->nativeBrowser == nullptr) {
    const bool boundToHostView = !targetHostBinding
      || bindBrowserToHostViewLocked(browserState, hostViewId, hostView);
    if (!boundToHostView) {
      return false;
    }
    browserState->nativeBrowser = CefRef<cef_browser_t>::adopt(createdBrowser);
    browserState->nativeClient = CefRef<cef_client_t>::adopt(createdClient);
    browserState->generation += 1;
    bindNativeBrowserIdForBrowser(browserId, nullptr, createdBrowser);
    miumCefTrace(
      "browser-registry",
      "installNativeBrowser initial browserId=%llu browser=%p client=%p generation=%llu\n",
      static_cast<unsigned long long>(browserId),
      static_cast<void*>(createdBrowser),
      static_cast<void*>(createdClient),
      static_cast<unsigned long long>(browserState->generation)
    );
    if (releaseCreated != nullptr) {
      *releaseCreated = false;
    }
    return true;
  }

  if (targetHostBinding && (!browserState->hostViewBound || browserState->hostViewId != hostViewId)) {
    const bool boundToHostView = bindBrowserToHostViewLocked(browserState, hostViewId, hostView);
    if (!boundToHostView) {
      return false;
    }
    if (browserToClose != nullptr) {
      *browserToClose = browserState->nativeBrowser.leak();
    } else {
      browserState->nativeBrowser.reset();
    }
    if (browserToCloseClient != nullptr) {
      *browserToCloseClient = browserState->nativeClient.leak();
    } else {
      browserState->nativeClient.reset();
    }
    registerPendingBrowserCloseLocked(MiumCEFNativeBrowserCloseKind::replacement);
    browserState->nativeBrowser = CefRef<cef_browser_t>::adopt(createdBrowser);
    browserState->nativeClient = CefRef<cef_client_t>::adopt(createdClient);
    browserState->generation += 1;
    bindNativeBrowserIdForBrowser(browserId, browserToClose == nullptr ? nullptr : *browserToClose, createdBrowser);
    miumCefTrace(
      "browser-registry",
      "installNativeBrowser replacement browserId=%llu browser=%p client=%p oldBrowser=%p generation=%llu\n",
      static_cast<unsigned long long>(browserId),
      static_cast<void*>(createdBrowser),
      static_cast<void*>(createdClient),
      browserToClose == nullptr ? nullptr : static_cast<void*>(*browserToClose),
      static_cast<unsigned long long>(browserState->generation)
    );
    if (releaseCreated != nullptr) {
      *releaseCreated = false;
    }
    if (shouldReplaceManagedSubviews != nullptr) {
      *shouldReplaceManagedSubviews = true;
    }
    return true;
  }

  return !targetHostBinding || bindBrowserToHostViewLocked(browserState, hostViewId, hostView);
}

// Requires gStateLock to be held.
void clearBrowserHostViewBindingLocked(MiumCEFBrowserState* browserState) {
  if (browserState == nullptr) {
    return;
  }
  miumCefTrace(
    "browser-registry",
    "HostView clear browserId=%llu hostViewId=%llu lane=%s\n",
    static_cast<unsigned long long>(browserState == nullptr ? 0 : browserState->id),
    static_cast<unsigned long long>(browserState == nullptr ? 0 : browserState->hostViewId),
    miumCEFThreadLaneLabel()
  );
  clearHostViewBindingsForBrowserLocked(browserState->id);
  browserState->hostViewId = 0;
  browserState->attached = false;
  browserState->hostViewBound = false;
  assertBrowserStateConsistencyLocked(browserState);
}

MiumCEFHostViewHandle currentHostViewHandleForBrowserLocked(uint64_t browserId) {
  auto* browserState = activeBrowserStateLocked(browserId);
  if (browserState == nullptr || browserState->hostViewId == 0) {
    return nullptr;
  }
  auto hostIter = gHostViews.find(browserState->hostViewId);
  if (hostIter == gHostViews.end() || hostIter->second == nullptr || !hostIter->second->active) {
    return nullptr;
  }
  return static_cast<MiumCEFHostViewHandle>(miumCEFIdToHandle(browserState->hostViewId));
}

bool snapshotNativeCallbackPayloadDeliverable(
  uint64_t browserId,
  const char* channel,
  uint64_t handlerGeneration
) {
  if (browserId == 0) {
    return true;
  }

  CefStateLockGuard lock;
  auto browserIter = gBrowsers.find(browserId);
  if (browserIter == gBrowsers.end() || !shouldTrackBrowserForNativeCallbacksLocked(browserIter->second.get())) {
    return false;
  }
  if (channel == nullptr || channel[0] == '\0' || handlerGeneration == 0) {
    return true;
  }

  auto handlerIter = browserIter->second->handlers.find(channel);
  return handlerIter != browserIter->second->handlers.end()
    && handlerIter->second.callback != nullptr
    && handlerIter->second.registration != nullptr
    && handlerIter->second.registration->active.load(std::memory_order_acquire)
    && handlerIter->second.generation == handlerGeneration;
}

uint64_t browserIdFromNativeBrowser(cef_browser_t* browser) {
  if (browser == nullptr) {
    return 0;
  }

  const int64_t browserIdentifier = miumCEFBrowserIdentifierFromNativeBrowser(browser);

  CefStateLockGuard lock;
  if (browserIdentifier >= 0) {
    auto identifierIter = gBrowserIdByNativeBrowserIdentifier.find(browserIdentifier);
    if (identifierIter != gBrowserIdByNativeBrowserIdentifier.end()) {
      const uint64_t browserId = identifierIter->second;
      auto browserIter = gBrowsers.find(browserId);
      if (browserIter != gBrowsers.end() && shouldTrackBrowserForNativeCallbacksLocked(browserIter->second.get())) {
        if (browserIter->second->closing) {
          miumCefTrace(
            "browser-registry",
            "Late callback by identifier while closing browserId=%llu native=%p identifier=%lld lane=%s\n",
            static_cast<unsigned long long>(browserId),
            static_cast<void*>(browser),
            static_cast<long long>(browserIdentifier),
            miumCEFThreadLaneLabel()
          );
        }
        return browserId;
      }
    }
  }

  auto nativeIter = gBrowserIdByNativeBrowser.find(browser);
  if (nativeIter != gBrowserIdByNativeBrowser.end()) {
    const uint64_t browserId = nativeIter->second;
    auto browserIter = gBrowsers.find(browserId);
    if (browserIter != gBrowsers.end() && shouldTrackBrowserForNativeCallbacksLocked(browserIter->second.get())) {
      if (browserIter->second->closing) {
        miumCefTrace(
          "browser-registry",
          "Late callback by pointer while closing browserId=%llu native=%p lane=%s\n",
          static_cast<unsigned long long>(browserId),
          static_cast<void*>(browser),
          miumCEFThreadLaneLabel()
        );
      }
      return browserId;
    }
  }

  for (const auto& browserPair : gBrowsers) {
    auto* state = browserPair.second.get();
    if (shouldTrackBrowserForNativeCallbacksLocked(state) && state->nativeBrowser.get() == browser) {
      return browserPair.first;
    }
  }
  return 0;
}

static void clearNativeBrowserMappingsForBrowserLocked(uint64_t browserId) {
  miumCefTrace(
    "browser-registry",
    "BrowserMapping clear browserId=%llu lane=%s\n",
    static_cast<unsigned long long>(browserId),
    miumCEFThreadLaneLabel()
  );
  for (auto nativeIter = gBrowserIdByNativeBrowser.begin(); nativeIter != gBrowserIdByNativeBrowser.end();) {
    if (nativeIter->second == browserId) {
      nativeIter = gBrowserIdByNativeBrowser.erase(nativeIter);
      continue;
    }
    ++nativeIter;
  }

  for (auto identifierIter = gBrowserIdByNativeBrowserIdentifier.begin();
       identifierIter != gBrowserIdByNativeBrowserIdentifier.end();) {
    if (identifierIter->second == browserId) {
      identifierIter = gBrowserIdByNativeBrowserIdentifier.erase(identifierIter);
      continue;
    }
    ++identifierIter;
  }
}

void bindNativeBrowserIdForBrowser(uint64_t browserId, cef_browser_t* previousNative, cef_browser_t* nextNative) {
  if (previousNative == nextNative && nextNative != nullptr) {
    return;
  }

  miumCefTrace(
    "browser-registry",
    "BrowserMapping bind browserId=%llu previous=%p next=%p lane=%s\n",
    static_cast<unsigned long long>(browserId),
    static_cast<void*>(previousNative),
    static_cast<void*>(nextNative),
    miumCEFThreadLaneLabel()
  );
  clearNativeBrowserMappingsForBrowserLocked(browserId);

  if (nextNative == nullptr) {
#if !defined(NDEBUG)
    auto browserIter = gBrowsers.find(browserId);
    if (browserIter != gBrowsers.end() && browserIter->second != nullptr) {
      assertBrowserStateConsistencyLocked(browserIter->second.get());
    }
#endif
    return;
  }

  gBrowserIdByNativeBrowser[nextNative] = browserId;
  const int64_t nextBrowserId = miumCEFBrowserIdentifierFromNativeBrowser(nextNative);
  if (nextBrowserId >= 0) {
    gBrowserIdByNativeBrowserIdentifier[nextBrowserId] = browserId;
    miumCefTrace(
      "browser-registry",
      "BrowserMapping identifier browserId=%llu nativeIdentifier=%lld lane=%s\n",
      static_cast<unsigned long long>(browserId),
      static_cast<long long>(nextBrowserId),
      miumCEFThreadLaneLabel()
    );
  }

#if !defined(NDEBUG)
  auto browserIter = gBrowsers.find(browserId);
  if (browserIter != gBrowsers.end() && browserIter->second != nullptr) {
    assertBrowserStateConsistencyLocked(browserIter->second.get());
  }
#endif
}

void registerPendingBrowserCloseLocked(MiumCEFNativeBrowserCloseKind kind) {
  switch (kind) {
    case MiumCEFNativeBrowserCloseKind::teardown:
      gPendingTeardownBrowserCloseCount += 1;
      break;
    case MiumCEFNativeBrowserCloseKind::replacement:
      gPendingReplacementBrowserCloseCount += 1;
      break;
  }
}

// Requires gStateLock to be held.
bool detachNativeBrowserForReplacementLocked(
  MiumCEFBrowserState* browserState,
  cef_browser_t** outBrowser,
  cef_client_t** outClient
) {
  if (outBrowser != nullptr) {
    *outBrowser = nullptr;
  }
  if (outClient != nullptr) {
    *outClient = nullptr;
  }
  if (browserState == nullptr) {
    return false;
  }

  clearBrowserHostViewBindingLocked(browserState);
  if (browserState->nativeBrowser == nullptr) {
    return true;
  }

  if (outBrowser != nullptr) {
    *outBrowser = browserState->nativeBrowser.leak();
  } else {
    browserState->nativeBrowser.reset();
  }
  if (outClient != nullptr) {
    *outClient = browserState->nativeClient.leak();
  } else {
    browserState->nativeClient.reset();
  }

  registerPendingBrowserCloseLocked(MiumCEFNativeBrowserCloseKind::replacement);
  clearNativeBrowserMappingsForBrowserLocked(browserState->id);
  return true;
}

// Requires gStateLock to be held.
// Ownership contract:
// - `failed`: no browser/client refs are returned.
// - `completedSynchronously`: browser state is removed inline and no browser/client refs are returned.
// - `closePending`: retained browser/client refs are returned via `outBrowser` / `outClient` when requested,
//   and the caller becomes responsible for closing or releasing them.
MiumCEFBrowserCloseDisposition beginClosingNativeBrowserForIdLocked(
  uint64_t browserId,
  cef_browser_t** outBrowser,
  cef_client_t** outClient,
  uint64_t* outRuntimeId,
  bool trackRuntimePendingClose
) {
  if (outBrowser != nullptr) {
    *outBrowser = nullptr;
  }
  if (outClient != nullptr) {
    *outClient = nullptr;
  }
  if (outRuntimeId != nullptr) {
    *outRuntimeId = 0;
  }

  auto browserIter = gBrowsers.find(browserId);
  if (browserIter == gBrowsers.end()) {
    return MiumCEFBrowserCloseDisposition::failed;
  }

  auto& browser = browserIter->second;
  if (browser == nullptr || !browser->active || browser->closing) {
    return MiumCEFBrowserCloseDisposition::failed;
  }

  const uint64_t runtimeId = browser->runtimeId;
  if (outRuntimeId != nullptr) {
    *outRuntimeId = runtimeId;
  }

  browser->active = false;
  clearBrowserHostViewBindingLocked(browser.get());

  auto runtimeIter = gRuntimes.find(runtimeId);
  if (runtimeIter != gRuntimes.end()) {
    runtimeIter->second->browserIds.erase(browserId);
  }

  if (browser->nativeBrowser == nullptr) {
    (void)miumCEFTakeRendererJavaScriptRequestsForBrowserLocked(browserId);
    clearNativeBrowserMappingsForBrowserLocked(browserId);
    browser->nativeClient.reset();
    browser->runtimeId = 0;
    gBrowsers.erase(browserIter);
    miumCEFPermissionUnregisterBrowser(browserId);
    return MiumCEFBrowserCloseDisposition::completedSynchronously;
  }

  if (outBrowser != nullptr) {
    *outBrowser = browser->nativeBrowser.leak();
  } else {
    browser->nativeBrowser.reset();
  }
  if (outClient != nullptr) {
    *outClient = browser->nativeClient.leak();
  } else {
    browser->nativeClient.reset();
  }
  browser->closing = true;
  if (trackRuntimePendingClose) {
    auto trackedRuntimeIter = gRuntimes.find(runtimeId);
    if (trackedRuntimeIter != gRuntimes.end()) {
      trackedRuntimeIter->second->pendingBrowserCloseCount += 1;
    }
  }
  registerPendingBrowserCloseLocked(MiumCEFNativeBrowserCloseKind::teardown);
  return MiumCEFBrowserCloseDisposition::closePending;
}

void finalizeClosedBrowserState(uint64_t browserId, uint64_t runtimeId) {
  miumCefTrace(
    "browser-registry",
    "closeBrowser finalize browserId=%llu runtimeId=%llu lane=%s\n",
    static_cast<unsigned long long>(browserId),
    static_cast<unsigned long long>(runtimeId),
    miumCEFThreadLaneLabel()
  );
  bool removedBrowserState = false;
  {
    CefStateLockGuard lock;

    auto browserIter = gBrowsers.find(browserId);
    if (browserIter != gBrowsers.end()) {
      auto& browser = browserIter->second;
      clearNativeBrowserMappingsForBrowserLocked(browserId);
      clearHostViewBindingsForBrowserLocked(browserId);
      browser->nativeBrowser = nullptr;
      browser->nativeClient = nullptr;
      browser->runtimeId = 0;
      browser->hostViewId = 0;
      browser->closing = false;
      browser->attached = false;
      browser->hostViewBound = false;
      gBrowsers.erase(browserIter);
      removedBrowserState = true;
    }

    auto runtimeIter = gRuntimes.find(runtimeId);
    if (runtimeIter == gRuntimes.end()) {
      return;
    }

    if (runtimeIter->second->pendingBrowserCloseCount > 0) {
      runtimeIter->second->pendingBrowserCloseCount -= 1;
    }

    if (!runtimeIter->second->active
        && runtimeIter->second->pendingBrowserCloseCount == 0
        && runtimeIter->second->browserIds.empty()) {
      gRuntimes.erase(runtimeIter);
    }
  }

  if (removedBrowserState) {
    miumCEFFailRendererJavaScriptRequestsForBrowser(
      browserId,
      "Browser closed before renderer JavaScript completed",
      true
    );
    miumCEFPermissionUnregisterBrowser(browserId);
  }
}
