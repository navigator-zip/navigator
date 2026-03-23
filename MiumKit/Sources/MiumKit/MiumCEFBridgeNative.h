#pragma once

#include <stdint.h>

#ifdef __cplusplus
#include "MiumCEFBridgeCallbackRegistration.h"

using MiumCEFResultCode = uint32_t;
using MiumCEFEventCallback = void (*)(MiumCEFResultCode, const char*, void*);
using MiumCEFCompletion = void (*)(MiumCEFResultCode, const char*, void*);
using MiumCEFRuntimeHandle = void*;
using MiumCEFBrowserHandle = void*;
using MiumCEFHostViewHandle = void*;
using MiumCEFPermissionSessionID = uint64_t;

// Browser-scoped best-effort UI/state channels. Delivery is pruned after browser teardown and
// follows the bridge queue's overflow policy when buffers back up.
static constexpr const char* MiumCEFAddressChangeChannel = "__addressChange__";
static constexpr const char* MiumCEFTitleChangeChannel = "__titleChange__";
static constexpr const char* MiumCEFFaviconURLChangeChannel = "__faviconURLChange__";
static constexpr const char* MiumCEFPictureInPictureStateChangeChannel = "__pictureInPictureStateChange__";
static constexpr const char* MiumCEFPictureInPicturePromptMessage = "__miumPictureInPictureStateChange__";
static constexpr const char* MiumCEFTopLevelNativeContentChannel = "__topLevelNativeContent__";
static constexpr const char* MiumCEFRenderProcessTerminationChannel = "__renderProcessTermination__";
static constexpr const char* MiumCEFMainFrameNavigationChannel = "__mainFrameNavigation__";
static constexpr const char* MiumCEFOpenURLInTabChannel = "__openURLInTab__";
static constexpr const char* MiumCEFCameraRoutingEventChannel = "__cameraRoutingEvent__";
static constexpr const char* MiumCEFCameraRoutingPromptMessage = "__navigatorCameraRoutingEvent__";
static constexpr const char* MiumCEFCameraRoutingEventBridgeFunctionName = "__navigatorCameraRoutingEmitEvent";
static constexpr const char* MiumCEFCameraRoutingConfigUpdateChannel = "__cameraRoutingConfigUpdate__";
static constexpr const char* MiumCEFCameraFrameDeliveryChannel = "__cameraFrameDelivery__";
static constexpr const char* MiumCEFCameraFrameClearChannel = "__cameraFrameClear__";
static constexpr const char* MiumCEFRendererExecuteJavaScriptChannel = "__rendererExecuteJavaScript__";
static constexpr const char* MiumCEFRendererExecuteJavaScriptResultChannel =
  "__rendererExecuteJavaScriptResult__";

enum class MiumCEFPermissionKindFlags : uint32_t {
  none = 0,
  camera = 1 << 0,
  microphone = 1 << 1,
  geolocation = 1 << 2,
};

enum class MiumCEFPermissionRequestSource : uint32_t {
  mediaAccess = 0,
  permissionPrompt = 1,
};

enum class MiumCEFPermissionResolution : uint32_t {
  deny = 0,
  allow = 1,
  cancel = 2,
};

enum class MiumCEFPermissionSessionDismissReason : uint32_t {
  unknown = 0,
  browserClosed = 1,
  renderProcessTerminated = 2,
  mainFrameNavigation = 3,
  promptDismissed = 4,
  explicitCancel = 5,
};

struct MiumCEFPermissionRequest {
  MiumCEFPermissionSessionID sessionID = 0;
  uint64_t browserID = 0;
  uint64_t promptID = 0;
  const char* frameIdentifier = nullptr;
  uint32_t permissionFlags = 0;
  uint32_t source = 0;
  const char* requestingOrigin = nullptr;
  const char* topLevelOrigin = nullptr;
};

using MiumCEFPermissionRequestCallback = void (*)(void* context, const MiumCEFPermissionRequest*);
using MiumCEFPermissionSessionDismissedCallback = void (*)(
  void* context,
  MiumCEFPermissionSessionID sessionID,
  uint32_t reason
);

extern "C" MiumCEFResultCode miumNativeCEFRegisterMessageHandlerWithRegistration(
  MiumCEFBrowserHandle browserHandle,
  const char* channel,
  const MiumCEFCallbackRegistrationRef& registration,
  void* handlerContext,
  MiumCEFEventCallback handler
);
extern "C" MiumCEFResultCode miumNativeCEFSetPermissionRequestHandlerWithRegistration(
  MiumCEFBrowserHandle browserHandle,
  const MiumCEFCallbackRegistrationRef& registration,
  void* handlerContext,
  MiumCEFPermissionRequestCallback handler
);
extern "C" MiumCEFResultCode miumNativeCEFSetPermissionSessionDismissedHandlerWithRegistration(
  MiumCEFBrowserHandle browserHandle,
  const MiumCEFCallbackRegistrationRef& registration,
  void* handlerContext,
  MiumCEFPermissionSessionDismissedCallback handler
);

