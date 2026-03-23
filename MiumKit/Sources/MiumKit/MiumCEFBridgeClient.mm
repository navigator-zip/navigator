#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#include <cstring>
#include <memory>
#include <string>
#include <vector>

#include "CefRef.h"
#include "MiumCEFBridgeClient.h"
#include "MiumCEFBridgeContentClassification.h"
#include "MiumCEFBridgeInternalAdapters.h"
#include "MiumCEFBridgeInternalPermissionAdapters.h"
#include "MiumCEFBridgeInternalRendererMessageAdapters.h"
#include "MiumCEFBridgeInternalBrowserMessagingSupport.h"
#include "MiumCEFBridgeInternalBrowserPayloadSupport.h"
#include "MiumCEFBridgeInternalPopupSupport.h"
#include "MiumCEFBridgeInternalState.h"
#include "MiumCEFBridgePermissions.h"
#if defined(MIUM_CEF_BRIDGE_TESTING)
#include "MiumCEFBridgeNative+Testing.h"
#endif

static void CEF_CALLBACK miumClientAddRef(cef_base_ref_counted_t* base) {
  if (base == nullptr) {
    return;
  }
  auto* state = getBrowserClientState(base);
  state->refCount.fetch_add(1, std::memory_order_relaxed);
}

static int CEF_CALLBACK miumClientRelease(cef_base_ref_counted_t* base) {
  if (base == nullptr) {
    return 0;
  }
  auto* state = getBrowserClientState(base);
  int remaining = state->refCount.fetch_sub(1, std::memory_order_acq_rel) - 1;
  if (remaining <= 0) {
    if (state->displayHandler != nullptr && state->displayHandler->displayHandler.base.release != nullptr) {
      releaseCefBase(&state->displayHandler->displayHandler.base);
      state->displayHandler = nullptr;
    }
    if (state->lifeSpanHandler != nullptr && state->lifeSpanHandler->lifeSpanHandler.base.release != nullptr) {
      releaseCefBase(&state->lifeSpanHandler->lifeSpanHandler.base);
      state->lifeSpanHandler = nullptr;
    }
    if (state->jsDialogHandler != nullptr && state->jsDialogHandler->jsDialogHandler.base.release != nullptr) {
      releaseCefBase(&state->jsDialogHandler->jsDialogHandler.base);
      state->jsDialogHandler = nullptr;
    }
    if (state->loadHandler != nullptr && state->loadHandler->loadHandler.base.release != nullptr) {
      releaseCefBase(&state->loadHandler->loadHandler.base);
      state->loadHandler = nullptr;
    }
    if (state->permissionHandler != nullptr && state->permissionHandler->permissionHandler.base.release != nullptr) {
      releaseCefBase(&state->permissionHandler->permissionHandler.base);
      state->permissionHandler = nullptr;
    }
    if (state->requestHandler != nullptr && state->requestHandler->requestHandler.base.release != nullptr) {
      releaseCefBase(&state->requestHandler->requestHandler.base);
      state->requestHandler = nullptr;
    }
    delete state;
    return 1;
  }
  return 0;
}

static int CEF_CALLBACK miumClientHasOneRef(cef_base_ref_counted_t* base) {
  if (base == nullptr) {
    return 0;
  }
  auto* state = getBrowserClientState(base);
  return state->refCount.load(std::memory_order_relaxed) == 1 ? 1 : 0;
}

static int CEF_CALLBACK miumClientHasAtLeastOneRef(cef_base_ref_counted_t* base) {
  if (base == nullptr) {
    return 0;
  }
  auto* state = getBrowserClientState(base);
  return state->refCount.load(std::memory_order_relaxed) > 0 ? 1 : 0;
}

static int CEF_CALLBACK miumClientOnProcessMessageReceived(
  cef_client_t* self,
  cef_browser_t* browser,
  cef_frame_t* frame,
  cef_process_id_t source_process,
  cef_process_message_t* message
) {
  (void)self;
  (void)frame;
  if (source_process != PID_RENDERER) {
    return 0;
  }

  const std::string channel = miumCEFNativeProcessMessageName(message);
  const std::string requestID = miumCEFNativeProcessMessageArgumentString(message, 0);
  const std::string result = miumCEFNativeProcessMessageArgumentString(message, 1);
  const std::string error = miumCEFNativeProcessMessageArgumentString(message, 2);
  return miumCEFNativeHandleRendererExecuteJavaScriptResultMessage(
    browser,
    channel.c_str(),
    requestID.c_str(),
    result.c_str(),
    error.c_str()
  ) ? 1 : 0;
}

static void CEF_CALLBACK miumDisplayHandlerAddRef(cef_base_ref_counted_t* base) {
  auto* state = getBrowserDisplayHandlerState(base);
  if (state == nullptr) {
    return;
  }
  state->refCount.fetch_add(1, std::memory_order_relaxed);
}

