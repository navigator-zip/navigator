#include "MiumCEFBridgeCallbackQueue.h"
#include "MiumCEFBridgeInternalAdapters.h"
#include "Tracing.h"

#if defined(MIUM_CEF_BRIDGE_TESTING)
#include "MiumCEFBridgeNative+Testing.h"
#endif

static constexpr const char* kMiumNativeExecutorCompletionQueueLabel =
  "com.mium.native.executor.completion";
static constexpr const char* kMiumNativeExecutorMessageQueueLabel =
  "com.mium.native.executor.message";
static constexpr uint64_t kMiumNativeCallbackMaxBufferCount = 512;

enum class MiumNativeCallbackOverflowPolicy : uint8_t {
  dropOldest = 0,
  latest,
  coalesce
};

struct MiumNativeCallbackQueueState {
  bool draining = false;
  MiumNativeCallbackOverflowPolicy overflowPolicy = MiumNativeCallbackOverflowPolicy::dropOldest;
  uint64_t maxBufferCount = kMiumNativeCallbackMaxBufferCount;
  std::deque<MiumNativeCallbackPayload> payloads;
};

struct MiumCEFContextCallbackRegistration : MiumCEFCallbackRegistration {};

MiumCEFCallbackRegistrationRef ensureNativeCallbackRegistrationContext(
  MiumCEFCallbackRegistrationRef registration,
  void* context
) {
  if (registration == nullptr) {
    registration = std::make_shared<MiumCEFContextCallbackRegistration>();
  }
  if (registration->userContext == nullptr) {
    registration->userContext = context;
  }
  return registration;
}

MiumCEFCallbackRegistrationRef makeNativeCallbackRegistration(void* context) {
  return ensureNativeCallbackRegistrationContext(std::make_shared<MiumCEFContextCallbackRegistration>(), context);
}

static void* nativeCallbackContext(const MiumNativeCallbackPayload& payload) {
  return payload.registration == nullptr ? nullptr : payload.registration->userContext;
}

dispatch_queue_t callbackCompletionQueue() {
  static dispatch_once_t once;
  static dispatch_queue_t queue;
  dispatch_once(&once, ^{
    queue = dispatch_queue_create(kMiumNativeExecutorCompletionQueueLabel, DISPATCH_QUEUE_SERIAL);
  });
  return queue;
}

static dispatch_queue_t callbackMessageQueue() {
  static dispatch_once_t once;
  static dispatch_queue_t queue;
  dispatch_once(&once, ^{
    queue = dispatch_queue_create(kMiumNativeExecutorMessageQueueLabel, DISPATCH_QUEUE_SERIAL);
  });
  return queue;
}

static dispatch_queue_t callbackQueueForRoute(MiumNativeCallbackRoute route) {
  return route == MiumNativeCallbackRoute::completion
    ? callbackCompletionQueue()
    : callbackMessageQueue();
}

static MiumNativeCallbackQueueState& nativeCallbackQueueStateForRoute(MiumNativeCallbackRoute route) {
  static MiumNativeCallbackQueueState completionState;
  static MiumNativeCallbackQueueState messageState;
  return route == MiumNativeCallbackRoute::completion ? completionState : messageState;
}

static bool canCoalesceNativeCallbackPayloads(
  const MiumNativeCallbackPayload& existing,
  const MiumNativeCallbackPayload& incoming
);

static std::mutex gNativeCallbackQueueLock;

#if defined(MIUM_CEF_BRIDGE_TESTING)
static MiumNativeCallbackRoute nativeCallbackRouteFromTestRoute(MiumCEFBridgeTestCallbackRoute route) {
  return route == MiumCEFBridgeTestCallbackRoute::nonUI
    ? MiumNativeCallbackRoute::message
    : MiumNativeCallbackRoute::completion;
}
#endif

