#pragma once

#import <Foundation/Foundation.h>

#include <string>

#include "MiumCEFBridgeContentClassification.h"
#include "MiumCEFBridgeStateModels.h"

NSString* NSStringFromCEFString(const cef_string_t* source);
NSString* NSStringFromCEFUserFreeString(cef_string_userfree_t source);
std::string stringFromCEFUserFreeString(cef_string_userfree_t source);
std::string stringFromNSStringUTF8(NSString* source);
void emitTopLevelNativeContentForBrowser(
  cef_browser_t* browser,
  NSString* urlString,
  MiumCEFTopLevelNativeContentKind kind,
  NSString* pathExtension,
  NSString* uniformTypeIdentifier
);
void emitBrowserMessageForMappedBrowser(
  cef_browser_t* browser,
  const char* channel,
  const char* message
);
std::string renderProcessTerminationPayloadString(
  cef_termination_status_t status,
  int errorCode,
  const cef_string_t* errorString
);
std::string mainFrameNavigationPayloadString(NSString* urlString, int userGesture, int isRedirect);
std::string openURLInTabPayloadString(NSString* urlString, bool activatesTab);
std::string normalizedPermissionOriginString(NSString* rawURLString);
std::string topLevelPermissionOriginString(cef_browser_t* browser);
std::string frameIdentifierString(cef_frame_t* frame);
const std::string& pictureInPictureObserverScript();
void injectPictureInPictureObserverScript(cef_frame_t* frame);
std::string firstFaviconURLFromList(cef_string_list_t iconURLs);
