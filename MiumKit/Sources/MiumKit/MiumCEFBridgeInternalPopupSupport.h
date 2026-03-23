#pragma once

#include "MiumCEFBridgeStateModels.h"

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
);