static int CEF_CALLBACK miumDisplayHandlerRelease(cef_base_ref_counted_t* base) {
  auto* state = getBrowserDisplayHandlerState(base);
  if (state == nullptr) {
    return 0;
  }
  const int remaining = state->refCount.fetch_sub(1, std::memory_order_acq_rel) - 1;
  if (remaining <= 0) {
    delete state;
    return 1;
  }
  return 0;
}

static int CEF_CALLBACK miumDisplayHandlerHasOneRef(cef_base_ref_counted_t* base) {
  auto* state = getBrowserDisplayHandlerState(base);
  if (state == nullptr) {
    return 0;
  }
  return state->refCount.load(std::memory_order_relaxed) == 1 ? 1 : 0;
}

static int CEF_CALLBACK miumDisplayHandlerHasAtLeastOneRef(cef_base_ref_counted_t* base) {
  auto* state = getBrowserDisplayHandlerState(base);
  if (state == nullptr) {
    return 0;
  }
  return state->refCount.load(std::memory_order_relaxed) > 0 ? 1 : 0;
}

static void CEF_CALLBACK miumLifeSpanHandlerAddRef(cef_base_ref_counted_t* base) {
  auto* state = getBrowserLifeSpanHandlerState(base);
  if (state == nullptr) {
    return;
  }
  state->refCount.fetch_add(1, std::memory_order_relaxed);
}

static int CEF_CALLBACK miumLifeSpanHandlerRelease(cef_base_ref_counted_t* base) {
  auto* state = getBrowserLifeSpanHandlerState(base);
  if (state == nullptr) {
    return 0;
  }
  const int remaining = state->refCount.fetch_sub(1, std::memory_order_acq_rel) - 1;
  if (remaining <= 0) {
    delete state;
    return 1;
  }
  return 0;
}

static int CEF_CALLBACK miumLifeSpanHandlerHasOneRef(cef_base_ref_counted_t* base) {
  auto* state = getBrowserLifeSpanHandlerState(base);
  if (state == nullptr) {
    return 0;
  }
  return state->refCount.load(std::memory_order_relaxed) == 1 ? 1 : 0;
}

static int CEF_CALLBACK miumLifeSpanHandlerHasAtLeastOneRef(cef_base_ref_counted_t* base) {
  auto* state = getBrowserLifeSpanHandlerState(base);
  if (state == nullptr) {
    return 0;
  }
  return state->refCount.load(std::memory_order_relaxed) > 0 ? 1 : 0;
}

static void CEF_CALLBACK miumJSDialogHandlerAddRef(cef_base_ref_counted_t* base) {
  auto* state = getBrowserJSDialogHandlerState(base);
  if (state == nullptr) {
    return;
  }
  state->refCount.fetch_add(1, std::memory_order_relaxed);
}

static int CEF_CALLBACK miumJSDialogHandlerRelease(cef_base_ref_counted_t* base) {
  auto* state = getBrowserJSDialogHandlerState(base);
  if (state == nullptr) {
    return 0;
  }
  const int remaining = state->refCount.fetch_sub(1, std::memory_order_acq_rel) - 1;
  if (remaining <= 0) {
    delete state;
    return 1;
  }
  return 0;
}

static int CEF_CALLBACK miumJSDialogHandlerHasOneRef(cef_base_ref_counted_t* base) {
  auto* state = getBrowserJSDialogHandlerState(base);
  if (state == nullptr) {
    return 0;
  }
  return state->refCount.load(std::memory_order_relaxed) == 1 ? 1 : 0;
}

static int CEF_CALLBACK miumJSDialogHandlerHasAtLeastOneRef(cef_base_ref_counted_t* base) {
  auto* state = getBrowserJSDialogHandlerState(base);
  if (state == nullptr) {
    return 0;
  }
  return state->refCount.load(std::memory_order_relaxed) > 0 ? 1 : 0;
}

static void CEF_CALLBACK miumLoadHandlerAddRef(cef_base_ref_counted_t* base) {
  auto* state = getBrowserLoadHandlerState(base);
  if (state == nullptr) {
    return;
  }
  state->refCount.fetch_add(1, std::memory_order_relaxed);
}

static int CEF_CALLBACK miumLoadHandlerRelease(cef_base_ref_counted_t* base) {
  auto* state = getBrowserLoadHandlerState(base);
  if (state == nullptr) {
    return 0;
  }
  const int remaining = state->refCount.fetch_sub(1, std::memory_order_acq_rel) - 1;
  if (remaining <= 0) {
    delete state;
    return 1;
  }
  return 0;
}

static int CEF_CALLBACK miumLoadHandlerHasOneRef(cef_base_ref_counted_t* base) {
  auto* state = getBrowserLoadHandlerState(base);
  if (state == nullptr) {
    return 0;
  }
  return state->refCount.load(std::memory_order_relaxed) == 1 ? 1 : 0;
}

static int CEF_CALLBACK miumLoadHandlerHasAtLeastOneRef(cef_base_ref_counted_t* base) {
  auto* state = getBrowserLoadHandlerState(base);
  if (state == nullptr) {
    return 0;
  }
  return state->refCount.load(std::memory_order_relaxed) > 0 ? 1 : 0;
}

