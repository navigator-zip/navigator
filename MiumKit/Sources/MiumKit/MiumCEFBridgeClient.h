#pragma once

#include <atomic>
#include <cstddef>

#include "MiumCEFBridgeAuxiliaryState.h"
#include "include/MiumCEFBridgeCefTypes.h"

struct MiumBrowserDisplayHandlerState;
struct MiumBrowserLifeSpanHandlerState;
struct MiumBrowserJSDialogHandlerState;
struct MiumBrowserLoadHandlerState;
struct MiumBrowserPermissionHandlerState;
struct MiumBrowserRequestHandlerState;
struct MiumBrowserResourceRequestHandlerState;

struct MiumBrowserClientState {
  cef_client_t client;
  std::atomic<int> refCount{1};
  MiumBrowserDisplayHandlerState* displayHandler = nullptr;
  MiumBrowserLifeSpanHandlerState* lifeSpanHandler = nullptr;
  MiumBrowserJSDialogHandlerState* jsDialogHandler = nullptr;
  MiumBrowserLoadHandlerState* loadHandler = nullptr;
  MiumBrowserPermissionHandlerState* permissionHandler = nullptr;
  MiumBrowserRequestHandlerState* requestHandler = nullptr;
};

struct MiumBrowserDisplayHandlerState {
  cef_display_handler_t displayHandler;
  std::atomic<int> refCount{1};
};

struct MiumBrowserLifeSpanHandlerState {
  cef_life_span_handler_t lifeSpanHandler;
  std::atomic<int> refCount{1};
};

struct MiumBrowserJSDialogHandlerState {
  cef_jsdialog_handler_t jsDialogHandler;
  std::atomic<int> refCount{1};
};

struct MiumBrowserLoadHandlerState {
  cef_load_handler_t loadHandler;
  std::atomic<int> refCount{1};
};

struct MiumBrowserPermissionHandlerState {
  cef_permission_handler_t permissionHandler;
  std::atomic<int> refCount{1};
};

struct MiumBrowserRequestHandlerState {
  cef_request_handler_t requestHandler;
  std::atomic<int> refCount{1};
  MiumBrowserResourceRequestHandlerState* resourceRequestHandler = nullptr;
};

struct MiumBrowserResourceRequestHandlerState {
  cef_resource_request_handler_t resourceRequestHandler;
  std::atomic<int> refCount{1};
};

static_assert(offsetof(MiumBrowserClientState, client) == 0);
static_assert(offsetof(MiumBrowserDisplayHandlerState, displayHandler) == 0);
static_assert(offsetof(MiumBrowserLifeSpanHandlerState, lifeSpanHandler) == 0);
static_assert(offsetof(MiumBrowserJSDialogHandlerState, jsDialogHandler) == 0);
static_assert(offsetof(MiumBrowserLoadHandlerState, loadHandler) == 0);
static_assert(offsetof(MiumBrowserPermissionHandlerState, permissionHandler) == 0);
static_assert(offsetof(MiumBrowserRequestHandlerState, requestHandler) == 0);
static_assert(offsetof(MiumBrowserResourceRequestHandlerState, resourceRequestHandler) == 0);

inline MiumBrowserClientState* getBrowserClientState(cef_base_ref_counted_t* base) {
  return reinterpret_cast<MiumBrowserClientState*>(base);
}

inline MiumBrowserDisplayHandlerState* getBrowserDisplayHandlerState(cef_base_ref_counted_t* base) {
  return base == nullptr ? nullptr : reinterpret_cast<MiumBrowserDisplayHandlerState*>(base);
}

inline MiumBrowserLifeSpanHandlerState* getBrowserLifeSpanHandlerState(cef_base_ref_counted_t* base) {
  return base == nullptr ? nullptr : reinterpret_cast<MiumBrowserLifeSpanHandlerState*>(base);
}

inline MiumBrowserJSDialogHandlerState* getBrowserJSDialogHandlerState(cef_base_ref_counted_t* base) {
  return base == nullptr ? nullptr : reinterpret_cast<MiumBrowserJSDialogHandlerState*>(base);
}

inline MiumBrowserLoadHandlerState* getBrowserLoadHandlerState(cef_base_ref_counted_t* base) {
  return base == nullptr ? nullptr : reinterpret_cast<MiumBrowserLoadHandlerState*>(base);
}

inline MiumBrowserPermissionHandlerState* getBrowserPermissionHandlerState(cef_base_ref_counted_t* base) {
  return base == nullptr ? nullptr : reinterpret_cast<MiumBrowserPermissionHandlerState*>(base);
}

inline MiumBrowserRequestHandlerState* getBrowserRequestHandlerState(cef_base_ref_counted_t* base) {
  return base == nullptr ? nullptr : reinterpret_cast<MiumBrowserRequestHandlerState*>(base);
}

inline MiumBrowserResourceRequestHandlerState* getBrowserResourceRequestHandlerState(cef_base_ref_counted_t* base) {
  return base == nullptr ? nullptr : reinterpret_cast<MiumBrowserResourceRequestHandlerState*>(base);
}

cef_client_t* createBrowserClient(void);
