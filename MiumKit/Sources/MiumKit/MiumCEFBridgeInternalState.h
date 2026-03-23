#pragma once

#include <condition_variable>
#include <functional>
#include <memory>
#include <mutex>
#include <unordered_map>

#include "MiumCEFBridgeCefApi.h"
#include "MiumCEFBridgePermissions.h"
#include "MiumCEFBridgeStateModels.h"

extern CefApi gCefApi;
extern std::mutex gStateLock;
extern std::mutex gFrameworkLoadLock;
extern std::condition_variable gStateCondition;
extern bool gCEFInitializing;
extern bool gCEFShutdownExecuting;
extern thread_local int gStateLockDepth;
extern bool gFrameworkLoaded;
extern bool gCEFInitialized;
extern bool gCEFShutdownPending;
extern bool gPendingShutdownPumpScheduled;
extern bool gExternalMessagePumpEnabled;
extern MiumCEFRuntimeShutdownState gRuntimeShutdownState;
extern int gCEFInitializeCount;
extern size_t gPendingTeardownBrowserCloseCount;
extern size_t gPendingReplacementBrowserCloseCount;
extern uint64_t gNextRuntimeId;
extern uint64_t gNextBrowserId;
extern uint64_t gNextHostViewId;
extern uint64_t gNextExternalMessagePumpScheduleId;
extern uint64_t gActiveExternalMessagePumpScheduleId;
extern uint64_t gLastPerformedMessagePumpSequence;
extern CFAbsoluteTime gLastPerformedMessagePumpTime;
extern uint64_t gNextRendererJavaScriptRequestId;
extern cef_app_t* gBrowserProcessApp;
extern std::unordered_map<uint64_t, std::unique_ptr<MiumCEFRuntimeState>> gRuntimes;
extern std::unordered_map<uint64_t, std::unique_ptr<MiumCEFBrowserState>> gBrowsers;
extern std::unordered_map<uint64_t, std::unique_ptr<MiumCEFHostViewState>> gHostViews;
extern std::unordered_map<cef_browser_t*, uint64_t> gBrowserIdByNativeBrowser;
extern std::unordered_map<int64_t, uint64_t> gBrowserIdByNativeBrowserIdentifier;
extern std::unordered_map<uint64_t, MiumCEFRendererJavaScriptRequestState> gRendererJavaScriptRequests;

struct CefStateLockDepthTracker {
  bool active = false;

  void activate() {
    if (!active) {
      ++gStateLockDepth;
      active = true;
    }
  }

  void deactivate() {
    if (active) {
      --gStateLockDepth;
      active = false;
    }
  }

  ~CefStateLockDepthTracker() {
    deactivate();
  }
};

struct CefStateLockGuard {
  explicit CefStateLockGuard(std::mutex& lock = gStateLock) : lock_(lock, std::defer_lock) {
    lock_.lock();
    depthTracker_.activate();
  }

  ~CefStateLockGuard() {
    depthTracker_.deactivate();
    lock_.unlock();
  }

  CefStateLockGuard(const CefStateLockGuard&) = delete;
  CefStateLockGuard& operator=(const CefStateLockGuard&) = delete;
  CefStateLockGuard(CefStateLockGuard&&) = delete;
  CefStateLockGuard& operator=(CefStateLockGuard&&) = delete;

 private:
  std::unique_lock<std::mutex> lock_;
  CefStateLockDepthTracker depthTracker_;
};

struct CefStateUniqueLock {
  explicit CefStateUniqueLock(std::mutex& lock = gStateLock) : lock_(lock) {
    depthTracker_.activate();
  }

  ~CefStateUniqueLock() {
    depthTracker_.deactivate();
  }

  CefStateUniqueLock(const CefStateUniqueLock&) = delete;
  CefStateUniqueLock& operator=(const CefStateUniqueLock&) = delete;
  CefStateUniqueLock(CefStateUniqueLock&&) = delete;
  CefStateUniqueLock& operator=(CefStateUniqueLock&&) = delete;

  void wait(std::condition_variable& condition) {
    depthTracker_.deactivate();
    condition.wait(lock_);
    depthTracker_.activate();
  }

 private:
  std::unique_lock<std::mutex> lock_;
  CefStateLockDepthTracker depthTracker_;
};