static void CEF_CALLBACK miumPermissionHandlerAddRef(cef_base_ref_counted_t* base) {
  auto* state = getBrowserPermissionHandlerState(base);
  if (state == nullptr) {
    return;
  }
  state->refCount.fetch_add(1, std::memory_order_relaxed);
}

static int CEF_CALLBACK miumPermissionHandlerRelease(cef_base_ref_counted_t* base) {
  auto* state = getBrowserPermissionHandlerState(base);
  if (state == nullptr) {
    return 0;
  }
  const int remaining = state->refCount.fetch_sub(1, std::memory_order_acq_rel) - 1;
  if (remaining <= 0) {
    delete state;
    return 1;
  }
  return 0;
}

static int CEF_CALLBACK miumPermissionHandlerHasOneRef(cef_base_ref_counted_t* base) {
  auto* state = getBrowserPermissionHandlerState(base);
  if (state == nullptr) {
    return 0;
  }
  return state->refCount.load(std::memory_order_relaxed) == 1 ? 1 : 0;
}

static int CEF_CALLBACK miumPermissionHandlerHasAtLeastOneRef(cef_base_ref_counted_t* base) {
  auto* state = getBrowserPermissionHandlerState(base);
  if (state == nullptr) {
    return 0;
  }
  return state->refCount.load(std::memory_order_relaxed) > 0 ? 1 : 0;
}

static int CEF_CALLBACK miumPermissionHandlerOnRequestMediaAccessPermission(
  cef_permission_handler_t* self,
  cef_browser_t* browser,
  cef_frame_t* frame,
  const cef_string_t* requesting_origin,
  uint32_t requested_permissions,
  cef_media_access_callback_t* callback
) {
  (void)self;
  const uint64_t browserId = miumCEFNativeBrowserIdFromNativeBrowser(browser);
  if (browserId == 0) {
    return 0;
  }

  return miumCEFPermissionHandleMediaAccessRequest(
    browserId,
    miumCEFNativeNormalizedPermissionOriginString(miumCEFNativeNSStringFromCEFString(requesting_origin)),
    miumCEFNativeTopLevelPermissionOriginString(browser),
    miumCEFNativeFrameIdentifierString(frame),
    requested_permissions,
    miumCEFNativeShouldEnableMediaStreamOverride(),
    callback
  ) ? 1 : 0;
}

static int CEF_CALLBACK miumPermissionHandlerOnShowPermissionPrompt(
  cef_permission_handler_t* self,
  cef_browser_t* browser,
  uint64_t prompt_id,
  const cef_string_t* requesting_origin,
  uint32_t requested_permissions,
  cef_permission_prompt_callback_t* callback
) {
  (void)self;
  const uint64_t browserId = miumCEFNativeBrowserIdFromNativeBrowser(browser);
  if (browserId == 0) {
    return 0;
  }

  return miumCEFPermissionHandleShowPromptRequest(
    browserId,
    miumCEFNativeNormalizedPermissionOriginString(miumCEFNativeNSStringFromCEFString(requesting_origin)),
    miumCEFNativeTopLevelPermissionOriginString(browser),
    prompt_id,
    requested_permissions,
    miumCEFNativeShouldEnableMediaStreamOverride(),
    callback
  ) ? 1 : 0;
}

static void CEF_CALLBACK miumPermissionHandlerOnDismissPermissionPrompt(
  cef_permission_handler_t* self,
  cef_browser_t* browser,
  uint64_t prompt_id,
  cef_permission_request_result_t result
) {
  (void)self;
  (void)result;
  const uint64_t browserId = miumCEFNativeBrowserIdFromNativeBrowser(browser);
  if (browserId == 0) {
    return;
  }
  MiumCEFPermissionExecutionBatch batch;
  if (!miumCEFPermissionTakePromptDismissalBatch(
        browserId,
        prompt_id,
        MiumCEFPermissionSessionDismissReason::promptDismissed,
        &batch
      )) {
    return;
  }
  miumCEFNativeExecutePermissionBatchOnCefMainThread(std::move(batch));
}

static void CEF_CALLBACK miumRequestHandlerAddRef(cef_base_ref_counted_t* base) {
  auto* state = getBrowserRequestHandlerState(base);
  if (state == nullptr) {
    return;
  }
  state->refCount.fetch_add(1, std::memory_order_relaxed);
}

static int CEF_CALLBACK miumRequestHandlerRelease(cef_base_ref_counted_t* base) {
  auto* state = getBrowserRequestHandlerState(base);
  if (state == nullptr) {
    return 0;
  }
  const int remaining = state->refCount.fetch_sub(1, std::memory_order_acq_rel) - 1;
  if (remaining <= 0) {
    if (
      state->resourceRequestHandler != nullptr
      && state->resourceRequestHandler->resourceRequestHandler.base.release != nullptr
    ) {
      releaseCefBase(&state->resourceRequestHandler->resourceRequestHandler.base);
      state->resourceRequestHandler = nullptr;
    }
    delete state;
    return 1;
  }
  return 0;
}

