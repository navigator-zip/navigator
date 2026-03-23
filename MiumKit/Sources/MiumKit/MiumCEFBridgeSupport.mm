#import <Foundation/Foundation.h>

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <string>
#include <vector>

#include "CefRef.h"
#include "CefThreadGate.h"
#include "MiumCEFBridgeAuxiliaryState.h"
#include "MiumCEFBridgeBrowserEvents.h"
#include "MiumCEFBridgeInternalAdapters.h"
#include "MiumCEFBridgeInternalRuntimeBootstrapSupport.h"
#include "MiumCEFBridgeInternalRuntimeExecutionSupport.h"
#include "MiumCEFBridgeInternalState.h"
#include "MiumCEFBridgePaths.h"
#include "MiumCEFBridgeRuntime.h"
#include "MiumCEFBridgeShutdown.h"
#include "MiumCEFBridgeThreading.h"
#include "Tracing.h"

namespace {

static constexpr const char* kMiumCEFExternalMessagePumpEnvironmentKey = "MIUM_CEF_ENABLE_EXTERNAL_MESSAGE_PUMP";
static constexpr double kRendererJavaScriptRequestTimeoutSeconds = 1.0;

static bool shouldEmitBootstrapDiagnostics() {
#if defined(MIUM_CEF_BRIDGE_TESTING)
  return miumCefTracingEnabled();
#else
  return true;
#endif
}

static void bootstrapDiagnostic(const char* format, ...) {
  if (!shouldEmitBootstrapDiagnostics()) {
    return;
  }
  va_list args;
  va_start(args, format);
  vfprintf(stderr, format, args);
  va_end(args);
}

static void bootstrapTrace(const char* format, ...) {
  if (!miumCefTracingEnabled()) {
    return;
  }
  va_list args;
  va_start(args, format);
  miumCefTraceV("support", format, args);
  va_end(args);
}

static bool bridgeExternalMessagePumpEnabled() {
  const char* rawValue = getenv(kMiumCEFExternalMessagePumpEnvironmentKey);
  if (rawValue == nullptr || rawValue[0] == '\0') {
    return true;
  }

  std::string value(rawValue);
  for (char& ch : value) {
    ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
  }

  if (
    value == "0" ||
    value == "false" ||
    value == "no" ||
    value == "off" ||
    value == "disabled"
  ) {
    return false;
  }

  return true;
}

struct CefStringAPISnapshot {
  CefStringUTF8ToUTF16 utf8ToUTF16 = nullptr;
  CefStringUTF16Clear utf16Clear = nullptr;
  CefStringUserFreeUTF16Free userfreeFree = nullptr;
  CefStringListSizeFn stringListSize = nullptr;
  CefStringListValueFn stringListValue = nullptr;
};

static CefStringAPISnapshot snapshotStringAPI(bool requireInitialized) {
  CefStateLockGuard lock;
  if (requireInitialized && !gCEFInitialized) {
    return {};
  }
  CefStringAPISnapshot api;
  api.utf8ToUTF16 = gCefApi.utf8ToUTF16;
  api.utf16Clear = gCefApi.utf16Clear;
  api.userfreeFree = gCefApi.userfreeFree;
  api.stringListSize = gCefApi.stringListSize;
  api.stringListValue = gCefApi.stringListValue;
  return api;
}

static void runOnCefMainThread(std::function<void()> fn) {
  miumCEFRunOnCefMainThread(std::move(fn));
}

static bool performCefMessageLoopWork(const char* reason) {
  CefDoMessageLoopWorkFn doMessageLoopWork = nullptr;
  uint64_t sequenceNumber = 0;
  CFAbsoluteTime now = 0.0;
  CFAbsoluteTime elapsedSinceLastPump = 0.0;

  {
    CefStateLockGuard lock;
    if (!miumCEFIsCefRuntimeUsableLocked()) {
      return false;
    }
    doMessageLoopWork = gCefApi.doMessageLoopWork;
    if (doMessageLoopWork == nullptr) {
      return false;
    }
    now = CFAbsoluteTimeGetCurrent();
    elapsedSinceLastPump =
      gLastPerformedMessagePumpTime <= 0.0 ? 0.0 : (now - gLastPerformedMessagePumpTime) * 1000.0;
    gLastPerformedMessagePumpTime = now;
    gLastPerformedMessagePumpSequence += 1;
    sequenceNumber = gLastPerformedMessagePumpSequence;
  }

  bootstrapTrace(
    "cef_do_message_loop_work lane=%s reason=%s sequence=%llu elapsed_ms=%.2f\n",
    miumCEFThreadLaneLabel(),
    reason == nullptr ? "unknown" : reason,
    static_cast<unsigned long long>(sequenceNumber),
    elapsedSinceLastPump
  );
  doMessageLoopWork();
  return true;
}

static void cancelExternalMessagePumpWork() {
  CefStateLockGuard lock;
  gActiveExternalMessagePumpScheduleId = ++gNextExternalMessagePumpScheduleId;
}

static void scheduleExternalMessagePumpWork(int64_t delayMS) {
  uint64_t scheduleId = 0;
  int64_t normalizedDelayMS = std::max<int64_t>(0, delayMS);
  {
    CefStateLockGuard lock;
    if (!gExternalMessagePumpEnabled || !miumCEFIsCefRuntimeUsableLocked()) {
      return;
    }
    scheduleId = ++gNextExternalMessagePumpScheduleId;
    gActiveExternalMessagePumpScheduleId = scheduleId;
  }

  const auto scheduleBlock = ^{
    bool shouldRun = false;
    {
      CefStateLockGuard lock;
      shouldRun =
        gExternalMessagePumpEnabled &&
        miumCEFIsCefRuntimeUsableLocked() &&
        gActiveExternalMessagePumpScheduleId == scheduleId;
    }
    if (!shouldRun) {
      return;
    }
    runOnCefMainThread([=] {
      bool stillCurrent = false;
      {
        CefStateLockGuard lock;
        stillCurrent =
          gExternalMessagePumpEnabled &&
          miumCEFIsCefRuntimeUsableLocked() &&
          gActiveExternalMessagePumpScheduleId == scheduleId;
      }
      if (!stillCurrent) {
        return;
      }
      (void)performCefMessageLoopWork("external_message_pump");
    });
  };

  bootstrapTrace(
    "schedule external message pump delay_ms=%lld schedule_id=%llu\n",
    static_cast<long long>(normalizedDelayMS),
    static_cast<unsigned long long>(scheduleId)
  );
  if (normalizedDelayMS <= 0) {
    miumCefDispatchAsyncOnMainThread(scheduleBlock);
    return;
  }

  miumCefDispatchAfterOnMainThread(
    dispatch_time(DISPATCH_TIME_NOW, normalizedDelayMS * NSEC_PER_MSEC),
    scheduleBlock
  );
}

static void clearUTF16String(cef_string_t& value) {
  if (value.str != nullptr && value.dtor != nullptr) {
    value.dtor(value.str);
  }
  value.str = nullptr;
  value.length = 0;
  value.dtor = nullptr;
}

static bool utf16FromUTF8(const char* input, cef_string_t& output, std::string* errorOut = nullptr) {
  output.str = nullptr;
  output.length = 0;
  output.dtor = nullptr;

  const CefStringUTF8ToUTF16 utf8ToUTF16 = snapshotStringAPI(/*requireInitialized=*/false).utf8ToUTF16;
  if (utf8ToUTF16 == nullptr) {
    if (errorOut != nullptr) {
      *errorOut = "CEF UTF8->UTF16 API unavailable";
    }
    return false;
  }

  if (input == nullptr || input[0] == '\0') {
    return true;
  }

  const int result = utf8ToUTF16(input, std::strlen(input), &output);
  if (result == 0) {
    clearUTF16String(output);
    if (errorOut != nullptr) {
      *errorOut = "Failed to convert UTF8 to UTF16";
    }
    return false;
  }

  return true;
}

static bool setCefSettingPath(cef_string_t& output, const std::string& value, std::string* errorOut = nullptr) {
  output.str = nullptr;
  output.length = 0;
  output.dtor = nullptr;
  if (value.empty()) {
    return true;
  }
  return utf16FromUTF8(value.c_str(), output, errorOut);
}

static std::string stringFromV8Value(cef_v8_value_t* value) {
  if (value == nullptr) {
    return {};
  }
  if (value->is_string != nullptr && value->is_string(value) != 0 && value->get_string_value != nullptr) {
    return stringFromCEFUserFreeString(value->get_string_value(value));
  }
  if (value->is_bool != nullptr && value->is_bool(value) != 0 && value->get_bool_value != nullptr) {
    return value->get_bool_value(value) != 0 ? "true" : "false";
  }
  if (value->is_int != nullptr && value->is_int(value) != 0 && value->get_int_value != nullptr) {
    return std::to_string(value->get_int_value(value));
  }
  if (value->is_uint != nullptr && value->is_uint(value) != 0 && value->get_uint_value != nullptr) {
    return std::to_string(value->get_uint_value(value));
  }
  if (value->is_double != nullptr && value->is_double(value) != 0 && value->get_double_value != nullptr) {
    const double number = value->get_double_value(value);
    if (std::isfinite(number) && std::floor(number) == number) {
      return std::to_string(static_cast<long long>(number));
    }
    char buffer[64];
    std::snprintf(buffer, sizeof(buffer), "%.17g", number);
    return buffer;
  }
  if (value->is_null != nullptr && value->is_null(value) != 0) {
    return "null";
  }
  if (value->is_undefined != nullptr && value->is_undefined(value) != 0) {
    return {};
  }
  return {};
}

static std::string stringFromV8Exception(cef_v8_exception_t* exception) {
  if (exception == nullptr || exception->get_message == nullptr) {
    return {};
  }
  return stringFromCEFUserFreeString(exception->get_message(exception));
}

static bool evaluateRendererJavaScript(
  cef_frame_t* frame,
  const char* script,
  std::string* resultOut,
  std::string* errorOut
) {
  if (resultOut != nullptr) {
    resultOut->clear();
  }
  if (errorOut != nullptr) {
    errorOut->clear();
  }

  if (frame == nullptr) {
    if (errorOut != nullptr) {
      *errorOut = "Renderer frame is unavailable";
    }
    return true;
  }
  if (frame->is_main == nullptr || frame->is_main(frame) == 0) {
    if (errorOut != nullptr) {
      *errorOut = "Renderer frame is not the main frame";
    }
    return true;
  }
  if (frame->get_v8_context == nullptr) {
    if (errorOut != nullptr) {
      *errorOut = "Renderer V8 context is unavailable";
    }
    return true;
  }

  cef_v8_context_t* context = frame->get_v8_context(frame);
  if (context == nullptr) {
    if (errorOut != nullptr) {
      *errorOut = "Renderer V8 context is unavailable";
    }
    return true;
  }
  const bool isContextValid = context->is_valid == nullptr || context->is_valid(context) != 0;
  if (!isContextValid || context->enter == nullptr || context->exit == nullptr || context->eval == nullptr) {
    releaseCefBase(&context->base);
    if (errorOut != nullptr) {
      *errorOut = "Renderer V8 context is unavailable";
    }
    return true;
  }

  cef_string_t scriptUTF16{};
  std::string conversionError;
  if (!utf16FromUTF8(script == nullptr ? "" : script, scriptUTF16, &conversionError)) {
    releaseCefBase(&context->base);
    if (errorOut != nullptr) {
      *errorOut = conversionError;
    }
    return true;
  }

  if (context->enter(context) == 0) {
    clearUTF16String(scriptUTF16);
    releaseCefBase(&context->base);
    if (errorOut != nullptr) {
      *errorOut = "Renderer V8 context enter failed";
    }
    return true;
  }

  cef_v8_value_t* resultValue = nullptr;
  cef_v8_exception_t* exception = nullptr;
  const int evaluationSucceeded = context->eval(
    context,
    &scriptUTF16,
    nullptr,
    1,
    &resultValue,
    &exception
  );
  context->exit(context);
  clearUTF16String(scriptUTF16);

  std::string resultString;
  std::string errorString;
  if (evaluationSucceeded != 0) {
    resultString = stringFromV8Value(resultValue);
  } else {
    errorString = stringFromV8Exception(exception);
    if (errorString.empty()) {
      errorString = "Renderer JavaScript evaluation failed";
    }
  }

  if (resultValue != nullptr) {
    releaseCefBase(&resultValue->base);
  }
  if (exception != nullptr) {
    releaseCefBase(&exception->base);
  }
  releaseCefBase(&context->base);

  if (resultOut != nullptr) {
    *resultOut = resultString;
  }
  if (errorOut != nullptr) {
    *errorOut = errorString;
  }
  return true;
}

static std::vector<std::string> frameworkFallbackCandidates() {
#if defined(MIUM_CEF_BRIDGE_TESTING)
  if (!gTestFrameworkFallbackCandidates.empty()) {
    return gTestFrameworkFallbackCandidates;
  }
#endif
  return {
    "Chromium Embedded Framework",
    "@rpath/Chromium Embedded Framework"
  };
}

static bool interceptProcessExitCodeIfTesting(int exitCode) {
#if defined(MIUM_CEF_BRIDGE_TESTING)
  if (gTestInterceptProcessExit) {
    gTestInterceptedProcessExitCode = exitCode;
    return true;
  }
#endif
  (void)exitCode;
  return false;
}

static void terminateProcessAfterCEFExecuteProcess(int exitCode) {
#if defined(MIUM_CEF_BRIDGE_TESTING)
  if (gTestProcessExitCallback != nullptr) {
    gTestProcessExitCallback(exitCode);
  }
  return;
#else
  std::_Exit(exitCode);
#endif
}

static bool isDevelopmentEligibleForMediaStreamOverride() {
#if defined(MIUM_CEF_BRIDGE_TESTING)
  if (gTestMediaStreamOverrideDevelopmentEligibility >= 0) {
    return gTestMediaStreamOverrideDevelopmentEligibility != 0;
  }
#endif
#if DEBUG
  return true;
#else
  return false;
#endif
}

static bool shouldEnableMediaStreamOverride() {
  return isDevelopmentEligibleForMediaStreamOverride()
    && parseBooleanEnvironmentFlag("MIUM_CEF_ENABLE_MEDIA_STREAM");
}

static bool verifyCefApiCompatibility(const char* runtimeHash, const char* expectedHash) {
  if (runtimeHash == nullptr) {
    bootstrapDiagnostic("CEF ABI check failed: runtime cef_api_hash(CEF_API_VERSION, 0) returned null\n");
    return false;
  }
  if (expectedHash == nullptr) {
    bootstrapDiagnostic("CEF ABI check failed: compiled CEF API hash macro is null\n");
    return false;
  }

  if (std::strcmp(runtimeHash, expectedHash) != 0) {
    bootstrapDiagnostic(
      "CEF ABI mismatch: runtime cef_api_hash(CEF_API_VERSION, 0)=%s, expected=%s, CEF_API_VERSION=%d\n",
      runtimeHash,
      expectedHash,
      static_cast<int>(CEF_API_VERSION)
    );
    return false;
  }

  bootstrapTrace("CEF API hash (platform): %s\n", runtimeHash);
  return true;
}

static bool loadSymbol(void* handle, const char* symbolName, void** destination) {
  if (handle == nullptr || symbolName == nullptr || destination == nullptr) {
    return false;
  }

  dlerror();
  void* value = dlsym(handle, symbolName);
  const char* error = dlerror();
  if (value == nullptr) {
    bootstrapDiagnostic("CEF symbol load failed: %s (%s)\n", symbolName, error ? error : "dlsym returned nil");
    return false;
  }

  *destination = value;
  return true;
}

} // namespace

