#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#include <cerrno>
#include <csignal>
#include <cctype>
#include <libproc.h>
#include <unordered_set>

#include "MiumCEFBridgeAuxiliaryState.h"
#include "MiumCEFBridgePaths.h"
#include "Tracing.h"

namespace {

static bool shouldEmitPathDiagnostics() {
#if defined(MIUM_CEF_BRIDGE_TESTING)
  return miumCefTracingEnabled();
#else
  return true;
#endif
}

static void pathDiagnostic(const char* format, ...) {
  if (!shouldEmitPathDiagnostics()) {
    return;
  }
  va_list args;
  va_start(args, format);
  vfprintf(stderr, format, args);
  va_end(args);
}

std::string stringFromNSStringUTF8(NSString* source) {
  if (source == nil) {
    return {};
  }
  const char* utf8 = source.UTF8String;
  return utf8 == nullptr ? std::string() : std::string(utf8);
}

NSString* mainBundlePathValue() {
#if defined(MIUM_CEF_BRIDGE_TESTING)
  if (gTestBundlePathNil) {
    return nil;
  }
#endif
  return [NSBundle mainBundle].bundlePath;
}

NSString* mainBundleIdentifierValue() {
#if defined(MIUM_CEF_BRIDGE_TESTING)
  if (gTestBundleIdentifierNil) {
    return nil;
  }
  if (!gTestBundleIdentifierOverride.empty()) {
    return [NSString stringWithUTF8String:gTestBundleIdentifierOverride.c_str()];
  }
#endif
  return [NSBundle mainBundle].bundleIdentifier;
}

NSArray<NSString*>* cacheDirectorySearchPaths() {
#if defined(MIUM_CEF_BRIDGE_TESTING)
  if (gTestCachesDirectoriesEmpty) {
    return @[];
  }
  if (!gTestCachesDirectoryOverride.empty()) {
    NSString* overridePath = [NSString stringWithUTF8String:gTestCachesDirectoryOverride.c_str()];
    return overridePath == nil ? @[] : @[ overridePath ];
  }
#endif
  return NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
}

void appendCandidatePaths(
  std::vector<std::string>& output,
  std::unordered_set<std::string>& seen,
  const std::string& root,
  const std::vector<std::string>& suffixes
) {
  if (root.empty()) {
    return;
  }

  NSString* rootNs = [NSString stringWithUTF8String:root.c_str()];
  if (rootNs == nil) {
    return;
  }

  NSString* normalizedRoot = [rootNs stringByStandardizingPath];
  for (const auto& suffix : suffixes) {
    NSString* candidate =
      [[normalizedRoot stringByAppendingPathComponent:[NSString stringWithUTF8String:suffix.c_str()]] stringByStandardizingPath];
    const std::string candidatePath = stringFromNSStringUTF8(candidate);
    if (!candidatePath.empty() && seen.insert(candidatePath).second) {
      output.push_back(candidatePath);
    }
  }
}

bool directoryContainsDirectCefLocaleResources(NSString* directoryPath) {
  if (directoryPath == nil || directoryPath.length == 0) {
    return false;
  }

  NSFileManager* fileManager = NSFileManager.defaultManager;
  BOOL isDirectory = NO;
  if (![fileManager fileExistsAtPath:directoryPath isDirectory:&isDirectory] || !isDirectory) {
    return false;
  }

  NSArray<NSString*>* entries = [fileManager contentsOfDirectoryAtPath:directoryPath error:nil];
  if (entries == nil) {
    return false;
  }

  for (NSString* entry in entries) {
    NSString* lowercased = entry.lowercaseString;
    NSString* entryPath = [directoryPath stringByAppendingPathComponent:entry];

    if ([lowercased.pathExtension isEqualToString:@"lproj"]) {
      BOOL entryIsDirectory = NO;
      NSString* localePakPath = [entryPath stringByAppendingPathComponent:@"locale.pak"];
      if ([fileManager fileExistsAtPath:localePakPath isDirectory:&entryIsDirectory] && !entryIsDirectory) {
        return true;
      }
      continue;
    }

    if ([lowercased.pathExtension isEqualToString:@"pak"] && ![lowercased isEqualToString:@"resources.pak"]) {
      return true;
    }
  }

  return false;
}

const char* cStringOrEmpty(NSString* value) {
  const char* bytes = value == nil ? nullptr : value.UTF8String;
  return bytes == nullptr ? "" : bytes;
}

}  // namespace