static int CEF_CALLBACK miumRequestHandlerHasOneRef(cef_base_ref_counted_t* base) {
  auto* state = getBrowserRequestHandlerState(base);
  if (state == nullptr) {
    return 0;
  }
  return state->refCount.load(std::memory_order_relaxed) == 1 ? 1 : 0;
}

static int CEF_CALLBACK miumRequestHandlerHasAtLeastOneRef(cef_base_ref_counted_t* base) {
  auto* state = getBrowserRequestHandlerState(base);
  if (state == nullptr) {
    return 0;
  }
  return state->refCount.load(std::memory_order_relaxed) > 0 ? 1 : 0;
}

static void CEF_CALLBACK miumResourceRequestHandlerAddRef(cef_base_ref_counted_t* base) {
  auto* state = getBrowserResourceRequestHandlerState(base);
  if (state == nullptr) {
    return;
  }
  state->refCount.fetch_add(1, std::memory_order_relaxed);
}

static int CEF_CALLBACK miumResourceRequestHandlerRelease(cef_base_ref_counted_t* base) {
  auto* state = getBrowserResourceRequestHandlerState(base);
  if (state == nullptr) {
    return 0;
  }
  const int remaining = state->refCount.fetch_sub(1, std::memory_order_acq_rel) - 1;
  if (remaining <= 0) {
    delete state;
    return 1;
  }
  return 0;
}

static int CEF_CALLBACK miumResourceRequestHandlerHasOneRef(cef_base_ref_counted_t* base) {
  auto* state = getBrowserResourceRequestHandlerState(base);
  if (state == nullptr) {
    return 0;
  }
  return state->refCount.load(std::memory_order_relaxed) == 1 ? 1 : 0;
}

static int CEF_CALLBACK miumResourceRequestHandlerHasAtLeastOneRef(cef_base_ref_counted_t* base) {
  auto* state = getBrowserResourceRequestHandlerState(base);
  if (state == nullptr) {
    return 0;
  }
  return state->refCount.load(std::memory_order_relaxed) > 0 ? 1 : 0;
}

static void CEF_CALLBACK miumDisplayHandlerOnAddressChange(
  cef_display_handler_t* self,
  cef_browser_t* browser,
  cef_frame_t* frame,
  const cef_string_t* url
) {
  (void)self;
  (void)frame;
  NSString* urlString = miumCEFNativeNSStringFromCEFString(url);
  const char* rawUrl = urlString == nil ? "" : urlString.UTF8String;
  miumCEFNativeEmitBrowserMessageForMappedBrowser(
    browser,
    MiumCEFAddressChangeChannel,
    rawUrl == nullptr ? "" : rawUrl
  );
}

static void CEF_CALLBACK miumDisplayHandlerOnTitleChange(
  cef_display_handler_t* self,
  cef_browser_t* browser,
  const cef_string_t* title
) {
  (void)self;
  NSString* titleString = miumCEFNativeNSStringFromCEFString(title);
  const char* rawTitle = titleString == nil ? "" : titleString.UTF8String;
  miumCEFNativeEmitBrowserMessageForMappedBrowser(
    browser,
    MiumCEFTitleChangeChannel,
    rawTitle == nullptr ? "" : rawTitle
  );
}

static void CEF_CALLBACK miumDisplayHandlerOnFaviconURLChange(
  cef_display_handler_t* self,
  cef_browser_t* browser,
  cef_string_list_t icon_urls
) {
  (void)self;
  const std::string faviconURL = miumCEFNativeFirstFaviconURLFromList(icon_urls);
  miumCEFNativeEmitBrowserMessageForMappedBrowser(
    browser,
    MiumCEFFaviconURLChangeChannel,
    faviconURL.c_str()
  );
}

static int CEF_CALLBACK miumJSDialogHandlerOnJSDialog(
  cef_jsdialog_handler_t* self,
  cef_browser_t* browser,
  const cef_string_t* origin_url,
  cef_jsdialog_type_t dialog_type,
  const cef_string_t* message_text,
  const cef_string_t* default_prompt_text,
  cef_jsdialog_callback_t* callback,
  int* suppress_message
) {
  (void)self;
  (void)origin_url;
  (void)callback;
  if (dialog_type != JSDIALOGTYPE_PROMPT) {
    return 0;
  }

  NSString* messageText = miumCEFNativeNSStringFromCEFString(message_text);
  const char* rawMessageText = messageText == nil ? "" : messageText.UTF8String;
  if (rawMessageText == nullptr) {
    return 0;
  }

  NSString* payloadText = miumCEFNativeNSStringFromCEFString(default_prompt_text);
  const char* rawPayload = payloadText == nil ? "" : payloadText.UTF8String;
  const char* promptPayload = rawPayload == nullptr ? "" : rawPayload;
  if (std::strcmp(rawMessageText, MiumCEFPictureInPicturePromptMessage) == 0) {
    if (suppress_message != nullptr) {
      *suppress_message = 1;
    }
    miumCEFNativeEmitBrowserMessageForMappedBrowser(
      browser,
      MiumCEFPictureInPictureStateChangeChannel,
      promptPayload
    );
    return 0;
  }
  if (std::strcmp(rawMessageText, MiumCEFCameraRoutingPromptMessage) == 0) {
    if (suppress_message != nullptr) {
      *suppress_message = 1;
    }
    miumCEFNativeEmitBrowserMessageForMappedBrowser(
      browser,
      MiumCEFCameraRoutingEventChannel,
      promptPayload
    );
    return 0;
  }
  return 0;
}

