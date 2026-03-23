#pragma once

#if defined(MIUM_CEF_BRIDGE_TESTING)

#include "MiumCEFBridgeNative.h"
#include "include/MiumCEFBridgeCefTypes.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef int (*MiumCEFTestStringUTF8ToUTF16Fn)(const char* source, size_t source_length, cef_string_t* output);
typedef void (*MiumCEFTestStringUTF16ClearFn)(cef_string_t* value);
typedef void (*MiumCEFTestStringUserFreeUTF16FreeFn)(cef_string_userfree_utf16_t value);
typedef size_t (*MiumCEFTestStringListSizeFn)(cef_string_list_t list);
typedef int (*MiumCEFTestStringListValueFn)(cef_string_list_t list, size_t index, cef_string_t* value);
typedef int (*MiumCEFTestInitializeFn)(
  const cef_main_args_t* args,
  const cef_settings_t* settings,
  cef_app_t* application,
  void* windows_sandbox_info
);
typedef int (*MiumCEFTestExecuteProcessFn)(
  const cef_main_args_t* args,
  cef_app_t* application,
  void* windows_sandbox_info
);
typedef void (*MiumCEFTestShutdownFn)(void);
typedef void (*MiumCEFTestDoMessageLoopWorkFn)(void);
typedef cef_browser_t* (*MiumCEFTestCreateBrowserSyncFn)(
  const cef_window_info_t* windowInfo,
  cef_client_t* client,
  const cef_string_t* url,
  const cef_browser_settings_t* settings,
  cef_dictionary_value_t* extraInfo,
  cef_request_context_t* requestContext
);
typedef cef_process_message_t* (*MiumCEFTestCreateProcessMessageFn)(const cef_string_t* name);
typedef cef_v8_value_t* (*MiumCEFTestCreateV8FunctionFn)(
  const cef_string_t* name,
  cef_v8_handler_t* handler
);
typedef cef_v8_context_t* (*MiumCEFTestCurrentV8ContextFn)(void);
typedef void (*MiumCEFBridgeTestVoidCallback)(void* context);
typedef void (*MiumCEFBridgeTestProcessExitCallback)(int exitCode);

typedef struct MiumCEFBridgeTestAPI {
  MiumCEFTestStringUTF8ToUTF16Fn utf8ToUTF16;
  MiumCEFTestStringUTF16ClearFn utf16Clear;
  MiumCEFTestStringUserFreeUTF16FreeFn userfreeFree;
  MiumCEFTestStringListSizeFn stringListSize;
  MiumCEFTestStringListValueFn stringListValue;
  MiumCEFTestInitializeFn initialize;
  MiumCEFTestExecuteProcessFn executeProcess;
  MiumCEFTestShutdownFn shutdown;
  MiumCEFTestDoMessageLoopWorkFn doMessageLoopWork;
  MiumCEFTestCreateBrowserSyncFn createBrowserSync;
  MiumCEFTestCreateProcessMessageFn createProcessMessage;
  MiumCEFTestCreateV8FunctionFn createV8Function;
  MiumCEFTestCurrentV8ContextFn currentV8Context;
} MiumCEFBridgeTestAPI;