void clearNativeCallbackPayloadsForBrowser(uint64_t browserId) {
  std::lock_guard<std::mutex> lock(gNativeCallbackQueueLock);
  auto& completionState = nativeCallbackQueueStateForRoute(MiumNativeCallbackRoute::completion);
  auto& messageState = nativeCallbackQueueStateForRoute(MiumNativeCallbackRoute::message);

  completionState.payloads.erase(
    std::remove_if(
      completionState.payloads.begin(),
      completionState.payloads.end(),
      [browserId](const MiumNativeCallbackPayload& payload) {
        return payload.browserId == browserId;
      }
    ),
    completionState.payloads.end()
  );

  messageState.payloads.erase(
    std::remove_if(
      messageState.payloads.begin(),
      messageState.payloads.end(),
      [browserId](const MiumNativeCallbackPayload& payload) {
        return payload.browserId == browserId;
      }
    ),
    messageState.payloads.end()
  );
}

void clearNativeCallbackPayloadsForBrowsers(const std::unordered_set<uint64_t>& browserIds) {
  if (!browserIds.empty()) {
    std::lock_guard<std::mutex> lock(gNativeCallbackQueueLock);
    auto& completionState = nativeCallbackQueueStateForRoute(MiumNativeCallbackRoute::completion);
    auto& messageState = nativeCallbackQueueStateForRoute(MiumNativeCallbackRoute::message);

    completionState.payloads.erase(
      std::remove_if(
        completionState.payloads.begin(),
        completionState.payloads.end(),
        [&browserIds](const MiumNativeCallbackPayload& payload) {
          return browserIds.find(payload.browserId) != browserIds.end();
        }
      ),
      completionState.payloads.end()
    );

    messageState.payloads.erase(
      std::remove_if(
        messageState.payloads.begin(),
        messageState.payloads.end(),
        [&browserIds](const MiumNativeCallbackPayload& payload) {
          return browserIds.find(payload.browserId) != browserIds.end();
        }
      ),
      messageState.payloads.end()
    );
  }
}

static bool canCoalesceNativeCallbackPayloads(
  const MiumNativeCallbackPayload& existing,
  const MiumNativeCallbackPayload& incoming
) {
  return existing.callback == incoming.callback
    && existing.code == incoming.code
    && existing.payload == incoming.payload
    && existing.channel == incoming.channel
    && nativeCallbackContext(existing) == nativeCallbackContext(incoming)
    && existing.browserId == incoming.browserId
    && existing.handlerGeneration == incoming.handlerGeneration;
}

void enqueueNativeCallbackPayload(
  MiumNativeCallbackPayload payload,
  MiumNativeCallbackRoute route
) {
  // Completion/message callbacks are delivered on serialized background queues, not AppKit main.
  // Callers that touch UI must dispatch to main before using AppKit.
  // Callers must also avoid re-entering bridge APIs synchronously from these callbacks
  // while holding external locks; that can create lock-order inversions outside this file.
  bool shouldDrain = false;
  {
    std::lock_guard<std::mutex> lock(gNativeCallbackQueueLock);
    auto& queueState = nativeCallbackQueueStateForRoute(route);

    switch (queueState.overflowPolicy) {
      case MiumNativeCallbackOverflowPolicy::dropOldest:
        queueState.payloads.push_back(std::move(payload));
        if (queueState.payloads.size() > queueState.maxBufferCount) {
          queueState.payloads.pop_front();
        }
        break;
      case MiumNativeCallbackOverflowPolicy::latest:
        queueState.payloads.clear();
        queueState.payloads.push_back(std::move(payload));
        break;
      case MiumNativeCallbackOverflowPolicy::coalesce:
        if (!queueState.payloads.empty()
            && canCoalesceNativeCallbackPayloads(queueState.payloads.back(), payload)) {
          queueState.payloads.back() = std::move(payload);
        } else {
          queueState.payloads.push_back(std::move(payload));
          if (queueState.payloads.size() > queueState.maxBufferCount) {
            queueState.payloads.pop_front();
          }
        }
        break;
    }

    if (!queueState.draining) {
      queueState.draining = true;
      shouldDrain = true;
    }
  }
  if (!shouldDrain) {
    return;
  }

  dispatch_async(callbackQueueForRoute(route), ^{
    #ifndef NDEBUG
    dispatch_assert_queue(callbackQueueForRoute(route));
    #endif

    while (true) {
      MiumNativeCallbackPayload queued;
      {
        std::lock_guard<std::mutex> lock(gNativeCallbackQueueLock);
        auto& queueState = nativeCallbackQueueStateForRoute(route);
        if (queueState.payloads.empty()) {
          queueState.draining = false;
          return;
        }
        queued = std::move(queueState.payloads.front());
        queueState.payloads.pop_front();
      }
      if (queued.callback == nullptr) {
        continue;
      }
      assert(queued.registration != nullptr && "Queued callback payload is missing a stable registration");
      if (queued.registration != nullptr && !queued.registration->active.load(std::memory_order_acquire)) {
        continue;
      }
      if (!queued.deliverable) {
        continue;
      }

      queued.callback(
        queued.code,
        queued.payload.c_str(),
        nativeCallbackContext(queued)
      );
    }
  });
}

