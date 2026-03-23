#include "CefRef.h"
#include "MiumCEFBridgeBrowserRegistry.h"
#include "MiumCEFBridgeCallbackQueue.h"
#include "MiumCEFBridgeInternalAdapters.h"
#include "MiumCEFBridgeInternalRuntimeBootstrapSupport.h"
#include "MiumCEFBridgeInternalRuntimeExecutionSupport.h"
#include "MiumCEFBridgeInternalState.h"
#include "MiumCEFBridgeNative.h"
#include "MiumCEFBridgeRendererJavaScript.h"

namespace {

constexpr const char* kCefRuntimeUnavailableMessage = "CEF runtime is unavailable";
constexpr cef_process_id_t kCefProcessIdRenderer = static_cast<cef_process_id_t>(1);

void releaseProcessMessage(cef_process_message_t* message) {
  releaseOwnedCefValue(message);
}

template <typename Fn>
MiumCEFResultCode withRetainedActiveBrowser(
  MiumCEFBrowserHandle browserHandle,
  MiumCEFResultCode invalidArgumentCode,
  MiumCEFResultCode unavailableCode,
  Fn&& fn
) {
  if (browserHandle == nullptr) {
    return invalidArgumentCode;
  }

  const uint64_t browserId = miumCEFNativeHandleToId(browserHandle);
  cef_browser_t* nativeBrowser = nullptr;
  {
    CefStateLockGuard lock;
    auto* browserState = activeBrowserStateLocked(browserId);
    if (browserState == nullptr || !miumCEFIsCefRuntimeUsableLocked()) {
      return unavailableCode;
    }
    nativeBrowser = retainCefBorrowed(browserState->nativeBrowser.get());
  }

  const MiumCEFResultCode result = fn(browserId, nativeBrowser);
  miumCEFNativeReleaseBrowserOnCefMainThread(nativeBrowser);
  return result;
}

}  // namespace

extern "C" MiumCEFResultCode miumNativeCEFGoBack(MiumCEFBrowserHandle browserHandle) {
  return withRetainedActiveBrowser(
    browserHandle,
    MiumCEFResultInvalidArgument,
    MiumCEFResultNotInitialized,
    [](uint64_t, cef_browser_t* nativeBrowser) {
      bool called = false;
      miumCEFNativeRunOnCefMainThread([&] {
        {
          CefStateLockGuard lock;
          if (!miumCEFIsCefRuntimeUsableLocked()) {
            return;
          }
        }
        if (nativeBrowser != nullptr && nativeBrowser->go_back != nullptr) {
          nativeBrowser->go_back(nativeBrowser);
          called = true;
        }
      });
      return called ? MiumCEFResultOK : MiumCEFResultError;
    }
  );
}

extern "C" MiumCEFResultCode miumNativeCEFGoForward(MiumCEFBrowserHandle browserHandle) {
  return withRetainedActiveBrowser(
    browserHandle,
    MiumCEFResultInvalidArgument,
    MiumCEFResultNotInitialized,
    [](uint64_t, cef_browser_t* nativeBrowser) {
      bool called = false;
      miumCEFNativeRunOnCefMainThread([&] {
        {
          CefStateLockGuard lock;
          if (!miumCEFIsCefRuntimeUsableLocked()) {
            return;
          }
        }
        if (nativeBrowser != nullptr && nativeBrowser->go_forward != nullptr) {
          nativeBrowser->go_forward(nativeBrowser);
          called = true;
        }
      });
      return called ? MiumCEFResultOK : MiumCEFResultError;
    }
  );
}

extern "C" int miumNativeCEFCanGoBack(MiumCEFBrowserHandle browserHandle) {
  return withRetainedActiveBrowser(
    browserHandle,
    static_cast<MiumCEFResultCode>(0),
    static_cast<MiumCEFResultCode>(0),
    [](uint64_t, cef_browser_t* nativeBrowser) {
      int canGoBack = 0;
      miumCEFNativeRunOnCefMainThread([&] {
        {
          CefStateLockGuard lock;
          if (!miumCEFIsCefRuntimeUsableLocked()) {
            return;
          }
        }
        if (nativeBrowser != nullptr && nativeBrowser->can_go_back != nullptr) {
          canGoBack = nativeBrowser->can_go_back(nativeBrowser);
        }
      });
      return static_cast<MiumCEFResultCode>(canGoBack);
    }
  );
}

extern "C" int miumNativeCEFCanGoForward(MiumCEFBrowserHandle browserHandle) {
  return withRetainedActiveBrowser(
    browserHandle,
    static_cast<MiumCEFResultCode>(0),
    static_cast<MiumCEFResultCode>(0),
    [](uint64_t, cef_browser_t* nativeBrowser) {
      int canGoForward = 0;
      miumCEFNativeRunOnCefMainThread([&] {
        {
          CefStateLockGuard lock;
          if (!miumCEFIsCefRuntimeUsableLocked()) {
            return;
          }
        }
        if (nativeBrowser != nullptr && nativeBrowser->can_go_forward != nullptr) {
          canGoForward = nativeBrowser->can_go_forward(nativeBrowser);
        }
      });
      return static_cast<MiumCEFResultCode>(canGoForward);
    }
  );
}

