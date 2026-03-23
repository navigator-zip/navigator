#pragma once

#import <AppKit/AppKit.h>

#include <functional>
#include <string>

#include "MiumCEFBridgeStateModels.h"

inline void* miumCEFIdToHandle(uint64_t id) {
  return reinterpret_cast<void*>(static_cast<uintptr_t>(id));
}

inline uint64_t miumCEFNativeHandleToId(void* handle) {
  return static_cast<uint64_t>(reinterpret_cast<uintptr_t>(handle));
}

bool miumCEFNativeBridgeLoggingEnabled(void);
bool miumCEFNativeBridgeExternalMessagePumpEnabled(void);
void miumCEFNativeScheduleExternalMessagePumpWork(int64_t delayMS);
bool miumCEFNativePerformCefMessageLoopWork(const char* reason);
void miumCEFNativeCancelExternalMessagePumpWork(void);
void miumCEFNativeRunOnCefMainThread(std::function<void()> fn);
void miumCEFNativeCloseBrowserReplacementTracked(cef_browser_t* browser, cef_client_t* client);
void miumCEFNativeCloseBrowser(
  cef_browser_t* browser,
  cef_client_t* client,
  MiumCEFNativeBrowserCloseKind closeKind,
  bool tracked,
  NSView* retainedHostView,
  std::function<void()> completion = {}
);
void miumCEFNativeReleaseBrowserOnCefMainThread(cef_browser_t* browser);
bool miumCEFNativeEvaluateRendererJavaScript(
  cef_frame_t* frame,
  const char* script,
  std::string* resultOut,
  std::string* errorOut
);
double miumCEFNativeRendererJavaScriptRequestTimeoutSeconds(void);