void miumNativeCEFTestResetState(void);
// Replaces the injected CEF API and clears framework/load and CEF init bookkeeping.
// Does not clear runtimes, browsers, or host views; use `miumNativeCEFTestResetState` for that.
void miumNativeCEFTestInstallAPI(const MiumCEFBridgeTestAPI* api);
void miumNativeCEFTestSetFrameworkLoaded(bool loaded);
void miumNativeCEFTestSetFrameworkHandle(void* frameworkHandle);
void miumNativeCEFTestSetInitialized(bool initialized, int initializeCount);
void miumNativeCEFTestSetShutdownExecuting(bool shutdownExecuting);
bool miumNativeCEFTestIsInitialized(void);
bool miumNativeCEFTestIsShutdownExecuting(void);
MiumCEFRuntimeHandle miumNativeCEFTestInsertRuntime(
  const char* runtimeRootPath,
  const char* runtimeMetadataPath,
  bool active
);
bool miumNativeCEFTestSetHostViewPointer(MiumCEFHostViewHandle hostViewHandle, void* hostView);
void* miumNativeCEFTestGetHostViewPointer(MiumCEFHostViewHandle hostViewHandle);
uint64_t miumNativeCEFTestGetBrowserHostViewId(MiumCEFBrowserHandle browserHandle);
cef_client_t* miumNativeCEFTestGetNativeClient(MiumCEFBrowserHandle browserHandle);
size_t miumNativeCEFTestActivePermissionSessionCount(void);
bool miumNativeCEFTestHasActivePermissionSession(MiumCEFPermissionSessionID sessionID);
// Transfers one owned CEF ref for each non-null pointer into bridge-managed state.
// The bridge releases or replaces those refs during later teardown/rebinding.
bool miumNativeCEFTestAttachNativeBrowser(
  MiumCEFBrowserHandle browserHandle,
  cef_browser_t* browser,
  cef_client_t* client
);
MiumCEFHostViewHandle miumNativeCEFTestHostViewHandleForBrowser(MiumCEFBrowserHandle browserHandle);
MiumCEFBrowserHandle miumNativeCEFTestBrowserHandleForHostView(MiumCEFHostViewHandle hostViewHandle);
void miumNativeCEFTestRunOnCefExecutor(void* context, MiumCEFBridgeTestVoidCallback callback);
void miumNativeCEFTestRunOnCefExecutorAsync(void* context, MiumCEFBridgeTestVoidCallback callback);
void miumNativeCEFTestRunOnMainThread(void* context, MiumCEFBridgeTestVoidCallback callback);
void miumNativeCEFTestRunOffMainThread(void* context, MiumCEFBridgeTestVoidCallback callback);
void miumNativeCEFTestRunOnMessageQueue(
  MiumCEFEventCallback callback,
  MiumCEFResultCode code,
  const char* message,
  void* context,
  uint64_t browserId
);
void miumNativeCEFTestRunOnMessageQueueForHandler(
  MiumCEFEventCallback callback,
  MiumCEFResultCode code,
  const char* message,
  void* context,
  uint64_t browserId,
  const char* channel,
  uint64_t handlerGeneration
);
void miumNativeCEFTestRunOnMessageQueueForHandlerWithRegistration(
  MiumCEFEventCallback callback,
  MiumCEFResultCode code,
  const char* message,
  const MiumCEFCallbackRegistrationRef& registration,
  void* context,
  uint64_t browserId,
  const char* channel,
  uint64_t handlerGeneration
);
void miumNativeCEFTestSetBundleExecutablePathOverride(const char* path);
void miumNativeCEFTestSetBundleExecutablePathNil(bool enabled);
void miumNativeCEFTestSetBundlePathNil(bool enabled);
void miumNativeCEFTestSetBundleIdentifierOverride(const char* bundleIdentifier);
void miumNativeCEFTestSetBundleIdentifierNil(bool enabled);
void miumNativeCEFTestSetCachesDirectoryOverride(const char* cachesDirectory);
void miumNativeCEFTestSetCachesDirectoriesEmpty(bool enabled);
void miumNativeCEFTestSetRendererJavaScriptRequestTimeoutSeconds(double timeoutSeconds);
void miumNativeCEFTestSetMediaStreamOverrideDevelopmentEligible(bool enabled);
void miumNativeCEFTestResetMediaStreamOverrideDevelopmentEligibility(void);
void miumNativeCEFTestSetProcessExitCallback(MiumCEFBridgeTestProcessExitCallback callback);
void miumNativeCEFTestSetInterceptProcessExit(bool enabled);
int miumNativeCEFTestLastInterceptedProcessExitCode(void);
void miumNativeCEFTestSetCreateBrowserClientReturnsNull(bool enabled);
void miumNativeCEFTestSetNextBrowserClientMissingDisplayHandler(bool enabled);
void miumNativeCEFTestSetNextIds(uint64_t runtimeId, uint64_t browserId, uint64_t hostViewId);
bool miumNativeCEFTestHandleRendererExecuteJavaScriptRequestMessage(
  cef_frame_t* frame,
  const char* channel,
  const char* requestID,
  const char* script
);
bool miumNativeCEFTestHandleRendererManagedCameraFrameMessage(
  cef_frame_t* frame,
  const char* channel,
  const char* payload
);
bool miumNativeCEFTestHandleRendererManagedCameraConfigMessage(
  cef_frame_t* frame,
  const char* channel,
  const char* payload
);
bool miumNativeCEFTestInstallRendererCameraRoutingEventBridge(
  cef_frame_t* frame,
  cef_v8_context_t* context
);
bool miumNativeCEFTestHandleRendererExecuteJavaScriptResultMessage(
  cef_browser_t* browser,
  const char* channel,
  const char* requestID,
  const char* result,
  const char* error
);
void miumNativeCEFTestTriggerRenderProcessTerminated(
  cef_browser_t* browser,
  int status,
  int errorCode,
  const char* errorString
);

