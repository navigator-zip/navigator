#pragma once

#include <string>
#include <vector>

#include "MiumCEFBridgeInternalState.h"

bool miumCEFIsCefRuntimeUsableLocked();
int64_t miumCEFBrowserIdentifierFromNativeBrowser(cef_browser_t* browser);
std::vector<MiumCEFRendererJavaScriptRequestState> miumCEFTakeRendererJavaScriptRequestsForBrowserLocked(
  uint64_t browserId
);
void miumCEFFailRendererJavaScriptRequestsForBrowser(
  uint64_t browserId,
  const char* message,
  bool deliverAfterBrowserRemoval = false
);
bool miumCEFSnapshotNativeCallbackPayloadDeliverable(
  uint64_t browserId,
  const char* channel,
  uint64_t handlerGeneration
);
uint64_t miumCEFNativeBrowserIdFromNativeBrowser(cef_browser_t* browser);
