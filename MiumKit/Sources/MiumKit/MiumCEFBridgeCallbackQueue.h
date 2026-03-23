#pragma once

#include "MiumCEFBridgeInternalState.h"

enum class MiumNativeCallbackRoute : uint8_t {
  completion = 0,
  message
};

struct MiumNativeCallbackPayload {
  MiumCEFEventCallback callback = nullptr;
  MiumCEFResultCode code = MiumCEFResultError;
  std::string payload;
  std::string channel;
  MiumCEFCallbackRegistrationRef registration;
  uint64_t browserId = 0;
  uint64_t handlerGeneration = 0;
  bool deliverable = true;
};

MiumCEFCallbackRegistrationRef ensureNativeCallbackRegistrationContext(
  MiumCEFCallbackRegistrationRef registration,
  void* context
);
MiumCEFCallbackRegistrationRef makeNativeCallbackRegistration(void* context);
dispatch_queue_t callbackCompletionQueue();
void clearNativeCallbackPayloadsForBrowser(uint64_t browserId);
void clearNativeCallbackPayloadsForBrowsers(const std::unordered_set<uint64_t>& browserIds);
void enqueueNativeCallbackPayload(MiumNativeCallbackPayload payload, MiumNativeCallbackRoute route);
void runOnCallbackQueue(
  MiumCEFCompletion completion,
  MiumCEFResultCode code,
  const char* message,
  void* context,
  uint64_t browserId = 0
);
void runOnEventQueue(MiumCEFEventCallback callback, MiumCEFResultCode code, const char* message, void* context);
void runOnMessageQueue(
  MiumCEFEventCallback callback,
  MiumCEFResultCode code,
  const char* message,
  void* context,
  uint64_t browserId = 0,
  const char* channel = nullptr,
  uint64_t handlerGeneration = 0,
  MiumCEFCallbackRegistrationRef registration = nullptr
);
