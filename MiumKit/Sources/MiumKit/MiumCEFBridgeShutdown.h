#pragma once

#include "MiumCEFBridgeCefApi.h"
#include "MiumCEFBridgeStateModels.h"

struct MiumCEFDetachedFrameworkArtifacts {
  void* frameworkHandle = nullptr;
};

struct MiumCEFFinalShutdown {
  CefShutdownFn shutdown = nullptr;
  MiumCEFDetachedFrameworkArtifacts artifacts;
};

bool miumCEFHasLoadedFrameworkArtifactsLocked();
MiumCEFDetachedFrameworkArtifacts miumCEFDetachFrameworkArtifactsLocked();
MiumCEFDetachedFrameworkArtifacts miumCEFDetachFrameworkArtifacts();
void miumCEFReleaseDetachedFrameworkArtifactsAndResetApiState(MiumCEFDetachedFrameworkArtifacts artifacts);
bool miumCEFBeginFinalShutdownLocked(MiumCEFFinalShutdown* shutdownContext);
void miumCEFUnloadFrameworkArtifactsWithoutShutdown();
void miumCEFShutdownAndUnloadFrameworkArtifacts(MiumCEFFinalShutdown shutdownContext);
void miumCEFClearRuntimeLivenessLocked();
void miumCEFResetDetachedFrameworkApiState();
void miumCEFResetRuntimeStateLocked();
size_t miumCEFPendingNativeBrowserCloseCountLocked();
void miumCEFFinishPendingBrowserClose(MiumCEFNativeBrowserCloseKind kind);
void miumCEFMaybeCompletePendingCefShutdown();
void miumCEFSchedulePendingShutdownPumpIfNeeded();
void miumCEFPumpPendingShutdownMessageLoop();
void miumCEFCloseUncommittedFrameworkHandle(void* frameworkHandle);
#if defined(MIUM_CEF_BRIDGE_TESTING)
void* miumCEFTestInjectedFrameworkHandleSentinel();
#endif
