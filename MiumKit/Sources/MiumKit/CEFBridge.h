#ifndef CEFBRIDGE_H
#define CEFBRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

typedef void* CEFBridgeBrowserRef;

// Callback string arguments are borrowed bridge-owned memory and remain valid only for the
// duration of the callback invocation. Copy any string value you need to retain after the
// callback returns.
typedef void (*CEFBridgeMessageCallback)(void* user_data, const char* message);

// `result` and `error` are borrowed callback-scoped strings. Copy either value if you need to
// retain it after the callback returns.
typedef void (*CEFBridgeJavaScriptResultCallback)(void* user_data, const char* result, const char* error);

typedef uint64_t CEFBridgePermissionSessionID;

typedef enum CEFBridgePermissionKindFlags {
  CEFBridgePermissionKindNone = 0,
  CEFBridgePermissionKindCamera = 1 << 0,
  CEFBridgePermissionKindMicrophone = 1 << 1,
  CEFBridgePermissionKindGeolocation = 1 << 2,
} CEFBridgePermissionKindFlags;

typedef enum CEFBridgePermissionRequestSource {
  CEFBridgePermissionRequestSourceMediaAccess = 0,
  CEFBridgePermissionRequestSourcePermissionPrompt = 1,
} CEFBridgePermissionRequestSource;

typedef enum CEFBridgePermissionResolution {
  CEFBridgePermissionResolutionDeny = 0,
  CEFBridgePermissionResolutionAllow = 1,
  CEFBridgePermissionResolutionCancel = 2,
} CEFBridgePermissionResolution;

typedef enum CEFBridgePermissionSessionDismissReason {
  CEFBridgePermissionSessionDismissReasonUnknown = 0,
  CEFBridgePermissionSessionDismissReasonBrowserClosed = 1,
  CEFBridgePermissionSessionDismissReasonRenderProcessTerminated = 2,
  CEFBridgePermissionSessionDismissReasonMainFrameNavigation = 3,
  CEFBridgePermissionSessionDismissReasonPromptDismissed = 4,
  CEFBridgePermissionSessionDismissReasonExplicitCancel = 5,
} CEFBridgePermissionSessionDismissReason;

typedef struct CEFBridgePermissionRequest {
  // String fields are borrowed for the duration of the callback only. Copy any value you need to
  // retain after the callback returns.
  CEFBridgePermissionSessionID session_id;
  uint64_t browser_id;
  uint64_t prompt_id;
  const char* frame_identifier;
  uint32_t permission_flags;
  uint32_t source;
  const char* requesting_origin;
  const char* top_level_origin;
} CEFBridgePermissionRequest;

typedef void (*CEFBridgePermissionRequestCallback)(
  void* user_data,
  const CEFBridgePermissionRequest* request
);
typedef void (*CEFBridgePermissionSessionDismissedCallback)(
  void* user_data,
  CEFBridgePermissionSessionID session_id,
  uint32_t reason
);

int CEFBridge_MaybeRunSubprocess(int argc, const void* argv);
int CEFBridge_Initialize(const char* resources_path,
                         const char* locales_path,
                         const char* cache_path,
                         const char* subprocess_path);
void CEFBridge_Shutdown(void);
void CEFBridge_DoMessageLoopWork(void);
int CEFBridge_HasPendingBrowserClose(void);

// Main-thread-only APIs. Browser creation, resize, navigation, JavaScript execution, and
// host-view attachment must all be invoked from the AppKit main thread.
CEFBridgeBrowserRef CEFBridge_CreateBrowser(void* parent_view,
                                           const char* initial_url,
                                           int width,
                                           int height,
                                           double backing_scale_factor);
void CEFBridge_ResizeBrowser(CEFBridgeBrowserRef browser_ref,
                            int width,
                            int height,
                            double backing_scale_factor);