extern "C" int miumNativeCEFIsLoading(MiumCEFBrowserHandle browserHandle) {
  return withRetainedActiveBrowser(
    browserHandle,
    static_cast<MiumCEFResultCode>(0),
    static_cast<MiumCEFResultCode>(0),
    [](uint64_t, cef_browser_t* nativeBrowser) {
      int isLoading = 0;
      miumCEFNativeRunOnCefMainThread([&] {
        {
          CefStateLockGuard lock;
          if (!miumCEFIsCefRuntimeUsableLocked()) {
            return;
          }
        }
        if (nativeBrowser != nullptr && nativeBrowser->is_loading != nullptr) {
          isLoading = nativeBrowser->is_loading(nativeBrowser);
        }
      });
      return static_cast<MiumCEFResultCode>(isLoading);
    }
  );
}

extern "C" MiumCEFResultCode miumNativeCEFSendMessage(
  MiumCEFBrowserHandle browserHandle,
  const char* channel,
  const char* jsonPayload,
  void* completionContext,
  MiumCEFCompletion completion
) {
  if (browserHandle == nullptr || channel == nullptr) {
    runOnCallbackQueue(
      completion,
      MiumCEFResultInvalidArgument,
      "Invalid send message args",
      completionContext
    );
    return MiumCEFResultInvalidArgument;
  }

  const uint64_t browserId = miumCEFNativeHandleToId(browserHandle);
  const std::string normalizedChannel = channel;
  const std::string normalizedPayload = jsonPayload == nullptr ? std::string() : std::string(jsonPayload);
  cef_browser_t* nativeBrowser = nullptr;
  CefProcessMessageCreateFn createProcessMessage = nullptr;
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
      createProcessMessage = gCefApi.createProcessMessage;
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
  if (nativeBrowser == nullptr || createProcessMessage == nullptr) {
    miumCEFNativeReleaseBrowserOnCefMainThread(nativeBrowser);
    runOnCallbackQueue(
      completion,
      MiumCEFResultError,
      "CEF process messaging unavailable",
      completionContext,
      browserId
    );
    return MiumCEFResultError;
  }

  cef_string_t name{};
  cef_string_t payload{};
  std::string channelError;
  std::string payloadError;
  if (!miumCEFNativeUTF16FromUTF8(normalizedChannel.c_str(), name, &channelError)) {
    miumCEFNativeReleaseBrowserOnCefMainThread(nativeBrowser);
    runOnCallbackQueue(
      completion,
      MiumCEFResultError,
      channelError.c_str(),
      completionContext,
      browserId
    );
    return MiumCEFResultError;
  }
  if (!miumCEFNativeUTF16FromUTF8(normalizedPayload.c_str(), payload, &payloadError)) {
    miumCEFNativeClearUTF16String(name);
    miumCEFNativeReleaseBrowserOnCefMainThread(nativeBrowser);
    runOnCallbackQueue(
      completion,
      MiumCEFResultError,
      payloadError.c_str(),
      completionContext,
      browserId
    );
    return MiumCEFResultError;
  }

  bool sent = false;
  miumCEFNativeRunOnCefMainThread([&] {
    {
      CefStateLockGuard lock;
      if (!miumCEFIsCefRuntimeUsableLocked()) {
        return;
      }
    }

    cef_process_message_t* message = createProcessMessage(&name);
    if (message == nullptr) {
      return;
    }

    cef_list_value_t* args = message->get_argument_list != nullptr
      ? message->get_argument_list(message)
      : nullptr;
    if (args != nullptr && args->set_size != nullptr && args->set_string != nullptr) {
      args->set_size(args, 1);
      args->set_string(args, 0, &payload);
    }

    auto* frame = nativeBrowser->get_main_frame != nullptr
      ? nativeBrowser->get_main_frame(nativeBrowser)
      : nullptr;
    if (frame != nullptr && frame->send_process_message != nullptr) {
      frame->send_process_message(frame, kCefProcessIdRenderer, message);
      sent = true;
    }
    releaseOwnedCefValue(frame);

    if (!sent) {
      releaseProcessMessage(message);
    }
  });

  miumCEFNativeClearUTF16String(name);
  miumCEFNativeClearUTF16String(payload);
  miumCEFNativeReleaseBrowserOnCefMainThread(nativeBrowser);

  if (!sent) {
    runOnCallbackQueue(
      completion,
      MiumCEFResultError,
      "CEF renderer message delivery unavailable",
      completionContext,
      browserId
    );
    return MiumCEFResultError;
  }

  runOnCallbackQueue(
    completion,
    MiumCEFResultOK,
    "{\"acknowledged\":true}",
    completionContext,
    browserId
  );
  return MiumCEFResultOK;
}

