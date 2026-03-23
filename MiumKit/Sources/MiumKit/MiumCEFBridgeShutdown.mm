#import <AppKit/AppKit.h>

#include <cassert>
#include <cstdio>
#include <dlfcn.h>

#include "CefRef.h"
#include "CefThreadGate.h"
#include "MiumCEFBridgeHostView.h"
#include "MiumCEFBridgeInternalAdapters.h"
#include "MiumCEFBridgeInternalRuntimeExecutionSupport.h"
#include "MiumCEFBridgeInternalState.h"
#include "MiumCEFBridgePermissions.h"
#include "MiumCEFBridgeShutdown.h"
#include "MiumCEFBridgeThreading.h"
#include "Tracing.h"

namespace {

constexpr uint64_t kBrowserCloseReleasePollIntervalMs = 16;
constexpr uint64_t kBrowserCloseReleaseMaxWaitMs = 2000;
constexpr bool kUseManualCefMessageLoopWork = true;

void cancelExternalMessagePumpWorkLocked() {
  gActiveExternalMessagePumpScheduleId = ++gNextExternalMessagePumpScheduleId;
}

#if defined(MIUM_CEF_BRIDGE_TESTING)
void* testInjectedFrameworkHandleSentinel() {
  static int sentinel = 0;
  return &sentinel;
}
#endif

void closeDetachedFrameworkHandle(void* frameworkHandle) {
  if (frameworkHandle == nullptr) {
    return;
  }
#if defined(MIUM_CEF_BRIDGE_TESTING)
  if (frameworkHandle == testInjectedFrameworkHandleSentinel()) {
    return;
  }
#endif
  (void)frameworkHandle;
  // Intentionally do not dlclose() committed CEF framework handles. Bridge-owned call
  // sites may retain exported pointers across asynchronous boundaries.
}

bool shouldContinuePendingShutdownPumpLocked() {
  return gCEFShutdownPending
    && miumCEFIsCefRuntimeUsableLocked()
    && gCEFInitializeCount == 0
    && miumCEFPendingNativeBrowserCloseCountLocked() > 0;
}

void pumpPendingShutdownMessageLoop() {
  bool shouldPump = false;

  {
    CefStateLockGuard lock;
    shouldPump = shouldContinuePendingShutdownPumpLocked();
    if (!shouldPump || gCefApi.doMessageLoopWork == nullptr) {
      gPendingShutdownPumpScheduled = false;
      shouldPump = false;
    }
  }

  if (!shouldPump) {
    miumCEFMaybeCompletePendingCefShutdown();
    return;
  }

  miumCEFNativeRunOnCefMainThread([] {
    miumCefTrace("shutdown", "cef_do_message_loop_work (shutdown pump) lane=%s\n", miumCEFThreadLaneLabel());
    (void)miumCEFNativePerformCefMessageLoopWork("shutdown_pump");
  });

  const dispatch_time_t nextTick = dispatch_time(
    DISPATCH_TIME_NOW,
    static_cast<int64_t>(kBrowserCloseReleasePollIntervalMs) * static_cast<int64_t>(NSEC_PER_MSEC)
  );
  miumCefDispatchAfterOnMainThread(nextTick, ^{
    pumpPendingShutdownMessageLoop();
  });
}

}  // namespace

bool miumCEFHasLoadedFrameworkArtifactsLocked() {
  return gFrameworkLoaded && gCefApi.frameworkHandle != nullptr && gCefApi.loaded;
}

MiumCEFDetachedFrameworkArtifacts miumCEFDetachFrameworkArtifactsLocked() {
  MiumCEFDetachedFrameworkArtifacts artifacts;
  artifacts.frameworkHandle = gCefApi.frameworkHandle;
  gCefApi.frameworkHandle = nullptr;
  gFrameworkLoaded = false;
  return artifacts;
}

MiumCEFDetachedFrameworkArtifacts miumCEFDetachFrameworkArtifacts() {
  CefStateLockGuard lock;
  return miumCEFDetachFrameworkArtifactsLocked();
}

void miumCEFCloseUncommittedFrameworkHandle(void* frameworkHandle) {
  if (frameworkHandle == nullptr) {
    return;
  }
#if defined(MIUM_CEF_BRIDGE_TESTING)
  if (frameworkHandle == testInjectedFrameworkHandleSentinel()) {
    return;
  }
#endif
  dlclose(frameworkHandle);
}

void miumCEFReleaseDetachedFrameworkArtifactsAndResetApiState(MiumCEFDetachedFrameworkArtifacts artifacts) {
  miumCEFResetDetachedFrameworkApiState();
  closeDetachedFrameworkHandle(artifacts.frameworkHandle);
}

bool miumCEFBeginFinalShutdownLocked(MiumCEFFinalShutdown* shutdownContext) {
  if (shutdownContext == nullptr || gCEFShutdownExecuting || !gCEFInitialized) {
    return false;
  }

  gCEFShutdownExecuting = true;
  miumCEFClearRuntimeLivenessLocked();
  shutdownContext->shutdown = gCefApi.shutdown;
  shutdownContext->artifacts = miumCEFDetachFrameworkArtifactsLocked();
  return true;
}

