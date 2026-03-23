#include <cerrno>
#include <cstdlib>
#include <cstring>

#include "CefRef.h"
#include "MiumCEFBridgeCallbackQueue.h"
#include "MiumCEFBridgeInternalAdapters.h"
#include "MiumCEFBridgeInternalRendererMessageAdapters.h"
#include "MiumCEFBridgeInternalBrowserPayloadSupport.h"
#include "MiumCEFBridgeInternalRuntimeBootstrapSupport.h"
#include "MiumCEFBridgeInternalRuntimeExecutionSupport.h"
#include "MiumCEFBridgeRendererJavaScript.h"

std::string processMessageName(cef_process_message_t* message) {
  if (message == nullptr || message->get_name == nullptr) {
    return {};
  }

  return miumCEFNativeStringFromNSStringUTF8(miumCEFNativeNSStringFromCEFUserFreeString(message->get_name(message)));
}

std::string processMessageArgumentString(cef_process_message_t* message, size_t index) {
  if (message == nullptr || message->get_argument_list == nullptr) {
    return {};
  }

  cef_list_value_t* arguments = message->get_argument_list(message);
  if (arguments == nullptr || arguments->get_string == nullptr) {
    return {};
  }

  return miumCEFNativeStringFromNSStringUTF8(
    miumCEFNativeNSStringFromCEFUserFreeString(arguments->get_string(arguments, index))
  );
}

uint64_t miumCEFRendererJavaScriptRequestIDFromString(const char* value) {
  if (value == nullptr || value[0] == '\0') {
    return 0;
  }
  char* end = nullptr;
  errno = 0;
  const unsigned long long parsed = std::strtoull(value, &end, 10);
  if (errno != 0 || end == value || (end != nullptr && end[0] != '\0')) {
    return 0;
  }
  return static_cast<uint64_t>(parsed);
}

namespace {

void releaseProcessMessage(cef_process_message_t* message) {
  releaseOwnedCefValue(message);
}

bool sendRendererJavaScriptResultMessage(
  cef_frame_t* frame,
  uint64_t requestID,
  const std::string& result,
  const std::string& error
) {
  if (frame == nullptr || frame->send_process_message == nullptr || gCefApi.createProcessMessage == nullptr) {
    return false;
  }

  cef_string_t name{};
  cef_string_t requestIDValue{};
  cef_string_t resultValue{};
  cef_string_t errorValue{};
  std::string conversionError;
  const std::string requestIDString = std::to_string(requestID);
  if (!miumCEFNativeUTF16FromUTF8(MiumCEFRendererExecuteJavaScriptResultChannel, name, &conversionError)
      || !miumCEFNativeUTF16FromUTF8(requestIDString.c_str(), requestIDValue, &conversionError)
      || !miumCEFNativeUTF16FromUTF8(result.c_str(), resultValue, &conversionError)
      || !miumCEFNativeUTF16FromUTF8(error.c_str(), errorValue, &conversionError)) {
    miumCEFNativeClearUTF16String(name);
    miumCEFNativeClearUTF16String(requestIDValue);
    miumCEFNativeClearUTF16String(resultValue);
    miumCEFNativeClearUTF16String(errorValue);
    return false;
  }

  cef_process_message_t* response = gCefApi.createProcessMessage(&name);
  if (response == nullptr) {
    miumCEFNativeClearUTF16String(name);
    miumCEFNativeClearUTF16String(requestIDValue);
    miumCEFNativeClearUTF16String(resultValue);
    miumCEFNativeClearUTF16String(errorValue);
    return false;
  }

  cef_list_value_t* arguments = response->get_argument_list != nullptr
    ? response->get_argument_list(response)
    : nullptr;
  bool sent = false;
  if (arguments != nullptr && arguments->set_size != nullptr && arguments->set_string != nullptr) {
    arguments->set_size(arguments, 3);
    arguments->set_string(arguments, 0, &requestIDValue);
    arguments->set_string(arguments, 1, &resultValue);
    arguments->set_string(arguments, 2, &errorValue);
    frame->send_process_message(frame, PID_BROWSER, response);
    sent = true;
  }
  if (!sent) {
    releaseProcessMessage(response);
  }
  miumCEFNativeClearUTF16String(name);
  miumCEFNativeClearUTF16String(requestIDValue);
  miumCEFNativeClearUTF16String(resultValue);
  miumCEFNativeClearUTF16String(errorValue);
  return sent;
}

double rendererJavaScriptRequestTimeoutSeconds() {
  return miumCEFNativeRendererJavaScriptRequestTimeoutSeconds();
}

}  // namespace