std::string normalizePath(const char* path) {
  if (path == nullptr) {
    return {};
  }

  NSString* rawPath = [NSString stringWithUTF8String:path];
  if (rawPath == nil) {
    return {};
  }

  NSString* normalized = [rawPath stringByStandardizingPath];
  return stringFromNSStringUTF8(normalized);
}

std::vector<std::string> candidatePathsFor(const std::string& runtimeRootPath, const std::string& runtimeMetadataPath) {
  std::vector<std::string> out;
  std::unordered_set<std::string> seen;

  const std::vector<std::string> suffixes = {
    "Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework",
    "Contents/Frameworks/Chromium Embedded Framework.framework/Versions/A/Chromium Embedded Framework",
    "Contents/Frameworks/MiumRuntime/Chromium Embedded Framework.framework/Chromium Embedded Framework",
    "Contents/Frameworks/MiumRuntime/Chromium Embedded Framework.framework/Versions/A/Chromium Embedded Framework",
    "Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework",
    "Frameworks/Chromium Embedded Framework.framework/Versions/A/Chromium Embedded Framework",
    "Frameworks/MiumRuntime/Chromium Embedded Framework.framework/Chromium Embedded Framework",
    "Frameworks/MiumRuntime/Chromium Embedded Framework.framework/Versions/A/Chromium Embedded Framework"
  };

  appendCandidatePaths(out, seen, runtimeRootPath, suffixes);

  if (!runtimeMetadataPath.empty()) {
    NSString* metadataDirectory = [NSString stringWithUTF8String:runtimeMetadataPath.c_str()];
    if (metadataDirectory != nil) {
      metadataDirectory = metadataDirectory.stringByDeletingLastPathComponent;
      if (metadataDirectory != nil) {
        appendCandidatePaths(
          out,
          seen,
          normalizePath(metadataDirectory.fileSystemRepresentation),
          {
            "Chromium Embedded Framework.framework/Chromium Embedded Framework",
            "Chromium Embedded Framework.framework/Versions/A/Chromium Embedded Framework"
          }
        );
      }
    }
  }

  NSString* privateFrameworksPath = NSBundle.mainBundle.privateFrameworksPath;
  if (privateFrameworksPath != nil) {
    std::string normalizedPrivateFrameworks = normalizePath(privateFrameworksPath.fileSystemRepresentation);
    if (!normalizedPrivateFrameworks.empty()) {
      appendCandidatePaths(
        out,
        seen,
        normalizedPrivateFrameworks,
        {
          "Chromium Embedded Framework.framework/Chromium Embedded Framework",
          "Chromium Embedded Framework.framework/Versions/A/Chromium Embedded Framework",
          "MiumRuntime/Chromium Embedded Framework.framework/Chromium Embedded Framework",
          "MiumRuntime/Chromium Embedded Framework.framework/Versions/A/Chromium Embedded Framework"
        }
      );
    }
  }

  return out;
}

std::string trimWhitespaceInString(const std::string& value) {
  size_t start = 0;
  while (start < value.size() && std::isspace(static_cast<unsigned char>(value[start])) != 0) {
    ++start;
  }

  size_t end = value.size();
  while (end > start && std::isspace(static_cast<unsigned char>(value[end - 1])) != 0) {
    --end;
  }

  return value.substr(start, end - start);
}