void miumCEFUnloadFrameworkArtifactsWithoutShutdown() {
  miumCEFReleaseDetachedFrameworkArtifactsAndResetApiState(miumCEFDetachFrameworkArtifacts());
}

void miumCEFShutdownAndUnloadFrameworkArtifacts(MiumCEFFinalShutdown shutdownContext) {
  {
    CefStateLockGuard lock;
    cancelExternalMessagePumpWorkLocked();
  }
  if (shutdownContext.shutdown != nullptr) {
    miumCEFNativeRunOnCefMainThread([shutdown = shutdownContext.shutdown] {
      miumCefTrace("shutdown", "cef_shutdown lane=%s\n", miumCEFThreadLaneLabel());
      shutdown();
    });
  }
  {
    CefStateLockGuard lock;
    gExternalMessagePumpEnabled = false;
    gLastPerformedMessagePumpSequence = 0;
    gLastPerformedMessagePumpTime = 0.0;
    if (gBrowserProcessApp != nullptr && gBrowserProcessApp->base.release != nullptr) {
      releaseOwnedCefValue(gBrowserProcessApp);
      gBrowserProcessApp = nullptr;
    }
  }
  miumCEFReleaseDetachedFrameworkArtifactsAndResetApiState(shutdownContext.artifacts);
}

void miumCEFClearRuntimeLivenessLocked() {
  gCEFInitialized = false;
  gCEFShutdownPending = false;
  gPendingShutdownPumpScheduled = false;
  gExternalMessagePumpEnabled = false;
}

void miumCEFResetDetachedFrameworkApiState() {
  CefStateLockGuard lock;
  miumCEFResetRuntimeStateLocked();
  gFrameworkLoaded = false;
  gCefApi.reset();
  gStateCondition.notify_all();
}

void miumCEFResetRuntimeStateLocked() {
  miumCEFClearRuntimeLivenessLocked();
  gCEFShutdownExecuting = false;
  gCEFInitializeCount = 0;
  gLastPerformedMessagePumpSequence = 0;
  gLastPerformedMessagePumpTime = 0.0;
  gActiveExternalMessagePumpScheduleId = ++gNextExternalMessagePumpScheduleId;
  if (gBrowserProcessApp != nullptr && gBrowserProcessApp->base.release != nullptr) {
    releaseOwnedCefValue(gBrowserProcessApp);
    gBrowserProcessApp = nullptr;
  }
}

size_t miumCEFPendingNativeBrowserCloseCountLocked() {
  return gPendingTeardownBrowserCloseCount + gPendingReplacementBrowserCloseCount;
}

void miumCEFFinishPendingBrowserClose(MiumCEFNativeBrowserCloseKind kind) {
  {
    CefStateLockGuard lock;
    size_t* counter = nullptr;
    switch (kind) {
      case MiumCEFNativeBrowserCloseKind::teardown:
        counter = &gPendingTeardownBrowserCloseCount;
        break;
      case MiumCEFNativeBrowserCloseKind::replacement:
        counter = &gPendingReplacementBrowserCloseCount;
        break;
    }
    assert(counter != nullptr && "finishPendingBrowserClose called with invalid close kind");
    assert(*counter > 0 && "finishPendingBrowserClose called without a registered pending close");
    if (counter == nullptr || *counter == 0) {
      return;
    }
    *counter -= 1;
  }
  miumCEFMaybeCompletePendingCefShutdown();
}

void miumCEFMaybeCompletePendingCefShutdown() {
  MiumCEFFinalShutdown shutdownContext;
  bool shouldShutdown = false;

  {
    CefStateLockGuard lock;
    if (!gCEFShutdownPending || !gCEFInitialized || gCEFInitializeCount != 0
        || miumCEFPendingNativeBrowserCloseCountLocked() != 0) {
      return;
    }

    gCEFShutdownPending = false;
    gPendingShutdownPumpScheduled = false;
    shouldShutdown = miumCEFBeginFinalShutdownLocked(&shutdownContext);
  }

  if (shouldShutdown) {
    miumCEFShutdownAndUnloadFrameworkArtifacts(shutdownContext);
  }
}

void miumCEFSchedulePendingShutdownPumpIfNeeded() {
  bool shouldSchedule = false;

  {
    CefStateLockGuard lock;
    if (!gPendingShutdownPumpScheduled
        && kUseManualCefMessageLoopWork
        && shouldContinuePendingShutdownPumpLocked()
        && gCefApi.doMessageLoopWork != nullptr) {
      gPendingShutdownPumpScheduled = true;
      shouldSchedule = true;
    }
  }

  if (!shouldSchedule) {
    miumCEFMaybeCompletePendingCefShutdown();
    return;
  }

  miumCefDispatchAsyncOnMainThread(^{
    pumpPendingShutdownMessageLoop();
  });
}

void miumCEFPumpPendingShutdownMessageLoop() {
  pumpPendingShutdownMessageLoop();
}

#if defined(MIUM_CEF_BRIDGE_TESTING)
void* miumCEFTestInjectedFrameworkHandleSentinel() {
  return testInjectedFrameworkHandleSentinel();
}
#endif