bool miumCEFNativeShouldEnableMediaStreamOverride(void) {
  return shouldEnableMediaStreamOverride();
}

bool miumCEFNativeBridgeLoggingEnabled(void) {
  return miumCefTracingEnabled();
}

bool miumCEFNativeBridgeExternalMessagePumpEnabled(void) {
  return bridgeExternalMessagePumpEnabled();
}

void miumCEFNativeScheduleExternalMessagePumpWork(int64_t delayMS) {
  scheduleExternalMessagePumpWork(delayMS);
}

bool miumCEFNativePerformCefMessageLoopWork(const char* reason) {
  return performCefMessageLoopWork(reason);
}

void miumCEFNativeCancelExternalMessagePumpWork(void) {
  cancelExternalMessagePumpWork();
}

bool miumCEFNativeSetCefSettingPath(cef_string_t& output, const std::string& value, std::string* errorOut) {
  return setCefSettingPath(output, value, errorOut);
}

void miumCEFNativeClearUTF16String(cef_string_t& value) {
  clearUTF16String(value);
}

NSString* miumCEFNativeMainBundleExecutablePath(void) {
  return mainBundleExecutablePath();
}

bool miumCEFNativeHasEnvironmentValue(const char* name) {
  return hasEnvironmentValue(name);
}

