#pragma once

#include <atomic>
#include <cstddef>

#include "include/MiumCEFBridgeCefTypes.h"

struct MiumExternalBrowserProcessHandlerState {
  cef_browser_process_handler_t handler;
  std::atomic<int> refCount{1};
};

struct MiumExternalRenderProcessHandlerState {
  cef_render_process_handler_t handler;
  std::atomic<int> refCount{1};
};

struct MiumExternalBrowserProcessAppState {
  cef_app_t app;
  std::atomic<int> refCount{1};
  MiumExternalBrowserProcessHandlerState* browserProcessHandler = nullptr;
  MiumExternalRenderProcessHandlerState* renderProcessHandler = nullptr;
};

static_assert(offsetof(MiumExternalBrowserProcessHandlerState, handler) == 0);
static_assert(offsetof(MiumExternalRenderProcessHandlerState, handler) == 0);
static_assert(offsetof(MiumExternalBrowserProcessAppState, app) == 0);
