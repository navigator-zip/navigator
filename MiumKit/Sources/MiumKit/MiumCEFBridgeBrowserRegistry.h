#pragma once

#include "MiumCEFBridgeStateModels.h"

MiumCEFBrowserState* activeBrowserStateLocked(uint64_t browserId);
MiumCEFHostViewState* activeHostViewStateLocked(uint64_t hostViewId);
void assertBrowserStateConsistencyLocked(const MiumCEFBrowserState* browserState);
MiumCEFHostResourceState* ensureHostResources(MiumCEFHostViewState* hostViewState);
NSView* resolvedHostViewForState(MiumCEFHostViewState* hostViewState);
MiumBrowserContainerView* resolvedContainerViewForState(MiumCEFHostViewState* hostViewState);
MiumCEFHostViewState* activeHostViewStateForViewLocked(NSView* hostView);
bool shouldTrackBrowserForNativeCallbacksLocked(const MiumCEFBrowserState* browserState);
bool canBindBrowserToHostViewLocked(
  const MiumCEFBrowserState* browserState,
  uint64_t hostViewId,
  void* hostView
);
bool bindBrowserToHostViewLocked(
  MiumCEFBrowserState* browserState,
  uint64_t hostViewId,
  void* hostView
);
bool installNativeBrowserForHostViewLocked(
  uint64_t browserId,
  uint64_t hostViewId,
  void* hostView,
  cef_browser_t* createdBrowser,
  cef_client_t* createdClient,
  bool* releaseCreated,
  bool* shouldReplaceManagedSubviews,
  cef_browser_t** browserToClose,
  cef_client_t** browserToCloseClient
);
void clearBrowserHostViewBindingLocked(MiumCEFBrowserState* browserState);
MiumCEFHostViewHandle currentHostViewHandleForBrowserLocked(uint64_t browserId);
bool snapshotNativeCallbackPayloadDeliverable(
  uint64_t browserId,
  const char* channel,
  uint64_t handlerGeneration
);
uint64_t browserIdFromNativeBrowser(cef_browser_t* browser);
void bindNativeBrowserIdForBrowser(uint64_t browserId, cef_browser_t* previousNative, cef_browser_t* nextNative);
void registerPendingBrowserCloseLocked(MiumCEFNativeBrowserCloseKind kind);
bool detachNativeBrowserForReplacementLocked(
  MiumCEFBrowserState* browserState,
  cef_browser_t** outBrowser,
  cef_client_t** outClient
);
MiumCEFBrowserCloseDisposition beginClosingNativeBrowserForIdLocked(
  uint64_t browserId,
  cef_browser_t** outBrowser,
  cef_client_t** outClient,
  uint64_t* outRuntimeId,
  bool trackRuntimePendingClose = false
);
void finalizeClosedBrowserState(uint64_t browserId, uint64_t runtimeId);
