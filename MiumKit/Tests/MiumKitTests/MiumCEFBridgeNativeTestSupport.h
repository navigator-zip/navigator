#pragma once

#import <AppKit/AppKit.h>
#import <XCTest/XCTest.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

#include <atomic>
#include <condition_variable>
#include <cstring>
#include <cstdint>
#include <cstdlib>
#include <dlfcn.h>
#include <fcntl.h>
#include <functional>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <unordered_map>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#include <utility>
#include <vector>

#include "../../Sources/MiumKit/MiumCEFBridgeNative.h"
#include "../../Sources/MiumKit/MiumCEFBridgeNative+Testing.h"
#include "../../Sources/MiumKit/CEFBridge.h"
#include "../../Sources/MiumKit/CEFBridge+Testing.h"
#include "../../Sources/MiumKit/Vendor/CEF/include/capi/cef_v8_capi.h"

#if !defined(MIUM_CEF_BRIDGE_TESTING)
#error MiumCEFBridgeNative test hooks must be enabled for debug test builds.
#endif

namespace MiumCEFBridgeNativeTestSupport {

constexpr NSTimeInterval kCallbackTimeout = 1.0;
constexpr const char* _Nonnull kRuntimeUnavailableMessage = "CEF runtime is unavailable";
inline int gExecuteProcessCalls = 0;
inline int gExecuteProcessLastArgc = 0;
inline int gExecuteProcessReturnCode = -1;
inline bool gExecuteProcessLastHadApplication = false;
inline bool gExecuteProcessLastAppHasBrowserProcessHandler = false;
inline bool gExecuteProcessLastAppHasScheduleMessagePumpWork = false;
inline bool gExecuteProcessLastAppHasRenderProcessHandler = false;
inline bool gExecuteProcessLastAppHasProcessMessageReceivedHandler = false;
inline int gProcessExitCallbackCode = -1;
inline int gMessageLoopWorkCalls = 0;
inline int gShutdownCalls = 0;
extern "C" bool miumNativeCEFTestHandleRendererExecuteJavaScriptMessage(
  cef_frame_t* frame,
  const char* channel,
  const char* script
);
struct ShutdownSnapshotState;
inline ShutdownSnapshotState* gShutdownSnapshotState = nullptr;
inline std::string gUTF8ConversionFailureNeedle;
inline int gUTF8ConversionFailureCallIndex = -1;
inline int gUTF8ConversionCallCount = 0;
struct BlockingInitializeState;
inline BlockingInitializeState* gBlockingInitializeState = nullptr;
inline cef_v8_context_t* gCurrentV8Context = nullptr;

struct ScopedEnvironmentVariable {
  std::string name;
  std::string previousValue;
  bool hadPreviousValue = false;

  explicit ScopedEnvironmentVariable(const char* variableName, const char* value = nullptr)
    : name(variableName == nullptr ? "" : variableName) {
    if (name.empty()) {
      return;
    }

    const char* existingValue = std::getenv(name.c_str());
    if (existingValue != nullptr) {
      previousValue = existingValue;
      hadPreviousValue = true;
    }

    if (value == nullptr) {
      unsetenv(name.c_str());
    } else {
      setenv(name.c_str(), value, 1);
    }
  }

  ~ScopedEnvironmentVariable() {
    if (name.empty()) {
      return;
    }

    if (hadPreviousValue) {
      setenv(name.c_str(), previousValue.c_str(), 1);
    } else {
      unsetenv(name.c_str());
    }
  }

