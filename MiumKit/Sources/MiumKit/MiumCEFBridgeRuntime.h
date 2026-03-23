#pragma once

#include "MiumCEFBridgeNative.h"

bool miumCEFRuntimeIsLoaded(void);
int miumCEFRuntimeHasPendingBrowserClose(void);
int miumCEFRuntimeMaybeRunSubprocess(int argc, const char* const* argv);
MiumCEFResultCode miumCEFRuntimeInitialize(
  const char* runtimeRootPath,
  const char* runtimeMetadataPath,
  MiumCEFEventCallback eventCallback,
  void* eventContext,
  MiumCEFRuntimeHandle* outRuntimeHandle
);
MiumCEFResultCode miumCEFRuntimeShutdown(MiumCEFRuntimeHandle runtimeHandle);
MiumCEFResultCode miumCEFRuntimeDoMessageLoopWork(void);
