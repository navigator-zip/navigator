#include "MiumCEFBridgeThreading.h"

#include <cassert>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <utility>

#include "CefThreadGate.h"
#include "MiumCEFBridgeInternalRuntimeExecutionSupport.h"
#include "MiumCEFBridgeInternalState.h"
#include "Tracing.h"

namespace {

static const void* kCefExecutorSpecific = reinterpret_cast<const void*>(0xC1EF7EC3);

static dispatch_queue_t cefExecutorQueue() {
  static dispatch_once_t once;
  static dispatch_queue_t queue;
  dispatch_once(&once, ^{
    dispatch_queue_attr_t attrs = dispatch_queue_attr_make_with_qos_class(
      DISPATCH_QUEUE_SERIAL,
      QOS_CLASS_USER_INITIATED,
      0
    );
    queue = dispatch_queue_create("com.mium.native.cef-executor", attrs);
    dispatch_queue_set_specific(queue, kCefExecutorSpecific, const_cast<void*>(kCefExecutorSpecific), nullptr);
  });
  return queue;
}

static bool isOnCefExecutor() {
  return dispatch_get_specific(kCefExecutorSpecific) == kCefExecutorSpecific;
}

static bool isOnCefMainThread() {
  return [NSThread isMainThread];
}

} // namespace

const char* miumCEFThreadLaneLabel() {
  const bool onMainThread = isOnCefMainThread();
  const bool onCefExecutor = isOnCefExecutor();
  if (onMainThread && onCefExecutor) {
    return "main+cef-executor";
  }
  if (onMainThread) {
    return "main";
  }
  if (onCefExecutor) {
    return "cef-executor";
  }
  return "other";
}

void miumCEFRunOnCefExecutor(std::function<void()> fn) {
  miumCefTrace("threading", "runOnCefExecutor enter lane=%s\n", miumCEFThreadLaneLabel());
  if (isOnCefExecutor()) {
    fn();
    miumCefTrace("threading", "runOnCefExecutor leave lane=%s (inline)\n", miumCEFThreadLaneLabel());
    return;
  }

  dispatch_sync(cefExecutorQueue(), ^{
    miumCefTrace("threading", "runOnCefExecutor body lane=%s\n", miumCEFThreadLaneLabel());
    fn();
  });
  miumCefTrace("threading", "runOnCefExecutor leave lane=%s\n", miumCEFThreadLaneLabel());
}

void miumCEFRunOnCefExecutorAsync(std::function<void()> fn) {
  miumCefTrace("threading", "runOnCefExecutorAsync enqueue lane=%s\n", miumCEFThreadLaneLabel());
  if (isOnCefExecutor()) {
    fn();
    miumCefTrace("threading", "runOnCefExecutorAsync leave lane=%s (inline)\n", miumCEFThreadLaneLabel());
    return;
  }
  dispatch_async(cefExecutorQueue(), ^{
    miumCefTrace("threading", "runOnCefExecutorAsync body lane=%s\n", miumCEFThreadLaneLabel());
    fn();
  });
}

void miumCEFRunOnCefMainThread(std::function<void()> fn) {
  auto task = std::make_shared<std::function<void()>>(std::move(fn));
  miumCefTrace("threading", "runOnCefMainThread enter lane=%s\n", miumCEFThreadLaneLabel());
  if (gStateLockDepth != 0) {
    fprintf(
      stderr,
      "[MiumCEFBridge] runOnCefMainThread called while gStateLock is held (depth=%d, lane=%s)\n",
      gStateLockDepth,
      miumCEFThreadLaneLabel()
    );
    assert(gStateLockDepth == 0 && "runOnCefMainThread called while gStateLock is held");
    abort();
  }
  if (miumCefIsOnMainThread()) {
    (*task)();
    miumCefTrace("threading", "runOnCefMainThread leave lane=%s (inline)\n", miumCEFThreadLaneLabel());
    return;
  }
  miumCefDispatchSyncOnMainThread([&] {
    miumCefTrace("threading", "runOnCefMainThread body lane=%s\n", miumCEFThreadLaneLabel());
    (*task)();
  });
  miumCefTrace("threading", "runOnCefMainThread leave lane=%s\n", miumCEFThreadLaneLabel());
}