  void set(const char* value) const {
    if (name.empty()) {
      return;
    }
    if (value == nullptr) {
      unsetenv(name.c_str());
    } else {
      setenv(name.c_str(), value, 1);
    }
  }
};

struct FakeInitializeCapture {
  int returnValue = 1;
  int callCount = 0;
  int lastArgc = 0;
  std::vector<std::string> argv;
  std::string browserSubprocessPath;
  std::string resourcesDirPath;
  std::string localesDirPath;
  std::string cachePath;
  std::string rootCachePath;
  std::string locale;
  std::string acceptLanguageList;
  int noSandbox = 0;
  int logSeverity = 0;
  int multiThreadedMessageLoop = 0;
  int externalMessagePump = 0;
  int persistSessionCookies = 0;
  bool lastHadApplication = false;
  bool lastAppHasBrowserProcessHandler = false;
  bool lastAppHasScheduleMessagePumpWork = false;
  bool lastAppHasRenderProcessHandler = false;
  bool lastAppHasProcessMessageReceivedHandler = false;
};

inline FakeInitializeCapture* gInitializeCapture = nullptr;

struct FakeRefCountedLifetime {
  std::atomic<int> refCount{1};
  std::atomic<int> finalReleaseCount{0};
  std::function<void()> onFinalRelease;
};

template <typename State>
inline State* stateFromBase(cef_base_ref_counted_t* base) {
  return base == nullptr ? nullptr : reinterpret_cast<State*>(base);
}

template <typename State>
inline void CEF_CALLBACK fakeAddRef(cef_base_ref_counted_t* base) {
  auto* state = stateFromBase<State>(base);
  if (state == nullptr) {
    return;
  }
  state->lifetime.refCount.fetch_add(1, std::memory_order_relaxed);
}

template <typename State>
inline int CEF_CALLBACK fakeRelease(cef_base_ref_counted_t* base) {
  auto* state = stateFromBase<State>(base);
  if (state == nullptr) {
    return 0;
  }
  if (state->lifetime.refCount.fetch_sub(1, std::memory_order_acq_rel) != 1) {
    return 0;
  }
  state->lifetime.finalReleaseCount.fetch_add(1, std::memory_order_relaxed);
  if (state->lifetime.onFinalRelease) {
    state->lifetime.onFinalRelease();
  }
  return 1;
}

template <typename State>
inline int CEF_CALLBACK fakeHasOneRef(cef_base_ref_counted_t* base) {
  auto* state = stateFromBase<State>(base);
  if (state == nullptr) {
    return 0;
  }
  return state->lifetime.refCount.load(std::memory_order_relaxed) == 1 ? 1 : 0;
}

template <typename State>
inline int CEF_CALLBACK fakeHasAtLeastOneRef(cef_base_ref_counted_t* base) {
  auto* state = stateFromBase<State>(base);
  if (state == nullptr) {
    return 0;
  }
  return state->lifetime.refCount.load(std::memory_order_relaxed) > 0 ? 1 : 0;
}

inline std::string stringFromCEFString(const cef_string_t* value) {
  if (value == nullptr || value->str == nullptr || value->length == 0) {
    return {};
  }

  NSString* string = [[NSString alloc] initWithCharacters:reinterpret_cast<const unichar*>(value->str)
                                                   length:static_cast<NSUInteger>(value->length)];
  if (string == nil) {
    return {};
  }
  const char* utf8 = string.UTF8String;
  return utf8 == nullptr ? std::string() : std::string(utf8);
}

inline void freeUTF16Chars(char16_t* value) {
  std::free(value);
}

inline void captureAppHandlerConfiguration(
  cef_app_t* application,
  bool* outHasBrowserProcessHandler,
  bool* outHasScheduleMessagePumpWork,
  bool* outHasRenderProcessHandler,
  bool* outHasProcessMessageReceived
) {
  if (outHasBrowserProcessHandler != nullptr) {
    *outHasBrowserProcessHandler = false;
  }
  if (outHasScheduleMessagePumpWork != nullptr) {
    *outHasScheduleMessagePumpWork = false;
  }
  if (outHasRenderProcessHandler != nullptr) {
    *outHasRenderProcessHandler = false;
  }
  if (outHasProcessMessageReceived != nullptr) {
    *outHasProcessMessageReceived = false;
  }
  if (application == nullptr) {
    return;
  }

  if (application->get_browser_process_handler != nullptr) {
    cef_browser_process_handler_t* browserHandler = application->get_browser_process_handler(application);
    if (browserHandler != nullptr) {
      if (outHasBrowserProcessHandler != nullptr) {
        *outHasBrowserProcessHandler = true;
      }
      if (outHasScheduleMessagePumpWork != nullptr) {
        *outHasScheduleMessagePumpWork = browserHandler->on_schedule_message_pump_work != nullptr;
      }
      if (browserHandler->base.release != nullptr) {
        browserHandler->base.release(&browserHandler->base);
      }
    }
  }

  if (application->get_render_process_handler != nullptr) {
    cef_render_process_handler_t* renderHandler = application->get_render_process_handler(application);
    if (renderHandler != nullptr) {
      if (outHasRenderProcessHandler != nullptr) {
        *outHasRenderProcessHandler = true;
      }
      if (outHasProcessMessageReceived != nullptr) {
        *outHasProcessMessageReceived = renderHandler->on_process_message_received != nullptr;
      }
      if (renderHandler->base.release != nullptr) {
        renderHandler->base.release(&renderHandler->base);
      }
    }
  }
}

inline int fakeUTF8ToUTF16(const char* source, size_t sourceLength, cef_string_t* output) {
  gUTF8ConversionCallCount += 1;
  if (output == nullptr) {
    return 0;
  }

  output->str = nullptr;
  output->length = 0;
  output->dtor = nullptr;

  if (source == nullptr || sourceLength == 0) {
    return 1;
  }

  auto* buffer = static_cast<char16_t*>(std::calloc(sourceLength + 1, sizeof(char16_t)));
  if (buffer == nullptr) {
    return 0;
  }

  for (size_t index = 0; index < sourceLength; ++index) {
    buffer[index] = static_cast<char16_t>(static_cast<unsigned char>(source[index]));
  }

  output->str = buffer;
  output->length = sourceLength;
  output->dtor = freeUTF16Chars;
  return 1;
}

inline int fakeUTF8ToUTF16MaybeFail(const char* source, size_t sourceLength, cef_string_t* output) {
  if (!gUTF8ConversionFailureNeedle.empty() && source != nullptr) {
    const std::string value(source, sourceLength);
    if (value.find(gUTF8ConversionFailureNeedle) != std::string::npos) {
      if (output != nullptr) {
        output->str = nullptr;
        output->length = 0;
        output->dtor = nullptr;
      }
      return 0;
    }
  }

  return fakeUTF8ToUTF16(source, sourceLength, output);
}

inline int fakeUTF8ToUTF16MaybeFailOnCall(const char* source, size_t sourceLength, cef_string_t* output) {
  const int nextCallIndex = gUTF8ConversionCallCount + 1;
  if (gUTF8ConversionFailureCallIndex > 0 && nextCallIndex == gUTF8ConversionFailureCallIndex) {
    gUTF8ConversionCallCount = nextCallIndex;
    if (output != nullptr) {
      output->str = nullptr;
      output->length = 0;
      output->dtor = nullptr;
    }
    return 0;
  }

  return fakeUTF8ToUTF16(source, sourceLength, output);
}

inline void fakeUTF16Clear(cef_string_t* value) {
  if (value == nullptr) {
    return;
  }
  if (value->str != nullptr && value->dtor != nullptr) {
    value->dtor(value->str);
  }
  value->str = nullptr;
  value->length = 0;
  value->dtor = nullptr;
}

inline void fakeUserFreeUTF16Free(cef_string_userfree_utf16_t value) {
  if (value == nullptr) {
    return;
  }
  fakeUTF16Clear(value);
  std::free(value);
}

inline int fakeExecuteProcess(const cef_main_args_t* args, cef_app_t* application, void*) {
  gExecuteProcessCalls += 1;
  gExecuteProcessLastArgc = args == nullptr ? 0 : args->argc;
  gExecuteProcessLastHadApplication = application != nullptr;
  captureAppHandlerConfiguration(
    application,
    &gExecuteProcessLastAppHasBrowserProcessHandler,
    &gExecuteProcessLastAppHasScheduleMessagePumpWork,
    &gExecuteProcessLastAppHasRenderProcessHandler,
    &gExecuteProcessLastAppHasProcessMessageReceivedHandler
  );
  return gExecuteProcessReturnCode;
}

inline void fakeDoMessageLoopWork(void) {
  gMessageLoopWorkCalls += 1;
}

inline void fakeShutdown(void) {
  gShutdownCalls += 1;
}

struct ShutdownSnapshotState {
  bool initialized = true;
  bool shutdownExecuting = false;
  bool frameworkLoaded = true;
};

inline void fakeShutdownCapturingState(void) {
  gShutdownCalls += 1;
  if (gShutdownSnapshotState == nullptr) {
    return;
  }

  gShutdownSnapshotState->initialized = miumNativeCEFTestIsInitialized();
  gShutdownSnapshotState->shutdownExecuting = miumNativeCEFTestIsShutdownExecuting();
  gShutdownSnapshotState->frameworkLoaded = miumNativeCEFIsLoaded();
}

inline void captureProcessExitCode(int exitCode) {
  gProcessExitCallbackCode = exitCode;
}

inline int fakeInitialize(const cef_main_args_t* args, const cef_settings_t* settings, cef_app_t* application, void*) {
  if (gInitializeCapture == nullptr || settings == nullptr) {
    return 0;
  }

  gInitializeCapture->callCount += 1;
  gInitializeCapture->lastArgc = args == nullptr ? 0 : args->argc;
  gInitializeCapture->argv.clear();
  if (args != nullptr && args->argv != nullptr) {
    for (int index = 0; index < args->argc; ++index) {
      const char* value = args->argv[index];
      gInitializeCapture->argv.push_back(value == nullptr ? std::string() : std::string(value));
    }
  }
  gInitializeCapture->browserSubprocessPath = stringFromCEFString(&settings->browser_subprocess_path);
  gInitializeCapture->resourcesDirPath = stringFromCEFString(&settings->resources_dir_path);
  gInitializeCapture->localesDirPath = stringFromCEFString(&settings->locales_dir_path);
  gInitializeCapture->cachePath = stringFromCEFString(&settings->cache_path);
  gInitializeCapture->rootCachePath = stringFromCEFString(&settings->root_cache_path);
  gInitializeCapture->locale = stringFromCEFString(&settings->locale);
  gInitializeCapture->acceptLanguageList = stringFromCEFString(&settings->accept_language_list);
  gInitializeCapture->noSandbox = settings->no_sandbox;
  gInitializeCapture->logSeverity = settings->log_severity;
  gInitializeCapture->multiThreadedMessageLoop = settings->multi_threaded_message_loop;
  gInitializeCapture->externalMessagePump = settings->external_message_pump;
  gInitializeCapture->persistSessionCookies = settings->persist_session_cookies;
  gInitializeCapture->lastHadApplication = application != nullptr;
  captureAppHandlerConfiguration(
    application,
    &gInitializeCapture->lastAppHasBrowserProcessHandler,
    &gInitializeCapture->lastAppHasScheduleMessagePumpWork,
    &gInitializeCapture->lastAppHasRenderProcessHandler,
    &gInitializeCapture->lastAppHasProcessMessageReceivedHandler
  );
  return gInitializeCapture->returnValue;
}

struct BlockingInitializeState {
  std::mutex mutex;
  std::condition_variable enteredCondition;
  std::condition_variable releaseCondition;
  int returnValue = 1;
  int callCount = 0;
  bool entered = false;
  bool released = false;
};

inline int blockingFakeInitialize(const cef_main_args_t*, const cef_settings_t*, cef_app_t*, void*) {
  auto* state = gBlockingInitializeState;
  if (state == nullptr) {
    return 0;
  }

  std::unique_lock<std::mutex> lock(state->mutex);
  state->callCount += 1;
  state->entered = true;
  state->enteredCondition.notify_all();
  state->releaseCondition.wait(lock, [&] {
    return state->released;
  });
  return state->returnValue;
}

inline int slowFakeInitialize(const cef_main_args_t*, const cef_settings_t*, cef_app_t*, void*) {
  auto* state = gBlockingInitializeState;
  if (state != nullptr) {
    std::lock_guard<std::mutex> lock(state->mutex);
    state->callCount += 1;
  }
  usleep(200000);
  return 1;
}

inline int failingUTF8ToUTF16(const char*, size_t, cef_string_t*) {
  return 0;
}

struct FakeProcessMessageState;

struct FakeListValueState {
  cef_list_value_t list{};
  FakeRefCountedLifetime lifetime{};
  std::vector<std::string> values;
};

struct FakeStringListState {
  std::vector<std::string> values;
  bool failValueLookup = false;
};

struct FakeBrowserState;
struct FakeFrameState;

struct FakeBrowserHostState {
  cef_browser_host_t host{};
  FakeRefCountedLifetime lifetime{};
  FakeBrowserState* owner = nullptr;
  int closeBrowserCalls = 0;
  int notifyMoveOrResizeStartedCalls = 0;
  int wasResizedCalls = 0;
  bool invalidatesOwnerOnClose = true;
};

enum class FakeV8ValueKind : uint8_t {
  undefined = 0,
  nullValue = 1,
  boolValue = 2,
  intValue = 3,
  uintValue = 4,
  doubleValue = 5,
  stringValue = 6,
  objectValue = 7,
  functionValue = 8,
};

struct FakeV8ValueState {
  cef_v8_value_t value{};
  FakeRefCountedLifetime lifetime{};
  FakeV8ValueKind kind = FakeV8ValueKind::undefined;
  bool boolValue = false;
  int32_t intValue = 0;
  uint32_t uintValue = 0;
  double doubleValue = 0;
  std::string stringValue;
  std::string functionName;
  cef_v8_handler_t* functionHandler = nullptr;
  std::unordered_map<std::string, cef_v8_value_t*> keyedValues;
};

struct FakeV8ExceptionState {
  cef_v8_exception_t exception{};
  FakeRefCountedLifetime lifetime{};
  std::string message;
};

struct FakeV8ContextState {
  cef_v8_context_t context{};
  FakeRefCountedLifetime lifetime{};
  FakeBrowserState* browser = nullptr;
  FakeFrameState* frame = nullptr;
  FakeV8ValueState* globalObject = nullptr;
  bool isValid = true;
  bool enterResult = true;
  bool nextEvalSucceeds = true;
  int enterCalls = 0;
  int exitCalls = 0;
  std::string lastEvaluatedScript;
  FakeV8ValueState* evalResult = nullptr;
  FakeV8ExceptionState* evalException = nullptr;
};

struct FakeFrameState {
  cef_frame_t frame{};
  FakeRefCountedLifetime lifetime{};
  std::string identifier = "frame-identifier";
  std::string currentURL = "https://navigator.test";
  std::string lastLoadedURL;
  std::string lastExecutedScript;
  int sendProcessMessageCalls = 0;
  int lastProcessId = -1;
  FakeProcessMessageState* lastMessage = nullptr;
  int isMainResult = 1;
  FakeV8ContextState* v8Context = nullptr;
};

struct FakeBrowserState {
  cef_browser_t browser{};
  FakeRefCountedLifetime lifetime{};
  FakeBrowserHostState* host = nullptr;
  FakeFrameState* frame = nullptr;
  int goBackCalls = 0;
  int goForwardCalls = 0;
  int reloadCalls = 0;
  int stopLoadCalls = 0;
  int canGoBackResult = 0;
  int canGoForwardResult = 0;
  int isLoadingResult = 0;
  int identifier = 1337;
  bool isValid = true;
};

struct FakeBrowserHarnessBacking {
  std::unique_ptr<FakeBrowserState> browser = std::make_unique<FakeBrowserState>();
  std::unique_ptr<FakeBrowserHostState> host = std::make_unique<FakeBrowserHostState>();
  std::unique_ptr<FakeFrameState> frame = std::make_unique<FakeFrameState>();
  std::unique_ptr<FakeV8ContextState> v8Context = std::make_unique<FakeV8ContextState>();
  std::unique_ptr<FakeV8ValueState> globalV8Value = std::make_unique<FakeV8ValueState>();
  std::unique_ptr<FakeV8ValueState> v8Value = std::make_unique<FakeV8ValueState>();
  std::unique_ptr<FakeV8ExceptionState> v8Exception = std::make_unique<FakeV8ExceptionState>();
};

struct FakeProcessMessageState {
  cef_process_message_t message{};
  FakeRefCountedLifetime lifetime{};
  std::string name;
  FakeListValueState arguments{};
};

inline void initializeRefCountedBase(cef_base_ref_counted_t& base, size_t size) {
  std::memset(&base, 0, sizeof(base));
  base.size = size;
}

inline int CEF_CALLBACK fakeBrowserIsValid(cef_browser_t* self) {
  auto* state = reinterpret_cast<FakeBrowserState*>(self);
  return (state != nullptr && state->isValid) ? 1 : 0;
}

inline cef_browser_host_t* CEF_CALLBACK fakeBrowserGetHost(cef_browser_t* self) {
  auto* state = reinterpret_cast<FakeBrowserState*>(self);
  if (state == nullptr || state->host == nullptr) {
    return nullptr;
  }
  fakeAddRef<FakeBrowserHostState>(&state->host->host.base);
  return &state->host->host;
}

inline int CEF_CALLBACK fakeBrowserCanGoBack(cef_browser_t* self) {
  auto* state = reinterpret_cast<FakeBrowserState*>(self);
  return state == nullptr ? 0 : state->canGoBackResult;
}

inline void CEF_CALLBACK fakeBrowserGoBack(cef_browser_t* self) {
  auto* state = reinterpret_cast<FakeBrowserState*>(self);
  if (state != nullptr) {
    state->goBackCalls += 1;
  }
}

inline int CEF_CALLBACK fakeBrowserCanGoForward(cef_browser_t* self) {
  auto* state = reinterpret_cast<FakeBrowserState*>(self);
  return state == nullptr ? 0 : state->canGoForwardResult;
}

inline void CEF_CALLBACK fakeBrowserGoForward(cef_browser_t* self) {
  auto* state = reinterpret_cast<FakeBrowserState*>(self);
  if (state != nullptr) {
    state->goForwardCalls += 1;
  }
}

inline int CEF_CALLBACK fakeBrowserIsLoading(cef_browser_t* self) {
  auto* state = reinterpret_cast<FakeBrowserState*>(self);
  return state == nullptr ? 0 : state->isLoadingResult;
}

inline void CEF_CALLBACK fakeBrowserReload(cef_browser_t* self) {
  auto* state = reinterpret_cast<FakeBrowserState*>(self);
  if (state != nullptr) {
    state->reloadCalls += 1;
  }
}

inline void CEF_CALLBACK fakeBrowserStopLoad(cef_browser_t* self) {
  auto* state = reinterpret_cast<FakeBrowserState*>(self);
  if (state != nullptr) {
    state->stopLoadCalls += 1;
  }
}

inline int CEF_CALLBACK fakeBrowserGetIdentifier(cef_browser_t* self) {
  auto* state = reinterpret_cast<FakeBrowserState*>(self);
  return state == nullptr ? 0 : state->identifier;
}

inline cef_frame_t* CEF_CALLBACK fakeBrowserGetMainFrame(cef_browser_t* self) {
  auto* state = reinterpret_cast<FakeBrowserState*>(self);
  if (state == nullptr || state->frame == nullptr) {
    return nullptr;
  }
  fakeAddRef<FakeFrameState>(&state->frame->frame.base);
  return &state->frame->frame;
}

inline void CEF_CALLBACK fakeHostCloseBrowser(cef_browser_host_t* self, int) {
  auto* state = reinterpret_cast<FakeBrowserHostState*>(self);
  if (state == nullptr) {
    return;
  }
  state->closeBrowserCalls += 1;
  if (state->invalidatesOwnerOnClose && state->owner != nullptr) {
    state->owner->isValid = false;
  }
}

inline void CEF_CALLBACK fakeHostNotifyMoveOrResizeStarted(cef_browser_host_t* self) {
  auto* state = reinterpret_cast<FakeBrowserHostState*>(self);
  if (state != nullptr) {
    state->notifyMoveOrResizeStartedCalls += 1;
  }
}

inline void CEF_CALLBACK fakeHostWasResized(cef_browser_host_t* self) {
  auto* state = reinterpret_cast<FakeBrowserHostState*>(self);
  if (state != nullptr) {
    state->wasResizedCalls += 1;
  }
}

inline void CEF_CALLBACK fakeFrameLoadURL(cef_frame_t* self, const cef_string_t* url) {
  auto* state = reinterpret_cast<FakeFrameState*>(self);
  if (state != nullptr) {
    state->lastLoadedURL = stringFromCEFString(url);
    state->currentURL = state->lastLoadedURL;
  }
}

inline void CEF_CALLBACK fakeFrameExecuteJavaScript(
  cef_frame_t* self,
  const cef_string_t* code,
  const cef_string_t*,
  int
) {
  auto* state = reinterpret_cast<FakeFrameState*>(self);
  if (state != nullptr) {
    state->lastExecutedScript = stringFromCEFString(code);
  }
}

inline int CEF_CALLBACK fakeFrameIsMain(cef_frame_t* self) {
  auto* state = reinterpret_cast<FakeFrameState*>(self);
  return state == nullptr ? 0 : state->isMainResult;
}

inline cef_string_userfree_t fakeUserFreeString(const std::string& value) {
  auto* output = static_cast<cef_string_userfree_t>(std::calloc(1, sizeof(cef_string_t)));
  if (output == nullptr) {
    return nullptr;
  }
  if (!value.empty()) {
    fakeUTF8ToUTF16(value.c_str(), value.size(), output);
  }
  return output;
}

inline cef_string_userfree_t CEF_CALLBACK fakeFrameGetIdentifier(cef_frame_t* self) {
  auto* state = reinterpret_cast<FakeFrameState*>(self);
  return state == nullptr ? nullptr : fakeUserFreeString(state->identifier);
}

inline cef_string_userfree_t CEF_CALLBACK fakeFrameGetURL(cef_frame_t* self) {
  auto* state = reinterpret_cast<FakeFrameState*>(self);
  return state == nullptr ? nullptr : fakeUserFreeString(state->currentURL);
}

inline int CEF_CALLBACK fakeV8ContextIsValid(cef_v8_context_t* self) {
  auto* state = reinterpret_cast<FakeV8ContextState*>(self);
  return state != nullptr && state->isValid ? 1 : 0;
}

inline cef_browser_t* CEF_CALLBACK fakeV8ContextGetBrowser(cef_v8_context_t* self) {
  auto* state = reinterpret_cast<FakeV8ContextState*>(self);
  return state == nullptr || state->browser == nullptr ? nullptr : &state->browser->browser;
}

inline cef_frame_t* CEF_CALLBACK fakeV8ContextGetFrame(cef_v8_context_t* self) {
  auto* state = reinterpret_cast<FakeV8ContextState*>(self);
  if (state == nullptr || state->frame == nullptr) {
    return nullptr;
  }
  fakeAddRef<FakeFrameState>(&state->frame->frame.base);
  return &state->frame->frame;
}

inline cef_v8_value_t* CEF_CALLBACK fakeV8ContextGetGlobal(cef_v8_context_t* self) {
  auto* state = reinterpret_cast<FakeV8ContextState*>(self);
  if (state == nullptr || state->globalObject == nullptr) {
    return nullptr;
  }
  fakeAddRef<FakeV8ValueState>(&state->globalObject->value.base);
  return &state->globalObject->value;
}

inline int CEF_CALLBACK fakeV8ContextEnter(cef_v8_context_t* self) {
  auto* state = reinterpret_cast<FakeV8ContextState*>(self);
  if (state == nullptr) {
    return 0;
  }
  state->enterCalls += 1;
  return state->enterResult ? 1 : 0;
}

inline int CEF_CALLBACK fakeV8ContextExit(cef_v8_context_t* self) {
  auto* state = reinterpret_cast<FakeV8ContextState*>(self);
  if (state == nullptr) {
    return 0;
  }
  state->exitCalls += 1;
  return 1;
}

inline int CEF_CALLBACK fakeV8ValueIsValid(cef_v8_value_t*) {
  return 1;
}

inline int CEF_CALLBACK fakeV8ValueIsUndefined(cef_v8_value_t* self) {
  auto* state = reinterpret_cast<FakeV8ValueState*>(self);
  return state != nullptr && state->kind == FakeV8ValueKind::undefined ? 1 : 0;
}

inline int CEF_CALLBACK fakeV8ValueIsNull(cef_v8_value_t* self) {
  auto* state = reinterpret_cast<FakeV8ValueState*>(self);
  return state != nullptr && state->kind == FakeV8ValueKind::nullValue ? 1 : 0;
}

inline int CEF_CALLBACK fakeV8ValueIsBool(cef_v8_value_t* self) {
  auto* state = reinterpret_cast<FakeV8ValueState*>(self);
  return state != nullptr && state->kind == FakeV8ValueKind::boolValue ? 1 : 0;
}

inline int CEF_CALLBACK fakeV8ValueIsInt(cef_v8_value_t* self) {
  auto* state = reinterpret_cast<FakeV8ValueState*>(self);
  return state != nullptr && state->kind == FakeV8ValueKind::intValue ? 1 : 0;
}

inline int CEF_CALLBACK fakeV8ValueIsUInt(cef_v8_value_t* self) {
  auto* state = reinterpret_cast<FakeV8ValueState*>(self);
  return state != nullptr && state->kind == FakeV8ValueKind::uintValue ? 1 : 0;
}

inline int CEF_CALLBACK fakeV8ValueIsDouble(cef_v8_value_t* self) {
  auto* state = reinterpret_cast<FakeV8ValueState*>(self);
  return state != nullptr && state->kind == FakeV8ValueKind::doubleValue ? 1 : 0;
}

inline int CEF_CALLBACK fakeV8ValueIsString(cef_v8_value_t* self) {
  auto* state = reinterpret_cast<FakeV8ValueState*>(self);
  return state != nullptr && state->kind == FakeV8ValueKind::stringValue ? 1 : 0;
}

inline int CEF_CALLBACK fakeV8ValueGetBoolValue(cef_v8_value_t* self) {
  auto* state = reinterpret_cast<FakeV8ValueState*>(self);
  return state != nullptr && state->boolValue ? 1 : 0;
}

inline int32_t CEF_CALLBACK fakeV8ValueGetIntValue(cef_v8_value_t* self) {
  auto* state = reinterpret_cast<FakeV8ValueState*>(self);
  return state == nullptr ? 0 : state->intValue;
}

inline uint32_t CEF_CALLBACK fakeV8ValueGetUIntValue(cef_v8_value_t* self) {
  auto* state = reinterpret_cast<FakeV8ValueState*>(self);
  return state == nullptr ? 0 : state->uintValue;
}

inline double CEF_CALLBACK fakeV8ValueGetDoubleValue(cef_v8_value_t* self) {
  auto* state = reinterpret_cast<FakeV8ValueState*>(self);
  return state == nullptr ? 0.0 : state->doubleValue;
}

inline cef_string_userfree_t CEF_CALLBACK fakeV8ValueGetStringValue(cef_v8_value_t* self) {
  auto* state = reinterpret_cast<FakeV8ValueState*>(self);
  return state == nullptr ? nullptr : fakeUserFreeString(state->stringValue);
}

inline cef_v8_value_t* CEF_CALLBACK fakeV8ValueGetValueByKey(cef_v8_value_t* self, const cef_string_t* key) {
  auto* state = reinterpret_cast<FakeV8ValueState*>(self);
  if (state == nullptr || state->kind != FakeV8ValueKind::objectValue) {
    return nullptr;
  }
  const auto iterator = state->keyedValues.find(stringFromCEFString(key));
  if (iterator == state->keyedValues.end() || iterator->second == nullptr) {
    return nullptr;
  }
  auto* valueState = reinterpret_cast<FakeV8ValueState*>(iterator->second);
  fakeAddRef<FakeV8ValueState>(&valueState->value.base);
  return iterator->second;
}

inline int CEF_CALLBACK fakeV8ValueSetValueByKey(
  cef_v8_value_t* self,
  const cef_string_t* key,
  cef_v8_value_t* value,
  cef_v8_propertyattribute_t
) {
  auto* state = reinterpret_cast<FakeV8ValueState*>(self);
  if (state == nullptr || state->kind != FakeV8ValueKind::objectValue) {
    return 0;
  }
  const std::string propertyName = stringFromCEFString(key);
  if (const auto existing = state->keyedValues.find(propertyName);
      existing != state->keyedValues.end() && existing->second != nullptr) {
    fakeRelease<FakeV8ValueState>(&reinterpret_cast<FakeV8ValueState*>(existing->second)->value.base);
  }
  if (value != nullptr) {
    fakeAddRef<FakeV8ValueState>(&reinterpret_cast<FakeV8ValueState*>(value)->value.base);
  }
  state->keyedValues[propertyName] = value;
  return 1;
}

inline cef_v8_value_t* CEF_CALLBACK fakeV8ValueExecuteFunction(
  cef_v8_value_t* self,
  cef_v8_value_t* object,
  size_t argumentsCount,
  cef_v8_value_t* const* arguments
) {
  auto* state = reinterpret_cast<FakeV8ValueState*>(self);
  if (state == nullptr || state->kind != FakeV8ValueKind::functionValue || state->functionHandler == nullptr) {
    return nullptr;
  }
  cef_v8_value_t* retval = nullptr;
  cef_string_t exception{};
  cef_string_t name{};
  fakeUTF8ToUTF16(state->functionName.c_str(), state->functionName.size(), &name);
  const int handled = state->functionHandler->execute(
    state->functionHandler,
    &name,
    object,
    argumentsCount,
    arguments,
    &retval,
    &exception
  );
  fakeUTF16Clear(&name);
  fakeUTF16Clear(&exception);
  return handled != 0 ? retval : nullptr;
}

inline cef_string_userfree_t CEF_CALLBACK fakeV8ExceptionGetMessage(cef_v8_exception_t* self) {
  auto* state = reinterpret_cast<FakeV8ExceptionState*>(self);
  return state == nullptr ? nullptr : fakeUserFreeString(state->message);
}

inline cef_v8_value_t* fakeCreateV8Function(
  const cef_string_t* name,
  cef_v8_handler_t* handler
) {
  auto* state = new FakeV8ValueState();
  std::memset(&state->value, 0, sizeof(state->value));
  initializeRefCountedBase(state->value.base, sizeof(state->value));
  state->value.base.add_ref = fakeAddRef<FakeV8ValueState>;
  state->value.base.release = fakeRelease<FakeV8ValueState>;
  state->value.base.has_one_ref = fakeHasOneRef<FakeV8ValueState>;
  state->value.base.has_at_least_one_ref = fakeHasAtLeastOneRef<FakeV8ValueState>;
  state->value.is_valid = fakeV8ValueIsValid;
  state->value.is_undefined = fakeV8ValueIsUndefined;
  state->value.is_null = fakeV8ValueIsNull;
  state->value.is_bool = fakeV8ValueIsBool;
  state->value.is_int = fakeV8ValueIsInt;
  state->value.is_uint = fakeV8ValueIsUInt;
  state->value.is_double = fakeV8ValueIsDouble;
  state->value.is_string = fakeV8ValueIsString;
  state->value.get_bool_value = fakeV8ValueGetBoolValue;
  state->value.get_int_value = fakeV8ValueGetIntValue;
  state->value.get_uint_value = fakeV8ValueGetUIntValue;
  state->value.get_double_value = fakeV8ValueGetDoubleValue;
  state->value.get_string_value = fakeV8ValueGetStringValue;
  state->value.get_value_bykey = fakeV8ValueGetValueByKey;
  state->value.set_value_bykey = fakeV8ValueSetValueByKey;
  state->value.execute_function = fakeV8ValueExecuteFunction;
  state->kind = FakeV8ValueKind::functionValue;
  state->functionName = stringFromCEFString(name);
  state->functionHandler = handler;
  if (handler != nullptr && handler->base.add_ref != nullptr) {
    handler->base.add_ref(&handler->base);
  }
  state->lifetime.onFinalRelease = [state]() {
    if (state->functionHandler != nullptr && state->functionHandler->base.release != nullptr) {
      state->functionHandler->base.release(&state->functionHandler->base);
    }
    delete state;
  };
  return &state->value;
}

inline cef_v8_context_t* fakeCurrentV8Context(void) {
  if (gCurrentV8Context != nullptr) {
    fakeAddRef<FakeV8ContextState>(&reinterpret_cast<FakeV8ContextState*>(gCurrentV8Context)->context.base);
  }
  return gCurrentV8Context;
}

inline int CEF_CALLBACK fakeV8ContextEval(
  cef_v8_context_t* self,
  const cef_string_t* code,
  const cef_string_t*,
  int,
  cef_v8_value_t** retval,
  cef_v8_exception_t** exception
) {
  auto* state = reinterpret_cast<FakeV8ContextState*>(self);
  if (retval != nullptr) {
    *retval = nullptr;
  }
  if (exception != nullptr) {
    *exception = nullptr;
  }
  if (state == nullptr) {
    return 0;
  }
  state->lastEvaluatedScript = stringFromCEFString(code);
  if (state->nextEvalSucceeds) {
    if (retval != nullptr && state->evalResult != nullptr) {
      fakeAddRef<FakeV8ValueState>(&state->evalResult->value.base);
      *retval = &state->evalResult->value;
    }
    return 1;
  }

  if (exception != nullptr && state->evalException != nullptr) {
    fakeAddRef<FakeV8ExceptionState>(&state->evalException->exception.base);
    *exception = &state->evalException->exception;
  }
  return 0;
}

inline cef_v8_context_t* CEF_CALLBACK fakeFrameGetV8Context(cef_frame_t* self) {
  auto* state = reinterpret_cast<FakeFrameState*>(self);
  if (state == nullptr || state->v8Context == nullptr) {
    return nullptr;
  }
  fakeAddRef<FakeV8ContextState>(&state->v8Context->context.base);
  return &state->v8Context->context;
}

inline void CEF_CALLBACK fakeFrameSendProcessMessage(
  cef_frame_t* self,
  cef_process_id_t targetProcess,
  cef_process_message_t* message
) {
  auto* state = reinterpret_cast<FakeFrameState*>(self);
  if (state == nullptr) {
    return;
  }
  state->sendProcessMessageCalls += 1;
  state->lastProcessId = static_cast<int>(targetProcess);
  state->lastMessage = reinterpret_cast<FakeProcessMessageState*>(message);
}

inline int CEF_CALLBACK fakeListSetSize(cef_list_value_t* self, size_t size) {
  auto* state = reinterpret_cast<FakeListValueState*>(self);
  if (state == nullptr) {
    return 0;
  }
  state->values.resize(size);
  return 1;
}

inline int CEF_CALLBACK fakeListSetString(cef_list_value_t* self, size_t index, const cef_string_t* value) {
  auto* state = reinterpret_cast<FakeListValueState*>(self);
  if (state == nullptr || index >= state->values.size()) {
    return 0;
  }
  state->values[index] = stringFromCEFString(value);
  return 1;
}

inline cef_list_value_t* CEF_CALLBACK fakeMessageGetArgumentList(cef_process_message_t* self) {
  auto* state = reinterpret_cast<FakeProcessMessageState*>(self);
  return state == nullptr ? nullptr : &state->arguments.list;
}

inline size_t fakeStringListSize(cef_string_list_t list) {
  const auto* state = reinterpret_cast<const FakeStringListState*>(list);
  return state == nullptr ? 0 : state->values.size();
}

inline int fakeStringListValue(cef_string_list_t list, size_t index, cef_string_t* value) {
  const auto* state = reinterpret_cast<const FakeStringListState*>(list);
  if (state == nullptr || value == nullptr || state->failValueLookup || index >= state->values.size()) {
    return 0;
  }
  const std::string& entry = state->values[index];
  return fakeUTF8ToUTF16(entry.c_str(), entry.size(), value);
}

struct FakeBrowserHarness {
  std::shared_ptr<FakeBrowserHarnessBacking> backing = std::make_shared<FakeBrowserHarnessBacking>();
  FakeBrowserState* browser = nullptr;
  FakeBrowserHostState* host = nullptr;
  FakeFrameState* frame = nullptr;

