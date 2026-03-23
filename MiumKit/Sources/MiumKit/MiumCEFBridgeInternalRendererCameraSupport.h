#pragma once

#include "MiumCEFBridgeStateModels.h"

bool miumCEFNativeHandleRendererManagedCameraFrameMessage(
  cef_frame_t* frame,
  const char* channel,
  const char* payload
);
bool miumCEFNativeHandleRendererManagedCameraConfigMessage(
  cef_frame_t* frame,
  const char* channel,
  const char* payload
);
bool miumCEFNativeInstallRendererCameraRoutingEventBridge(
  cef_frame_t* frame,
  cef_v8_context_t* context
);
