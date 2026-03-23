#import <Foundation/Foundation.h>

#include <functional>
#include <utility>

#include "MiumCEFBridgeBrowserRegistry.h"
#include "MiumCEFBridgeInternalRuntimeExecutionSupport.h"
#include "MiumCEFBridgeInternalState.h"
#include "MiumCEFBridgeRuntime.h"
#include "MiumCEFBridgeThreading.h"
#if defined(MIUM_CEF_BRIDGE_TESTING)
#include "MiumCEFBridgeNative+Testing.h"
#endif

#if !defined(MIUM_CEF_BRIDGE_TESTING)
using MiumCEFResultCode = uint32_t;
using MiumCEFEventCallback = void (*)(MiumCEFResultCode, const char*, void*);
using MiumCEFRuntimeHandle = void*;
using MiumCEFBrowserHandle = void*;
using MiumCEFHostViewHandle = void*;
#endif

extern "C" MiumCEFResultCode miumNativeCEFEmitMessage(
  MiumCEFBrowserHandle browserHandle,
  const char* channel,
  const char* message
);
extern "C" MiumCEFResultCode miumNativeCEFDestroyBrowserHostView(MiumCEFHostViewHandle hostViewHandle);

namespace {

template <typename Fn>
static void runOnCefExecutor(Fn fn) {
  miumCEFRunOnCefExecutor(std::function<void()>(std::move(fn)));
}

template <typename Fn>
static void runOnCefExecutorAsync(Fn fn) {
  miumCEFRunOnCefExecutorAsync(std::function<void()>(std::move(fn)));
}

} // namespace

extern "C" {

bool miumNativeCEFIsLoaded(void) {
  return miumCEFRuntimeIsLoaded();
}

int miumNativeCEFHasPendingBrowserClose(void) {
  return miumCEFRuntimeHasPendingBrowserClose();
}

int miumNativeCEFMaybeRunSubprocess(int argc, const char* const* argv) {
  return miumCEFRuntimeMaybeRunSubprocess(argc, argv);
}

MiumCEFResultCode miumNativeCEFInitialize(
  const char* runtimeRootPath,
  const char* runtimeMetadataPath,
  MiumCEFEventCallback eventCallback,
  void* eventContext,
  MiumCEFRuntimeHandle* outRuntimeHandle
) {
  return miumCEFRuntimeInitialize(
    runtimeRootPath,
    runtimeMetadataPath,
    eventCallback,
    eventContext,
    outRuntimeHandle
  );
}

MiumCEFResultCode miumNativeCEFShutdown(MiumCEFRuntimeHandle runtimeHandle) {
  return miumCEFRuntimeShutdown(runtimeHandle);
}

MiumCEFResultCode miumNativeCEFDoMessageLoopWork() {
  return miumCEFRuntimeDoMessageLoopWork();
}

MiumCEFHostViewHandle miumNativeCEFHostViewHandleForBrowser(MiumCEFBrowserHandle browserHandle) {
  if (browserHandle == nullptr) {
    return nullptr;
  }

  CefStateLockGuard lock;
  return currentHostViewHandleForBrowserLocked(miumCEFNativeHandleToId(browserHandle));
}

#if defined(MIUM_CEF_BRIDGE_TESTING)
void miumNativeCEFTestRunOnCefExecutor(void* context, MiumCEFBridgeTestVoidCallback callback) {
  if (callback == nullptr) {
    return;
  }
  runOnCefExecutor([context, callback] {
    callback(context);
  });
}

void miumNativeCEFTestRunOnCefExecutorAsync(void* context, MiumCEFBridgeTestVoidCallback callback) {
  if (callback == nullptr) {
    return;
  }
  runOnCefExecutorAsync([context, callback] {
    callback(context);
  });
}
#endif

} // extern "C"