  FakeBrowserHarness() {
    browser = backing->browser.get();
    host = backing->host.get();
    frame = backing->frame.get();
    auto* v8Context = backing->v8Context.get();
    auto* globalV8Value = backing->globalV8Value.get();
    auto* v8Value = backing->v8Value.get();
    auto* v8Exception = backing->v8Exception.get();
    retainedFakeBrowserHarnesses().push_back(backing);

    std::memset(&browser->browser, 0, sizeof(browser->browser));
    std::memset(&host->host, 0, sizeof(host->host));
    std::memset(&frame->frame, 0, sizeof(frame->frame));
    std::memset(&v8Context->context, 0, sizeof(v8Context->context));
    std::memset(&globalV8Value->value, 0, sizeof(globalV8Value->value));
    std::memset(&v8Value->value, 0, sizeof(v8Value->value));
    std::memset(&v8Exception->exception, 0, sizeof(v8Exception->exception));

    initializeRefCountedBase(browser->browser.base, sizeof(browser->browser));
    browser->browser.base.add_ref = fakeAddRef<FakeBrowserState>;
    browser->browser.base.release = fakeRelease<FakeBrowserState>;
    browser->browser.base.has_one_ref = fakeHasOneRef<FakeBrowserState>;
    browser->browser.base.has_at_least_one_ref = fakeHasAtLeastOneRef<FakeBrowserState>;
    browser->browser.is_valid = fakeBrowserIsValid;
    browser->browser.get_host = fakeBrowserGetHost;
    browser->browser.can_go_back = fakeBrowserCanGoBack;
    browser->browser.go_back = fakeBrowserGoBack;
    browser->browser.can_go_forward = fakeBrowserCanGoForward;
    browser->browser.go_forward = fakeBrowserGoForward;
    browser->browser.is_loading = fakeBrowserIsLoading;
    browser->browser.reload = fakeBrowserReload;
    browser->browser.stop_load = fakeBrowserStopLoad;
    browser->browser.get_identifier = fakeBrowserGetIdentifier;
    browser->browser.get_main_frame = fakeBrowserGetMainFrame;

    initializeRefCountedBase(host->host.base, sizeof(host->host));
    host->host.base.add_ref = fakeAddRef<FakeBrowserHostState>;
    host->host.base.release = fakeRelease<FakeBrowserHostState>;
    host->host.base.has_one_ref = fakeHasOneRef<FakeBrowserHostState>;
    host->host.base.has_at_least_one_ref = fakeHasAtLeastOneRef<FakeBrowserHostState>;
    host->host.close_browser = fakeHostCloseBrowser;
    host->host.notify_move_or_resize_started = fakeHostNotifyMoveOrResizeStarted;
    host->host.was_resized = fakeHostWasResized;

    initializeRefCountedBase(frame->frame.base, sizeof(frame->frame));
    frame->frame.base.add_ref = fakeAddRef<FakeFrameState>;
    frame->frame.base.release = fakeRelease<FakeFrameState>;
    frame->frame.base.has_one_ref = fakeHasOneRef<FakeFrameState>;
    frame->frame.base.has_at_least_one_ref = fakeHasAtLeastOneRef<FakeFrameState>;
    frame->frame.load_url = fakeFrameLoadURL;
    frame->frame.execute_java_script = fakeFrameExecuteJavaScript;
    frame->frame.send_process_message = fakeFrameSendProcessMessage;
    frame->frame.is_main = fakeFrameIsMain;
    frame->frame.get_identifier = fakeFrameGetIdentifier;
    frame->frame.get_url = fakeFrameGetURL;
    frame->frame.get_v8_context = fakeFrameGetV8Context;

    initializeRefCountedBase(v8Context->context.base, sizeof(v8Context->context));
    v8Context->context.base.add_ref = fakeAddRef<FakeV8ContextState>;
    v8Context->context.base.release = fakeRelease<FakeV8ContextState>;
    v8Context->context.base.has_one_ref = fakeHasOneRef<FakeV8ContextState>;
    v8Context->context.base.has_at_least_one_ref = fakeHasAtLeastOneRef<FakeV8ContextState>;
    v8Context->context.is_valid = fakeV8ContextIsValid;
    v8Context->context.get_browser = fakeV8ContextGetBrowser;
    v8Context->context.get_frame = fakeV8ContextGetFrame;
    v8Context->context.get_global = fakeV8ContextGetGlobal;
    v8Context->context.enter = fakeV8ContextEnter;
    v8Context->context.exit = fakeV8ContextExit;
    v8Context->context.eval = fakeV8ContextEval;

    initializeRefCountedBase(globalV8Value->value.base, sizeof(globalV8Value->value));
    globalV8Value->value.base.add_ref = fakeAddRef<FakeV8ValueState>;
    globalV8Value->value.base.release = fakeRelease<FakeV8ValueState>;
    globalV8Value->value.base.has_one_ref = fakeHasOneRef<FakeV8ValueState>;
    globalV8Value->value.base.has_at_least_one_ref = fakeHasAtLeastOneRef<FakeV8ValueState>;
    globalV8Value->value.is_valid = fakeV8ValueIsValid;
    globalV8Value->value.is_undefined = fakeV8ValueIsUndefined;
    globalV8Value->value.is_null = fakeV8ValueIsNull;
    globalV8Value->value.is_bool = fakeV8ValueIsBool;
    globalV8Value->value.is_int = fakeV8ValueIsInt;
    globalV8Value->value.is_uint = fakeV8ValueIsUInt;
    globalV8Value->value.is_double = fakeV8ValueIsDouble;
    globalV8Value->value.is_string = fakeV8ValueIsString;
    globalV8Value->value.get_bool_value = fakeV8ValueGetBoolValue;
    globalV8Value->value.get_int_value = fakeV8ValueGetIntValue;
    globalV8Value->value.get_uint_value = fakeV8ValueGetUIntValue;
    globalV8Value->value.get_double_value = fakeV8ValueGetDoubleValue;
    globalV8Value->value.get_string_value = fakeV8ValueGetStringValue;
    globalV8Value->value.get_value_bykey = fakeV8ValueGetValueByKey;
    globalV8Value->value.set_value_bykey = fakeV8ValueSetValueByKey;
    globalV8Value->kind = FakeV8ValueKind::objectValue;

    initializeRefCountedBase(v8Value->value.base, sizeof(v8Value->value));
    v8Value->value.base.add_ref = fakeAddRef<FakeV8ValueState>;
    v8Value->value.base.release = fakeRelease<FakeV8ValueState>;
    v8Value->value.base.has_one_ref = fakeHasOneRef<FakeV8ValueState>;
    v8Value->value.base.has_at_least_one_ref = fakeHasAtLeastOneRef<FakeV8ValueState>;
    v8Value->value.is_valid = fakeV8ValueIsValid;
    v8Value->value.is_undefined = fakeV8ValueIsUndefined;
    v8Value->value.is_null = fakeV8ValueIsNull;
    v8Value->value.is_bool = fakeV8ValueIsBool;
    v8Value->value.is_int = fakeV8ValueIsInt;
    v8Value->value.is_uint = fakeV8ValueIsUInt;
    v8Value->value.is_double = fakeV8ValueIsDouble;
    v8Value->value.is_string = fakeV8ValueIsString;
    v8Value->value.get_bool_value = fakeV8ValueGetBoolValue;
    v8Value->value.get_int_value = fakeV8ValueGetIntValue;
    v8Value->value.get_uint_value = fakeV8ValueGetUIntValue;
    v8Value->value.get_double_value = fakeV8ValueGetDoubleValue;
    v8Value->value.get_string_value = fakeV8ValueGetStringValue;
    v8Value->kind = FakeV8ValueKind::stringValue;
    v8Value->stringValue = "renderer-result";

    initializeRefCountedBase(v8Exception->exception.base, sizeof(v8Exception->exception));
    v8Exception->exception.base.add_ref = fakeAddRef<FakeV8ExceptionState>;
    v8Exception->exception.base.release = fakeRelease<FakeV8ExceptionState>;
    v8Exception->exception.base.has_one_ref = fakeHasOneRef<FakeV8ExceptionState>;
    v8Exception->exception.base.has_at_least_one_ref = fakeHasAtLeastOneRef<FakeV8ExceptionState>;
    v8Exception->exception.get_message = fakeV8ExceptionGetMessage;
    v8Exception->message = "Renderer evaluation failed";

    browser->host = host;
    browser->frame = frame;
    host->owner = browser;
    v8Context->browser = browser;
    v8Context->frame = frame;
    v8Context->globalObject = globalV8Value;
    v8Context->evalResult = v8Value;
    v8Context->evalException = v8Exception;
    frame->v8Context = v8Context;
  }

