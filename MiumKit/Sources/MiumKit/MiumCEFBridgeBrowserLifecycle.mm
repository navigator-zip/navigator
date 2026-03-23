#include "MiumCEFBridgeBrowserRegistry.h"
#include "MiumCEFBridgeCallbackQueue.h"
#include "MiumCEFBridgeHostView.h"
#include "MiumCEFBridgeInternalAdapters.h"
#include "MiumCEFBridgeInternalPermissionAdapters.h"
#include "MiumCEFBridgeInternalRuntimeExecutionSupport.h"
#include "MiumCEFBridgeInternalState.h"
#include "MiumCEFBridgeNative.h"
#include "MiumCEFBridgePermissions.h"

namespace {

template <typename Map>
uint64_t nextIdFromMap(uint64_t& nextId, const Map& map) {
  while (nextId == 0 || map.find(nextId) != map.end()) {
    ++nextId;
  }
  return nextId++;
}

}  // namespace

extern "C" MiumCEFResultCode miumNativeCEFCreateBrowser(
  MiumCEFRuntimeHandle runtimeHandle,
  MiumCEFBrowserHandle* outBrowserHandle
) {
  if (runtimeHandle == nullptr || outBrowserHandle == nullptr) {
    return MiumCEFResultInvalidArgument;
  }
  *outBrowserHandle = nullptr;

  const uint64_t runtimeId = miumCEFNativeHandleToId(runtimeHandle);
  uint64_t browserId = 0;

  {
    CefStateLockGuard lock;
    auto runtimeIter = gRuntimes.find(runtimeId);
    if (runtimeIter == gRuntimes.end() || !runtimeIter->second->active) {
      return MiumCEFResultNotInitialized;
    }

    auto browser = std::make_unique<MiumCEFBrowserState>();
    browserId = nextIdFromMap(gNextBrowserId, gBrowsers);
    browser->id = browserId;
    browser->runtimeId = runtimeId;

    gBrowsers[browserId] = std::move(browser);
    runtimeIter->second->browserIds.insert(browserId);
  }
  miumCEFPermissionRegisterBrowser(browserId);
  *outBrowserHandle = static_cast<MiumCEFBrowserHandle>(miumCEFIdToHandle(browserId));
  return MiumCEFResultOK;
}

extern "C" MiumCEFResultCode miumNativeCEFDestroyBrowser(MiumCEFBrowserHandle browserHandle) {
  if (browserHandle == nullptr) {
    return MiumCEFResultInvalidArgument;
  }

  const uint64_t browserId = miumCEFNativeHandleToId(browserHandle);
  NSView* retainedBoundHostView = nil;
  uint64_t runtimeId = 0;
  cef_browser_t* nativeBrowser = nullptr;
  cef_client_t* nativeClient = nullptr;
  MiumCEFBrowserCloseDisposition closeDisposition = MiumCEFBrowserCloseDisposition::failed;

  std::vector<MiumCEFPermissionExecutionBatch> permissionBatches;
  miumCEFPermissionTakeBrowserDismissalBatches(
    browserId,
    MiumCEFPermissionSessionDismissReason::browserClosed,
    true,
    &permissionBatches
  );
  miumCEFNativeExecutePermissionBatchesOnCefMainThread(std::move(permissionBatches));

  {
    CefStateLockGuard lock;
    auto browserIter = gBrowsers.find(browserId);
    if (browserIter == gBrowsers.end() || !browserIter->second->active) {
      return MiumCEFResultNotInitialized;
    }

    if (browserIter->second->hostViewBound && browserIter->second->hostViewId != 0) {
      auto hostIter = gHostViews.find(browserIter->second->hostViewId);
      if (hostIter != gHostViews.end() && hostIter->second != nullptr && hostIter->second->active) {
        retainedBoundHostView = resolvedHostViewForState(hostIter->second.get());
      }
    }

    closeDisposition = beginClosingNativeBrowserForIdLocked(
      browserId,
      &nativeBrowser,
      &nativeClient,
      &runtimeId
    );
  }

  assert(closeDisposition != MiumCEFBrowserCloseDisposition::failed);
  assert(closeDisposition != MiumCEFBrowserCloseDisposition::completedSynchronously || nativeBrowser == nullptr);
  assert(closeDisposition != MiumCEFBrowserCloseDisposition::completedSynchronously || nativeClient == nullptr);

  if (retainedBoundHostView != nil) {
    miumCEFNativeRunOnCefMainThread([retainedBoundHostView] {
      removeManagedBrowserSubviewsForHostView(retainedBoundHostView);
    });
  }
  if (closeDisposition == MiumCEFBrowserCloseDisposition::closePending) {
    miumCEFNativeCloseBrowser(
      nativeBrowser,
      nativeClient,
      MiumCEFNativeBrowserCloseKind::teardown,
      true,
      retainedBoundHostView,
      [browserId, runtimeId] {
        finalizeClosedBrowserState(browserId, runtimeId);
      }
    );
  }

  clearNativeCallbackPayloadsForBrowser(browserId);
  return MiumCEFResultOK;
}

