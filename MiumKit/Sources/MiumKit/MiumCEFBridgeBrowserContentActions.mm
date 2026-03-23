#import <AppKit/AppKit.h>

#include "CefRef.h"
#include "MiumCEFBridgeBrowserRegistry.h"
#include "MiumCEFBridgeCallbackQueue.h"
#include "MiumCEFBridgeHostView.h"
#include "MiumCEFBridgeInternalAdapters.h"
#include "MiumCEFBridgeInternalRuntimeBootstrapSupport.h"
#include "MiumCEFBridgeInternalRuntimeExecutionSupport.h"
#include "MiumCEFBridgeInternalState.h"
#include "MiumCEFBridgeNative.h"

namespace {

constexpr const char* kCefRuntimeUnavailableMessage = "CEF runtime is unavailable";

template <typename Fn>
MiumCEFResultCode withRetainedActiveBrowserForContent(
  MiumCEFBrowserHandle browserHandle,
  void* completionContext,
  MiumCEFCompletion completion,
  Fn&& fn
) {
  if (browserHandle == nullptr) {
    runOnCallbackQueue(
      completion,
      MiumCEFResultInvalidArgument,
      "Invalid browser handle",
      completionContext
    );
    return MiumCEFResultInvalidArgument;
  }

  const uint64_t browserId = miumCEFNativeHandleToId(browserHandle);
  cef_browser_t* nativeBrowser = nullptr;
  MiumCEFResultCode earlyResult = MiumCEFResultOK;
  const char* earlyMessage = nullptr;
  {
    CefStateLockGuard lock;
    auto* browserState = activeBrowserStateLocked(browserId);
    if (browserState == nullptr) {
      earlyResult = MiumCEFResultNotInitialized;
      earlyMessage = "Browser handle is not active";
    } else if (!miumCEFIsCefRuntimeUsableLocked()) {
      earlyResult = MiumCEFResultNotInitialized;
      earlyMessage = kCefRuntimeUnavailableMessage;
    } else {
      nativeBrowser = retainCefBorrowed(browserState->nativeBrowser.get());
    }
  }

  if (earlyResult != MiumCEFResultOK) {
    runOnCallbackQueue(
      completion,
      earlyResult,
      earlyMessage,
      completionContext,
      browserId
    );
    return earlyResult;
  }

  const MiumCEFResultCode result = fn(browserId, nativeBrowser);
  miumCEFNativeReleaseBrowserOnCefMainThread(nativeBrowser);
  return result;
}

template <typename Fn>
MiumCEFResultCode withRetainedActiveBrowserNoCompletion(
  MiumCEFBrowserHandle browserHandle,
  Fn&& fn
) {
  if (browserHandle == nullptr) {
    return MiumCEFResultInvalidArgument;
  }

  const uint64_t browserId = miumCEFNativeHandleToId(browserHandle);
  cef_browser_t* nativeBrowser = nullptr;
  {
    CefStateLockGuard lock;
    auto* browserState = activeBrowserStateLocked(browserId);
    if (browserState == nullptr || !miumCEFIsCefRuntimeUsableLocked()) {
      return MiumCEFResultNotInitialized;
    }
    nativeBrowser = retainCefBorrowed(browserState->nativeBrowser.get());
  }

  const MiumCEFResultCode result = fn(browserId, nativeBrowser);
  miumCEFNativeReleaseBrowserOnCefMainThread(nativeBrowser);
  return result;
}

}  // namespace