bool miumCEFNativeShouldDisableCEFChildProcessSandbox(void) {
  return shouldDisableCEFChildProcessSandbox();
}

bool miumCEFNativeInterceptProcessExitCodeIfTesting(int exitCode) {
  return interceptProcessExitCodeIfTesting(exitCode);
}

void miumCEFNativeTerminateProcessAfterCEFExecuteProcess(int exitCode) {
  terminateProcessAfterCEFExecuteProcess(exitCode);
}

RuntimeLayoutConfig miumCEFNativeResolveRuntimeLayoutConfig(
  const std::string& runtimeRootPath,
  const std::string& runtimeMetadataPath
) {
  return resolveRuntimeLayoutConfig(runtimeRootPath, runtimeMetadataPath);
}

std::string miumCEFNativeResolveHelperSubprocessPath(
  const std::string& runtimeRootPath,
  const std::string& runtimeMetadataPath
) {
  return resolveHelperSubprocessPath(runtimeRootPath, runtimeMetadataPath);
}

std::string miumCEFNativeResolveCEFUserDataDirectory(void) {
  return resolveCEFUserDataDirectory();
}

std::string miumCEFNativeResolveChromiumLocalesPath(const std::string& runtimeRootPath) {
  return resolveChromiumLocalesPath(runtimeRootPath);
}

