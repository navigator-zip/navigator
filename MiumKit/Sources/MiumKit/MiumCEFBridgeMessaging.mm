#include "MiumCEFBridgeNative.h"

#include <atomic>
#include <cstdint>
#include <string>
#include <utility>

#include "MiumCEFBridgeBrowserRegistry.h"
#include "MiumCEFBridgeCallbackQueue.h"
#include "MiumCEFBridgeInternalAdapters.h"
#include "MiumCEFBridgeInternalPermissionAdapters.h"
#include "MiumCEFBridgeInternalRuntimeExecutionSupport.h"
#include "MiumCEFBridgeInternalState.h"
#include "MiumCEFBridgePermissions.h"
#include "Tracing.h"

namespace {

static MiumCEFResultCode registerMessageHandler(
  MiumCEFBrowserHandle browserHandle,
  const char* channel,
  const MiumCEFCallbackRegistrationRef& registration,
  void* handlerContext,
  MiumCEFEventCallback handler
) {
  if (browserHandle == nullptr || channel == nullptr) {
    miumCefTrace("messaging", "RegisterMessageHandler invalid args\n");
    return MiumCEFResultInvalidArgument;
  }

  const std::string channelString(channel);
  const uint64_t browserId = miumCEFNativeHandleToId(browserHandle);
  miumCefTrace(
    "messaging",
    "registerMessageHandler browserId=%llu channel=%s installing=%d\n",
    static_cast<unsigned long long>(browserId),
    channelString.c_str(),
    handler != nullptr ? 1 : 0
  );

  CefStateLockGuard lock;
  auto browserIter = gBrowsers.find(browserId);
  if (browserIter == gBrowsers.end() || !browserIter->second->active) {
    miumCefTrace(
      "messaging",
      "RegisterMessageHandler browser not active browserId=%llu channel=%s\n",
      static_cast<unsigned long long>(browserId),
      channelString.c_str()
    );
    return MiumCEFResultNotInitialized;
  }

  if (handler == nullptr) {
    miumCefTrace(
      "messaging",
      "RegisterMessageHandler remove channel=%s browserId=%llu\n",
      channelString.c_str(),
      static_cast<unsigned long long>(browserId)
    );
    if (auto handlerIt = browserIter->second->handlers.find(channelString);
        handlerIt != browserIter->second->handlers.end() && handlerIt->second.registration != nullptr) {
      handlerIt->second.registration->active.store(false, std::memory_order_release);
    }
    browserIter->second->handlers.erase(channelString);
    return MiumCEFResultOK;
  }

  MiumCEFMessageState state;
  state.channel = channelString;
  state.callback = handler;
  state.context = handlerContext;
  state.registration = ensureNativeCallbackRegistrationContext(registration, handlerContext);
  uint64_t generation = browserIter->second->nextMessageHandlerGeneration++;
  if (generation == 0) {
    generation = browserIter->second->nextMessageHandlerGeneration++;
  }
  state.generation = generation;
  if (auto existingIt = browserIter->second->handlers.find(channelString); existingIt != browserIter->second->handlers.end()
      && existingIt->second.registration != nullptr) {
    existingIt->second.registration->active.store(false, std::memory_order_release);
  }
  browserIter->second->handlers[channelString] = std::move(state);
  miumCefTrace(
    "messaging",
    "registerMessageHandler stored browserId=%llu channel=%s generation=%llu\n",
    static_cast<unsigned long long>(browserId),
    channelString.c_str(),
    static_cast<unsigned long long>(generation)
  );
  return MiumCEFResultOK;
}

} // namespace

MiumCEFResultCode miumNativeCEFRegisterMessageHandlerWithRegistration(
  MiumCEFBrowserHandle browserHandle,
  const char* channel,
  const MiumCEFCallbackRegistrationRef& registration,
  void* handlerContext,
  MiumCEFEventCallback handler
) {
  return registerMessageHandler(browserHandle, channel, registration, handlerContext, handler);
}

