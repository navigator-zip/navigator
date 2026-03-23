#pragma once

#include <string>
#include <vector>

#if defined(MIUM_CEF_BRIDGE_TESTING)
#include "MiumCEFBridgeNative+Testing.h"
#endif

extern std::vector<std::string> gLastCandidatePaths;

#if defined(MIUM_CEF_BRIDGE_TESTING)
extern MiumCEFBridgeTestWindowSnapshotMode gTestWindowSnapshotMode;
extern std::vector<std::string> gTestSubprocessFrameworkCandidates;
extern std::vector<std::string> gTestFrameworkFallbackCandidates;
extern bool gTestBundlePathNil;
extern std::string gTestBundleExecutablePathOverride;
extern bool gTestBundleExecutablePathNil;
extern std::string gTestBundleIdentifierOverride;
extern bool gTestBundleIdentifierNil;
extern std::string gTestCachesDirectoryOverride;
extern bool gTestCachesDirectoriesEmpty;
extern int gTestMediaStreamOverrideDevelopmentEligibility;
extern MiumCEFBridgeTestProcessExitCallback gTestProcessExitCallback;
extern bool gTestInterceptProcessExit;
extern int gTestInterceptedProcessExitCode;
extern double gTestRendererJavaScriptRequestTimeoutSeconds;
extern bool gTestCreateBrowserClientReturnsNull;
extern bool gTestNextBrowserClientMissingDisplayHandler;
extern MiumCEFBridgeTestOnePixelImageFailureMode gTestOnePixelImageFailureMode;
#endif
