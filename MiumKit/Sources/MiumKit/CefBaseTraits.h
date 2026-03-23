#pragma once

#include <cassert>
#include <cstddef>
#include <cstdio>

#include "include/MiumCEFBridgeCefTypes.h"

static_assert(offsetof(cef_app_t, base) == 0, "CEF layout change: cef_app_t.base must remain first");
static_assert(
  offsetof(cef_browser_process_handler_t, base) == 0,
  "CEF layout change: cef_browser_process_handler_t.base must remain first"
);
static_assert(offsetof(cef_browser_t, base) == 0, "CEF layout change: cef_browser_t.base must remain first");
static_assert(
  offsetof(cef_browser_host_t, base) == 0,
  "CEF layout change: cef_browser_host_t.base must remain first"
);
static_assert(offsetof(cef_client_t, base) == 0, "CEF layout change: cef_client_t.base must remain first");
static_assert(
  offsetof(cef_display_handler_t, base) == 0,
  "CEF layout change: cef_display_handler_t.base must remain first"
);
static_assert(offsetof(cef_frame_t, base) == 0, "CEF layout change: cef_frame_t.base must remain first");
static_assert(
  offsetof(cef_jsdialog_handler_t, base) == 0,
  "CEF layout change: cef_jsdialog_handler_t.base must remain first"
);
static_assert(
  offsetof(cef_load_handler_t, base) == 0,
  "CEF layout change: cef_load_handler_t.base must remain first"
);
static_assert(
  offsetof(cef_media_access_callback_t, base) == 0,
  "CEF layout change: cef_media_access_callback_t.base must remain first"
);
static_assert(
  offsetof(cef_permission_handler_t, base) == 0,
  "CEF layout change: cef_permission_handler_t.base must remain first"
);
static_assert(
  offsetof(cef_permission_prompt_callback_t, base) == 0,
  "CEF layout change: cef_permission_prompt_callback_t.base must remain first"
);
static_assert(
  offsetof(cef_preference_manager_t, base) == 0,
  "CEF layout change: cef_preference_manager_t.base moved"
);
static_assert(
  offsetof(cef_process_message_t, base) == 0,
  "CEF layout change: cef_process_message_t.base must remain first"
);
static_assert(
  offsetof(cef_render_process_handler_t, base) == 0,
  "CEF layout change: cef_render_process_handler_t.base must remain first"
);
static_assert(
  offsetof(cef_list_value_t, base) == 0,
  "CEF layout change: cef_list_value_t.base must remain first"
);
static_assert(
  offsetof(cef_request_context_t, base) == 0,
  "CEF layout change: cef_request_context_t.base moved"
);
static_assert(
  offsetof(cef_request_handler_t, base) == 0,
  "CEF layout change: cef_request_handler_t.base must remain first"
);
static_assert(
  offsetof(cef_resource_request_handler_t, base) == 0,
  "CEF layout change: cef_resource_request_handler_t.base must remain first"
);
static_assert(
  offsetof(cef_v8_context_t, base) == 0,
  "CEF layout change: cef_v8_context_t.base must remain first"
);
static_assert(
  offsetof(cef_v8_handler_t, base) == 0,
  "CEF layout change: cef_v8_handler_t.base must remain first"
);
static_assert(
  offsetof(cef_v8_value_t, base) == 0,
  "CEF layout change: cef_v8_value_t.base must remain first"
);

// All supported CEF C API base accessors are centralized here so refcounted access patterns are
// auditable against the vendored headers in this target.
template <typename T>
struct CefBaseTraits;

template <>
struct CefBaseTraits<cef_app_t> {
  static cef_base_ref_counted_t* base(cef_app_t* value) {
    return value == nullptr ? nullptr : &value->base;
  }
};

template <>
struct CefBaseTraits<cef_browser_process_handler_t> {
  static cef_base_ref_counted_t* base(cef_browser_process_handler_t* value) {
    return value == nullptr ? nullptr : &value->base;
  }
};

template <>
struct CefBaseTraits<cef_browser_t> {
  static cef_base_ref_counted_t* base(cef_browser_t* value) {
    return value == nullptr ? nullptr : &value->base;
  }
};

template <>
struct CefBaseTraits<cef_browser_host_t> {
  static cef_base_ref_counted_t* base(cef_browser_host_t* value) {
    return value == nullptr ? nullptr : &value->base;
  }
};

template <>
struct CefBaseTraits<cef_client_t> {
  static cef_base_ref_counted_t* base(cef_client_t* value) {
    return value == nullptr ? nullptr : &value->base;
  }
};

template <>
struct CefBaseTraits<cef_display_handler_t> {
  static cef_base_ref_counted_t* base(cef_display_handler_t* value) {
    return value == nullptr ? nullptr : &value->base;
  }
};

