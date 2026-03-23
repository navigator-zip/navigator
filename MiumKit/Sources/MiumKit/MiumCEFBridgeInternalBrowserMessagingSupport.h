#pragma once

#import <Foundation/Foundation.h>

#include "MiumCEFBridgeStateModels.h"

void miumCEFNativeEmitBrowserMessageForMappedBrowser(
  cef_browser_t* browser,
  const char* channel,
  const char* message
);
void miumCEFNativeEmitTopLevelNativeContentForBrowser(
  cef_browser_t* browser,
  NSString* urlString,
  MiumCEFTopLevelNativeContentKind kind,
  NSString* pathExtension,
  NSString* uniformTypeIdentifier
);
void miumCEFNativeInjectPictureInPictureObserverScript(cef_frame_t* frame);
void CEF_CALLBACK miumCEFNativeRequestHandlerOnRenderProcessTerminated(
  cef_request_handler_t* self,
  cef_browser_t* browser,
  cef_termination_status_t status,
  int error_code,
  const cef_string_t* error_string
);