  cef_browser_t* browserRef() const {
    return const_cast<cef_browser_t*>(&browser->browser);
  }

  static std::vector<std::shared_ptr<FakeBrowserHarnessBacking>>& retainedFakeBrowserHarnesses() {
    static std::vector<std::shared_ptr<FakeBrowserHarnessBacking>> retainedHarnesses;
    return retainedHarnesses;
  }

  static void resetRetainedHarnesses() {
    retainedFakeBrowserHarnesses().clear();
  }
};

struct FakeProcessMessageFactory {
  std::vector<std::unique_ptr<FakeProcessMessageState>> messages;
  std::string lastCreatedName;
};

inline FakeProcessMessageFactory* gProcessMessageFactory = nullptr;

inline cef_process_message_t* fakeCreateProcessMessage(const cef_string_t* name) {
  if (gProcessMessageFactory == nullptr) {
    return nullptr;
  }

  auto message = std::make_unique<FakeProcessMessageState>();
  std::memset(&message->message, 0, sizeof(message->message));
  std::memset(&message->arguments.list, 0, sizeof(message->arguments.list));

  initializeRefCountedBase(message->message.base, sizeof(message->message));
  message->message.base.add_ref = fakeAddRef<FakeProcessMessageState>;
  message->message.base.release = fakeRelease<FakeProcessMessageState>;
  message->message.base.has_one_ref = fakeHasOneRef<FakeProcessMessageState>;
  message->message.base.has_at_least_one_ref = fakeHasAtLeastOneRef<FakeProcessMessageState>;
  message->message.is_valid = [](cef_process_message_t*) { return 1; };
  message->message.is_read_only = [](cef_process_message_t*) { return 0; };
  message->message.get_argument_list = fakeMessageGetArgumentList;
  message->name = stringFromCEFString(name);

  initializeRefCountedBase(message->arguments.list.base, sizeof(message->arguments.list));
  message->arguments.list.base.add_ref = fakeAddRef<FakeListValueState>;
  message->arguments.list.base.release = fakeRelease<FakeListValueState>;
  message->arguments.list.base.has_one_ref = fakeHasOneRef<FakeListValueState>;
  message->arguments.list.base.has_at_least_one_ref = fakeHasAtLeastOneRef<FakeListValueState>;
  message->arguments.list.is_valid = [](cef_list_value_t*) { return 1; };
  message->arguments.list.is_owned = [](cef_list_value_t*) { return 0; };
  message->arguments.list.is_read_only = [](cef_list_value_t*) { return 0; };
  message->arguments.list.set_size = fakeListSetSize;
  message->arguments.list.set_string = fakeListSetString;

  auto* rawMessage = message.get();
  gProcessMessageFactory->lastCreatedName = rawMessage->name;
  gProcessMessageFactory->messages.push_back(std::move(message));
  return &rawMessage->message;
}

inline cef_process_message_t* fakeCreateNullProcessMessage(const cef_string_t*) {
  return nullptr;
}

inline cef_process_message_t* fakeCreateProcessMessageWithoutArguments(const cef_string_t* name) {
  if (gProcessMessageFactory == nullptr) {
    return nullptr;
  }

  auto message = std::make_unique<FakeProcessMessageState>();
  std::memset(&message->message, 0, sizeof(message->message));
  initializeRefCountedBase(message->message.base, sizeof(message->message));
  message->message.base.add_ref = fakeAddRef<FakeProcessMessageState>;
  message->message.base.release = fakeRelease<FakeProcessMessageState>;
  message->message.base.has_one_ref = fakeHasOneRef<FakeProcessMessageState>;
  message->message.base.has_at_least_one_ref = fakeHasAtLeastOneRef<FakeProcessMessageState>;
  message->message.is_valid = [](cef_process_message_t*) { return 1; };
  message->message.is_read_only = [](cef_process_message_t*) { return 0; };
  message->message.get_argument_list = nullptr;
  message->name = stringFromCEFString(name);

  auto* rawMessage = message.get();
  gProcessMessageFactory->lastCreatedName = rawMessage->name;
  gProcessMessageFactory->messages.push_back(std::move(message));
  return &rawMessage->message;
}

struct FakeCreateBrowserFactory {
  std::vector<std::unique_ptr<FakeBrowserHarness>> createdBrowsers;
  int callCount = 0;
  void* lastParentView = nullptr;
  int lastWidth = 0;
  int lastHeight = 0;
  std::string lastURL;
  std::function<void()> onCreate;
};

inline FakeCreateBrowserFactory* gCreateBrowserFactory = nullptr;

inline cef_browser_t* fakeCreateBrowserSync(
  const cef_window_info_t* windowInfo,
  cef_client_t*,
  const cef_string_t* url,
  const cef_browser_settings_t*,
  cef_dictionary_value_t*,
  cef_request_context_t*
) {
  if (gCreateBrowserFactory == nullptr) {
    return nullptr;
  }

  auto browser = std::make_unique<FakeBrowserHarness>();
  auto* rawBrowser = browser->browserRef();

  gCreateBrowserFactory->callCount += 1;
  gCreateBrowserFactory->lastParentView = windowInfo == nullptr ? nullptr : windowInfo->parent_view;
  gCreateBrowserFactory->lastWidth = windowInfo == nullptr ? 0 : windowInfo->bounds.width;
  gCreateBrowserFactory->lastHeight = windowInfo == nullptr ? 0 : windowInfo->bounds.height;
  gCreateBrowserFactory->lastURL = stringFromCEFString(url);
  gCreateBrowserFactory->createdBrowsers.push_back(std::move(browser));
  if (gCreateBrowserFactory->onCreate) {
    gCreateBrowserFactory->onCreate();
  }
  return rawBrowser;
}

struct CallbackProbe {
  XCTestExpectation* expectation = nil;
  MiumCEFResultCode code = UINT32_MAX;
  std::string message;
  void* callbackContext = nullptr;
  int invocationCount = 0;
};

struct RecordingProbe {
  std::mutex mutex;
  XCTestExpectation* expectation = nil;
  std::vector<std::string> messages;
};

struct BridgeMessageProbe {
  XCTestExpectation* expectation = nil;
  std::vector<std::string> messages;
};

struct BridgeJavaScriptProbe {
  XCTestExpectation* expectation = nil;
  std::string result;
  std::string error;
  int invocationCount = 0;
};

struct FakeMediaAccessCallbackState {
  cef_media_access_callback_t callback{};
  FakeRefCountedLifetime lifetime{};
  int continueCalls = 0;
  int cancelCalls = 0;
  uint32_t lastAllowedPermissions = 0;
};

inline void CEF_CALLBACK fakeMediaAccessCallbackContinue(
  cef_media_access_callback_t* self,
  uint32_t allowedPermissions
) {
  auto* state = reinterpret_cast<FakeMediaAccessCallbackState*>(self);
  if (state == nullptr) {
    return;
  }
  state->continueCalls += 1;
  state->lastAllowedPermissions = allowedPermissions;
}

inline void CEF_CALLBACK fakeMediaAccessCallbackCancel(cef_media_access_callback_t* self) {
  auto* state = reinterpret_cast<FakeMediaAccessCallbackState*>(self);
  if (state == nullptr) {
    return;
  }
  state->cancelCalls += 1;
}

struct FakeMediaAccessCallbackHarness {
  std::shared_ptr<FakeMediaAccessCallbackState> state = std::make_shared<FakeMediaAccessCallbackState>();