bool miumCEFNativePathExistsAsDirectory(const std::string& path) {
  return pathExistsAsDirectory(path);
}

std::vector<std::string> miumCEFNativeCandidatePathsFor(
  const std::string& runtimeRootPath,
  const std::string& runtimeMetadataPath
) {
  return candidatePathsFor(runtimeRootPath, runtimeMetadataPath);
}

std::string miumCEFNativeDescribeFrameworkCandidateFailure(const std::vector<std::string>& candidates) {
  return describeFrameworkCandidateFailure(candidates);
}

std::vector<std::string> miumCEFNativeFrameworkFallbackCandidates(void) {
  return frameworkFallbackCandidates();
}

bool miumCEFNativeLoadSymbol(void* handle, const char* symbolName, void** destination) {
  return loadSymbol(handle, symbolName, destination);
}

bool miumCEFNativeVerifyCefApiCompatibility(const char* runtimeHash, const char* expectedHash) {
  return verifyCefApiCompatibility(runtimeHash, expectedHash);
}

bool miumCEFNativeLoadRequiredCefSymbols(void* frameworkHandle, CefApi* loadedApi) {
  return loadRequiredCefSymbols(frameworkHandle, loadedApi);
}

bool miumCEFNativeOpenFrameworkIfNeeded(const std::vector<std::string>& candidates) {
  return openFrameworkIfNeeded(candidates);
}