#ifdef __cplusplus
} // extern "C"

#include <cstdint>
#include <cstddef>
#include <string>
#include <vector>

struct MiumCEFBridgeTestRuntimeLayout {
  std::string resourcesDir;
  std::string localesDir;
  std::string helpersDir;
};

struct MiumCEFBridgeTestSnapshotOptions {
  long bitmapFileType = 0;
  double jpegCompressionFactor = 0;
  bool usesJPEGCompressionFactor = false;
  bool captureAsPDF = false;
  bool hasClipRect = false;
  double clipX = 0;
  double clipY = 0;
  double clipWidth = 0;
  double clipHeight = 0;
};

enum class MiumCEFBridgeTestCloseKind : uint8_t {
  teardown = 0,
  replacement = 1,
};

enum class MiumCEFBridgeTestCallbackRoute : uint8_t {
  ui = 0,
  nonUI = 1,
};

enum class MiumCEFBridgeTestCallbackOverflowPolicy : uint8_t {
  dropOldest = 0,
  latest = 1,
  coalesce = 2,
};

enum class MiumCEFBridgeTestWindowSnapshotMode : uint8_t {
  live = 0,
  forceNullImage = 1,
  forceOnePixelImage = 2,
};

enum class MiumCEFBridgeTestOnePixelImageFailureMode : uint8_t {
  none = 0,
  nullProvider = 1,
  nullColorSpace = 2,
};

enum class MiumCEFBridgeTestBrowserCloseDisposition : uint8_t {
  failed = 0,
  completedSynchronously = 1,
  closePending = 2,
};