  FakeMediaAccessCallbackHarness() {
    retainedHarnesses().push_back(state);
    std::memset(&state->callback, 0, sizeof(state->callback));
    initializeRefCountedBase(state->callback.base, sizeof(state->callback));
    state->callback.base.add_ref = fakeAddRef<FakeMediaAccessCallbackState>;
    state->callback.base.release = fakeRelease<FakeMediaAccessCallbackState>;
    state->callback.base.has_one_ref = fakeHasOneRef<FakeMediaAccessCallbackState>;
    state->callback.base.has_at_least_one_ref = fakeHasAtLeastOneRef<FakeMediaAccessCallbackState>;
    state->callback.cont = fakeMediaAccessCallbackContinue;
    state->callback.cancel = fakeMediaAccessCallbackCancel;
  }

  cef_media_access_callback_t* callbackRef() const {
    return const_cast<cef_media_access_callback_t*>(&state->callback);
  }

  static std::vector<std::shared_ptr<FakeMediaAccessCallbackState>>& retainedHarnesses() {
    static std::vector<std::shared_ptr<FakeMediaAccessCallbackState>> retained;
    return retained;
  }

  static void resetRetainedHarnesses() {
    retainedHarnesses().clear();
  }
};

struct FakePermissionPromptCallbackState {
  cef_permission_prompt_callback_t callback{};
  FakeRefCountedLifetime lifetime{};
  int continueCalls = 0;
  cef_permission_request_result_t lastResult = CEF_PERMISSION_RESULT_IGNORE;
};

inline void CEF_CALLBACK fakePermissionPromptCallbackContinue(
  cef_permission_prompt_callback_t* self,
  cef_permission_request_result_t result
) {
  auto* state = reinterpret_cast<FakePermissionPromptCallbackState*>(self);
  if (state == nullptr) {
    return;
  }
  state->continueCalls += 1;
  state->lastResult = result;
}

struct FakePermissionPromptCallbackHarness {
  std::shared_ptr<FakePermissionPromptCallbackState> state =
    std::make_shared<FakePermissionPromptCallbackState>();

