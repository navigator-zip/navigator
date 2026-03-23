#pragma once

#include <string>

#include "MiumCEFBridgeStateModels.h"

std::string miumCEFNativeProcessMessageName(cef_process_message_t* message);
std::string miumCEFNativeProcessMessageArgumentString(cef_process_message_t* message, size_t index);
bool miumCEFNativeHandleRendererExecuteJavaScriptResultMessage(
  cef_browser_t* browser,
  const char* channel,
  const char* requestID,
  const char* result,
  const char* error
);
bool miumCEFNativeHandleRendererExecuteJavaScriptRequestMessage(
  cef_frame_t* frame,
  const char* channel,
  const char* requestID,
  const char* script
);
