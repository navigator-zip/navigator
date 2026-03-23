#include "MiumCEFBridgeInternalState.h"

#include <cassert>
#include <cstdint>
#include <cstdio>
#include <functional>
#include <utility>

#include "CefThreadGate.h"
#include "CefRef.h"
#include "MiumCEFBridgeInternalRuntimeExecutionSupport.h"
#include "MiumCEFBridgeShutdown.h"
#include "MiumCEFBridgeThreading.h"
#include "Tracing.h"

namespace {

using BrowserCloseCompletion = std::function<void()>;

static constexpr uint64_t kBrowserCloseReleasePollIntervalMs = 16;
static constexpr uint64_t kBrowserCloseReleaseMaxWaitMs = 2000;
static constexpr uint64_t kBrowserCloseReleasePollCount =
  (kBrowserCloseReleaseMaxWaitMs + kBrowserCloseReleasePollIntervalMs - 1) / kBrowserCloseReleasePollIntervalMs;

enum class MiumCEFNativeBrowserCloseTracking : uint8_t {
  tracked = 0,
  untracked = 1,
};

static BrowserCloseCompletion retainHostViewUntilCloseCompletion(
  NSView* hostView,
  BrowserCloseCompletion completion = {}
) {
  if (hostView == nil) {
    return completion;
  }

  return [retainedHostView = hostView, completion = std::move(completion)]() mutable {
    (void)retainedHostView;
    if (completion) {
      completion();
    }
  };
}

template <typename T>
static void releaseOwnedCefRef(T* value) {
  releaseOwnedCefValue(value);
}

static void releaseBrowser(cef_browser_t* browser) {
  releaseOwnedCefRef(browser);
}

static void releaseBrowserAfterClose(
  cef_browser_t* browser,
  cef_browser_host_t* host,
  cef_client_t* client,
  uint64_t remainingPolls,
  MiumCEFNativeBrowserCloseKind closeKind,
  MiumCEFNativeBrowserCloseTracking closeTracking,
  BrowserCloseCompletion completion
) {
  assert(miumCefIsOnMainThread());
  miumCefTrace(
    "browser-close",
    "releaseBrowserAfterClose browser=%p host=%p remainingPolls=%llu closeKind=%u lane=%s\n",
    static_cast<void*>(browser),
    static_cast<void*>(host),
    static_cast<unsigned long long>(remainingPolls),
    static_cast<unsigned int>(closeKind),
    miumCEFThreadLaneLabel()
  );

  const bool canCheck = (browser != nullptr && browser->is_valid != nullptr);
  const bool isInvalid = canCheck && (browser->is_valid(browser) == 0);
  if (!browser || !canCheck || isInvalid || remainingPolls == 0) {
    miumCefTrace(
      "browser-close",
      "releaseBrowserAfterClose finalize browser=%p host=%p closeKind=%u remainingPolls=%llu lane=%s\n",
      static_cast<void*>(browser),
      static_cast<void*>(host),
      static_cast<unsigned int>(closeKind),
      static_cast<unsigned long long>(remainingPolls),
      miumCEFThreadLaneLabel()
    );
    releaseOwnedCefRef(host);
    releaseBrowser(browser);
    releaseOwnedCefRef(client);
    if (completion) {
      completion();
    }
    if (closeTracking == MiumCEFNativeBrowserCloseTracking::tracked) {
      miumCEFFinishPendingBrowserClose(closeKind);
    }
    return;
  }

  const dispatch_time_t pollTime = dispatch_time(
    DISPATCH_TIME_NOW,
    static_cast<int64_t>(kBrowserCloseReleasePollIntervalMs) * static_cast<int64_t>(NSEC_PER_MSEC)
  );
  miumCefDispatchAfterOnMainThread(pollTime, ^{
    releaseBrowserAfterClose(
      browser,
      host,
      client,
      remainingPolls - 1,
      closeKind,
      closeTracking,
      completion
    );
  });
}

static void closeBrowser(
  cef_browser_t* browser,
  cef_client_t* client,
  MiumCEFNativeBrowserCloseKind closeKind,
  MiumCEFNativeBrowserCloseTracking closeTracking,
  BrowserCloseCompletion completion = {}
) {
  if (browser == nullptr) {
    releaseOwnedCefRef(client);
    if (completion) {
      completion();
    }
    if (closeTracking == MiumCEFNativeBrowserCloseTracking::tracked) {
      miumCEFFinishPendingBrowserClose(closeKind);
    }
    return;
  }

  miumCefTrace(
    "browser-close",
    "closeBrowser schedule browser=%p client=%p closeKind=%u lane=%s\n",
    static_cast<void*>(browser),
    static_cast<void*>(client),
    static_cast<unsigned int>(closeKind),
    miumCEFThreadLaneLabel()
  );
  miumCEFRunOnCefMainThread([browser, client, closeKind, closeTracking, completion] {
    miumCefTrace(
      "browser-close",
      "closeBrowser begin browser=%p client=%p closeKind=%u lane=%s\n",
      static_cast<void*>(browser),
      static_cast<void*>(client),
      static_cast<unsigned int>(closeKind),
      miumCEFThreadLaneLabel()
    );
    cef_browser_host_t* host = nullptr;
    if (browser->get_host != nullptr) {
      host = browser->get_host(browser);
    }

    if (host != nullptr && host->close_browser != nullptr) {
      host->close_browser(host, /*force_close=*/1);
    }

    releaseBrowserAfterClose(
      browser,
      host,
      client,
      kBrowserCloseReleasePollCount,
      closeKind,
      closeTracking,
      completion
    );
  });
}

} // namespace

void miumCEFNativeRunOnCefMainThread(std::function<void()> fn) {
  miumCEFRunOnCefMainThread(std::move(fn));
}

void miumCEFNativeCloseBrowser(
  cef_browser_t* browser,
  cef_client_t* client,
  MiumCEFNativeBrowserCloseKind closeKind,
  bool tracked,
  NSView* retainedHostView,
  std::function<void()> completion
) {
  closeBrowser(
    browser,
    client,
    closeKind,
    tracked ? MiumCEFNativeBrowserCloseTracking::tracked : MiumCEFNativeBrowserCloseTracking::untracked,
    retainHostViewUntilCloseCompletion(retainedHostView, std::move(completion))
  );
}

void miumCEFNativeReleaseBrowserOnCefMainThread(cef_browser_t* browser) {
  if (browser == nullptr) {
    return;
  }
  miumCEFRunOnCefMainThread([browser] {
    releaseBrowser(browser);
  });
}

void miumCEFNativeCloseBrowserReplacementTracked(cef_browser_t* browser, cef_client_t* client) {
  closeBrowser(
    browser,
    client,
    MiumCEFNativeBrowserCloseKind::replacement,
    MiumCEFNativeBrowserCloseTracking::tracked
  );
}