std::string miumNativeCEFTestNormalizePath(const char* path);
bool miumNativeCEFTestSetCefSettingPath(const char* value, std::string* errorOut);
std::vector<std::string> miumNativeCEFTestCandidatePaths(
  const char* runtimeRootPath,
  const char* runtimeMetadataPath
);
std::string miumNativeCEFTestTrimWhitespaceInString(const char* value);
std::string miumNativeCEFTestMakePathFromRootAndRelative(
  const char* rootPath,
  const char* relativePath
);
bool miumNativeCEFTestDirectoryContainsCefLocaleResources(const char* directoryPath);
std::string miumNativeCEFTestNormalizeChromiumLocalesPathCandidate(const char* candidatePath);
std::string miumNativeCEFTestResolveChromiumLocalesPath(const char* runtimeRootPath);
MiumCEFBridgeTestRuntimeLayout miumNativeCEFTestResolveRuntimeLayoutConfig(
  const char* runtimeRootPath,
  const char* runtimeMetadataPath
);
std::string miumNativeCEFTestHostExecutableBasename(void);
bool miumNativeCEFTestPathExistsAndIsDirectory(const char* path, bool mustBeDirectory);
bool miumNativeCEFTestPathExistsAsFile(const char* path);
std::string miumNativeCEFTestResolveHelperBundlePath(const char* helpersDirPath);
std::string miumNativeCEFTestResolveHelperSubprocessPath(
  const char* runtimeRootPath,
  const char* runtimeMetadataPath
);
std::string miumNativeCEFTestDescribeFrameworkCandidateFailure(
  const std::vector<std::string>& candidates
);
bool miumNativeCEFTestVerifyCefApiCompatibility(const char* runtimeHash, const char* expectedHash);
bool miumNativeCEFTestLoadSymbol(void* handle, const char* symbolName, void** destination);
bool miumNativeCEFTestLoadRequiredCefSymbols(void* frameworkHandle);
bool miumNativeCEFTestOpenFrameworkIfNeeded(const std::vector<std::string>& candidates);
bool miumNativeCEFTestEnsureCefInitialized(
  const char* runtimeRootPath,
  const char* runtimeMetadataPath,
  std::string* failureReason
);
bool miumNativeCEFTestParseBooleanEnvironmentFlag(const char* name);
bool miumNativeCEFTestHasEnvironmentValue(const char* name);
bool miumNativeCEFTestShouldDisableCEFChildProcessSandbox(void);
bool miumNativeCEFTestShouldInterceptProcessExitCode(int exitCode);
int miumNativeCEFTestSingletonOwnerPIDFromLockDestination(const char* destinationPath);
bool miumNativeCEFTestIsLiveNavigatorProcess(int pid);
void miumNativeCEFTestRemoveStaleSingletonArtifacts(const char* candidatePath);
std::string miumNativeCEFTestResolveCEFUserDataDirectory(void);
bool miumNativeCEFTestCanBindBrowserToHostView(
  MiumCEFBrowserHandle browserHandle,
  MiumCEFHostViewHandle hostViewHandle,
  void* hostView
);
bool miumNativeCEFTestBindBrowserToHostView(
  MiumCEFBrowserHandle browserHandle,
  MiumCEFHostViewHandle hostViewHandle,
  void* hostView
);
void miumNativeCEFTestClearBrowserHostViewBinding(MiumCEFBrowserHandle browserHandle);
bool miumNativeCEFTestIsBrowserHandleAvailableForCallbacks(uint64_t browserId);
uint64_t miumNativeCEFTestMessageHandlerGeneration(
  MiumCEFBrowserHandle browserHandle,
  const char* channel
);
bool miumNativeCEFTestParseSnapshotOptions(
  const char* jsonOptions,
  const char* outputPath,
  MiumCEFBridgeTestSnapshotOptions* outOptions,
  std::string* errorOut
);
bool miumNativeCEFTestConfigureSnapshotFormat(
  const char* format,
  MiumCEFBridgeTestSnapshotOptions* outOptions,
  std::string* errorOut
);
bool miumNativeCEFTestSnapshotBoundsForHostView(
  void* hostView,
  const MiumCEFBridgeTestSnapshotOptions* options,
  std::string* errorOut
);
bool miumNativeCEFTestSnapshotBitmapRepForHostViewFromWindow(
  void* hostView,
  double x,
  double y,
  double width,
  double height
);
void miumNativeCEFTestSetWindowSnapshotMode(MiumCEFBridgeTestWindowSnapshotMode mode);
void miumNativeCEFTestSetOnePixelImageFailureMode(MiumCEFBridgeTestOnePixelImageFailureMode mode);
void miumNativeCEFTestSetSubprocessFrameworkCandidates(
  const std::vector<std::string>& candidates
);
void miumNativeCEFTestSetFrameworkFallbackCandidates(
  const std::vector<std::string>& candidates
);
void miumNativeCEFTestResizeEmbeddedBrowserHostView(void* hostView, int pixelWidth, int pixelHeight);
double miumNativeCEFTestBackingScaleFactorForHostView(void* hostView);
cef_client_t* miumNativeCEFTestCreateBrowserClient(void);
bool miumNativeCEFTestCreateBrowserWithWindowInfo(
  void* hostView,
  cef_browser_t** outBrowser,
  cef_client_t** outClient
);
uint64_t miumNativeCEFTestBrowserIdFromNativeBrowser(cef_browser_t* browser);
uint64_t miumNativeCEFTestBrowserIdFromNativeBrowserPointerMapping(cef_browser_t* browser);
void miumNativeCEFTestEraseNativeBrowserPointerMapping(cef_browser_t* browser);
void miumNativeCEFTestEraseNativeBrowserIdentifierMapping(int64_t browserIdentifier);
void miumNativeCEFTestBindNativeBrowserMappings(
  MiumCEFBrowserHandle browserHandle,
  cef_browser_t* previousBrowser,
  cef_browser_t* nextBrowser
);
void miumNativeCEFTestSetBrowserStateFlags(
  MiumCEFBrowserHandle browserHandle,
  bool active,
  bool closing
);
bool miumNativeCEFTestSetHostViewBrowserId(
  MiumCEFHostViewHandle hostViewHandle,
  uint64_t browserId
);
bool miumNativeCEFTestEnsureNativeBrowser(
  MiumCEFBrowserHandle browserHandle,
  MiumCEFHostViewHandle hostViewHandle
);
void miumNativeCEFTestCloseBrowserDirect(
  cef_browser_t* browser,
  cef_client_t* client,
  MiumCEFBridgeTestCloseKind kind,
  void* context,
  MiumCEFBridgeTestVoidCallback callback
);
MiumCEFBridgeTestBrowserCloseDisposition miumNativeCEFTestBeginClosingNativeBrowser(
  MiumCEFBrowserHandle browserHandle,
  bool trackRuntimePendingClose,
  bool returnClient,
  uint64_t* outRuntimeId,
  cef_browser_t** outBrowser,
  cef_client_t** outClient
);
void miumNativeCEFTestFinalizeClosedBrowserState(
  MiumCEFBrowserHandle browserHandle,
  MiumCEFRuntimeHandle runtimeHandle
);
void miumNativeCEFTestMaybeCompletePendingCefShutdown(void);
void miumNativeCEFTestEmitDisplayHandlerFaviconURLChange(cef_browser_t* browser, const char* url);
void miumNativeCEFTestRegisterPendingBrowserClose(MiumCEFBridgeTestCloseKind kind);
void miumNativeCEFTestFinishPendingBrowserClose(MiumCEFBridgeTestCloseKind kind);
size_t miumNativeCEFTestPendingNativeBrowserCloseCount(void);
size_t miumNativeCEFTestPendingTeardownBrowserCloseCount(void);
size_t miumNativeCEFTestPendingReplacementBrowserCloseCount(void);
void miumNativeCEFTestPumpPendingShutdownMessageLoop(void);
void miumNativeCEFTestSchedulePendingShutdownPumpIfNeeded(void);
void miumNativeCEFTestSetCallbackQueueOverflowPolicy(
  MiumCEFBridgeTestCallbackRoute route,
  MiumCEFBridgeTestCallbackOverflowPolicy policy,
  uint64_t maxBufferCount
);
void miumNativeCEFTestResetCallbackQueues(void);
void miumNativeCEFTestSetCallbackQueueDraining(
  MiumCEFBridgeTestCallbackRoute route,
  bool draining
);
size_t miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute route);
std::vector<std::string> miumNativeCEFTestBufferedCallbackMessages(
  MiumCEFBridgeTestCallbackRoute route
);
void miumNativeCEFTestEnqueueCallbackPayload(
  MiumCEFEventCallback callback,
  MiumCEFResultCode code,
  const char* message,
  void* context,
  uint64_t browserId,
  MiumCEFBridgeTestCallbackRoute route
);
void miumNativeCEFTestClearCallbackPayloadsForBrowser(uint64_t browserId);
void miumNativeCEFTestClearCallbackPayloadsForBrowsers(const std::vector<uint64_t>& browserIds);
void miumNativeCEFTestSetShutdownState(bool shutdownPending, bool pumpScheduled);
bool miumNativeCEFTestIsShutdownPumpScheduled(void);
#endif

#endif