std::string makePathFromRootAndRelative(const std::string& rootPath, const std::string& relativePath) {
  if (rootPath.empty() || relativePath.empty()) {
    return {};
  }

  NSString* root = [NSString stringWithUTF8String:rootPath.c_str()];
  NSString* relative = [NSString stringWithUTF8String:relativePath.c_str()];
  if (root == nil || relative == nil) {
    return {};
  }

  NSString* candidate = [[root stringByAppendingPathComponent:relative] stringByStandardizingPath];
  return normalizePath(candidate.fileSystemRepresentation);
}

bool directoryContainsCefLocaleResources(NSString* directoryPath) {
  if (directoryContainsDirectCefLocaleResources(directoryPath)) {
    return true;
  }

  if (directoryPath == nil || directoryPath.length == 0) {
    return false;
  }

  NSFileManager* fileManager = NSFileManager.defaultManager;
  BOOL isDirectory = NO;
  if (![fileManager fileExistsAtPath:directoryPath isDirectory:&isDirectory] || !isDirectory) {
    return false;
  }
  NSArray<NSString*>* entries = [fileManager contentsOfDirectoryAtPath:directoryPath error:nil];
  if (entries == nil) {
    return false;
  }

  for (NSString* entry in entries) {
    if ([entry.lowercaseString isEqualToString:@"locales"]) {
      NSString* entryPath = [directoryPath stringByAppendingPathComponent:entry];
      if (directoryContainsCefLocaleResources(entryPath)) {
        return true;
      }
    }
  }
  return false;
}

std::string normalizeChromiumLocalesPathCandidate(const std::string& candidatePath) {
  if (candidatePath.empty()) {
    return {};
  }

  NSString* candidate = [NSString stringWithUTF8String:candidatePath.c_str()];
  if (candidate == nil || candidate.length == 0) {
    return {};
  }

  candidate = candidate.stringByStandardizingPath;
  NSMutableArray<NSString*>* candidates = [NSMutableArray array];
  if ([candidate.lastPathComponent isEqualToString:@"locales"]) {
    [candidates addObject:candidate];
  } else {
    NSString* localesSubdirectory = [candidate stringByAppendingPathComponent:@"locales"];
    if (localesSubdirectory != nil && localesSubdirectory.length > 0) {
      [candidates addObject:localesSubdirectory];
    }
    [candidates addObject:candidate];
  }

  NSMutableSet<NSString*>* seen = [NSMutableSet set];
  for (NSString* path in candidates) {
    if ([seen containsObject:path]) {
      continue;
    }
    [seen addObject:path];

    const bool isLocalesDirectory = [path.lastPathComponent.lowercaseString isEqualToString:@"locales"];
    const bool hasLocaleResources = isLocalesDirectory
      ? directoryContainsCefLocaleResources(path)
      : directoryContainsDirectCefLocaleResources(path);
    if (!hasLocaleResources) {
      continue;
    }

    const char* bytes = path.fileSystemRepresentation;
    if (bytes != nullptr && bytes[0] != '\0') {
      return normalizePath(bytes);
    }
  }

  return {};
}

std::string resolveChromiumLocalesPath(const std::string& runtimeRootPath) {
  const std::vector<std::string> candidateRelativePaths = {
    "Contents/Resources",
    "Contents/Resources/locales",
    "Contents/Frameworks/Chromium Embedded Framework.framework/Versions/A/Resources",
    "Contents/Frameworks/Chromium Embedded Framework.framework/Versions/A/Resources/locales",
    "Contents/Frameworks/Chromium Embedded Framework.framework/Resources",
    "Contents/Frameworks/Chromium Embedded Framework.framework/Resources/locales",
    "Contents/Frameworks/MiumRuntime/Chromium Embedded Framework.framework/Versions/A/Resources",
    "Contents/Frameworks/MiumRuntime/Chromium Embedded Framework.framework/Versions/A/Resources/locales",
    "Contents/Frameworks/MiumRuntime/Chromium Embedded Framework.framework/Resources",
    "Contents/Frameworks/MiumRuntime/Chromium Embedded Framework.framework/Resources/locales"
  };

  for (const auto& candidate : candidateRelativePaths) {
    const std::string candidatePath = makePathFromRootAndRelative(runtimeRootPath, candidate);
    const std::string normalizedCandidate = normalizeChromiumLocalesPathCandidate(candidatePath);
    if (!normalizedCandidate.empty()) {
      return normalizedCandidate;
    }
  }

  return {};
}