extern "C" MiumCEFResultCode miumNativeCEFCreateBrowserHostView(
  MiumCEFBrowserHandle browserHandle,
  MiumCEFHostViewHandle* outHostViewHandle
) {
  if (browserHandle == nullptr || outHostViewHandle == nullptr) {
    return MiumCEFResultInvalidArgument;
  }
  *outHostViewHandle = nullptr;

  const uint64_t browserId = miumCEFNativeHandleToId(browserHandle);
  CefStateLockGuard lock;

  auto browserIter = gBrowsers.find(browserId);
  if (browserIter == gBrowsers.end() || !browserIter->second->active) {
    return MiumCEFResultNotInitialized;
  }

  auto hostView = std::make_unique<MiumCEFHostViewState>();
  const uint64_t hostViewId = nextIdFromMap(gNextHostViewId, gHostViews);
  hostView->id = hostViewId;
  gHostViews[hostViewId] = std::move(hostView);

  *outHostViewHandle = static_cast<MiumCEFHostViewHandle>(miumCEFIdToHandle(hostViewId));
  return MiumCEFResultOK;
}

extern "C" MiumCEFResultCode miumNativeCEFCreateBrowserHostViewForNSView(
  MiumCEFBrowserHandle browserHandle,
  void* hostView,
  MiumCEFHostViewHandle* outHostViewHandle
) {
  if (outHostViewHandle != nullptr) {
    *outHostViewHandle = nullptr;
  }
  if (hostView == nullptr) {
    return MiumCEFResultInvalidArgument;
  }

  const MiumCEFResultCode createResult = miumNativeCEFCreateBrowserHostView(browserHandle, outHostViewHandle);
  if (createResult != MiumCEFResultOK) {
    return createResult;
  }

  const uint64_t hostViewId = miumCEFNativeHandleToId(*outHostViewHandle);
  {
    CefStateLockGuard lock;
    auto hostIter = gHostViews.find(hostViewId);
    if (hostIter != gHostViews.end() && hostIter->second->active) {
      ensureHostResources(hostIter->second.get()).hostView = (__bridge NSView*)hostView;
    }
  }

  if (!ensureNativeBrowser(miumCEFNativeHandleToId(browserHandle), hostViewId, hostView)) {
    bool runtimeUsable = false;
    {
      CefStateLockGuard lock;
      runtimeUsable = miumCEFIsCefRuntimeUsableLocked();
    }
    const MiumCEFResultCode destroyResult = miumNativeCEFDestroyBrowserHostView(*outHostViewHandle);
    *outHostViewHandle = nullptr;
    if (!runtimeUsable || destroyResult == MiumCEFResultNotInitialized) {
      return MiumCEFResultNotInitialized;
    }
    return MiumCEFResultError;
  }

  return MiumCEFResultOK;
}

