#pragma once

#include "MiumCEFBridgeStateModels.h"

std::string processMessageName(cef_process_message_t* message);
std::string processMessageArgumentString(cef_process_message_t* message, size_t index);
uint64_t miumCEFRendererJavaScriptRequestIDFromString(const char* value);
bool handleRendererExecuteJavaScriptRequestMessage(
  cef_frame_t* frame,
  const char* channel,
  const char* requestID,
  const char* script
);
bool handleRendererExecuteJavaScriptResultMessage(
  cef_browser_t* browser,
  const char* channel,
  const char* requestID,
  const char* result,
  const char* error
);
std::vector<MiumCEFRendererJavaScriptRequestState> takeRendererJavaScriptRequestsForBrowserLocked(
  uint64_t browserId
);
void failRendererJavaScriptRequestsForBrowser(
  uint64_t browserId,
  const char* message,
  bool deliverAfterBrowserRemoval = false
);
void scheduleRendererJavaScriptRequestTimeout(uint64_t requestID);