RuntimeLayoutConfig resolveRuntimeLayoutConfig(
  const std::string& runtimeRootPath,
  const std::string& runtimeMetadataPath
) {
  RuntimeLayoutConfig layoutConfig;
  const std::string defaultResourcesRelativePath = "Contents/Resources";
  const std::string defaultLocalesRelativePath =
    "Contents/Frameworks/Chromium Embedded Framework.framework/Versions/A/Resources/locales";
  const std::string defaultHelpersRelativePath = "Contents/Frameworks";

  layoutConfig.resourcesDir = makePathFromRootAndRelative(runtimeRootPath, defaultResourcesRelativePath);
  layoutConfig.localesDir = resolveChromiumLocalesPath(runtimeRootPath);
  if (layoutConfig.localesDir.empty()) {
    layoutConfig.localesDir = normalizeChromiumLocalesPathCandidate(
      makePathFromRootAndRelative(runtimeRootPath, defaultLocalesRelativePath)
    );
  }
  layoutConfig.helpersDir = makePathFromRootAndRelative(runtimeRootPath, defaultHelpersRelativePath);

  if (runtimeMetadataPath.empty()) {
    return layoutConfig;
  }
  NSString* metadataDirectory = [NSString stringWithUTF8String:runtimeMetadataPath.c_str()];
  if (metadataDirectory == nil || metadataDirectory.length == 0) {
    return layoutConfig;
  }
  NSString* runtimeLayoutPath = [metadataDirectory stringByAppendingPathComponent:@"runtime_layout.json"];
  NSData* layoutData = [NSData dataWithContentsOfFile:runtimeLayoutPath];
  if (layoutData == nil || layoutData.length == 0) {
    return layoutConfig;
  }

  NSError* layoutError = nil;
  id layoutObj = [NSJSONSerialization JSONObjectWithData:layoutData options:0 error:&layoutError];
  if (layoutError != nil || layoutObj == nil) {
    return layoutConfig;
  }

  NSDictionary* layout = [layoutObj isKindOfClass:NSDictionary.class] ? layoutObj : nil;
  if (layout == nil) {
    return layoutConfig;
  }

  NSDictionary* expectedPaths = layout[@"expectedPaths"];
  if (expectedPaths == nil || ![expectedPaths isKindOfClass:NSDictionary.class]) {
    return layoutConfig;
  }

  auto readExpectedPath = [&](NSString* key) -> std::string {
    NSString* raw = expectedPaths[key];
    if (raw == nil || ![raw isKindOfClass:NSString.class]) {
      return {};
    }

    NSString* trimmed = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed == nil || trimmed.length == 0) {
      return {};
    }
    const std::string trimmedPath = trimWhitespaceInString(stringFromNSStringUTF8(trimmed));
    return trimmedPath.empty() ? std::string() : trimmedPath;
  };

  const std::string resourcesRelativePath = readExpectedPath(@"resourcesRelativePath");
  const std::string localesRelativePath = readExpectedPath(@"localesRelativePath");
  const std::string helpersRelativePath = readExpectedPath(@"helpersDirRelativePath");

  if (!resourcesRelativePath.empty()) {
    layoutConfig.resourcesDir = makePathFromRootAndRelative(runtimeRootPath, resourcesRelativePath);
  }
  if (!localesRelativePath.empty()) {
    const std::string configuredLocalesDir = makePathFromRootAndRelative(runtimeRootPath, localesRelativePath);
    const std::string normalizedLocalesDir = normalizeChromiumLocalesPathCandidate(configuredLocalesDir);
    layoutConfig.localesDir = normalizedLocalesDir.empty() ? configuredLocalesDir : normalizedLocalesDir;
  }
  if (!helpersRelativePath.empty()) {
    layoutConfig.helpersDir = makePathFromRootAndRelative(runtimeRootPath, helpersRelativePath);
  }

  return layoutConfig;
}

