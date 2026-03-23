#pragma once

#import <Foundation/Foundation.h>

#include <signal.h>
#include <string>
#include <vector>

#include "MiumCEFBridgeInternalState.h"

std::string normalizePath(const char* path);
std::vector<std::string> candidatePathsFor(const std::string& runtimeRootPath, const std::string& runtimeMetadataPath);
std::string trimWhitespaceInString(const std::string& value);
std::string makePathFromRootAndRelative(const std::string& rootPath, const std::string& relativePath);
bool directoryContainsCefLocaleResources(NSString* directoryPath);
std::string normalizeChromiumLocalesPathCandidate(const std::string& candidatePath);
std::string resolveChromiumLocalesPath(const std::string& runtimeRootPath);
RuntimeLayoutConfig resolveRuntimeLayoutConfig(
  const std::string& runtimeRootPath,
  const std::string& runtimeMetadataPath
);
NSString* mainBundleExecutablePath(void);
bool pathExists(const std::string& path);
bool pathExistsAsDirectory(const std::string& path);
bool pathExistsAsFile(const std::string& path);
std::string hostExecutableBasename(void);
std::string resolveHelperBundlePath(const std::string& helpersDirPath);
std::string resolveHelperSubprocessPath(const std::string& runtimeRootPath, const std::string& runtimeMetadataPath);
std::string describeFrameworkCandidateFailure(const std::vector<std::string>& candidates);
bool parseBooleanEnvironmentFlag(const char* name);
bool hasEnvironmentValue(const char* name);
bool shouldDisableCEFChildProcessSandbox(void);
pid_t singletonOwnerPIDFromLockDestination(NSString* lockDestination);
bool isLiveNavigatorProcess(pid_t pid);
void removeStaleSingletonArtifacts(NSString* userDataDirectory);
std::string resolveCEFUserDataDirectory(void);
