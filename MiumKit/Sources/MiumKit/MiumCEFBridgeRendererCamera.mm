#include "MiumCEFBridgeInternalState.h"
#include "MiumCEFBridgeInternalBrowserPayloadSupport.h"
#include "MiumCEFBridgeInternalRendererCameraSupport.h"
#include "MiumCEFBridgeInternalRuntimeBootstrapSupport.h"
#include "MiumCEFBridgeInternalRuntimeExecutionSupport.h"

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string>

#include "CefRef.h"

namespace {

static constexpr const char* kNavigatorCameraRoutingShimKey = "__navigatorCameraRoutingShim";
static constexpr const char* kNavigatorCameraRoutingEventBridgeKey =
  MiumCEFCameraRoutingEventBridgeFunctionName;

struct MiumCameraRoutingEventV8HandlerState {
  cef_v8_handler_t handler;
  std::atomic<int> refCount{1};
};

static_assert(offsetof(MiumCameraRoutingEventV8HandlerState, handler) == 0);

static std::string stringFromCEFUserFreeStringValue(cef_string_userfree_t source) {
  return miumCEFNativeStringFromNSStringUTF8(miumCEFNativeNSStringFromCEFUserFreeString(source));
}

static std::string makeManagedCameraFrameDeliveryScript(const char* payload) {
  const std::string normalizedPayload = (payload == nullptr || payload[0] == '\0') ? "{}" : payload;
  return
    "(function() {"
    "  const shim = window."
    + std::string(kNavigatorCameraRoutingShimKey)
    + ";"
    "  if (!shim || typeof shim.receiveFrame !== \"function\") {"
    "    return \"missing-shim\";"
    "  }"
    "  shim.receiveFrame("
    + normalizedPayload +
    ");"
    "  return \"delivered\";"
    "})();";
}

static std::string makeManagedCameraFrameClearScript() {
  return
    "(function() {"
    "  const shim = window."
    + std::string(kNavigatorCameraRoutingShimKey)
    + ";"
    "  if (!shim || typeof shim.clearFrame !== \"function\") {"
    "    return \"missing-shim\";"
    "  }"
    "  shim.clearFrame();"
    "  return \"cleared\";"
    "})();";
}

static std::string makeManagedCameraRoutingConfigUpdateScript(const char* payload) {
  const std::string normalizedPayload = (payload == nullptr || payload[0] == '\0') ? "{}" : payload;
  return
    "(function() {"
    "  const shim = window."
    + std::string(kNavigatorCameraRoutingShimKey)
    + ";"
    "  if (!shim || typeof shim.applyConfig !== \"function\") {"
    "    return \"missing-shim\";"
    "  }"
    "  shim.applyConfig("
    + normalizedPayload +
    ");"
    "  return \"updated\";"
    "})();";
}

static bool sendRendererCameraRoutingEventMessage(cef_frame_t* frame, const char* payload) {
  if (frame == nullptr
      || frame->is_main == nullptr
      || frame->is_main(frame) == 0
      || frame->send_process_message == nullptr
      || gCefApi.createProcessMessage == nullptr) {
    return false;
  }

  cef_string_t name{};
  cef_string_t payloadValue{};
  std::string conversionError;
  if (!miumCEFNativeUTF16FromUTF8(MiumCEFCameraRoutingEventChannel, name, &conversionError)
      || !miumCEFNativeUTF16FromUTF8(payload == nullptr ? "" : payload, payloadValue, &conversionError)) {
    miumCEFNativeClearUTF16String(name);
    miumCEFNativeClearUTF16String(payloadValue);
    return false;
  }

  cef_process_message_t* response = gCefApi.createProcessMessage(&name);
  if (response == nullptr) {
    miumCEFNativeClearUTF16String(name);
    miumCEFNativeClearUTF16String(payloadValue);
    return false;
  }

  cef_list_value_t* arguments = response->get_argument_list != nullptr
    ? response->get_argument_list(response)
    : nullptr;
  bool sent = false;
  if (arguments != nullptr && arguments->set_size != nullptr && arguments->set_string != nullptr) {
    arguments->set_size(arguments, 1);
    arguments->set_string(arguments, 0, &payloadValue);
    frame->send_process_message(frame, PID_BROWSER, response);
    sent = true;
  }
  if (!sent) {
    releaseOwnedCefValue(response);
  }
  miumCEFNativeClearUTF16String(name);
  miumCEFNativeClearUTF16String(payloadValue);
  return sent;
}

static void CEF_CALLBACK miumCameraRoutingEventV8HandlerAddRef(cef_base_ref_counted_t* base) {
  auto* state = miumCEFStateFromRefCountedBase<MiumCameraRoutingEventV8HandlerState>(base);
  if (state != nullptr) {
    state->refCount.fetch_add(1, std::memory_order_relaxed);
  }
}

static int CEF_CALLBACK miumCameraRoutingEventV8HandlerRelease(cef_base_ref_counted_t* base) {
  auto* state = miumCEFStateFromRefCountedBase<MiumCameraRoutingEventV8HandlerState>(base);
  if (state == nullptr) {
    return 1;
  }
  const int previousCount = state->refCount.fetch_sub(1, std::memory_order_acq_rel);
  if (previousCount == 1) {
    delete state;
    return 1;
  }
  return 0;
}

static int CEF_CALLBACK miumCameraRoutingEventV8HandlerHasOneRef(cef_base_ref_counted_t* base) {
  auto* state = miumCEFStateFromRefCountedBase<MiumCameraRoutingEventV8HandlerState>(base);
  return state != nullptr && state->refCount.load(std::memory_order_acquire) == 1;
}

static int CEF_CALLBACK miumCameraRoutingEventV8HandlerHasAtLeastOneRef(cef_base_ref_counted_t* base) {
  auto* state = miumCEFStateFromRefCountedBase<MiumCameraRoutingEventV8HandlerState>(base);
  return state != nullptr && state->refCount.load(std::memory_order_acquire) >= 1;
}

static void setV8ExceptionMessage(cef_string_t* exception, const char* message) {
  if (exception == nullptr) {
    return;
  }
  exception->str = nullptr;
  exception->length = 0;
  exception->dtor = nullptr;
  if (message == nullptr) {
    return;
  }
  (void)miumCEFNativeUTF16FromUTF8(message, *exception, nullptr);
}

static int CEF_CALLBACK miumCameraRoutingEventV8HandlerExecute(
  cef_v8_handler_t* self,
  const cef_string_t*,
  cef_v8_value_t*,
  size_t argumentsCount,
  cef_v8_value_t* const* arguments,
  cef_v8_value_t** retval,
  cef_string_t* exception
) {
  auto* state = miumCEFStateFromRefCountedBase<MiumCameraRoutingEventV8HandlerState>(&self->base);
  if (retval != nullptr) {
    *retval = nullptr;
  }

  const bool hasValidStringArgument =
    argumentsCount >= 1 &&
    arguments != nullptr &&
    arguments[0] != nullptr &&
    arguments[0]->is_string != nullptr &&
    arguments[0]->is_string(arguments[0]) != 0 &&
    arguments[0]->get_string_value != nullptr;
  if (state == nullptr || !hasValidStringArgument) {
    setV8ExceptionMessage(
      exception,
      "Navigator camera routing event bridge expected a JSON string payload."
    );
    return 1;
  }

  CefV8ContextGetCurrentContextFn currentV8Context = nullptr;
  {
    CefStateLockGuard lock;
    currentV8Context = gCefApi.currentV8Context;
  }
  cef_v8_context_t* context = currentV8Context == nullptr ? nullptr : currentV8Context();
  cef_frame_t* frame =
    context != nullptr && context->get_frame != nullptr
    ? context->get_frame(context)
    : nullptr;
  if (frame == nullptr || frame->send_process_message == nullptr) {
    releaseOwnedCefValue(frame);
    releaseOwnedCefValue(context);
    setV8ExceptionMessage(
      exception,
      "Navigator camera routing event bridge could not resolve the current frame."
    );
    return 1;
  }

  const std::string payload = stringFromCEFUserFreeStringValue(arguments[0]->get_string_value(arguments[0]));
  if (!sendRendererCameraRoutingEventMessage(frame, payload.c_str())) {
    setV8ExceptionMessage(
      exception,
      "Navigator camera routing event bridge failed to send the renderer event payload."
    );
  }
  releaseOwnedCefValue(frame);
  releaseOwnedCefValue(context);
  return 1;
}

static bool installRendererCameraRoutingEventBridge(
  cef_frame_t* frame,
  cef_v8_context_t* context
) {
  if (frame == nullptr
      || context == nullptr
      || frame->is_main == nullptr
      || frame->is_main(frame) == 0
      || context->enter == nullptr
      || context->exit == nullptr
      || context->get_global == nullptr
      || gCefApi.createV8Function == nullptr) {
    return false;
  }

  if (context->enter(context) == 0) {
    return false;
  }

  cef_v8_value_t* global = context->get_global(context);
  if (global == nullptr || global->set_value_bykey == nullptr) {
    releaseOwnedCefValue(global);
    context->exit(context);
    return false;
  }

  auto* handlerState = new MiumCameraRoutingEventV8HandlerState{};
  handlerState->handler.base.size = sizeof(cef_v8_handler_t);
  handlerState->handler.base.add_ref = miumCameraRoutingEventV8HandlerAddRef;
  handlerState->handler.base.release = miumCameraRoutingEventV8HandlerRelease;
  handlerState->handler.base.has_one_ref = miumCameraRoutingEventV8HandlerHasOneRef;
  handlerState->handler.base.has_at_least_one_ref = miumCameraRoutingEventV8HandlerHasAtLeastOneRef;
  handlerState->handler.execute = miumCameraRoutingEventV8HandlerExecute;

  cef_string_t propertyName{};
  std::string conversionError;
  if (!miumCEFNativeUTF16FromUTF8(kNavigatorCameraRoutingEventBridgeKey, propertyName, &conversionError)) {
    releaseCefBase(&handlerState->handler.base);
    releaseOwnedCefValue(global);
    context->exit(context);
    return false;
  }

  cef_v8_value_t* functionValue = gCefApi.createV8Function(&propertyName, &handlerState->handler);
  bool installed = false;
  if (functionValue != nullptr) {
    installed = global->set_value_bykey(
      global,
      &propertyName,
      functionValue,
      static_cast<cef_v8_propertyattribute_t>(V8_PROPERTY_ATTRIBUTE_NONE)
    ) != 0;
  } else {
    releaseCefBase(&handlerState->handler.base);
  }

  releaseOwnedCefValue(functionValue);
  miumCEFNativeClearUTF16String(propertyName);
  releaseOwnedCefValue(global);
  context->exit(context);
  return installed;
}

static bool handleRendererManagedCameraFrameMessage(
  cef_frame_t* frame,
  const char* channel,
  const char* payload
) {
  if (frame == nullptr || channel == nullptr) {
    return false;
  }

  std::string script;
  if (std::strcmp(channel, MiumCEFCameraFrameDeliveryChannel) == 0) {
    script = makeManagedCameraFrameDeliveryScript(payload);
  } else if (std::strcmp(channel, MiumCEFCameraFrameClearChannel) == 0) {
    script = makeManagedCameraFrameClearScript();
  } else {
    return false;
  }

  std::string resultString;
  std::string errorString;
  miumCEFNativeEvaluateRendererJavaScript(frame, script.c_str(), &resultString, &errorString);
  return true;
}

static bool handleRendererManagedCameraConfigMessage(
  cef_frame_t* frame,
  const char* channel,
  const char* payload
) {
  if (frame == nullptr || channel == nullptr) {
    return false;
  }
  if (std::strcmp(channel, MiumCEFCameraRoutingConfigUpdateChannel) != 0) {
    return false;
  }

  const std::string script = makeManagedCameraRoutingConfigUpdateScript(payload);
  std::string resultString;
  std::string errorString;
  miumCEFNativeEvaluateRendererJavaScript(frame, script.c_str(), &resultString, &errorString);
  return true;
}

} // namespace

bool miumCEFNativeHandleRendererManagedCameraFrameMessage(
  cef_frame_t* frame,
  const char* channel,
  const char* payload
) {
  return handleRendererManagedCameraFrameMessage(frame, channel, payload);
}

bool miumCEFNativeHandleRendererManagedCameraConfigMessage(
  cef_frame_t* frame,
  const char* channel,
  const char* payload
) {
  return handleRendererManagedCameraConfigMessage(frame, channel, payload);
}

bool miumCEFNativeInstallRendererCameraRoutingEventBridge(
  cef_frame_t* frame,
  cef_v8_context_t* context
) {
  return installRendererCameraRoutingEventBridge(frame, context);
}