NSString* mainBundleExecutablePath(void) {
#if defined(MIUM_CEF_BRIDGE_TESTING)
  if (gTestBundleExecutablePathNil) {
    return nil;
  }
  if (!gTestBundleExecutablePathOverride.empty()) {
    return [NSString stringWithUTF8String:gTestBundleExecutablePathOverride.c_str()];
  }
#endif
  return NSBundle.mainBundle.executablePath;
}

bool pathExists(const std::string& path) {
  if (path.empty()) {
    return false;
  }

  BOOL isDirectory = NO;
  return [NSFileManager.defaultManager fileExistsAtPath:[NSString stringWithUTF8String:path.c_str()] isDirectory:&isDirectory];
}

bool pathExistsAsDirectory(const std::string& path) {
  if (!pathExists(path)) {
    return false;
  }

  BOOL isDirectory = NO;
  BOOL fileExists = [NSFileManager.defaultManager fileExistsAtPath:[NSString stringWithUTF8String:path.c_str()] isDirectory:&isDirectory];
  return fileExists && isDirectory == YES;
}

bool pathExistsAsFile(const std::string& path) {
  if (!pathExists(path)) {
    return false;
  }

  BOOL isDirectory = NO;
  BOOL fileExists = [NSFileManager.defaultManager fileExistsAtPath:[NSString stringWithUTF8String:path.c_str()] isDirectory:&isDirectory];
  return fileExists && isDirectory == NO;
}

std::string hostExecutableBasename(void) {
  NSString* executablePath = mainBundleExecutablePath();
  if (executablePath == nil || executablePath.length == 0) {
    return {};
  }

  NSString* baseName = executablePath.lastPathComponent.stringByDeletingPathExtension;
  return trimWhitespaceInString(stringFromNSStringUTF8(baseName));
}