extern "C" MiumCEFResultCode miumNativeCEFExecuteJavaScriptInRendererWithResult(
  MiumCEFBrowserHandle browserHandle,
  const char* script,
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
  if (completion == nullptr) {
    return MiumCEFResultInvalidArgument;
  }

  const uint64_t browserId = miumCEFNativeHandleToId(browserHandle);
  cef_browser_t* nativeBrowser = nullptr;
  CefProcessMessageCreateFn createProcessMessage = nullptr;
  uint64_t requestID = 0;

  {
    CefStateLockGuard lock;
    auto* browserState = activeBrowserStateLocked(browserId);
    if (browserState == nullptr) {
      runOnCallbackQueue(
        completion,
        MiumCEFResultNotInitialized,
        "Browser handle is not active",
        completionContext,
        browserId
      );
      return MiumCEFResultNotInitialized;
    }
    if (!miumCEFIsCefRuntimeUsableLocked()) {
      runOnCallbackQueue(
        completion,
        MiumCEFResultNotInitialized,
        kCefRuntimeUnavailableMessage,
        completionContext,
        browserId
      );
      return MiumCEFResultNotInitialized;
    }
    if (gCefApi.createProcessMessage == nullptr) {
      runOnCallbackQueue(
        completion,
        MiumCEFResultError,
        "CEF process messaging unavailable",
        completionContext,
        browserId
      );
      return MiumCEFResultError;
    }
    nativeBrowser = retainCefBorrowed(browserState->nativeBrowser.get());
    createProcessMessage = gCefApi.createProcessMessage;
    while (true) {
      if (gNextRendererJavaScriptRequestId == 0) {
        gNextRendererJavaScriptRequestId = 1;
      }
      const uint64_t candidate = gNextRendererJavaScriptRequestId++;
      if (gRendererJavaScriptRequests.find(candidate) == gRendererJavaScriptRequests.end()) {
        requestID = candidate;
        break;
      }
    }
    gRendererJavaScriptRequests[requestID] = MiumCEFRendererJavaScriptRequestState{
      .requestID = requestID,
      .browserId = browserId,
      .completionContext = completionContext,
      .completion = completion,
    };
  }

  const std::string normalizedScript = script == nullptr ? std::string() : std::string(script);
  const std::string requestIDString = std::to_string(requestID);
  std::string conversionError;
  cef_string_t name{};
  cef_string_t requestIDValue{};
  cef_string_t scriptValue{};
  if (!miumCEFNativeUTF16FromUTF8(MiumCEFRendererExecuteJavaScriptChannel, name, &conversionError)
      || !miumCEFNativeUTF16FromUTF8(requestIDString.c_str(), requestIDValue, &conversionError)
      || !miumCEFNativeUTF16FromUTF8(normalizedScript.c_str(), scriptValue, &conversionError)) {
    {
      CefStateLockGuard lock;
      gRendererJavaScriptRequests.erase(requestID);
    }
    miumCEFNativeClearUTF16String(name);
    miumCEFNativeClearUTF16String(requestIDValue);
    miumCEFNativeClearUTF16String(scriptValue);
    miumCEFNativeReleaseBrowserOnCefMainThread(nativeBrowser);
    runOnCallbackQueue(
      completion,
      MiumCEFResultError,
      conversionError.c_str(),
      completionContext,
      browserId
    );
    return MiumCEFResultError;
  }

  bool sent = false;
  miumCEFNativeRunOnCefMainThread([&] {
    {
      CefStateLockGuard lock;
      if (!miumCEFIsCefRuntimeUsableLocked()) {
        return;
      }
    }
    if (nativeBrowser == nullptr || createProcessMessage == nullptr) {
      return;
    }

    cef_process_message_t* message = createProcessMessage(&name);
    if (message == nullptr) {
      return;
    }

    cef_list_value_t* arguments = message->get_argument_list != nullptr
      ? message->get_argument_list(message)
      : nullptr;
    if (arguments != nullptr && arguments->set_size != nullptr && arguments->set_string != nullptr) {
      arguments->set_size(arguments, 2);
      arguments->set_string(arguments, 0, &requestIDValue);
      arguments->set_string(arguments, 1, &scriptValue);
    }

    auto* frame = nativeBrowser->get_main_frame != nullptr
      ? nativeBrowser->get_main_frame(nativeBrowser)
      : nullptr;
    if (arguments != nullptr
        && arguments->set_size != nullptr
        && arguments->set_string != nullptr
        && frame != nullptr
        && frame->send_process_message != nullptr) {
      frame->send_process_message(frame, kCefProcessIdRenderer, message);
      sent = true;
    }
    releaseOwnedCefValue(frame);
    if (!sent) {
      releaseProcessMessage(message);
    }
  });

  miumCEFNativeClearUTF16String(name);
  miumCEFNativeClearUTF16String(requestIDValue);
  miumCEFNativeClearUTF16String(scriptValue);
  miumCEFNativeReleaseBrowserOnCefMainThread(nativeBrowser);

  if (!sent) {
    {
      CefStateLockGuard lock;
      gRendererJavaScriptRequests.erase(requestID);
    }
    runOnCallbackQueue(
      completion,
      MiumCEFResultError,
      "CEF renderer message delivery unavailable",
      completionContext,
      browserId
    );
    return MiumCEFResultError;
  }

  scheduleRendererJavaScriptRequestTimeout(requestID);
  return MiumCEFResultOK;
}