int CEF_CALLBACK miumRequestHandlerOnBeforeBrowse(
  cef_request_handler_t* self,
  cef_browser_t* browser,
  cef_frame_t* frame,
  cef_request_t* request,
  int user_gesture,
  int is_redirect
) {
  (void)self;
  (void)user_gesture;
  (void)is_redirect;
  if (browser == nullptr || frame == nullptr || request == nullptr) {
    return 0;
  }
  if (frame->is_main == nullptr || frame->is_main(frame) == 0) {
    return 0;
  }

  const uint64_t browserId = miumCEFNativeBrowserIdFromNativeBrowser(browser);
  if (browserId == 0) {
    return 0;
  }

  cef_string_userfree_t rawURL = request->get_url == nullptr ? nullptr : request->get_url(request);
  NSString* urlString = miumCEFNativeNSStringFromCEFUserFreeString(rawURL);
  std::vector<MiumCEFPermissionExecutionBatch> permissionBatches;
  miumCEFPermissionTakeNavigationDismissalBatches(
    browserId,
    miumCEFNativeNormalizedPermissionOriginString(urlString),
    &permissionBatches
  );
  miumCEFNativeExecutePermissionBatchesOnCefMainThread(std::move(permissionBatches));
  const std::string navigationPayload =
    miumCEFNativeMainFrameNavigationPayloadString(urlString, user_gesture, is_redirect);
  miumCEFNativeEmitBrowserMessageForMappedBrowser(
    browser,
    MiumCEFMainFrameNavigationChannel,
    navigationPayload.c_str()
  );
  MiumCEFTopLevelNativeContentKind classifiedKind = MiumCEFTopLevelNativeContentKind::image;
  NSString* pathExtension = nil;
  NSString* uniformTypeIdentifier = nil;
  if (!classifyTopLevelNativeContentURL(
        urlString,
        &classifiedKind,
        &pathExtension,
        &uniformTypeIdentifier
      )) {
    return 0;
  }

  miumCEFNativeEmitTopLevelNativeContentForBrowser(
    browser,
    urlString,
    classifiedKind,
    pathExtension,
    uniformTypeIdentifier
  );
  return 0;
}

static cef_resource_request_handler_t* CEF_CALLBACK miumRequestHandlerGetResourceRequestHandler(
  cef_request_handler_t* self,
  cef_browser_t* browser,
  cef_frame_t* frame,
  cef_request_t* request,
  int is_navigation,
  int is_download,
  const cef_string_t* request_initiator,
  int* disable_default_handling
) {
  (void)browser;
  (void)frame;
  (void)request;
  (void)is_download;
  (void)request_initiator;
  if (disable_default_handling != nullptr) {
    *disable_default_handling = 0;
  }
  if (self == nullptr || is_navigation == 0) {
    return nullptr;
  }

  auto* state = getBrowserRequestHandlerState(&self->base);
  if (state == nullptr || state->resourceRequestHandler == nullptr) {
    return nullptr;
  }
  return reinterpret_cast<cef_resource_request_handler_t*>(
    retainCefBase(&state->resourceRequestHandler->resourceRequestHandler.base)
  );
}

int CEF_CALLBACK miumRequestHandlerOnOpenURLFromTab(
  cef_request_handler_t* self,
  cef_browser_t* browser,
  cef_frame_t* frame,
  const cef_string_t* target_url,
  cef_window_open_disposition_t target_disposition,
  int user_gesture
) {
  (void)self;
  (void)frame;
  (void)user_gesture;
  if (browser == nullptr) {
    return 0;
  }
  if (target_disposition != CEF_WOD_NEW_FOREGROUND_TAB
      && target_disposition != CEF_WOD_NEW_BACKGROUND_TAB) {
    return 0;
  }

  NSString* targetURLString = miumCEFNativeNSStringFromCEFString(target_url);
  const std::string payload = miumCEFNativeOpenURLInTabPayloadString(
    targetURLString,
    target_disposition == CEF_WOD_NEW_FOREGROUND_TAB
  );
  miumCEFNativeEmitBrowserMessageForMappedBrowser(
    browser,
    MiumCEFOpenURLInTabChannel,
    payload.c_str()
  );
  return 1;
}