void CEFBridge_LoadUrl(CEFBridgeBrowserRef browser_ref, const char* url);
void CEFBridge_StopLoad(CEFBridgeBrowserRef browser_ref);
void CEFBridge_GoBack(CEFBridgeBrowserRef browser_ref);
void CEFBridge_GoForward(CEFBridgeBrowserRef browser_ref);
void CEFBridge_Reload(CEFBridgeBrowserRef browser_ref);
void CEFBridge_CloseBrowser(CEFBridgeBrowserRef browser_ref);
int CEFBridge_CanGoBack(CEFBridgeBrowserRef browser_ref);
int CEFBridge_CanGoForward(CEFBridgeBrowserRef browser_ref);
int CEFBridge_IsLoading(CEFBridgeBrowserRef browser_ref);
void CEFBridge_ExecuteJavaScript(CEFBridgeBrowserRef browser_ref, const char* script);

// Callback delivery may arrive on a serialized background queue rather than the AppKit main
// thread. This applies to browser message callbacks, JavaScript completion callbacks, and
// permission callbacks. Dispatch to the main thread before touching NSView, NSWindow, or other
// AppKit state.
void CEFBridge_SetMessageHandler(CEFBridgeBrowserRef browser_ref, CEFBridgeMessageCallback callback, void* user_data);
void CEFBridge_SetTitleChangeHandler(
  CEFBridgeBrowserRef browser_ref,
  CEFBridgeMessageCallback callback,
  void* user_data
);
void CEFBridge_SetFaviconURLChangeHandler(
  CEFBridgeBrowserRef browser_ref,
  CEFBridgeMessageCallback callback,
  void* user_data
);
void CEFBridge_SetPictureInPictureStateChangeHandler(
  CEFBridgeBrowserRef browser_ref,
  CEFBridgeMessageCallback callback,
  void* user_data
);
void CEFBridge_SetTopLevelNativeContentHandler(
  CEFBridgeBrowserRef browser_ref,
  CEFBridgeMessageCallback callback,
  void* user_data
);
void CEFBridge_SetRenderProcessTerminationHandler(
  CEFBridgeBrowserRef browser_ref,
  CEFBridgeMessageCallback callback,
  void* user_data
);
void CEFBridge_SetMainFrameNavigationHandler(
  CEFBridgeBrowserRef browser_ref,
  CEFBridgeMessageCallback callback,
  void* user_data
);
void CEFBridge_SetOpenURLInTabHandler(
  CEFBridgeBrowserRef browser_ref,
  CEFBridgeMessageCallback callback,
  void* user_data
);
void CEFBridge_SetCameraRoutingEventHandler(
  CEFBridgeBrowserRef browser_ref,
  CEFBridgeMessageCallback callback,
  void* user_data
);
void CEFBridge_SetPermissionRequestHandler(
  CEFBridgeBrowserRef browser_ref,
  CEFBridgePermissionRequestCallback callback,
  void* user_data
);
void CEFBridge_SetPermissionSessionDismissedHandler(
  CEFBridgeBrowserRef browser_ref,
  CEFBridgePermissionSessionDismissedCallback callback,
  void* user_data
);
int CEFBridge_ResolvePermissionRequest(
  CEFBridgePermissionSessionID session_id,
  uint32_t resolution
);
// JavaScript completion callbacks may execute on a serialized background queue.
void CEFBridge_ExecuteJavaScriptWithResult(CEFBridgeBrowserRef browser_ref,
                                          const char* script,
                                          CEFBridgeJavaScriptResultCallback callback,
                                          void* user_data);
// Renderer execution completion reflects renderer-side handling and returns the evaluated result
// string when available, or an error string when evaluation fails.
void CEFBridge_ExecuteJavaScriptInRendererWithResult(
  CEFBridgeBrowserRef browser_ref,
  const char* script,
  CEFBridgeJavaScriptResultCallback callback,
  void* user_data
);

#ifdef __cplusplus
}
#endif

#endif // CEFBRIDGE_H