extern "C" MiumCEFResultCode miumNativeCEFLoadURL(
  MiumCEFBrowserHandle browserHandle,
  const char* url,
  void* completionContext,
  MiumCEFCompletion completion
) {
  return withRetainedActiveBrowserForContent(
    browserHandle,
    completionContext,
    completion,
    [&](uint64_t browserId, cef_browser_t* nativeBrowser) {
      const std::string target = url == nullptr ? std::string("about:blank") : std::string(url);
      std::string conversionError;
      cef_string_t cefUrl{};
      if (!miumCEFNativeUTF16FromUTF8(target.c_str(), cefUrl, &conversionError)) {
        runOnCallbackQueue(
          completion,
          MiumCEFResultError,
          conversionError.c_str(),
          completionContext,
          browserId
        );
        return MiumCEFResultError;
      }

      bool called = false;
      miumCEFNativeRunOnCefMainThread([&] {
        {
          CefStateLockGuard lock;
          if (!miumCEFIsCefRuntimeUsableLocked()) {
            called = false;
            return;
          }
        }
        if (nativeBrowser == nullptr || nativeBrowser->get_main_frame == nullptr) {
          called = false;
          return;
        }

        auto* frame = nativeBrowser->get_main_frame(nativeBrowser);
        if (frame == nullptr || frame->load_url == nullptr) {
          releaseOwnedCefValue(frame);
          called = false;
          return;
        }

        frame->load_url(frame, &cefUrl);
        releaseOwnedCefValue(frame);
        called = true;
      });

      miumCEFNativeClearUTF16String(cefUrl);
      if (!called) {
        runOnCallbackQueue(
          completion,
          MiumCEFResultError,
          "CEF load_url unavailable",
          completionContext,
          browserId
        );
        return MiumCEFResultError;
      }

      runOnCallbackQueue(completion, MiumCEFResultOK, target.c_str(), completionContext, browserId);
      return MiumCEFResultOK;
    }
  );
}

extern "C" MiumCEFResultCode miumNativeCEFReload(MiumCEFBrowserHandle browserHandle) {
  return withRetainedActiveBrowserNoCompletion(
    browserHandle,
    [](uint64_t, cef_browser_t* nativeBrowser) {
      bool called = false;
      miumCEFNativeRunOnCefMainThread([&] {
        {
          CefStateLockGuard lock;
          if (!miumCEFIsCefRuntimeUsableLocked()) {
            return;
          }
        }
        if (nativeBrowser != nullptr && nativeBrowser->reload != nullptr) {
          nativeBrowser->reload(nativeBrowser);
          called = true;
        }
      });
      return called ? MiumCEFResultOK : MiumCEFResultError;
    }
  );
}

extern "C" MiumCEFResultCode miumNativeCEFStopLoad(MiumCEFBrowserHandle browserHandle) {
  return withRetainedActiveBrowserNoCompletion(
    browserHandle,
    [](uint64_t, cef_browser_t* nativeBrowser) {
      bool called = false;
      miumCEFNativeRunOnCefMainThread([&] {
        {
          CefStateLockGuard lock;
          if (!miumCEFIsCefRuntimeUsableLocked()) {
            return;
          }
        }
        if (nativeBrowser != nullptr && nativeBrowser->stop_load != nullptr) {
          nativeBrowser->stop_load(nativeBrowser);
          called = true;
        }
      });
      return called ? MiumCEFResultOK : MiumCEFResultError;
    }
  );
}

extern "C" MiumCEFResultCode miumNativeCEFResizeBrowser(
  MiumCEFBrowserHandle browserHandle,
  int width,
  int height
) {
  if (browserHandle == nullptr) {
    return MiumCEFResultInvalidArgument;
  }

  const uint64_t browserId = miumCEFNativeHandleToId(browserHandle);
  cef_browser_t* nativeBrowser = nullptr;
  void* hostView = nullptr;

  {
    CefStateLockGuard lock;
    auto* browserState = activeBrowserStateLocked(browserId);
    if (browserState == nullptr || !miumCEFIsCefRuntimeUsableLocked()) {
      return MiumCEFResultNotInitialized;
    }

    nativeBrowser = retainCefBorrowed(browserState->nativeBrowser.get());
    if (browserState->hostViewId != 0) {
      auto hostIter = gHostViews.find(browserState->hostViewId);
      if (hostIter != gHostViews.end()) {
        hostView = (__bridge void*)resolvedHostViewForState(hostIter->second.get());
      }
    }
  }
  if (nativeBrowser == nullptr) {
    return MiumCEFResultError;
  }

  const int safeWidth = width < 0 ? 0 : width;
  const int safeHeight = height < 0 ? 0 : height;
  if (safeWidth <= 0 || safeHeight <= 0) {
    miumCEFNativeReleaseBrowserOnCefMainThread(nativeBrowser);
    return MiumCEFResultError;
  }

  bool didResize = false;
  miumCEFNativeRunOnCefMainThread([hostView, safeWidth, safeHeight, nativeBrowser, &didResize] {
    struct BrowserReleaseScope {
      cef_browser_t* browser = nullptr;
      ~BrowserReleaseScope() {
        if (browser != nullptr) {
          releaseCefBase(&browser->base);
        }
      }
    } browserReleaseScope{nativeBrowser};

    {
      CefStateLockGuard lock;
      if (!miumCEFIsCefRuntimeUsableLocked()) {
        return;
      }
    }

    resizeEmbeddedBrowserHostView((__bridge NSView*)hostView, safeWidth, safeHeight);

    cef_browser_host_t* host = nullptr;
    if (nativeBrowser->get_host != nullptr) {
      host = nativeBrowser->get_host(nativeBrowser);
    }
    if (host == nullptr) {
      return;
    }
    if (host->notify_move_or_resize_started != nullptr) {
      host->notify_move_or_resize_started(host);
    }
    if (host->was_resized != nullptr) {
      host->was_resized(host);
    }
    didResize = true;
    releaseOwnedCefValue(host);
  });
  if (!didResize) {
    return MiumCEFResultError;
  }

  return MiumCEFResultOK;
}