template <>
struct CefBaseTraits<cef_frame_t> {
  static cef_base_ref_counted_t* base(cef_frame_t* value) {
    return value == nullptr ? nullptr : &value->base;
  }
};

template <>
struct CefBaseTraits<cef_jsdialog_handler_t> {
  static cef_base_ref_counted_t* base(cef_jsdialog_handler_t* value) {
    return value == nullptr ? nullptr : &value->base;
  }
};

template <>
struct CefBaseTraits<cef_load_handler_t> {
  static cef_base_ref_counted_t* base(cef_load_handler_t* value) {
    return value == nullptr ? nullptr : &value->base;
  }
};

template <>
struct CefBaseTraits<cef_media_access_callback_t> {
  static cef_base_ref_counted_t* base(cef_media_access_callback_t* value) {
    return value == nullptr ? nullptr : &value->base;
  }
};

template <>
struct CefBaseTraits<cef_permission_handler_t> {
  static cef_base_ref_counted_t* base(cef_permission_handler_t* value) {
    return value == nullptr ? nullptr : &value->base;
  }
};

template <>
struct CefBaseTraits<cef_permission_prompt_callback_t> {
  static cef_base_ref_counted_t* base(cef_permission_prompt_callback_t* value) {
    return value == nullptr ? nullptr : &value->base;
  }
};

template <>
struct CefBaseTraits<cef_process_message_t> {
  static cef_base_ref_counted_t* base(cef_process_message_t* value) {
    return value == nullptr ? nullptr : &value->base;
  }
};

template <>
struct CefBaseTraits<cef_render_process_handler_t> {
  static cef_base_ref_counted_t* base(cef_render_process_handler_t* value) {
    return value == nullptr ? nullptr : &value->base;
  }
};

template <>
struct CefBaseTraits<cef_list_value_t> {
  static cef_base_ref_counted_t* base(cef_list_value_t* value) {
    return value == nullptr ? nullptr : &value->base;
  }
};

template <>
struct CefBaseTraits<cef_request_context_t> {
  static cef_base_ref_counted_t* base(cef_request_context_t* value) {
    // `cef_request_context_t` embeds `cef_preference_manager_t base`, whose first field is the
    // ref-counted base for this pinned vendored CEF layout.
    return value == nullptr ? nullptr : &value->base.base;
  }
};

template <>
struct CefBaseTraits<cef_request_handler_t> {
  static cef_base_ref_counted_t* base(cef_request_handler_t* value) {
    return value == nullptr ? nullptr : &value->base;
  }
};

template <>
struct CefBaseTraits<cef_resource_request_handler_t> {
  static cef_base_ref_counted_t* base(cef_resource_request_handler_t* value) {
    return value == nullptr ? nullptr : &value->base;
  }
};

template <>
struct CefBaseTraits<cef_v8_context_t> {
  static cef_base_ref_counted_t* base(cef_v8_context_t* value) {
    return value == nullptr ? nullptr : &value->base;
  }
};

template <>
struct CefBaseTraits<cef_v8_handler_t> {
  static cef_base_ref_counted_t* base(cef_v8_handler_t* value) {
    return value == nullptr ? nullptr : &value->base;
  }
};

template <>
struct CefBaseTraits<cef_v8_value_t> {
  static cef_base_ref_counted_t* base(cef_v8_value_t* value) {
    return value == nullptr ? nullptr : &value->base;
  }
};

template <typename T>
inline cef_base_ref_counted_t* cefBaseForValue(T* value) {
  return CefBaseTraits<T>::base(value);
}

template <typename T>
inline bool hasValidCefBaseAccess(T* value) {
  if (value == nullptr) {
    return true;
  }
  const cef_base_ref_counted_t* base = cefBaseForValue(value);
  return base != nullptr && base->add_ref != nullptr && base->release != nullptr;
}

template <typename T>
inline void debugAssertValidCefBaseAccess(T* value) {
  if (hasValidCefBaseAccess(value)) {
    return;
  }
  cef_base_ref_counted_t* base = cefBaseForValue(value);
  if (base == nullptr || base->add_ref == nullptr || base->release == nullptr) {
    std::fprintf(
      stderr,
      "Invalid CEF base access in %s value=%p base=%p add_ref=%p release=%p\n",
      __PRETTY_FUNCTION__,
      static_cast<void*>(value),
      static_cast<void*>(base),
      base == nullptr ? nullptr : reinterpret_cast<void*>(base->add_ref),
      base == nullptr ? nullptr : reinterpret_cast<void*>(base->release)
    );
  }
#if !defined(NDEBUG)
  assert(base != nullptr && "Missing CEF base accessor");
  assert(base->add_ref != nullptr && "Missing CEF add_ref");
  assert(base->release != nullptr && "Missing CEF release");
#endif
}
