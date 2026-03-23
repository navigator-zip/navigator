#include "MiumCEFBridgeInternalState.h"

#include <functional>
#include <string>
#include <utility>
#include <vector>

#include "MiumCEFBridgeBrowserEvents.h"
#include "MiumCEFBridgeBrowserRegistry.h"
#include "MiumCEFBridgePermissions.h"
#include "MiumCEFBridgeRendererJavaScript.h"
#include "MiumCEFBridgeShutdown.h"
#include "MiumCEFBridgeThreading.h"

namespace {

template <typename Fn>
static void runOnCefMainThread(Fn fn) {
  miumCEFRunOnCefMainThread(std::function<void()>(std::move(fn)));
}

static void executePermissionBatchOnCefMainThread(MiumCEFPermissionExecutionBatch&& batch) {
  runOnCefMainThread([batch = std::move(batch)]() mutable {
    miumCEFPermissionExecuteBatch(&batch);
  });
}

static void executePermissionBatchesOnCefMainThread(std::vector<MiumCEFPermissionExecutionBatch>&& batches) {
  for (auto& batch : batches) {
    executePermissionBatchOnCefMainThread(std::move(batch));
  }
}

static int64_t browserIdentifierFromNativeBrowser(cef_browser_t* browser) {
  if (browser == nullptr || browser->get_identifier == nullptr) {
    return -1;
  }
  return browser->get_identifier(browser);
}

} // namespace

bool miumCEFIsCefRuntimeUsableLocked() {
  return gCEFInitialized && !gCEFShutdownExecuting && miumCEFHasLoadedFrameworkArtifactsLocked();
}

int64_t miumCEFBrowserIdentifierFromNativeBrowser(cef_browser_t* browser) {
  return browserIdentifierFromNativeBrowser(browser);
}

std::vector<MiumCEFRendererJavaScriptRequestState> miumCEFTakeRendererJavaScriptRequestsForBrowserLocked(
  uint64_t browserId
) {
  return takeRendererJavaScriptRequestsForBrowserLocked(browserId);
}

void miumCEFFailRendererJavaScriptRequestsForBrowser(
  uint64_t browserId,
  const char* message,
  bool deliverAfterBrowserRemoval
) {
  failRendererJavaScriptRequestsForBrowser(browserId, message, deliverAfterBrowserRemoval);
}

bool miumCEFSnapshotNativeCallbackPayloadDeliverable(
  uint64_t browserId,
  const char* channel,
  uint64_t handlerGeneration
) {
  return snapshotNativeCallbackPayloadDeliverable(browserId, channel, handlerGeneration);
}

uint64_t miumCEFNativeBrowserIdFromNativeBrowser(cef_browser_t* browser) {
  return browserIdFromNativeBrowser(browser);
}

std::string miumCEFNativeProcessMessageName(cef_process_message_t* message) {
  return processMessageName(message);
}

std::string miumCEFNativeProcessMessageArgumentString(cef_process_message_t* message, size_t index) {
  return processMessageArgumentString(message, index);
}

bool miumCEFNativeHandleRendererExecuteJavaScriptResultMessage(
  cef_browser_t* browser,
  const char* channel,
  const char* requestID,
  const char* result,
  const char* error
) {
  return handleRendererExecuteJavaScriptResultMessage(browser, channel, requestID, result, error);
}

void miumCEFNativeExecutePermissionBatchOnCefMainThread(MiumCEFPermissionExecutionBatch&& batch) {
  executePermissionBatchOnCefMainThread(std::move(batch));
}

void miumCEFNativeExecutePermissionBatchesOnCefMainThread(std::vector<MiumCEFPermissionExecutionBatch>&& batches) {
  executePermissionBatchesOnCefMainThread(std::move(batches));
}

bool miumCEFNativeHandleRendererExecuteJavaScriptRequestMessage(
  cef_frame_t* frame,
  const char* channel,
  const char* requestID,
  const char* script
) {
  return handleRendererExecuteJavaScriptRequestMessage(frame, channel, requestID, script);
}