extern "C" MiumCEFResultCode miumNativeCEFEvaluateJavaScript(
  MiumCEFBrowserHandle browserHandle,
  const char* script,
  void* completionContext,
  MiumCEFCompletion completion
) {
  return withRetainedActiveBrowserForContent(
    browserHandle,
    completionContext,
    completion,
    [&](uint64_t browserId, cef_browser_t* nativeBrowser) {
      const std::string normalizedScript = script == nullptr ? std::string() : std::string(script);
      std::string conversionError;
      cef_string_t cefScript{};
      if (!miumCEFNativeUTF16FromUTF8(normalizedScript.c_str(), cefScript, &conversionError)) {
        runOnCallbackQueue(
          completion,
          MiumCEFResultError,
          conversionError.c_str(),
          completionContext,
          browserId
        );
        return MiumCEFResultError;
      }

      bool called = false;
      miumCEFNativeRunOnCefMainThread([&] {
        {
          CefStateLockGuard lock;
          if (!miumCEFIsCefRuntimeUsableLocked()) {
            called = false;
            return;
          }
        }

        if (nativeBrowser == nullptr || nativeBrowser->get_main_frame == nullptr) {
          called = false;
          return;
        }

        auto* frame = nativeBrowser->get_main_frame(nativeBrowser);
        if (frame == nullptr || frame->execute_java_script == nullptr) {
          releaseOwnedCefValue(frame);
          called = false;
          return;
        }

        frame->execute_java_script(frame, &cefScript, nullptr, 0);
        releaseOwnedCefValue(frame);
        called = true;
      });

      miumCEFNativeClearUTF16String(cefScript);
      if (!called) {
        runOnCallbackQueue(
          completion,
          MiumCEFResultError,
          "CEF execute_java_script unavailable",
          completionContext,
          browserId
        );
        return MiumCEFResultError;
      }

      runOnCallbackQueue(
        completion,
        MiumCEFResultOK,
        "{\"dispatched\":true}",
        completionContext,
        browserId
      );
      return MiumCEFResultOK;
    }
  );
}

