#include "MiumCEFBridgeInternalState.h"
#include "MiumCEFBridgeInternalBrowserMessagingSupport.h"
#include "MiumCEFBridgeInternalBrowserPayloadSupport.h"
#include "MiumCEFBridgeInternalPopupSupport.h"

#include "CefRef.h"
#include "MiumCEFBridgeContentClassification.h"

namespace {

static bool shouldRedirectPopupTargetIntoSourceBrowser(NSString* targetURLString) {
  MiumCEFTopLevelNativeContentKind kind = MiumCEFTopLevelNativeContentKind::image;
  if (!classifyTopLevelNativeContentURL(targetURLString, &kind, nullptr, nullptr)) {
    return false;
  }
  return kind == MiumCEFTopLevelNativeContentKind::image
    || kind == MiumCEFTopLevelNativeContentKind::animatedImage;
}

static bool loadPopupTargetURLInSourceBrowser(
  cef_browser_t* browser,
  const cef_string_t* targetURL
) {
  if (browser == nullptr || browser->get_main_frame == nullptr || targetURL == nullptr) {
    return false;
  }

  auto* mainFrame = browser->get_main_frame(browser);
  if (mainFrame == nullptr || mainFrame->load_url == nullptr) {
    releaseOwnedCefValue(mainFrame);
    return false;
  }

  mainFrame->load_url(mainFrame, targetURL);
  releaseOwnedCefValue(mainFrame);
  return true;
}

static bool shouldOpenTargetInAppTab(cef_window_open_disposition_t targetDisposition) {
  return targetDisposition == CEF_WOD_NEW_FOREGROUND_TAB
    || targetDisposition == CEF_WOD_NEW_BACKGROUND_TAB;
}

static bool targetDispositionActivatesTab(cef_window_open_disposition_t targetDisposition) {
  return targetDisposition == CEF_WOD_NEW_FOREGROUND_TAB;
}

} // namespace

int CEF_CALLBACK miumCEFNativeLifeSpanHandlerOnBeforePopup(
  cef_life_span_handler_t* self,
  cef_browser_t* browser,
  cef_frame_t* frame,
  int popup_id,
  const cef_string_t* target_url,
  const cef_string_t* target_frame_name,
  cef_window_open_disposition_t target_disposition,
  int user_gesture,
  const cef_popup_features_t* popupFeatures,
  cef_window_info_t* windowInfo,
  cef_client_t** client,
  cef_browser_settings_t* settings,
  cef_dictionary_value_t** extra_info,
  int* no_javascript_access
) {
  (void)self;
  (void)frame;
  (void)popup_id;
  (void)target_frame_name;
  (void)user_gesture;
  (void)popupFeatures;
  (void)windowInfo;
  (void)client;
  (void)settings;
  (void)extra_info;
  (void)no_javascript_access;
  if (browser == nullptr) {
    return 0;
  }

  NSString* targetURLString = miumCEFNativeNSStringFromCEFString(target_url);
  if (!shouldRedirectPopupTargetIntoSourceBrowser(targetURLString)) {
    if (!shouldOpenTargetInAppTab(target_disposition)) {
      return 0;
    }

    const std::string payload = miumCEFNativeOpenURLInTabPayloadString(
      targetURLString,
      targetDispositionActivatesTab(target_disposition)
    );
    miumCEFNativeEmitBrowserMessageForMappedBrowser(
      browser,
      MiumCEFOpenURLInTabChannel,
      payload.c_str()
    );
    return 1;
  }

  if (!loadPopupTargetURLInSourceBrowser(browser, target_url)) {
    return 0;
  }

  return 1;
}
