#pragma once

#import <Foundation/Foundation.h>

#include <string>
#include <vector>

#include "MiumCEFBridgeCefApi.h"
#include "MiumCEFBridgeStateModels.h"

bool miumCEFNativeSetCefSettingPath(cef_string_t& output, const std::string& value, std::string* errorOut);
void miumCEFNativeClearUTF16String(cef_string_t& value);
NSString* miumCEFNativeMainBundleExecutablePath(void);
bool miumCEFNativeHasEnvironmentValue(const char* name);
bool miumCEFNativeShouldDisableCEFChildProcessSandbox(void);
bool miumCEFNativeInterceptProcessExitCodeIfTesting(int exitCode);
void miumCEFNativeTerminateProcessAfterCEFExecuteProcess(int exitCode);
RuntimeLayoutConfig miumCEFNativeResolveRuntimeLayoutConfig(
  const std::string& runtimeRootPath,
  const std::string& runtimeMetadataPath
);
std::string miumCEFNativeResolveHelperSubprocessPath(
  const std::string& runtimeRootPath,
  const std::string& runtimeMetadataPath
);
std::string miumCEFNativeResolveCEFUserDataDirectory(void);
std::string miumCEFNativeResolveChromiumLocalesPath(const std::string& runtimeRootPath);
bool miumCEFNativePathExistsAsDirectory(const std::string& path);
std::vector<std::string> miumCEFNativeCandidatePathsFor(
  const std::string& runtimeRootPath,
  const std::string& runtimeMetadataPath
);
std::string miumCEFNativeDescribeFrameworkCandidateFailure(const std::vector<std::string>& candidates);
std::vector<std::string> miumCEFNativeFrameworkFallbackCandidates(void);
bool miumCEFNativeLoadSymbol(void* handle, const char* symbolName, void** destination);
bool miumCEFNativeVerifyCefApiCompatibility(const char* runtimeHash, const char* expectedHash);
bool miumCEFNativeLoadRequiredCefSymbols(void* frameworkHandle, CefApi* loadedApi);
bool miumCEFNativeOpenFrameworkIfNeeded(const std::vector<std::string>& candidates);
bool miumCEFNativeEnsureCefInitialized(
  const std::string& runtimeRootPath,
  const std::string& runtimeMetadataPath,
  std::string* failureReason
);
bool loadRequiredCefSymbols(void* frameworkHandle, CefApi* apiOut);
bool openFrameworkIfNeeded(const std::vector<std::string>& candidates);
bool ensureCefInitialized(
  const std::string& runtimeRootPath,
  const std::string& runtimeMetadataPath,
  std::string* failureReason = nullptr
);
void miumCEFNativeCloseUncommittedFrameworkHandle(void* frameworkHandle);
bool miumCEFNativeUTF16FromUTF8(const char* input, cef_string_t& output, std::string* errorOut);