bool handleRendererExecuteJavaScriptRequestMessage(
  cef_frame_t* frame,
  const char* channel,
  const char* requestID,
  const char* script
) {
  if (frame == nullptr || channel == nullptr) {
    return false;
  }
  if (std::strcmp(channel, MiumCEFRendererExecuteJavaScriptChannel) != 0) {
    return false;
  }
  const uint64_t parsedRequestID = miumCEFRendererJavaScriptRequestIDFromString(requestID);
  if (parsedRequestID == 0) {
    return false;
  }
  std::string resultString;
  std::string errorString;
  miumCEFNativeEvaluateRendererJavaScript(frame, script, &resultString, &errorString);
  return sendRendererJavaScriptResultMessage(frame, parsedRequestID, resultString, errorString);
}

bool handleRendererExecuteJavaScriptResultMessage(
  cef_browser_t* browser,
  const char* channel,
  const char* requestID,
  const char* result,
  const char* error
) {
  if (browser == nullptr || channel == nullptr) {
    return false;
  }
  if (std::strcmp(channel, MiumCEFRendererExecuteJavaScriptResultChannel) != 0) {
    return false;
  }

  const uint64_t parsedRequestID = miumCEFRendererJavaScriptRequestIDFromString(requestID);
  if (parsedRequestID == 0) {
    return false;
  }

  MiumCEFRendererJavaScriptRequestState pendingRequest;
  {
    CefStateLockGuard lock;
    auto requestIter = gRendererJavaScriptRequests.find(parsedRequestID);
    if (requestIter == gRendererJavaScriptRequests.end()) {
      return false;
    }
    pendingRequest = requestIter->second;
    gRendererJavaScriptRequests.erase(requestIter);
  }

  const uint64_t browserId = miumCEFNativeBrowserIdFromNativeBrowser(browser);
  if (pendingRequest.browserId != 0 && browserId != 0 && pendingRequest.browserId != browserId) {
    runOnCallbackQueue(
      pendingRequest.completion,
      MiumCEFResultError,
      "Renderer JavaScript response browser mismatch",
      pendingRequest.completionContext,
      pendingRequest.browserId
    );
    return true;
  }

  const char* completionMessage = nullptr;
  MiumCEFResultCode completionCode = MiumCEFResultOK;
  if (error != nullptr && error[0] != '\0') {
    completionCode = MiumCEFResultError;
    completionMessage = error;
  } else {
    completionMessage = result == nullptr ? "" : result;
  }

  runOnCallbackQueue(
    pendingRequest.completion,
    completionCode,
    completionMessage,
    pendingRequest.completionContext,
    pendingRequest.browserId
  );
  return true;
}

std::vector<MiumCEFRendererJavaScriptRequestState> takeRendererJavaScriptRequestsForBrowserLocked(
  uint64_t browserId
) {
  std::vector<MiumCEFRendererJavaScriptRequestState> requests;
  if (browserId == 0) {
    return requests;
  }

  for (auto iter = gRendererJavaScriptRequests.begin(); iter != gRendererJavaScriptRequests.end();) {
    if (iter->second.browserId == browserId) {
      requests.push_back(iter->second);
      iter = gRendererJavaScriptRequests.erase(iter);
      continue;
    }
    ++iter;
  }
  return requests;
}

void failRendererJavaScriptRequestsForBrowser(
  uint64_t browserId,
  const char* message,
  bool deliverAfterBrowserRemoval
) {
  std::vector<MiumCEFRendererJavaScriptRequestState> requests;
  {
    CefStateLockGuard lock;
    requests = takeRendererJavaScriptRequestsForBrowserLocked(browserId);
  }

  for (const auto& request : requests) {
    runOnCallbackQueue(
      request.completion,
      MiumCEFResultError,
      message == nullptr ? "Renderer JavaScript request failed" : message,
      request.completionContext,
      deliverAfterBrowserRemoval ? 0 : request.browserId
    );
  }
}

void scheduleRendererJavaScriptRequestTimeout(uint64_t requestID) {
  const double timeoutSeconds = rendererJavaScriptRequestTimeoutSeconds();
  if (!(timeoutSeconds > 0.0)) {
    return;
  }

  dispatch_after(
    dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(timeoutSeconds * static_cast<double>(NSEC_PER_SEC))),
    callbackCompletionQueue(),
    ^{
      MiumCEFRendererJavaScriptRequestState timedOutRequest;
      {
        CefStateLockGuard lock;
        auto requestIter = gRendererJavaScriptRequests.find(requestID);
        if (requestIter == gRendererJavaScriptRequests.end()) {
          return;
        }
        timedOutRequest = requestIter->second;
        gRendererJavaScriptRequests.erase(requestIter);
      }

      runOnCallbackQueue(
        timedOutRequest.completion,
        MiumCEFResultError,
        "Renderer JavaScript timed out",
        timedOutRequest.completionContext,
        timedOutRequest.browserId
      );
    }
  );
}