  FakePermissionPromptCallbackHarness() {
    retainedHarnesses().push_back(state);
    std::memset(&state->callback, 0, sizeof(state->callback));
    initializeRefCountedBase(state->callback.base, sizeof(state->callback));
    state->callback.base.add_ref = fakeAddRef<FakePermissionPromptCallbackState>;
    state->callback.base.release = fakeRelease<FakePermissionPromptCallbackState>;
    state->callback.base.has_one_ref = fakeHasOneRef<FakePermissionPromptCallbackState>;
    state->callback.base.has_at_least_one_ref = fakeHasAtLeastOneRef<FakePermissionPromptCallbackState>;
    state->callback.cont = fakePermissionPromptCallbackContinue;
  }

  cef_permission_prompt_callback_t* callbackRef() const {
    return const_cast<cef_permission_prompt_callback_t*>(&state->callback);
  }

  static std::vector<std::shared_ptr<FakePermissionPromptCallbackState>>& retainedHarnesses() {
    static std::vector<std::shared_ptr<FakePermissionPromptCallbackState>> retained;
    return retained;
  }

  static void resetRetainedHarnesses() {
    retainedHarnesses().clear();
  }
};

struct ReentrantBridgeMessageContext {
  MiumCEFBrowserHandle browserHandle = nullptr;
  MiumCEFRuntimeHandle runtimeHandle = nullptr;
  CEFBridgeBrowserRef browserRef = nullptr;
  XCTestExpectation* messageExpectation = nil;
  CallbackProbe loadProbe;
  CallbackProbe scriptProbe;
  MiumCEFResultCode loadResult = MiumCEFResultError;
  MiumCEFResultCode scriptResult = MiumCEFResultError;
  MiumCEFResultCode resizeResult = MiumCEFResultError;
  MiumCEFResultCode destroyResult = MiumCEFResultError;
  MiumCEFResultCode shutdownResult = MiumCEFResultError;
  std::vector<std::string> messages;
  int invocationCount = 0;
};

struct SelfRemovingBridgeMessageContext {
  CEFBridgeBrowserRef browserRef = nullptr;
  XCTestExpectation* expectation = nil;
  std::vector<std::string> messages;
  int invocationCount = 0;
};

struct ReentrantCompletionContext {
  MiumCEFBrowserHandle browserHandle = nullptr;
  XCTestExpectation* expectation = nil;
  MiumCEFResultCode code = MiumCEFResultError;
  MiumCEFResultCode reloadResult = MiumCEFResultError;
  MiumCEFResultCode stopLoadResult = MiumCEFResultError;
  std::string message;
  int invocationCount = 0;
};

struct CoordinatedDestroyBridgeMessageContext {
  MiumCEFBrowserHandle browserHandle = nullptr;
  XCTestExpectation* startedExpectation = nil;
  XCTestExpectation* finishedExpectation = nil;
  dispatch_semaphore_t continueSemaphore = nullptr;
  std::vector<std::string> messages;
  MiumCEFResultCode destroyResult = MiumCEFResultError;
  int invocationCount = 0;
};

struct ExecutorCoverageContext {
  MiumCEFBrowserHandle browserHandle = nullptr;
  CallbackProbe* loadProbe = nullptr;
  CallbackProbe* scriptProbe = nullptr;
  CallbackProbe* sendProbe = nullptr;
  MiumCEFResultCode goBackResult = MiumCEFResultError;
  MiumCEFResultCode goForwardResult = MiumCEFResultError;
  MiumCEFResultCode reloadResult = MiumCEFResultError;
  MiumCEFResultCode stopLoadResult = MiumCEFResultError;
  MiumCEFResultCode resizeResult = MiumCEFResultError;
  MiumCEFResultCode loadURLResult = MiumCEFResultError;
  MiumCEFResultCode evaluateResult = MiumCEFResultError;
  MiumCEFResultCode sendResult = MiumCEFResultError;
  int canGoBack = 0;
  int canGoForward = 0;
  int isLoading = 0;
};

struct MaybeRunSubprocessContext {
  int argc = 0;
  const char* const* argv = nullptr;
  int result = INT32_MIN;
};

struct MessageLoopWorkContext {
  MiumCEFResultCode result = MiumCEFResultError;
};

struct ShutdownContext {
  MiumCEFRuntimeHandle runtimeHandle = nullptr;
  MiumCEFResultCode result = MiumCEFResultError;
};

struct SnapshotRequestContext {
  MiumCEFBrowserHandle browserHandle = nullptr;
  const char* outputPath = nullptr;
  const char* jsonOptions = nullptr;
  CallbackProbe* probe = nullptr;
  MiumCEFResultCode result = MiumCEFResultError;
};

inline void testNativeCallback(MiumCEFResultCode code, const char* message, void* context) {
  auto* probe = static_cast<CallbackProbe*>(context);
  if (probe == nullptr) {
    return;
  }
  probe->code = code;
  probe->message = message == nullptr ? std::string() : std::string(message);
  probe->callbackContext = context;
  probe->invocationCount += 1;
  if (probe->expectation != nil) {
    [probe->expectation fulfill];
  }
}

inline void recordingNativeCallback(MiumCEFResultCode, const char* message, void* context) {
  auto* probe = static_cast<RecordingProbe*>(context);
  if (probe == nullptr) {
    return;
  }

  {
    std::lock_guard<std::mutex> lock(probe->mutex);
    probe->messages.push_back(message == nullptr ? std::string() : std::string(message));
  }

  if (probe->expectation != nil) {
    [probe->expectation fulfill];
  }
}

inline void bridgeMessageCallback(void* userData, const char* message) {
  auto* probe = static_cast<BridgeMessageProbe*>(userData);
  if (probe == nullptr) {
    return;
  }
  probe->messages.push_back(message == nullptr ? std::string() : std::string(message));
  if (probe->expectation != nil) {
    [probe->expectation fulfill];
  }
}

inline void bridgeJavaScriptCallback(void* userData, const char* result, const char* error) {
  auto* probe = static_cast<BridgeJavaScriptProbe*>(userData);
  if (probe == nullptr) {
    return;
  }
  probe->result = result == nullptr ? std::string() : std::string(result);
  probe->error = error == nullptr ? std::string() : std::string(error);
  probe->invocationCount += 1;
  if (probe->expectation != nil) {
    [probe->expectation fulfill];
  }
}

inline void reentrantBridgeLoadEvalResizeCallback(void* userData, const char* message) {
  auto* context = static_cast<ReentrantBridgeMessageContext*>(userData);
  if (context == nullptr) {
    return;
  }

  context->messages.push_back(message == nullptr ? std::string() : std::string(message));
  context->invocationCount += 1;
  context->loadResult = miumNativeCEFLoadURL(
    context->browserHandle,
    "https://reentrant.load",
    &context->loadProbe,
    testNativeCallback
  );
  context->scriptResult = miumNativeCEFEvaluateJavaScript(
    context->browserHandle,
    "window.reentrant()",
    &context->scriptProbe,
    testNativeCallback
  );
  context->resizeResult = miumNativeCEFResizeBrowser(context->browserHandle, 210, 130);
  if (context->messageExpectation != nil) {
    [context->messageExpectation fulfill];
  }
}

inline void selfRemovingBridgeMessageCallback(void* userData, const char* message) {
  auto* context = static_cast<SelfRemovingBridgeMessageContext*>(userData);
  if (context == nullptr) {
    return;
  }

  context->messages.push_back(message == nullptr ? std::string() : std::string(message));
  context->invocationCount += 1;
  CEFBridge_SetMessageHandler(context->browserRef, nullptr, nullptr);
  if (context->expectation != nil) {
    [context->expectation fulfill];
  }
}

inline void destroyBrowserFromBridgeMessageCallback(void* userData, const char* message) {
  auto* context = static_cast<ReentrantBridgeMessageContext*>(userData);
  if (context == nullptr) {
    return;
  }

  context->messages.push_back(message == nullptr ? std::string() : std::string(message));
  context->invocationCount += 1;
  context->destroyResult = miumNativeCEFDestroyBrowser(context->browserHandle);
  if (context->messageExpectation != nil) {
    [context->messageExpectation fulfill];
  }
}

inline void shutdownRuntimeFromBridgeMessageCallback(void* userData, const char* message) {
  auto* context = static_cast<ReentrantBridgeMessageContext*>(userData);
  if (context == nullptr) {
    return;
  }

  context->messages.push_back(message == nullptr ? std::string() : std::string(message));
  context->invocationCount += 1;
  context->shutdownResult = miumNativeCEFShutdown(context->runtimeHandle);
  if (context->messageExpectation != nil) {
    [context->messageExpectation fulfill];
  }
}

inline void reentrantLoadCompletionCallback(MiumCEFResultCode code, const char* message, void* userData) {
  auto* context = static_cast<ReentrantCompletionContext*>(userData);
  if (context == nullptr) {
    return;
  }

  context->code = code;
  context->message = message == nullptr ? std::string() : std::string(message);
  context->invocationCount += 1;
  context->reloadResult = miumNativeCEFReload(context->browserHandle);
  context->stopLoadResult = miumNativeCEFStopLoad(context->browserHandle);
  if (context->expectation != nil) {
    [context->expectation fulfill];
  }
}

inline void coordinatedDestroyBridgeMessageCallback(void* userData, const char* message) {
  auto* context = static_cast<CoordinatedDestroyBridgeMessageContext*>(userData);
  if (context == nullptr) {
    return;
  }

  context->messages.push_back(message == nullptr ? std::string() : std::string(message));
  context->invocationCount += 1;
  if (context->invocationCount != 1) {
    return;
  }

  if (context->startedExpectation != nil) {
    [context->startedExpectation fulfill];
  }
  if (context->continueSemaphore != nullptr) {
    dispatch_semaphore_wait(
      context->continueSemaphore,
      dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(kCallbackTimeout * NSEC_PER_SEC))
    );
  }
  context->destroyResult = miumNativeCEFDestroyBrowser(context->browserHandle);
  if (context->finishedExpectation != nil) {
    [context->finishedExpectation fulfill];
  }
}