extern "C" MiumCEFResultCode miumNativeCEFRequestSnapshot(
  MiumCEFBrowserHandle browserHandle,
  const char* outputPath,
  const char* jsonOptions,
  void* completionContext,
  MiumCEFCompletion completion
) {
  if (browserHandle == nullptr) {
    runOnCallbackQueue(
      completion,
      MiumCEFResultInvalidArgument,
      "Invalid browser handle",
      completionContext
    );
    return MiumCEFResultInvalidArgument;
  }

  const uint64_t browserId = miumCEFNativeHandleToId(browserHandle);
  if (outputPath == nullptr || outputPath[0] == '\0') {
    runOnCallbackQueue(
      completion,
      MiumCEFResultInvalidArgument,
      "Output path is required",
      completionContext,
      browserId
    );
    return MiumCEFResultInvalidArgument;
  }

  void* hostView = nullptr;
  NSString* outPath = nil;
  MiumCEFResultCode earlyResult = MiumCEFResultOK;
  const char* earlyMessage = nullptr;
  {
    CefStateLockGuard lock;
    auto browserIter = gBrowsers.find(browserId);
    if (browserIter == gBrowsers.end() || !browserIter->second->active) {
      earlyResult = MiumCEFResultNotInitialized;
      earlyMessage = "Browser handle is not active";
    } else if (!miumCEFIsCefRuntimeUsableLocked()) {
      earlyResult = MiumCEFResultNotInitialized;
      earlyMessage = kCefRuntimeUnavailableMessage;
    } else if (browserIter->second->hostViewId != 0) {
      auto hostIter = gHostViews.find(browserIter->second->hostViewId);
      if (hostIter != gHostViews.end()) {
        hostView = (__bridge void*)resolvedHostViewForState(hostIter->second.get());
      }
    }
  }
  if (earlyResult != MiumCEFResultOK) {
    runOnCallbackQueue(
      completion,
      earlyResult,
      earlyMessage,
      completionContext,
      browserId
    );
    return earlyResult;
  }
  if ((outPath = [NSString stringWithUTF8String:outputPath]) == nil) {
    runOnCallbackQueue(
      completion,
      MiumCEFResultError,
      "Output path is not UTF8",
      completionContext,
      browserId
    );
    return MiumCEFResultError;
  }

  outPath = [outPath stringByStandardizingPath];
  MiumCEFSnapshotOptions snapshotOptions;
  NSString* optionsError = nil;
  if (!parseSnapshotOptions(jsonOptions, outPath, &snapshotOptions, &optionsError)) {
    runOnCallbackQueue(
      completion,
      MiumCEFResultInvalidArgument,
      optionsError == nil ? "Snapshot options are invalid" : optionsError.UTF8String,
      completionContext,
      browserId
    );
    return MiumCEFResultInvalidArgument;
  }

  NSData* snapshotData = nil;
  NSString* snapshotError = nil;
  bool snapshotRuntimeUnavailable = false;
  miumCEFNativeRunOnCefMainThread([&] {
    {
      CefStateLockGuard lock;
      if (!miumCEFIsCefRuntimeUsableLocked()) {
        snapshotError = [NSString stringWithUTF8String:kCefRuntimeUnavailableMessage];
        snapshotRuntimeUnavailable = true;
        return;
      }
    }
    snapshotData = snapshotDataForHostView((__bridge NSView*)hostView, snapshotOptions, &snapshotError);
  });

  if (snapshotData == nil) {
    if (snapshotRuntimeUnavailable) {
      runOnCallbackQueue(
        completion,
        MiumCEFResultNotInitialized,
        snapshotError == nil ? "CEF runtime became unavailable" : snapshotError.UTF8String,
        completionContext,
        browserId
      );
      return MiumCEFResultNotInitialized;
    }
    runOnCallbackQueue(
      completion,
      MiumCEFResultError,
      snapshotError == nil ? "Failed to capture browser snapshot" : snapshotError.UTF8String,
      completionContext,
      browserId
    );
    return MiumCEFResultError;
  }

  NSString* outputDirectory = outPath.stringByDeletingLastPathComponent;
  if (outputDirectory != nil && outputDirectory.length > 0) {
    NSError* createDirectoryError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:outputDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&createDirectoryError];
    if (createDirectoryError != nil) {
      runOnCallbackQueue(
        completion,
        MiumCEFResultError,
        createDirectoryError.localizedDescription.UTF8String,
        completionContext,
        browserId
      );
      return MiumCEFResultError;
    }
  }

  if (![snapshotData writeToFile:outPath atomically:YES]) {
    runOnCallbackQueue(
      completion,
      MiumCEFResultError,
      "Failed to write browser snapshot",
      completionContext,
      browserId
    );
    return MiumCEFResultError;
  }

  runOnCallbackQueue(completion, MiumCEFResultOK, outputPath, completionContext, browserId);
  return MiumCEFResultOK;
}