extern "C" {

MiumCEFResultCode miumNativeCEFRegisterMessageHandler(
  MiumCEFBrowserHandle browserHandle,
  const char* channel,
  void* handlerContext,
  MiumCEFEventCallback handler
) {
  return registerMessageHandler(
    browserHandle,
    channel,
    handler == nullptr ? MiumCEFCallbackRegistrationRef{} : ensureNativeCallbackRegistrationContext(nullptr, handlerContext),
    handlerContext,
    handler
  );
}

MiumCEFResultCode miumNativeCEFSetPermissionRequestHandlerWithRegistration(
  MiumCEFBrowserHandle browserHandle,
  const MiumCEFCallbackRegistrationRef& registration,
  void* handlerContext,
  MiumCEFPermissionRequestCallback handler
) {
  if (browserHandle == nullptr) {
    return MiumCEFResultInvalidArgument;
  }
  return miumCEFPermissionSetRequestHandler(
    miumCEFNativeHandleToId(browserHandle),
    handlerContext,
    ensureNativeCallbackRegistrationContext(registration, handlerContext),
    handler
  );
}

MiumCEFResultCode miumNativeCEFSetPermissionRequestHandler(
  MiumCEFBrowserHandle browserHandle,
  void* handlerContext,
  MiumCEFPermissionRequestCallback handler
) {
  if (browserHandle == nullptr) {
    return MiumCEFResultInvalidArgument;
  }
  return miumCEFPermissionSetRequestHandler(
    miumCEFNativeHandleToId(browserHandle),
    handlerContext,
    handler == nullptr ? MiumCEFCallbackRegistrationRef{} : ensureNativeCallbackRegistrationContext(nullptr, handlerContext),
    handler
  );
}

MiumCEFResultCode miumNativeCEFSetPermissionSessionDismissedHandlerWithRegistration(
  MiumCEFBrowserHandle browserHandle,
  const MiumCEFCallbackRegistrationRef& registration,
  void* handlerContext,
  MiumCEFPermissionSessionDismissedCallback handler
) {
  if (browserHandle == nullptr) {
    return MiumCEFResultInvalidArgument;
  }
  return miumCEFPermissionSetSessionDismissedHandler(
    miumCEFNativeHandleToId(browserHandle),
    handlerContext,
    ensureNativeCallbackRegistrationContext(registration, handlerContext),
    handler
  );
}

MiumCEFResultCode miumNativeCEFSetPermissionSessionDismissedHandler(
  MiumCEFBrowserHandle browserHandle,
  void* handlerContext,
  MiumCEFPermissionSessionDismissedCallback handler
) {
  if (browserHandle == nullptr) {
    return MiumCEFResultInvalidArgument;
  }
  return miumCEFPermissionSetSessionDismissedHandler(
    miumCEFNativeHandleToId(browserHandle),
    handlerContext,
    handler == nullptr ? MiumCEFCallbackRegistrationRef{} : ensureNativeCallbackRegistrationContext(nullptr, handlerContext),
    handler
  );
}

MiumCEFResultCode miumNativeCEFResolvePermissionRequest(
  MiumCEFPermissionSessionID sessionID,
  uint32_t resolution
) {
  MiumCEFPermissionExecutionBatch batch;
  switch (static_cast<MiumCEFPermissionResolution>(resolution)) {
    case MiumCEFPermissionResolution::allow:
      if (!miumCEFPermissionTakeResolutionBatch(
            sessionID,
            MiumCEFPermissionResolution::allow,
            MiumCEFPermissionSessionDismissReason::unknown,
            false,
            &batch
          )) {
        return MiumCEFResultNotInitialized;
      }
      miumCEFNativeExecutePermissionBatchOnCefMainThread(std::move(batch));
      return MiumCEFResultOK;
    case MiumCEFPermissionResolution::deny:
      if (!miumCEFPermissionTakeResolutionBatch(
            sessionID,
            MiumCEFPermissionResolution::deny,
            MiumCEFPermissionSessionDismissReason::unknown,
            false,
            &batch
          )) {
        return MiumCEFResultNotInitialized;
      }
      miumCEFNativeExecutePermissionBatchOnCefMainThread(std::move(batch));
      return MiumCEFResultOK;
    case MiumCEFPermissionResolution::cancel:
      if (!miumCEFPermissionTakeResolutionBatch(
            sessionID,
            MiumCEFPermissionResolution::cancel,
            MiumCEFPermissionSessionDismissReason::explicitCancel,
            true,
            &batch
          )) {
        return MiumCEFResultNotInitialized;
      }
      miumCEFNativeExecutePermissionBatchOnCefMainThread(std::move(batch));
      return MiumCEFResultOK;
  }
  return MiumCEFResultInvalidArgument;
}

MiumCEFResultCode miumNativeCEFEmitMessage(
  MiumCEFBrowserHandle browserHandle,
  const char* channel,
  const char* message
) {
  if (browserHandle == nullptr || channel == nullptr) {
    return MiumCEFResultInvalidArgument;
  }

  const uint64_t browserId = miumCEFNativeHandleToId(browserHandle);
  const std::string normalizedChannel = channel;
  const std::string normalizedMessage = message == nullptr ? std::string() : std::string(message);

  MiumCEFEventCallback callback = nullptr;
  void* context = nullptr;
  MiumCEFCallbackRegistrationRef registration;
  uint64_t handlerGeneration = 0;

  {
    CefStateLockGuard lock;
    auto browserIter = gBrowsers.find(browserId);
    if (browserIter == gBrowsers.end() || !shouldTrackBrowserForNativeCallbacksLocked(browserIter->second.get())) {
      miumCefTrace(
        "messaging",
        "EmitMessage browser unavailable for callbacks browserId=%llu channel=%s\n",
        static_cast<unsigned long long>(browserId),
        normalizedChannel.c_str()
      );
      return MiumCEFResultNotInitialized;
    }

    auto handlerIter = browserIter->second->handlers.find(normalizedChannel);
    if (handlerIter == browserIter->second->handlers.end() || handlerIter->second.callback == nullptr) {
      miumCefTrace(
        "messaging",
        "EmitMessage no handler for channel=%s browserId=%llu\n",
        normalizedChannel.c_str(),
        static_cast<unsigned long long>(browserId)
      );
      return MiumCEFResultError;
    }
    callback = handlerIter->second.callback;
    context = handlerIter->second.context;
    registration = handlerIter->second.registration;
    handlerGeneration = handlerIter->second.generation;
  }
  if (callback != nullptr) {
    runOnMessageQueue(
      callback,
      MiumCEFResultOK,
      normalizedMessage.c_str(),
      context,
      browserId,
      normalizedChannel.c_str(),
      handlerGeneration,
      registration
    );
  }
  return MiumCEFResultOK;
}

} // extern "C"
