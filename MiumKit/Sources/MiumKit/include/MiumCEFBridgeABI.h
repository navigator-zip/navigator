// MiumCEFBridge ABI contract.
//
// This file defines the stable C-facing API surface for the native bridge.
// Implementations can evolve internally as long as these exported symbols and
// payload contracts remain compatible.

#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - ABI and schema contract constants

// Bumped when runtime ABI contracts change.
#define MIUM_CEF_RUNTIME_ABI_VERSION "1.0.0"
// Bumped when the bridge public contract changes.
#define MIUM_CEF_BRIDGE_SCHEMA_VERSION "1.0.0"

// MARK: - Opaque runtime handles

typedef struct MiumCEFRuntime* MiumCEFRuntimeHandle;
typedef struct MiumCEFBrowser* MiumCEFBrowserHandle;
typedef struct MiumCEFHostView* MiumCEFHostViewHandle;
typedef uint64_t MiumCEFBrowserID;
typedef uint32_t MiumCEFErrorCode;

// MARK: - Result and error model

typedef enum MiumCEFResult {
  MIUM_CEF_OK = 0,
  MIUM_CEF_ERROR = 1,
  MIUM_CEF_INVALID_ARGUMENT = 2,
  MIUM_CEF_NOT_INITIALIZED = 3,
  MIUM_CEF_ALREADY_SHUTDOWN = 4,
} MiumCEFResult;

typedef void (*MiumCEFEventCallback)(MiumCEFErrorCode code, const char* message, void* context);

// MARK: - Runtime lifecycle

MiumCEFResult miumCEFInitialize(
  const char* runtimeRootPath,
  const char* runtimeMetadataPath,
  MiumCEFEventCallback eventCallback,
  void* eventContext,
  MiumCEFRuntimeHandle* outHandle
);

MiumCEFResult miumCEFShutdown(MiumCEFRuntimeHandle runtimeHandle);

// MARK: - Browser lifecycle

MiumCEFResult miumCEFCreateBrowser(
  MiumCEFRuntimeHandle runtimeHandle,
  MiumCEFBrowserHandle* outBrowserHandle
);

MiumCEFResult miumCEFDestroyBrowser(MiumCEFBrowserHandle browserHandle);
MiumCEFResult miumCEFCreateBrowserHostView(
  MiumCEFBrowserHandle browserHandle,
  MiumCEFHostViewHandle* outHostViewHandle
);
MiumCEFResult miumCEFCreateBrowserHostViewForNSView(
  MiumCEFBrowserHandle browserHandle,
  void* hostView,
  MiumCEFHostViewHandle* outHostViewHandle
);
MiumCEFResult miumCEFDestroyBrowserHostView(MiumCEFHostViewHandle hostViewHandle);
MiumCEFResult miumCEFAttachBrowserToHostView(
  MiumCEFBrowserHandle browserHandle,
  MiumCEFHostViewHandle hostViewHandle
);
MiumCEFResult miumCEFDetachBrowserFromHostView(
  MiumCEFBrowserHandle browserHandle
);

// MARK: - Navigation and load control

MiumCEFResult miumCEFLoadURL(
  MiumCEFBrowserHandle browserHandle,
  const char* url,
  void* completionContext,
  void (*completion)(MiumCEFErrorCode code, const char* result, void* context)
);

MiumCEFResult miumCEFReload(MiumCEFBrowserHandle browserHandle);
MiumCEFResult miumCEFStopLoad(MiumCEFBrowserHandle browserHandle);

// MARK: - JavaScript execution

MiumCEFResult miumCEFEvaluateJavaScript(
  MiumCEFBrowserHandle browserHandle,
  const char* script,
  void* completionContext,
  void (*completion)(MiumCEFErrorCode code, const char* jsonResult, void* context)
);

// MARK: - Snapshot and message bridge
//
// `jsonOptions` is an optional JSON object. Supported keys:
// - `format`: `png`, `jpg`/`jpeg`, `tif`/`tiff`, `gif`, `bmp`, or `pdf`
// - `quality`: JPEG compression quality in the range `0.0...1.0`
// - `clip` / `clipRect`: `{ "x": ..., "y": ..., "width": ..., "height": ... }`
//   in host-view point coordinates

MiumCEFResult miumCEFRequestSnapshot(
  MiumCEFBrowserHandle browserHandle,
  const char* outputPath,
  const char* jsonOptions,
  void* completionContext,
  void (*completion)(MiumCEFErrorCode code, const char* snapshotPath, void* context)
);

MiumCEFResult miumCEFResizeBrowser(
  MiumCEFBrowserHandle browserHandle,
  int width,
  int height
);

MiumCEFResult miumCEFDoMessageLoopWork(void);

MiumCEFResult miumCEFRegisterMessageHandler(
  MiumCEFBrowserHandle browserHandle,
  const char* channel,
  void* handlerContext,
  MiumCEFEventCallback handler
);

MiumCEFResult miumCEFSendMessage(
  MiumCEFBrowserHandle browserHandle,
  const char* channel,
  const char* jsonPayload,
  void* completionContext,
  void (*completion)(MiumCEFErrorCode code, const char* response, void* context)
);

#ifdef __cplusplus
}
#endif