extern "C" MiumCEFResultCode miumNativeCEFDestroyBrowserHostView(MiumCEFHostViewHandle hostViewHandle) {
  if (hostViewHandle == nullptr) {
    return MiumCEFResultInvalidArgument;
  }

  const uint64_t hostViewId = miumCEFNativeHandleToId(hostViewHandle);
  void* hostView = nullptr;

  {
    CefStateLockGuard lock;
    auto hostIter = gHostViews.find(hostViewId);
    if (hostIter == gHostViews.end() || !hostIter->second->active) {
      return MiumCEFResultNotInitialized;
    }
    hostView = (__bridge void*)resolvedHostViewForState(hostIter->second.get());

    if (hostIter->second->browserId != 0) {
      auto browserIter = gBrowsers.find(hostIter->second->browserId);
      if (browserIter != gBrowsers.end() && browserIter->second != nullptr && browserIter->second->hostViewId == hostViewId) {
        clearBrowserHostViewBindingLocked(browserIter->second.get());
      }
    }

    gHostViews.erase(hostIter);
  }
  miumCEFNativeRunOnCefMainThread([hostView] {
    removeManagedBrowserSubviewsForHostView((__bridge NSView*)hostView);
  });
  return MiumCEFResultOK;
}

extern "C" MiumCEFResultCode miumNativeCEFAttachBrowserToHostView(
  MiumCEFBrowserHandle browserHandle,
  MiumCEFHostViewHandle hostViewHandle
) {
  if (browserHandle == nullptr || hostViewHandle == nullptr) {
    return MiumCEFResultInvalidArgument;
  }

  const uint64_t browserId = miumCEFNativeHandleToId(browserHandle);
  const uint64_t hostViewId = miumCEFNativeHandleToId(hostViewHandle);
  void* hostView = nullptr;

  {
    CefStateLockGuard lock;
    auto browserIter = gBrowsers.find(browserId);
    auto hostIter = gHostViews.find(hostViewId);
    if (browserIter == gBrowsers.end() || !browserIter->second->active ||
        hostIter == gHostViews.end() || !hostIter->second->active) {
      return MiumCEFResultNotInitialized;
    }
    hostView = (__bridge void*)resolvedHostViewForState(hostIter->second.get());
  }
  if (hostView == nullptr) {
    return MiumCEFResultInvalidArgument;
  }

  if (!ensureNativeBrowser(browserId, hostViewId, hostView)) {
    CefStateLockGuard lock;
    auto* browserState = activeBrowserStateLocked(browserId);
    auto hostIter = gHostViews.find(hostViewId);
    if (!miumCEFIsCefRuntimeUsableLocked() ||
        browserState == nullptr ||
        hostIter == gHostViews.end() ||
        hostIter->second == nullptr ||
        !hostIter->second->active ||
        (__bridge void*)resolvedHostViewForState(hostIter->second.get()) != hostView) {
      return MiumCEFResultNotInitialized;
    }
    return MiumCEFResultError;
  }

  return MiumCEFResultOK;
}

extern "C" MiumCEFResultCode miumNativeCEFDetachBrowserFromHostView(MiumCEFBrowserHandle browserHandle) {
  if (browserHandle == nullptr) {
    return MiumCEFResultInvalidArgument;
  }

  const uint64_t browserId = miumCEFNativeHandleToId(browserHandle);
  void* hostView = nullptr;
  cef_browser_t* detachedBrowser = nullptr;
  cef_client_t* detachedClient = nullptr;
  {
    CefStateLockGuard lock;
    auto browserIter = gBrowsers.find(browserId);
    if (browserIter == gBrowsers.end() || !browserIter->second->active) {
      return MiumCEFResultNotInitialized;
    }
    if (browserIter->second->hostViewBound && browserIter->second->hostViewId != 0) {
      auto hostIter = gHostViews.find(browserIter->second->hostViewId);
      if (hostIter != gHostViews.end() && hostIter->second != nullptr && hostIter->second->active) {
        hostView = (__bridge void*)resolvedHostViewForState(hostIter->second.get());
      }
    }
    if (!detachNativeBrowserForReplacementLocked(browserIter->second.get(), &detachedBrowser, &detachedClient)) {
      return MiumCEFResultNotInitialized;
    }
  }
  clearNativeCallbackPayloadsForBrowser(browserId);
  if (hostView != nullptr) {
    miumCEFNativeRunOnCefMainThread([hostView] {
      removeManagedBrowserSubviewsForHostView((__bridge NSView*)hostView);
    });
  }
  if (detachedBrowser != nullptr) {
    miumCEFNativeCloseBrowser(
      detachedBrowser,
      detachedClient,
      MiumCEFNativeBrowserCloseKind::replacement,
      true,
      nil
    );
  }
  return MiumCEFResultOK;
}