inline void runExecutorCoverageActions(void* context) {
  auto* coverage = static_cast<ExecutorCoverageContext*>(context);
  if (coverage == nullptr) {
    return;
  }

  coverage->goBackResult = miumNativeCEFGoBack(coverage->browserHandle);
  coverage->goForwardResult = miumNativeCEFGoForward(coverage->browserHandle);
  coverage->reloadResult = miumNativeCEFReload(coverage->browserHandle);
  coverage->stopLoadResult = miumNativeCEFStopLoad(coverage->browserHandle);
  coverage->canGoBack = miumNativeCEFCanGoBack(coverage->browserHandle);
  coverage->canGoForward = miumNativeCEFCanGoForward(coverage->browserHandle);
  coverage->isLoading = miumNativeCEFIsLoading(coverage->browserHandle);
  coverage->resizeResult = miumNativeCEFResizeBrowser(coverage->browserHandle, 200, 120);
  coverage->loadURLResult = miumNativeCEFLoadURL(
    coverage->browserHandle,
    "https://executor.example",
    coverage->loadProbe,
    testNativeCallback
  );
  coverage->evaluateResult = miumNativeCEFEvaluateJavaScript(
    coverage->browserHandle,
    "window.executor()",
    coverage->scriptProbe,
    testNativeCallback
  );
  coverage->sendResult = miumNativeCEFSendMessage(
    coverage->browserHandle,
    "bridge",
    "{\"executor\":true}",
    coverage->sendProbe,
    testNativeCallback
  );
}

