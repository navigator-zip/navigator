#pragma once

#import <Foundation/Foundation.h>

#include <string>

#include "MiumCEFBridgeStateModels.h"

NSString* miumCEFNativeNSStringFromCEFString(const cef_string_t* source);
NSString* miumCEFNativeNSStringFromCEFUserFreeString(cef_string_userfree_t source);
std::string miumCEFNativeStringFromNSStringUTF8(NSString* source);
std::string miumCEFNativeNormalizedPermissionOriginString(NSString* rawURLString);
std::string miumCEFNativeTopLevelPermissionOriginString(cef_browser_t* browser);
std::string miumCEFNativeFrameIdentifierString(cef_frame_t* frame);
bool miumCEFNativeShouldEnableMediaStreamOverride(void);
std::string miumCEFNativeRenderProcessTerminationPayloadString(
  cef_termination_status_t status,
  int errorCode,
  const cef_string_t* errorString
);
std::string miumCEFNativeMainFrameNavigationPayloadString(
  NSString* urlString,
  int userGesture,
  int isRedirect
);
std::string miumCEFNativeOpenURLInTabPayloadString(
  NSString* urlString,
  bool activatesTab
);
std::string miumCEFNativeFirstFaviconURLFromList(cef_string_list_t iconURLs);