static int CEF_CALLBACK miumResourceRequestHandlerOnResourceResponse(
  cef_resource_request_handler_t* self,
  cef_browser_t* browser,
  cef_frame_t* frame,
  cef_request_t* request,
  cef_response_t* response
) {
  (void)self;
  if (browser == nullptr || frame == nullptr || request == nullptr || response == nullptr) {
    return 0;
  }
  if (frame->is_main == nullptr || frame->is_main(frame) == 0) {
    return 0;
  }

  cef_string_userfree_t rawURL = request->get_url == nullptr ? nullptr : request->get_url(request);
  NSString* urlString = miumCEFNativeNSStringFromCEFUserFreeString(rawURL);

  MiumCEFTopLevelNativeContentKind kind = MiumCEFTopLevelNativeContentKind::image;
  if (classifyTopLevelNativeContentURL(urlString, &kind, nullptr, nullptr)) {
    return 0;
  }

  cef_string_userfree_t rawMIMEType = response->get_mime_type == nullptr ? nullptr : response->get_mime_type(response);
  NSString* mimeTypeString = miumCEFNativeNSStringFromCEFUserFreeString(rawMIMEType);
  NSString* uniformTypeIdentifier = nil;
  if (!classifyTopLevelNativeContentMIMEType(mimeTypeString, &kind, &uniformTypeIdentifier)) {
    return 0;
  }

  miumCEFNativeEmitTopLevelNativeContentForBrowser(browser, urlString, kind, nil, uniformTypeIdentifier);
  return 0;
}

void CEF_CALLBACK miumCEFNativeRequestHandlerOnRenderProcessTerminated(
  cef_request_handler_t* self,
  cef_browser_t* browser,
  cef_termination_status_t status,
  int error_code,
  const cef_string_t* error_string
) {
  (void)self;
  const uint64_t browserId = miumCEFNativeBrowserIdFromNativeBrowser(browser);
  if (browserId != 0) {
    std::vector<MiumCEFPermissionExecutionBatch> permissionBatches;
    miumCEFPermissionTakeBrowserDismissalBatches(
      browserId,
      MiumCEFPermissionSessionDismissReason::renderProcessTerminated,
      true,
      &permissionBatches
    );
    miumCEFNativeExecutePermissionBatchesOnCefMainThread(std::move(permissionBatches));
    miumCEFFailRendererJavaScriptRequestsForBrowser(browserId, "Renderer process terminated");
  }
  const std::string payload =
    miumCEFNativeRenderProcessTerminationPayloadString(status, error_code, error_string);
  miumCEFNativeEmitBrowserMessageForMappedBrowser(
    browser,
    MiumCEFRenderProcessTerminationChannel,
    payload.c_str()
  );
}

static void CEF_CALLBACK miumLoadHandlerOnLoadEnd(
  cef_load_handler_t* self,
  cef_browser_t* browser,
  cef_frame_t* frame,
  int httpStatusCode
) {
  (void)self;
  (void)browser;
  (void)httpStatusCode;
  if (frame != nullptr && frame->is_main != nullptr && frame->is_main(frame) == 0) {
    return;
  }
  miumCEFNativeInjectPictureInPictureObserverScript(frame);
}

static cef_display_handler_t* miumClientGetDisplayHandler(cef_client_t* self) {
  if (self == nullptr) {
    return nullptr;
  }
  auto* state = getBrowserClientState(&self->base);
  if (state == nullptr || state->displayHandler == nullptr) {
    return nullptr;
  }
  return reinterpret_cast<cef_display_handler_t*>(
    retainCefBase(&state->displayHandler->displayHandler.base)
  );
}

static cef_life_span_handler_t* miumClientGetLifeSpanHandler(cef_client_t* self) {
  if (self == nullptr) {
    return nullptr;
  }
  auto* state = getBrowserClientState(&self->base);
  if (state == nullptr || state->lifeSpanHandler == nullptr) {
    return nullptr;
  }
  return reinterpret_cast<cef_life_span_handler_t*>(
    retainCefBase(&state->lifeSpanHandler->lifeSpanHandler.base)
  );
}

static cef_jsdialog_handler_t* miumClientGetJSDialogHandler(cef_client_t* self) {
  if (self == nullptr) {
    return nullptr;
  }
  auto* state = getBrowserClientState(&self->base);
  if (state == nullptr || state->jsDialogHandler == nullptr) {
    return nullptr;
  }
  return reinterpret_cast<cef_jsdialog_handler_t*>(
    retainCefBase(&state->jsDialogHandler->jsDialogHandler.base)
  );
}

static cef_load_handler_t* miumClientGetLoadHandler(cef_client_t* self) {
  if (self == nullptr) {
    return nullptr;
  }
  auto* state = getBrowserClientState(&self->base);
  if (state == nullptr || state->loadHandler == nullptr) {
    return nullptr;
  }
  return reinterpret_cast<cef_load_handler_t*>(
    retainCefBase(&state->loadHandler->loadHandler.base)
  );
}