inline void runMaybeRunSubprocess(void* context) {
  auto* invocation = static_cast<MaybeRunSubprocessContext*>(context);
  if (invocation == nullptr) {
    return;
  }
  invocation->result = miumNativeCEFMaybeRunSubprocess(invocation->argc, invocation->argv);
}

inline void runMessageLoopWork(void* context) {
  auto* invocation = static_cast<MessageLoopWorkContext*>(context);
  if (invocation == nullptr) {
    return;
  }
  invocation->result = miumNativeCEFDoMessageLoopWork();
}

inline void runShutdown(void* context) {
  auto* invocation = static_cast<ShutdownContext*>(context);
  if (invocation == nullptr) {
    return;
  }
  invocation->result = miumNativeCEFShutdown(invocation->runtimeHandle);
}

inline void runSnapshotRequest(void* context) {
  auto* invocation = static_cast<SnapshotRequestContext*>(context);
  if (invocation == nullptr) {
    return;
  }
  invocation->result = miumNativeCEFRequestSnapshot(
    invocation->browserHandle,
    invocation->outputPath,
    invocation->jsonOptions,
    invocation->probe,
    testNativeCallback
  );
}

inline void incrementIntegerCallback(void* context) {
  auto* value = static_cast<int*>(context);
  if (value != nullptr) {
    *value += 1;
  }
}

inline void runNestedExecutorIncrement(void* context) {
  miumNativeCEFTestRunOnCefExecutor(context, incrementIntegerCallback);
}

inline void runNestedExecutorAsyncIncrement(void* context) {
  miumNativeCEFTestRunOnCefExecutorAsync(context, incrementIntegerCallback);
}

inline void runExecutorThenMainThreadIncrement(void* context) {
  miumNativeCEFTestRunOnMainThread(context, incrementIntegerCallback);
}

inline NSString* stringFromCString(const char* value) {
  return value == nullptr ? @"" : [NSString stringWithUTF8String:value];
}

inline void clearBridgeEnvironmentOverrides() {
  unsetenv("MIUM_CEF_ROOT_CACHE_PATH");
  unsetenv("MIUM_CEF_BROWSER_SUBPROCESS_PATH");
}

using IntGetterFn = int (*)();
using CStringGetterFn = const char* (*)();

struct FakeCefLibrary {
  NSString* runtimeRoot = nil;
  NSString* metadataPath = nil;
  NSString* frameworkPath = nil;
  void* handle = nullptr;
};

struct MiumCEFBridgeNativeTestFixture {
  void resetGlobals() const {
    gExecuteProcessCalls = 0;
    gExecuteProcessLastArgc = 0;
    gExecuteProcessReturnCode = -1;
    gExecuteProcessLastHadApplication = false;
    gExecuteProcessLastAppHasBrowserProcessHandler = false;
    gExecuteProcessLastAppHasScheduleMessagePumpWork = false;
    gExecuteProcessLastAppHasRenderProcessHandler = false;
    gExecuteProcessLastAppHasProcessMessageReceivedHandler = false;
    gProcessExitCallbackCode = -1;
    gMessageLoopWorkCalls = 0;
    gShutdownCalls = 0;
    gUTF8ConversionFailureNeedle.clear();
    gUTF8ConversionFailureCallIndex = -1;
    gUTF8ConversionCallCount = 0;
    gBlockingInitializeState = nullptr;
    gInitializeCapture = nullptr;
    gProcessMessageFactory = nullptr;
    gCreateBrowserFactory = nullptr;
    gShutdownSnapshotState = nullptr;
  }
};

} // namespace MiumCEFBridgeNativeTestSupport

NS_ASSUME_NONNULL_BEGIN

@interface TestSnapshotView : NSView

@property(nonatomic, strong, nullable) NSData* forcedPDFData;
@property(nonatomic, assign) BOOL returnsNilPDFData;
@property(nonatomic, assign) BOOL returnsNilBitmapRep;
@property(nonatomic, assign) BOOL usesFailingBitmapRep;

@end

@interface FailingBitmapImageRep : NSBitmapImageRep
@end

@interface MiumCEFBridgeNativeTestCase : XCTestCase
@end

@interface MiumCEFBridgeNativeTestCase () {
@private
  MiumCEFBridgeNativeTestSupport::MiumCEFBridgeNativeTestFixture _fixture;
  std::vector<void*> _openedLibraryHandles;
  int _suiteLockFD;
}
- (void)acquireSuiteLock;
- (void)releaseSuiteLock;
- (void)drainPendingAsyncWork;
- (void)waitForMainQueueToDrain;
- (void)waitForMessageQueueToDrain;
- (void* _Nullable)openTrackedLibraryAtPath:(NSString*)path;
- (void)closeTrackedLibraries;
- (void)setUp;
- (void)tearDown;
- (MiumCEFRuntimeHandle _Nonnull)seedRuntime;
- (MiumCEFBrowserHandle _Nonnull)createBrowserForRuntime:(MiumCEFRuntimeHandle _Nonnull)runtimeHandle;
- (NSString*)temporaryDirectory;
- (void)installBasicAPI;
- (void)runOnBackgroundQueueAndWait:(dispatch_block_t _Nonnull)block;
- (void)runOnBackgroundQueueAndDrain:(dispatch_block_t _Nonnull)block;
- (void)waitUntil:(BOOL (NS_NOESCAPE ^ _Nonnull)(void))condition description:(NSString*)description;
- (void)writeString:(NSString*)string toPath:(NSString*)path;
- (void)createFileAtPath:(NSString*)path executable:(BOOL)executable;
- (void)createLocalesAtDirectory:(NSString*)resourcesDirectory;
- (void)createHelperAppNamed:(NSString*)bundleName
              executableName:(NSString*)executableName
              infoExecutable:(NSString* _Nullable)infoExecutable
                 inDirectory:(NSString*)helpersDirectory;
- (NSString*)fakeCEFRuntimeSource;
- (NSString*)compileFakeCEFRuntimeAtPath:(NSString*)binaryPath defines:(NSArray<NSString*>* _Nonnull)defines;
- (NSDictionary<NSString*, NSString*>*)createFakeRuntimeWithDefines:(NSArray<NSString*>* _Nonnull)defines;
- (NSArray<NSString*>*)logLinesAtPath:(NSString*)path;
- (NSString*)packageRoot;
- (void)createDirectoryAtPath:(NSString*)path;
- (void)writeText:(NSString*)text toPath:(NSString*)path;
- (void)writeBinaryData:(NSData*)data toPath:(NSString*)path;
- (NSString*)createHelperAppInDirectory:(NSString*)helpersDir
                                   name:(NSString*)name
                         executableName:(NSString*)executableName
                    infoPlistExecutable:(NSString* _Nullable)infoPlistExecutable;
- (MiumCEFBridgeNativeTestSupport::FakeCefLibrary)buildFakeCefLibraryVariant:(NSString*)variant;
- (void* _Nullable)symbolNamed:(const char* _Nonnull)name inHandle:(void* _Nullable)handle;
@end

NS_ASSUME_NONNULL_END

#pragma clang diagnostic pop