bool miumCEFNativeEnsureCefInitialized(
  const std::string& runtimeRootPath,
  const std::string& runtimeMetadataPath,
  std::string* failureReason
) {
  return ensureCefInitialized(runtimeRootPath, runtimeMetadataPath, failureReason);
}

void miumCEFNativeCloseUncommittedFrameworkHandle(void* frameworkHandle) {
  miumCEFCloseUncommittedFrameworkHandle(frameworkHandle);
}

bool miumCEFNativeUTF16FromUTF8(const char* input, cef_string_t& output, std::string* errorOut) {
  return utf16FromUTF8(input, output, errorOut);
}

bool miumCEFNativeEvaluateRendererJavaScript(
  cef_frame_t* frame,
  const char* script,
  std::string* resultOut,
  std::string* errorOut
) {
  return evaluateRendererJavaScript(frame, script, resultOut, errorOut);
}

double miumCEFNativeRendererJavaScriptRequestTimeoutSeconds(void) {
#if defined(MIUM_CEF_BRIDGE_TESTING)
  if (gTestRendererJavaScriptRequestTimeoutSeconds >= 0.0) {
    return gTestRendererJavaScriptRequestTimeoutSeconds;
  }
#endif
  return kRendererJavaScriptRequestTimeoutSeconds;
}