static cef_permission_handler_t* miumClientGetPermissionHandler(cef_client_t* self) {
  if (self == nullptr) {
    return nullptr;
  }
  auto* state = getBrowserClientState(&self->base);
  if (state == nullptr || state->permissionHandler == nullptr) {
    return nullptr;
  }
  return reinterpret_cast<cef_permission_handler_t*>(
    retainCefBase(&state->permissionHandler->permissionHandler.base)
  );
}

static cef_request_handler_t* miumClientGetRequestHandler(cef_client_t* self) {
  if (self == nullptr) {
    return nullptr;
  }
  auto* state = getBrowserClientState(&self->base);
  if (state == nullptr || state->requestHandler == nullptr) {
    return nullptr;
  }
  return reinterpret_cast<cef_request_handler_t*>(
    retainCefBase(&state->requestHandler->requestHandler.base)
  );
}

cef_client_t* createBrowserClient(void) {
#if defined(MIUM_CEF_BRIDGE_TESTING)
  if (gTestCreateBrowserClientReturnsNull) {
    return nullptr;
  }
#endif
  auto state = std::make_unique<MiumBrowserClientState>();
  std::unique_ptr<MiumBrowserDisplayHandlerState> displayHandlerState;
#if defined(MIUM_CEF_BRIDGE_TESTING)
  const bool missingDisplayHandler = gTestNextBrowserClientMissingDisplayHandler;
  gTestNextBrowserClientMissingDisplayHandler = false;
  if (missingDisplayHandler) {
    state->displayHandler = nullptr;
  } else {
#endif
    displayHandlerState = std::make_unique<MiumBrowserDisplayHandlerState>();
    std::memset(&displayHandlerState->displayHandler, 0, sizeof(displayHandlerState->displayHandler));
    displayHandlerState->displayHandler.base.size = sizeof(cef_display_handler_t);
    displayHandlerState->displayHandler.base.add_ref = miumDisplayHandlerAddRef;
    displayHandlerState->displayHandler.base.release = miumDisplayHandlerRelease;
    displayHandlerState->displayHandler.base.has_one_ref = miumDisplayHandlerHasOneRef;
    displayHandlerState->displayHandler.base.has_at_least_one_ref = miumDisplayHandlerHasAtLeastOneRef;
    displayHandlerState->displayHandler.on_address_change = miumDisplayHandlerOnAddressChange;
    displayHandlerState->displayHandler.on_title_change = miumDisplayHandlerOnTitleChange;
    displayHandlerState->displayHandler.on_favicon_urlchange = miumDisplayHandlerOnFaviconURLChange;
#if defined(MIUM_CEF_BRIDGE_TESTING)
  }
#endif
  auto lifeSpanHandlerState = std::make_unique<MiumBrowserLifeSpanHandlerState>();
  std::memset(&lifeSpanHandlerState->lifeSpanHandler, 0, sizeof(lifeSpanHandlerState->lifeSpanHandler));
  lifeSpanHandlerState->lifeSpanHandler.base.size = sizeof(cef_life_span_handler_t);
  lifeSpanHandlerState->lifeSpanHandler.base.add_ref = miumLifeSpanHandlerAddRef;
  lifeSpanHandlerState->lifeSpanHandler.base.release = miumLifeSpanHandlerRelease;
  lifeSpanHandlerState->lifeSpanHandler.base.has_one_ref = miumLifeSpanHandlerHasOneRef;
  lifeSpanHandlerState->lifeSpanHandler.base.has_at_least_one_ref = miumLifeSpanHandlerHasAtLeastOneRef;
  lifeSpanHandlerState->lifeSpanHandler.on_before_popup = miumCEFNativeLifeSpanHandlerOnBeforePopup;

  auto jsDialogHandlerState = std::make_unique<MiumBrowserJSDialogHandlerState>();
  std::memset(&jsDialogHandlerState->jsDialogHandler, 0, sizeof(jsDialogHandlerState->jsDialogHandler));
  jsDialogHandlerState->jsDialogHandler.base.size = sizeof(cef_jsdialog_handler_t);
  jsDialogHandlerState->jsDialogHandler.base.add_ref = miumJSDialogHandlerAddRef;
  jsDialogHandlerState->jsDialogHandler.base.release = miumJSDialogHandlerRelease;
  jsDialogHandlerState->jsDialogHandler.base.has_one_ref = miumJSDialogHandlerHasOneRef;
  jsDialogHandlerState->jsDialogHandler.base.has_at_least_one_ref = miumJSDialogHandlerHasAtLeastOneRef;
  jsDialogHandlerState->jsDialogHandler.on_jsdialog = miumJSDialogHandlerOnJSDialog;

  auto loadHandlerState = std::make_unique<MiumBrowserLoadHandlerState>();
  std::memset(&loadHandlerState->loadHandler, 0, sizeof(loadHandlerState->loadHandler));
  loadHandlerState->loadHandler.base.size = sizeof(cef_load_handler_t);
  loadHandlerState->loadHandler.base.add_ref = miumLoadHandlerAddRef;
  loadHandlerState->loadHandler.base.release = miumLoadHandlerRelease;
  loadHandlerState->loadHandler.base.has_one_ref = miumLoadHandlerHasOneRef;
  loadHandlerState->loadHandler.base.has_at_least_one_ref = miumLoadHandlerHasAtLeastOneRef;
  loadHandlerState->loadHandler.on_load_end = miumLoadHandlerOnLoadEnd;

  auto permissionHandlerState = std::make_unique<MiumBrowserPermissionHandlerState>();
  std::memset(&permissionHandlerState->permissionHandler, 0, sizeof(permissionHandlerState->permissionHandler));
  permissionHandlerState->permissionHandler.base.size = sizeof(cef_permission_handler_t);
  permissionHandlerState->permissionHandler.base.add_ref = miumPermissionHandlerAddRef;
  permissionHandlerState->permissionHandler.base.release = miumPermissionHandlerRelease;
  permissionHandlerState->permissionHandler.base.has_one_ref = miumPermissionHandlerHasOneRef;
  permissionHandlerState->permissionHandler.base.has_at_least_one_ref = miumPermissionHandlerHasAtLeastOneRef;
  permissionHandlerState->permissionHandler.on_request_media_access_permission =
    miumPermissionHandlerOnRequestMediaAccessPermission;
  permissionHandlerState->permissionHandler.on_show_permission_prompt = miumPermissionHandlerOnShowPermissionPrompt;
  permissionHandlerState->permissionHandler.on_dismiss_permission_prompt =
    miumPermissionHandlerOnDismissPermissionPrompt;

  auto requestHandlerState = std::make_unique<MiumBrowserRequestHandlerState>();
  std::memset(&requestHandlerState->requestHandler, 0, sizeof(requestHandlerState->requestHandler));
  requestHandlerState->requestHandler.base.size = sizeof(cef_request_handler_t);
  requestHandlerState->requestHandler.base.add_ref = miumRequestHandlerAddRef;
  requestHandlerState->requestHandler.base.release = miumRequestHandlerRelease;
  requestHandlerState->requestHandler.base.has_one_ref = miumRequestHandlerHasOneRef;
  requestHandlerState->requestHandler.base.has_at_least_one_ref = miumRequestHandlerHasAtLeastOneRef;
  requestHandlerState->requestHandler.on_before_browse = miumRequestHandlerOnBeforeBrowse;
  requestHandlerState->requestHandler.get_resource_request_handler =
    miumRequestHandlerGetResourceRequestHandler;
  requestHandlerState->requestHandler.on_open_urlfrom_tab = miumRequestHandlerOnOpenURLFromTab;
  requestHandlerState->requestHandler.on_render_process_terminated =
    miumCEFNativeRequestHandlerOnRenderProcessTerminated;

  auto resourceRequestHandlerState = std::make_unique<MiumBrowserResourceRequestHandlerState>();
  std::memset(
    &resourceRequestHandlerState->resourceRequestHandler,
    0,
    sizeof(resourceRequestHandlerState->resourceRequestHandler)
  );
  resourceRequestHandlerState->resourceRequestHandler.base.size = sizeof(cef_resource_request_handler_t);
  resourceRequestHandlerState->resourceRequestHandler.base.add_ref = miumResourceRequestHandlerAddRef;
  resourceRequestHandlerState->resourceRequestHandler.base.release = miumResourceRequestHandlerRelease;
  resourceRequestHandlerState->resourceRequestHandler.base.has_one_ref =
    miumResourceRequestHandlerHasOneRef;
  resourceRequestHandlerState->resourceRequestHandler.base.has_at_least_one_ref =
    miumResourceRequestHandlerHasAtLeastOneRef;
  resourceRequestHandlerState->resourceRequestHandler.on_resource_response =
    miumResourceRequestHandlerOnResourceResponse;
  requestHandlerState->resourceRequestHandler = resourceRequestHandlerState.release();

  std::memset(&state->client, 0, sizeof(state->client));
  state->client.base.size = sizeof(cef_client_t);
  state->client.base.add_ref = miumClientAddRef;
  state->client.base.release = miumClientRelease;
  state->client.base.has_one_ref = miumClientHasOneRef;
  state->client.base.has_at_least_one_ref = miumClientHasAtLeastOneRef;
  state->client.get_display_handler = miumClientGetDisplayHandler;
  state->client.get_life_span_handler = miumClientGetLifeSpanHandler;
  state->client.get_jsdialog_handler = miumClientGetJSDialogHandler;
  state->client.get_load_handler = miumClientGetLoadHandler;
  state->client.get_permission_handler = miumClientGetPermissionHandler;
  state->client.get_request_handler = miumClientGetRequestHandler;
  state->client.on_process_message_received = miumClientOnProcessMessageReceived;
  state->displayHandler = displayHandlerState.release();
  state->lifeSpanHandler = lifeSpanHandlerState.release();
  state->jsDialogHandler = jsDialogHandlerState.release();
  state->loadHandler = loadHandlerState.release();
  state->permissionHandler = permissionHandlerState.release();
  state->requestHandler = requestHandlerState.release();
  return &state.release()->client;
}
