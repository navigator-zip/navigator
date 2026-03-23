#include "MiumCEFBridgeAuxiliaryState.h"
#include "MiumCEFBridgeHostView.h"

#include <string>
#include <vector>

std::vector<std::string> gLastCandidatePaths;

#if defined(MIUM_CEF_BRIDGE_TESTING)
MiumCEFBridgeTestWindowSnapshotMode gTestWindowSnapshotMode =
  MiumCEFBridgeTestWindowSnapshotMode::live;
std::vector<std::string> gTestSubprocessFrameworkCandidates;
std::vector<std::string> gTestFrameworkFallbackCandidates;
bool gTestBundlePathNil = false;
std::string gTestBundleExecutablePathOverride;
bool gTestBundleExecutablePathNil = false;
std::string gTestBundleIdentifierOverride;
bool gTestBundleIdentifierNil = false;
std::string gTestCachesDirectoryOverride;
bool gTestCachesDirectoriesEmpty = false;
int gTestMediaStreamOverrideDevelopmentEligibility = -1;
MiumCEFBridgeTestProcessExitCallback gTestProcessExitCallback = nullptr;
bool gTestInterceptProcessExit = false;
int gTestInterceptedProcessExitCode = -1;
double gTestRendererJavaScriptRequestTimeoutSeconds = -1.0;
bool gTestCreateBrowserClientReturnsNull = false;
bool gTestNextBrowserClientMissingDisplayHandler = false;
MiumCEFBridgeTestOnePixelImageFailureMode gTestOnePixelImageFailureMode =
  MiumCEFBridgeTestOnePixelImageFailureMode::none;
#endif
