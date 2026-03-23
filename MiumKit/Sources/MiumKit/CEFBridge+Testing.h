#pragma once

#if defined(MIUM_CEF_BRIDGE_TESTING)

#include "CEFBridge.h"
#include "MiumCEFBridgeNative.h"

#ifdef __cplusplus

#include <string>

enum class CEFBridgeTestFailureMode : unsigned char {
  none = 0,
  normalizeStandardizeReturnsNil,
  normalizeUTF8ReturnsNull,
  bundlePathReturnsNil,
  bundleFileSystemRepresentationReturnsNull,
  resourcesFileSystemRepresentationReturnsNull,
  resourcesFileSystemRepresentationReturnsEmpty,
  bundleFileSystemRepresentationReturnsEmpty,
  initializeReturnsOKWithNullRuntime,
  createBrowserReturnsOKWithNullHandle,
  createHostViewReturnsOKWithNullHandle,
};

bool CEFBridgeTestIsCefSubprocessArgv(int argc, const char* const* argv);
std::string CEFBridgeTestNormalizeCPath(const char* path);
std::string CEFBridgeTestResolveRuntimeRoot(const char* resourcesPath);
std::string CEFBridgeTestResolveMetadataPath(const char* resourcesPath);
void CEFBridgeTestResetState(void);
void CEFBridgeTestSetBridgeRuntimeState(MiumCEFRuntimeHandle runtime, bool initialized);
void CEFBridgeTestBrowserBridgeMessageHandler(MiumCEFResultCode code, const char* message, void* context);
void CEFBridgeTestBrowserBridgeMessageHandlerForBrowser(
  CEFBridgeBrowserRef browserRef,
  const char* channel,
  MiumCEFResultCode code,
  const char* message
);
void CEFBridgeTestSetBrowserBridgeMessageHandler(
  CEFBridgeBrowserRef browserRef,
  const char* channel,
  CEFBridgeMessageCallback callback,
  void* userData
);
void CEFBridgeTestBrowserPermissionRequestHandler(void* context, const MiumCEFPermissionRequest* request);
void CEFBridgeTestBrowserPermissionRequestHandlerForBrowser(
  CEFBridgeBrowserRef browserRef,
  const MiumCEFPermissionRequest* request
);
void CEFBridgeTestInstallRawPermissionRequestHandlerState(
  CEFBridgeBrowserRef browserRef,
  CEFBridgePermissionRequestCallback callback,
  void* userData
);
void CEFBridgeTestBrowserPermissionSessionDismissedHandler(
  void* context,
  MiumCEFPermissionSessionID sessionID,
  uint32_t reason
);
void CEFBridgeTestBrowserPermissionSessionDismissedHandlerForBrowser(
  CEFBridgeBrowserRef browserRef,
  MiumCEFPermissionSessionID sessionID,
  uint32_t reason
);
void CEFBridgeTestInstallRawPermissionDismissedHandlerState(
  CEFBridgeBrowserRef browserRef,
  CEFBridgePermissionSessionDismissedCallback callback,
  void* userData
);
void CEFBridgeTestInstallRawMessageHandlerState(
  CEFBridgeBrowserRef browserRef,
  const char* channel,
  CEFBridgeMessageCallback callback,
  void* userData
);
void CEFBridgeTestForwardJavaScriptResult(
  MiumCEFResultCode code,
  const char* result,
  CEFBridgeJavaScriptResultCallback callback,
  void* userData,
  bool useNullContext
);
void CEFBridgeTestSetFailureMode(CEFBridgeTestFailureMode mode);

#endif

#endif