void runOnCallbackQueue(
  MiumCEFCompletion completion,
  MiumCEFResultCode code,
  const char* message,
  void* context,
  uint64_t browserId
) {
  if (completion == nullptr) {
    return;
  }

  // Completion callbacks are delivered on a serialized background queue.
  // This is NOT the AppKit main thread. Dispatch to main before touching NSView, NSWindow,
  // or other Cocoa/AppKit UI state. Never make synchronous main-thread bridge re-entries from
  // callback handlers while holding external locks.
  MiumNativeCallbackPayload payload;
  payload.callback = completion;
  payload.code = code;
  payload.payload = (message == nullptr ? std::string() : std::string(message));
  payload.channel = std::string();
  payload.registration = ensureNativeCallbackRegistrationContext(nullptr, context);
  payload.browserId = browserId;
  payload.handlerGeneration = 0;
  payload.deliverable = miumCEFSnapshotNativeCallbackPayloadDeliverable(browserId, nullptr, 0);
  enqueueNativeCallbackPayload(std::move(payload), MiumNativeCallbackRoute::completion);
}

void runOnEventQueue(MiumCEFEventCallback callback, MiumCEFResultCode code, const char* message, void* context) {
  miumCefTrace(
    "callback-queue",
    "event: code=%u message=%s\n",
    static_cast<unsigned int>(code),
    message == nullptr ? "<no message>" : message
  );
  if (callback == nullptr) {
    return;
  }

  // Runtime/global events are delivered on the serialized completion queue, not AppKit main.
  // They remain deliverable even if browsers teardown while the queue drains. AppKit callers
  // must dispatch to the main thread before touching Cocoa UI state.
  MiumNativeCallbackPayload payload;
  payload.callback = callback;
  payload.code = code;
  payload.payload = (message == nullptr ? std::string() : std::string(message));
  payload.channel = std::string();
  payload.registration = ensureNativeCallbackRegistrationContext(nullptr, context);
  payload.browserId = 0;
  payload.handlerGeneration = 0;
  payload.deliverable = true;
  enqueueNativeCallbackPayload(std::move(payload), MiumNativeCallbackRoute::completion);
}

void runOnMessageQueue(
  MiumCEFEventCallback callback,
  MiumCEFResultCode code,
  const char* message,
  void* context,
  uint64_t browserId,
  const char* channel,
  uint64_t handlerGeneration,
  MiumCEFCallbackRegistrationRef registration
) {
  if (callback == nullptr) {
    return;
  }

  // Browser-scoped messages are delivered on a serialized background message queue, not AppKit
  // main. They are pruned at delivery time once the logical browser is no longer available for
  // callbacks. AppKit callers must dispatch to the main thread before touching Cocoa UI state.
  MiumNativeCallbackPayload payload;
  payload.callback = callback;
  payload.code = code;
  payload.payload = (message == nullptr ? std::string() : std::string(message));
  payload.channel = channel == nullptr ? std::string() : std::string(channel);
  payload.registration = ensureNativeCallbackRegistrationContext(std::move(registration), context);
  payload.browserId = browserId;
  payload.handlerGeneration = handlerGeneration;
  payload.deliverable = miumCEFSnapshotNativeCallbackPayloadDeliverable(browserId, channel, handlerGeneration);
  enqueueNativeCallbackPayload(std::move(payload), MiumNativeCallbackRoute::message);
}