extern "C" {
#endif

static const MiumCEFResultCode MiumCEFResultOK = 0;
static const MiumCEFResultCode MiumCEFResultError = 1;
static const MiumCEFResultCode MiumCEFResultInvalidArgument = 2;
static const MiumCEFResultCode MiumCEFResultNotInitialized = 3;
static const MiumCEFResultCode MiumCEFResultAlreadyShutdown = 4;

bool miumNativeCEFIsLoaded(void);
int miumNativeCEFMaybeRunSubprocess(int argc, const char* const* argv);
int miumNativeCEFHasPendingBrowserClose(void);

MiumCEFResultCode miumNativeCEFDestroyBrowserHostView(MiumCEFHostViewHandle hostViewHandle);
MiumCEFResultCode miumNativeCEFInitialize(
  const char* runtimeRootPath,
  const char* runtimeMetadataPath,
  MiumCEFEventCallback eventCallback,
  void* eventContext,
  MiumCEFRuntimeHandle* outRuntimeHandle
);
MiumCEFResultCode miumNativeCEFShutdown(MiumCEFRuntimeHandle runtimeHandle);
MiumCEFResultCode miumNativeCEFDoMessageLoopWork();
MiumCEFResultCode miumNativeCEFCreateBrowser(
  MiumCEFRuntimeHandle runtimeHandle,
  MiumCEFBrowserHandle* outBrowserHandle
);
MiumCEFResultCode miumNativeCEFDestroyBrowser(MiumCEFBrowserHandle browserHandle);
MiumCEFResultCode miumNativeCEFCreateBrowserHostView(
  MiumCEFBrowserHandle browserHandle,
  MiumCEFHostViewHandle* outHostViewHandle
);
MiumCEFResultCode miumNativeCEFCreateBrowserHostViewForNSView(
  MiumCEFBrowserHandle browserHandle,
  void* hostView,
  MiumCEFHostViewHandle* outHostViewHandle
);
MiumCEFResultCode miumNativeCEFGoBack(MiumCEFBrowserHandle browserHandle);
MiumCEFResultCode miumNativeCEFGoForward(MiumCEFBrowserHandle browserHandle);
int miumNativeCEFCanGoBack(MiumCEFBrowserHandle browserHandle);
int miumNativeCEFCanGoForward(MiumCEFBrowserHandle browserHandle);
int miumNativeCEFIsLoading(MiumCEFBrowserHandle browserHandle);
MiumCEFResultCode miumNativeCEFDestroyBrowserHostView(MiumCEFHostViewHandle hostViewHandle);
MiumCEFResultCode miumNativeCEFAttachBrowserToHostView(
  MiumCEFBrowserHandle browserHandle,
  MiumCEFHostViewHandle hostViewHandle
);
MiumCEFResultCode miumNativeCEFDetachBrowserFromHostView(MiumCEFBrowserHandle browserHandle);
MiumCEFHostViewHandle miumNativeCEFHostViewHandleForBrowser(MiumCEFBrowserHandle browserHandle);
// Completion fires after the main-frame navigation request is submitted, not after navigation
// commits or the document finishes loading.
MiumCEFResultCode miumNativeCEFLoadURL(
  MiumCEFBrowserHandle browserHandle,
  const char* url,
  void* completionContext,
  MiumCEFCompletion completion
);
MiumCEFResultCode miumNativeCEFReload(MiumCEFBrowserHandle browserHandle);
MiumCEFResultCode miumNativeCEFStopLoad(MiumCEFBrowserHandle browserHandle);
MiumCEFResultCode miumNativeCEFResizeBrowser(
  MiumCEFBrowserHandle browserHandle,
  int width,
  int height
);
// Fire-and-forget main-frame script injection. Completion acknowledges dispatch only and does not
// return the JavaScript evaluation result.
MiumCEFResultCode miumNativeCEFEvaluateJavaScript(
  MiumCEFBrowserHandle browserHandle,
  const char* script,
  void* completionContext,
  MiumCEFCompletion completion
);
// Captures best-effort current host-view pixels (or a host-view PDF). Output may reflect transient
// AppKit compositing state and is not a guaranteed fully composited Chromium frame.
MiumCEFResultCode miumNativeCEFRequestSnapshot(
  MiumCEFBrowserHandle browserHandle,
  const char* outputPath,
  const char* jsonOptions,
  void* completionContext,
  MiumCEFCompletion completion
);
MiumCEFResultCode miumNativeCEFRegisterMessageHandler(
  MiumCEFBrowserHandle browserHandle,
  const char* channel,
  void* handlerContext,
  MiumCEFEventCallback handler
);
MiumCEFResultCode miumNativeCEFSetPermissionRequestHandler(
  MiumCEFBrowserHandle browserHandle,
  void* handlerContext,
  MiumCEFPermissionRequestCallback handler
);
MiumCEFResultCode miumNativeCEFSetPermissionSessionDismissedHandler(
  MiumCEFBrowserHandle browserHandle,
  void* handlerContext,
  MiumCEFPermissionSessionDismissedCallback handler
);
MiumCEFResultCode miumNativeCEFResolvePermissionRequest(
  MiumCEFPermissionSessionID sessionID,
  uint32_t resolution
);
MiumCEFResultCode miumNativeCEFEmitMessage(
  MiumCEFBrowserHandle browserHandle,
  const char* channel,
  const char* message
);
// Sends one UTF-8 payload as renderer-process argument slot 0 on the main frame. Completion only
// acknowledges CEF-side dispatch, not renderer-side handling or application-level response.
MiumCEFResultCode miumNativeCEFSendMessage(
  MiumCEFBrowserHandle browserHandle,
  const char* channel,
  const char* jsonPayload,
  void* completionContext,
  MiumCEFCompletion completion
);
// Evaluates JavaScript on the renderer main-frame V8 context and reports the renderer-side result
// or error text back to the completion callback.
MiumCEFResultCode miumNativeCEFExecuteJavaScriptInRendererWithResult(
  MiumCEFBrowserHandle browserHandle,
  const char* script,
  void* completionContext,
  MiumCEFCompletion completion
);

#ifdef __cplusplus
} // extern "C"
#endif