std::string resolveHelperBundlePath(const std::string& helpersDirPath) {
  if (helpersDirPath.empty() || !pathExistsAsDirectory(helpersDirPath)) {
    return {};
  }

  NSString* helpersDir = [NSString stringWithUTF8String:helpersDirPath.c_str()];
  NSError* enumerationError = nil;
  NSArray* entries = [NSFileManager.defaultManager contentsOfDirectoryAtPath:helpersDir error:&enumerationError];
  if (enumerationError != nil || entries == nil || entries.count == 0) {
    return {};
  }

  const std::string hostBase = hostExecutableBasename();
  std::vector<std::string> preferredNames;
  if (!hostBase.empty()) {
    preferredNames.push_back(hostBase + " Helper");
  }
  preferredNames.push_back("Navigator Helper");
  preferredNames.push_back("Chromium Helper");
  preferredNames.push_back("Mium Helper");

  for (const auto& preferredName : preferredNames) {
    const std::string candidateBundleName = preferredName + ".app";
    NSString* candidateBundlePath =
      [helpersDir stringByAppendingPathComponent:[NSString stringWithUTF8String:candidateBundleName.c_str()]];
    std::string candidateBundlePathString = normalizePath(candidateBundlePath.fileSystemRepresentation);
    if (!pathExistsAsDirectory(candidateBundlePathString)) {
      continue;
    }

    NSString* candidateExecutable = nil;
    NSBundle* helperBundle = [NSBundle bundleWithPath:candidateBundlePath];
    NSString* bundleExecutable = helperBundle == nil ? nil : helperBundle.infoDictionary[@"CFBundleExecutable"];
    if (bundleExecutable != nil) {
      candidateExecutable = [[[candidateBundlePath stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"MacOS"]
        stringByAppendingPathComponent:bundleExecutable];
    } else {
      NSString* binaryName = candidateBundlePath.lastPathComponent.stringByDeletingPathExtension;
      candidateExecutable = [[[candidateBundlePath stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"MacOS"]
        stringByAppendingPathComponent:binaryName];
    }

    std::string candidateExecutableString = normalizePath(candidateExecutable.fileSystemRepresentation);
    if (pathExistsAsFile(candidateExecutableString)) {
      return candidateExecutableString;
    }

    if (bundleExecutable != nil && !hostBase.empty()) {
      candidateExecutable = [[[candidateBundlePath stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"MacOS"]
        stringByAppendingPathComponent:[NSString stringWithUTF8String:hostBase.c_str()]];
      std::string fallbackExecutableString = normalizePath(candidateExecutable.fileSystemRepresentation);
      if (pathExistsAsFile(fallbackExecutableString)) {
        return fallbackExecutableString;
      }
    }

    candidateExecutable = [[[candidateBundlePath stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"MacOS"]
      stringByAppendingPathComponent:@"Navigator Helper"];
    std::string finalExecutableString = normalizePath(candidateExecutable.fileSystemRepresentation);
    if (pathExistsAsFile(finalExecutableString)) {
      return finalExecutableString;
    }
  }

  return {};
}

std::string resolveHelperSubprocessPath(const std::string& runtimeRootPath, const std::string& runtimeMetadataPath) {
  const char* envSubprocessPath = std::getenv("MIUM_CEF_BROWSER_SUBPROCESS_PATH");
  if (envSubprocessPath != nullptr && envSubprocessPath[0] != '\0') {
    const std::string configured = normalizePath(envSubprocessPath);
    if (!configured.empty() && pathExistsAsFile(configured)) {
      return configured;
    }
  }

  const RuntimeLayoutConfig layoutConfig = resolveRuntimeLayoutConfig(runtimeRootPath, runtimeMetadataPath);
  const std::vector<std::string> helperSearchDirs = {
    layoutConfig.helpersDir,
    makePathFromRootAndRelative(runtimeRootPath, "Contents/Frameworks/Chromium Embedded Framework.framework/Helpers"),
    makePathFromRootAndRelative(runtimeRootPath, "Contents/Frameworks/Chromium Embedded Framework.framework/Versions/A/Helpers"),
    makePathFromRootAndRelative(runtimeRootPath, "Contents/Frameworks/MiumRuntime/Chromium Embedded Framework.framework/Helpers"),
    makePathFromRootAndRelative(runtimeRootPath, "Contents/Frameworks/MiumRuntime/Chromium Embedded Framework.framework/Versions/A/Helpers"),
    makePathFromRootAndRelative(runtimeRootPath, "Contents/Helpers")
  };

  for (const auto& searchDir : helperSearchDirs) {
    if (searchDir.empty()) {
      continue;
    }
    const std::string helperExecutable = resolveHelperBundlePath(searchDir);
    if (!helperExecutable.empty()) {
      return helperExecutable;
    }
  }

  if (!layoutConfig.helpersDir.empty()) {
    miumCefTrace("paths", "no Chromium helper app found in %s\n", layoutConfig.helpersDir.c_str());
  }

  return {};
}

std::string describeFrameworkCandidateFailure(const std::vector<std::string>& candidates) {
  if (candidates.empty()) {
    return "Unable to open native bridge library. No candidate paths were discovered.";
  }

  std::string message = "Unable to open native bridge library. Candidate paths attempted:";
  const size_t maxCandidates = 24;
  for (size_t index = 0; index < candidates.size(); ++index) {
    if (index >= maxCandidates) {
      message += "\n - ... and " + std::to_string(candidates.size() - maxCandidates) + " more";
      break;
    }
    message += "\n - " + candidates[index];
  }
  return message;
}

bool parseBooleanEnvironmentFlag(const char* name) {
  const char* rawValue = getenv(name);
  if (rawValue == nullptr) {
    return false;
  }

  std::string value(rawValue);
  if (value.empty()) {
    return false;
  }

  for (char& ch : value) {
    ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
  }

  return value == "1" || value == "true" || value == "yes" || value == "on" || value == "enabled";
}

bool hasEnvironmentValue(const char* name) {
  return getenv(name) != nullptr;
}

bool shouldDisableCEFChildProcessSandbox(void) {
  const bool disableCefSandbox = parseBooleanEnvironmentFlag("MIUM_DISABLE_CEF_SANDBOX");
  const bool disableLegacy = parseBooleanEnvironmentFlag("MIUM_CEF_NO_SANDBOX");

  if (disableCefSandbox || disableLegacy) {
    return true;
  }

  if (hasEnvironmentValue("MIUM_DISABLE_CEF_SANDBOX") || hasEnvironmentValue("MIUM_CEF_NO_SANDBOX")) {
    return false;
  }

#if DEBUG
  return true;
#else
  return false;
#endif
}

pid_t singletonOwnerPIDFromLockDestination(NSString* lockDestination) {
  if (lockDestination == nil || lockDestination.length == 0) {
    return 0;
  }

  NSRange separatorRange = [lockDestination rangeOfString:@"-" options:NSBackwardsSearch];
  if (separatorRange.location == NSNotFound) {
    return 0;
  }

  NSUInteger pidStart = NSMaxRange(separatorRange);
  if (pidStart >= lockDestination.length) {
    return 0;
  }

  NSString* pidString = [lockDestination substringFromIndex:pidStart];
  NSScanner* scanner = [NSScanner scannerWithString:pidString];
  long long pidValue = 0;
  if (![scanner scanLongLong:&pidValue] || !scanner.isAtEnd || pidValue <= 0) {
    return 0;
  }

  return static_cast<pid_t>(pidValue);
}

bool isLiveNavigatorProcess(pid_t pid) {
  if (pid <= 0) {
    return false;
  }

  errno = 0;
  if (kill(pid, 0) != 0 && errno != EPERM) {
    return false;
  }

  char processPath[PROC_PIDPATHINFO_MAXSIZE] = {};
  const bool resolvedProcessPathValid = proc_pidpath(pid, processPath, sizeof(processPath)) > 0 && processPath[0] != '\0';
  NSString* resolvedProcessPath = resolvedProcessPathValid ? [NSString stringWithUTF8String:processPath] : nil;
  NSString* executablePath = mainBundleExecutablePath();
  NSString* expectedProcessName = executablePath.lastPathComponent;
  if (expectedProcessName == nil || expectedProcessName.length == 0) {
    expectedProcessName = @"Navigator";
  }

  return resolvedProcessPath != nil && [resolvedProcessPath.lastPathComponent isEqualToString:expectedProcessName];
}

void removeStaleSingletonArtifacts(NSString* userDataDirectory) {
  if (userDataDirectory == nil || userDataDirectory.length == 0) {
    return;
  }

  NSFileManager* fileManager = NSFileManager.defaultManager;
  NSString* singletonLockPath = [userDataDirectory stringByAppendingPathComponent:@"SingletonLock"];
  NSString* singletonLockDestination = [fileManager destinationOfSymbolicLinkAtPath:singletonLockPath error:nil];

  const bool hasSingletonArtifacts =
    [fileManager fileExistsAtPath:[userDataDirectory stringByAppendingPathComponent:@"SingletonCookie"]] ||
    [fileManager fileExistsAtPath:singletonLockPath] ||
    [fileManager fileExistsAtPath:[userDataDirectory stringByAppendingPathComponent:@"SingletonSocket"]];
  if (!hasSingletonArtifacts) {
    return;
  }

  const pid_t ownerPID = singletonOwnerPIDFromLockDestination(singletonLockDestination);
  const bool shouldRemoveArtifacts =
    singletonLockDestination == nil ||
    singletonLockDestination.length == 0 ||
    ownerPID <= 0 ||
    !isLiveNavigatorProcess(ownerPID);
  if (!shouldRemoveArtifacts) {
    return;
  }

  for (NSString* artifactName in @[ @"SingletonCookie", @"SingletonLock", @"SingletonSocket" ]) {
    NSString* artifactPath = [userDataDirectory stringByAppendingPathComponent:artifactName];
    if (![fileManager fileExistsAtPath:artifactPath]) {
      continue;
    }

    NSError* removeError = nil;
    if (![fileManager removeItemAtPath:artifactPath error:&removeError] && removeError != nil) {
      pathDiagnostic(
        "[MiumCEFBridge] Failed to remove stale %s at %s: %s\n",
        cStringOrEmpty(artifactName),
        artifactPath.fileSystemRepresentation,
        cStringOrEmpty(removeError.localizedDescription)
      );
    }
  }
}

std::string resolveCEFUserDataDirectory(void) {
  const char* configuredRootCachePath = getenv("MIUM_CEF_ROOT_CACHE_PATH");
  if (configuredRootCachePath != nullptr && configuredRootCachePath[0] != '\0') {
    NSString* configuredPath = [NSString stringWithUTF8String:configuredRootCachePath];
    if (configuredPath != nil) {
      configuredPath = configuredPath.stringByStandardizingPath;
      if (configuredPath != nil) {
        NSError* createError = nil;
        if ([NSFileManager.defaultManager createDirectoryAtPath:configuredPath
                                    withIntermediateDirectories:YES
                                                     attributes:nil
                                                          error:&createError]) {
          removeStaleSingletonArtifacts(configuredPath);
          const char* configuredBytes = configuredPath.fileSystemRepresentation;
          if (configuredBytes != nullptr && configuredBytes[0] != '\0') {
            return normalizePath(configuredBytes);
          }
        }

        if (createError != nullptr) {
          pathDiagnostic(
            "CEF user data directory override could not be prepared at %s: %s\n",
            configuredRootCachePath,
            cStringOrEmpty(createError.localizedDescription)
          );
        }
      }
    }
  }

  NSString* bundleIdentifier = mainBundleIdentifierValue();
  if (bundleIdentifier == nil || bundleIdentifier.length == 0) {
    bundleIdentifier = @"com.mium.desktop";
  }

  NSArray* cachePaths = cacheDirectorySearchPaths();
  if (cachePaths.count == 0) {
    return {};
  }

  NSString* cacheRoot = cachePaths.firstObject;
  NSString* candidatePath = [[[cacheRoot stringByAppendingPathComponent:@"MiumKit"] stringByAppendingPathComponent:@"CEF"]
    stringByAppendingPathComponent:bundleIdentifier];
  candidatePath = candidatePath.stringByStandardizingPath;
  NSError* createError = nil;
  if (![NSFileManager.defaultManager createDirectoryAtPath:candidatePath
                               withIntermediateDirectories:YES
                                                attributes:nil
                                                     error:&createError]) {
    if (createError != nil) {
      pathDiagnostic(
        "CEF user data directory could not be prepared at %s: %s\n",
        candidatePath.fileSystemRepresentation == nullptr ? "" : candidatePath.fileSystemRepresentation,
        cStringOrEmpty(createError.localizedDescription)
      );
    }
    return {};
  }

  removeStaleSingletonArtifacts(candidatePath);
  return normalizePath(candidatePath.fileSystemRepresentation);
}