#if defined(MIUM_CEF_BRIDGE_TESTING)
void miumNativeCEFTestResetCallbackQueues(void) {
  std::lock_guard<std::mutex> lock(gNativeCallbackQueueLock);
  auto& completionState = nativeCallbackQueueStateForRoute(MiumNativeCallbackRoute::completion);
  auto& messageState = nativeCallbackQueueStateForRoute(MiumNativeCallbackRoute::message);

  completionState.payloads.clear();
  completionState.draining = false;
  completionState.overflowPolicy = MiumNativeCallbackOverflowPolicy::dropOldest;
  completionState.maxBufferCount = kMiumNativeCallbackMaxBufferCount;

  messageState.payloads.clear();
  messageState.draining = false;
  messageState.overflowPolicy = MiumNativeCallbackOverflowPolicy::dropOldest;
  messageState.maxBufferCount = kMiumNativeCallbackMaxBufferCount;
}

void miumNativeCEFTestSetCallbackQueueOverflowPolicy(
  MiumCEFBridgeTestCallbackRoute route,
  MiumCEFBridgeTestCallbackOverflowPolicy policy,
  uint64_t maxBufferCount
) {
  std::lock_guard<std::mutex> lock(gNativeCallbackQueueLock);
  auto& state = nativeCallbackQueueStateForRoute(nativeCallbackRouteFromTestRoute(route));
  switch (policy) {
    case MiumCEFBridgeTestCallbackOverflowPolicy::dropOldest:
      state.overflowPolicy = MiumNativeCallbackOverflowPolicy::dropOldest;
      break;
    case MiumCEFBridgeTestCallbackOverflowPolicy::latest:
      state.overflowPolicy = MiumNativeCallbackOverflowPolicy::latest;
      break;
    case MiumCEFBridgeTestCallbackOverflowPolicy::coalesce:
      state.overflowPolicy = MiumNativeCallbackOverflowPolicy::coalesce;
      break;
  }
  state.maxBufferCount = maxBufferCount;
}

void miumNativeCEFTestSetCallbackQueueDraining(
  MiumCEFBridgeTestCallbackRoute route,
  bool draining
) {
  std::lock_guard<std::mutex> lock(gNativeCallbackQueueLock);
  auto& state = nativeCallbackQueueStateForRoute(nativeCallbackRouteFromTestRoute(route));
  state.draining = draining;
}

size_t miumNativeCEFTestBufferedCallbackCount(MiumCEFBridgeTestCallbackRoute route) {
  std::lock_guard<std::mutex> lock(gNativeCallbackQueueLock);
  const auto& state = nativeCallbackQueueStateForRoute(nativeCallbackRouteFromTestRoute(route));
  return state.payloads.size();
}

std::vector<std::string> miumNativeCEFTestBufferedCallbackMessages(
  MiumCEFBridgeTestCallbackRoute route
) {
  std::vector<std::string> messages;
  std::lock_guard<std::mutex> lock(gNativeCallbackQueueLock);
  const auto& state = nativeCallbackQueueStateForRoute(nativeCallbackRouteFromTestRoute(route));
  messages.reserve(state.payloads.size());
  for (const auto& payload : state.payloads) {
    messages.push_back(payload.payload);
  }
  return messages;
}

void miumNativeCEFTestEnqueueCallbackPayload(
  MiumCEFEventCallback callback,
  MiumCEFResultCode code,
  const char* message,
  void* context,
  uint64_t browserId,
  MiumCEFBridgeTestCallbackRoute route
) {
  MiumNativeCallbackPayload payload;
  payload.callback = callback;
  payload.code = code;
  payload.payload = message == nullptr ? std::string() : std::string(message);
  payload.channel = std::string();
  payload.registration = makeNativeCallbackRegistration(context);
  payload.browserId = browserId;
  payload.handlerGeneration = 0;
  payload.deliverable = miumCEFSnapshotNativeCallbackPayloadDeliverable(browserId, nullptr, 0);
  enqueueNativeCallbackPayload(std::move(payload), nativeCallbackRouteFromTestRoute(route));
}
#endif
