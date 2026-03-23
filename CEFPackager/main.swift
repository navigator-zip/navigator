import CEFShared
import Foundation

func resolveRepoRoot(from start: URL) -> URL {
	var current = start.standardizedFileURL
	let fm = FileManager.default
	for _ in 0..<8 {
		if fm.fileExists(atPath: current.appendingPathComponent("Navigator.xcodeproj").path) {
			return current
		}
		let parent = current.deletingLastPathComponent()
		if parent == current {
			break
		}
		current = parent
	}
	return start.standardizedFileURL
}

func looksLikeRepoRoot(_ url: URL) -> Bool {
	let fm = FileManager.default
	return fm.fileExists(atPath: url.appendingPathComponent("Navigator.xcodeproj").path) ||
		fm.fileExists(atPath: url.appendingPathComponent(".git").path)
}

var verboseLoggingEnabled = false

let requiredPrivacyUsageDescriptions: [String: String] = [
	"NSCameraUsageDescription": "Navigator uses your camera when a website requests video access.",
	"NSLocationWhenInUseUsageDescription": "Navigator uses your location when a website requests location access.",
	"NSMicrophoneUsageDescription": "Navigator uses your microphone when a website requests audio access.",
]

func packagerSourceRoot() -> URL {
	resolveRepoRoot(from: URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.standardizedFileURL)
}

@inline(__always)
func verboseLog(_ message: @autoclosure () -> String) {
	if verboseLoggingEnabled {
		print(message())
	}
}

func isGitLFSPlaceholderArchive(_ archiveURL: URL) -> Bool {
	let marker = "version https://git-lfs.github.com/spec/v1"
	guard archiveURL.isFileURL else { return false }
	guard FileManager.default.fileExists(atPath: archiveURL.path) else { return false }
	guard
		let text = try? String(contentsOf: archiveURL, encoding: .utf8),
		let firstLine = text.split(whereSeparator: \.isNewline).first
	else {
		return false
	}
	return firstLine.trimmingCharacters(in: .whitespacesAndNewlines) == marker
}

func runGitLFSFetch(_ includePath: String, repoRoot: URL) throws {
	let fileManager = FileManager.default
	let knownGitLFSPaths = [
		"/usr/bin/git-lfs",
		"/opt/homebrew/bin/git-lfs",
		"/usr/local/bin/git-lfs",
	]

	if let gitLFSPath = knownGitLFSPaths.first(where: { path in
		fileManager.fileExists(atPath: path) && fileManager.isExecutableFile(atPath: path)
	}) {
		try runShell(
			gitLFSPath,
			arguments: ["pull", "--include", includePath],
			workingDirectory: repoRoot
		)
		return
	}

	do {
		try runShell(
			"/usr/bin/git",
			arguments: ["lfs", "pull", "--include", includePath],
			workingDirectory: repoRoot
		)
	}
	catch {
		throw RunnerError.missing(
			"Detected Git LFS pointer for \(includePath), but neither git-lfs nor git lfs is available."
		)
	}
}

func ensureGitLFSArchiveAvailable(_ archiveURL: URL, repoRoot: URL, label: String) throws {
	guard isGitLFSPlaceholderArchive(archiveURL) else { return }

	let rootPath = repoRoot.standardized.path
	let archivePath = archiveURL.standardized.path
	let includePath: String = {
		let prefixedRoot = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
		if archivePath.hasPrefix(prefixedRoot) {
			let relative = String(archivePath.dropFirst(prefixedRoot.count))
			return relative.isEmpty ? archivePath : relative
		}
		return archivePath
	}()
	print("Detected Git LFS pointer for \(label), refreshing from git LFS include=\(includePath)")
	try runGitLFSFetch(includePath, repoRoot: repoRoot)
}

struct CLIConfig {
	enum Mode: String {
		case all
		case fetch
		case stage
		case package
		case sign
		case notarize
	}

	var mode: Mode = .all
	var repoRoot: URL
	var cefArchiveURL: URL?
	var cefArchivePath: URL?
	var cefClientArchiveURL: URL?
	var cefClientArchivePath: URL?
	var cefBuildSpecPath: URL?
	var cefSourceBuild: Bool
	var cefSourceWorkDir: URL?
	var cefSourceArtifactsDir: URL?
	var cefSourceForce: Bool
	var appPath: URL?
	var buildApp: Bool
	var appScheme: String
	var appConfiguration: String
	var teamID: String?
	var appleID: String?
	var notaryProfile: String?
	var notaryPassword: String?
	var signIdentity: String?
	var shouldSign: Bool
	var shouldNotarize: Bool
	var strictMode: Bool
	var skipFetch: Bool
	var verbose: Bool

	static func make() throws -> CLIConfig {
		let env = ProcessInfo.processInfo.environment
		let args = Array(CommandLine.arguments.dropFirst())

		func nextValue(_ idx: inout Int, _ args: [String]) -> String? {
			idx += 1
			guard idx < args.count else { return nil }
			return args[idx]
		}

		func expandPlaceholders(_ value: String, env: [String: String]) -> String {
			var expanded = value
			for (key, candidate) in env {
				let token = "$(\(key))"
				expanded = expanded.replacingOccurrences(of: token, with: candidate)
			}
			return expanded
		}

		func parseEnvPath(_ key: String, env: [String: String]) -> URL? {
			guard let rawValue = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else { return nil }
			let value = expandPlaceholders(rawValue, env: env)
			if value.contains("$(") {
				return nil
			}
			return URL(fileURLWithPath: value)
		}

		var mode: Mode = .all
		var skipFetch = false
		var cefArchiveURL: URL?
		var cefArchivePath: URL?
		var cefClientArchiveURL: URL?
		var cefClientArchivePath: URL?
		var cefBuildSpecPath: URL?
		var cefSourceBuild = false
		var cefSourceWorkDir: URL?
		var cefSourceArtifactsDir: URL?
		var cefSourceForce = false
		var appPath: URL?
		var appScheme = "Navigator"
		var appConfiguration = "Release"
		var teamID = env["TEAM_ID"]
		var appleID = env["APPLE_ID"]
		var notaryProfile = env["NOTARY_KEYCHAIN_PROFILE"]
		var notaryPassword = env["NOTARY_PASSWORD"]
		var signIdentity = env["SIGN_IDENTITY"] ?? env["CODE_SIGN_IDENTITY"]
		var shouldSign = true
		var shouldNotarize = false
		var strictMode = false
		var buildApp = false
		var verbose = true
		let repoRootEnv = parseEnvPath("REPO_ROOT", env: env)
			?? parseEnvPath("SRCROOT", env: env)
			?? parseEnvPath("PROJECT_DIR", env: env)
		var repoRoot =
			resolveRepoRoot(from: repoRootEnv ?? URL(fileURLWithPath: env["PWD"] ?? FileManager.default.currentDirectoryPath))
		let sourceRoot = packagerSourceRoot()
		if !looksLikeRepoRoot(repoRoot), !sourceRoot.path.contains("DerivedData") {
			repoRoot = sourceRoot
		}

		var i = 0
		while i < args.count {
			switch args[i] {
			case "--mode":
				if let value = nextValue(&i, args), let parsedMode = Mode(rawValue: value.lowercased()) {
					mode = parsedMode
				}
			case "--repo-root":
				if let value = nextValue(&i, args) {
					let expanded = expandPlaceholders(value, env: env)
					if !expanded.contains("$(") {
						repoRoot = URL(fileURLWithPath: expanded).standardizedFileURL
					}
				}
			case "--cef-archive-url":
				if let value = nextValue(&i, args) {
					let expanded = expandPlaceholders(value, env: env)
					if let url = URL(string: expanded) {
						cefArchiveURL = url
					}
				}
			case "--cef-archive-path":
				if let value = nextValue(&i, args) {
					cefArchivePath = URL(fileURLWithPath: value)
				}
			case "--cef-client-archive-url":
				if let value = nextValue(&i, args) {
					let expanded = expandPlaceholders(value, env: env)
					if let clientURL = URL(string: expanded) {
						cefClientArchiveURL = clientURL
					}
				}
			case "--cef-client-archive-path":
				if let value = nextValue(&i, args) {
					let expanded = expandPlaceholders(value, env: env)
					if !expanded.contains("$(") {
						cefClientArchivePath = URL(fileURLWithPath: expanded)
					}
				}
			case "--cef-build-spec":
				if let value = nextValue(&i, args) {
					let expanded = expandPlaceholders(value, env: env)
					if !expanded.contains("$(") {
						cefBuildSpecPath = URL(fileURLWithPath: expanded)
					}
				}
			case "--cef-source-build":
				cefSourceBuild = true
			case "--cef-source-work-dir":
				if let value = nextValue(&i, args) {
					let expanded = expandPlaceholders(value, env: env)
					if !expanded.contains("$(") {
						cefSourceWorkDir = URL(fileURLWithPath: expanded)
					}
				}
			case "--cef-source-output-dir":
				if let value = nextValue(&i, args) {
					let expanded = expandPlaceholders(value, env: env)
					if !expanded.contains("$(") {
						cefSourceArtifactsDir = URL(fileURLWithPath: expanded)
					}
				}
			case "--cef-source-force":
				cefSourceForce = true
			case "--app-bundle-path":
				if let value = nextValue(&i, args) {
					let expanded = expandPlaceholders(value, env: env)
					if !expanded.contains("$(") {
						appPath = URL(fileURLWithPath: expanded)
					}
				}
			case "--build-app":
				buildApp = true
			case "--app-scheme":
				if let value = nextValue(&i, args) { appScheme = value }
			case "--app-configuration":
				if let value = nextValue(&i, args) { appConfiguration = value }
			case "--team-id":
				if let value = nextValue(&i, args) { teamID = value }
			case "--notary-profile":
				if let value = nextValue(&i, args) { notaryProfile = value }
			case "--apple-id":
				if let value = nextValue(&i, args) { appleID = value }
			case "--notary-password":
				if let value = nextValue(&i, args) { notaryPassword = value }
			case "--sign-identity":
				if let value = nextValue(&i, args) { signIdentity = value }
			case "--sign":
				shouldSign = true
			case "--no-sign":
				shouldSign = false
			case "--notarize":
				shouldNotarize = true
			case "--skip-notarize":
				shouldNotarize = false
			case "--strict":
				strictMode = true
			case "--skip-fetch":
				skipFetch = true
			case "--verbose", "-v":
				verbose = true
			case "--no-verbose":
				verbose = false
			default:
				break
			}
			i += 1
		}

		if let fallbackVerbose = env["CEFPACKAGER_VERBOSE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
		   !fallbackVerbose.isEmpty {
			let normalized = fallbackVerbose.lowercased()
			if ["1", "true", "yes"].contains(normalized) {
				verbose = true
			}
			else if ["0", "false", "no"].contains(normalized) {
				verbose = false
			}
		}
		if let fallbackURL = env["CEF_ARCHIVE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
		   !fallbackURL.isEmpty,
		   cefArchiveURL == nil {
			let expandedURL = expandPlaceholders(fallbackURL, env: env)
			if let fallback = URL(string: expandedURL) {
				cefArchiveURL = fallback
			}
			else {
				print("Ignoring invalid CEF_ARCHIVE_URL=\(expandedURL)")
			}
		}
		if let fallbackURL = env["CEFPACKAGER_CEF_ARCHIVE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
		   !fallbackURL.isEmpty,
		   cefArchiveURL == nil {
			let expandedURL = expandPlaceholders(fallbackURL, env: env)
			if let fallback = URL(string: expandedURL) {
				cefArchiveURL = fallback
			}
			else {
				print("Ignoring invalid CEFPACKAGER_CEF_ARCHIVE_URL=\(expandedURL)")
			}
		}
		if let fallbackURL = env["CEF_CLIENT_ARCHIVE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
		   !fallbackURL.isEmpty,
		   cefClientArchiveURL == nil {
			let expandedURL = expandPlaceholders(fallbackURL, env: env)
			if let fallback = URL(string: expandedURL) {
				cefClientArchiveURL = fallback
			}
			else {
				print("Ignoring invalid CEF_CLIENT_ARCHIVE_URL=\(expandedURL)")
			}
		}
		if let fallbackURL = env["CEFPACKAGER_CEF_CLIENT_ARCHIVE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
		   !fallbackURL.isEmpty,
		   cefClientArchiveURL == nil {
			let expandedURL = expandPlaceholders(fallbackURL, env: env)
			if let fallback = URL(string: expandedURL) {
				cefClientArchiveURL = fallback
			}
			else {
				print("Ignoring invalid CEFPACKAGER_CEF_CLIENT_ARCHIVE_URL=\(expandedURL)")
			}
		}
		if let fallbackPath = parseEnvPath("CEF_CLIENT_ARCHIVE_PATH", env: env),
		   cefClientArchivePath == nil {
			cefClientArchivePath = fallbackPath
		}
		if let fallbackPath = parseEnvPath("CEFPACKAGER_CEF_CLIENT_ARCHIVE_PATH", env: env),
		   cefClientArchivePath == nil {
			cefClientArchivePath = fallbackPath
		}
		if let fallbackPath = parseEnvPath("CEF_BUILD_SPEC", env: env),
		   cefBuildSpecPath == nil {
			cefBuildSpecPath = fallbackPath
		}
		if let fallbackPath = parseEnvPath("CEF_BUILD_SPEC_PATH", env: env),
		   cefBuildSpecPath == nil {
			cefBuildSpecPath = fallbackPath
		}
		if let fallbackPath = parseEnvPath("CEF_SOURCE_WORK_DIR", env: env),
		   cefSourceWorkDir == nil {
			cefSourceWorkDir = fallbackPath
		}
		if let fallbackPath = parseEnvPath("CEF_SOURCE_OUTPUT_DIR", env: env),
		   cefSourceArtifactsDir == nil {
			cefSourceArtifactsDir = fallbackPath
		}
		if let fallbackPath = parseEnvPath("CEF_SOURCE_ARTIFACTS_DIR", env: env),
		   cefSourceArtifactsDir == nil {
			cefSourceArtifactsDir = fallbackPath
		}
		if cefSourceBuild == false,
		   let envValue = env["CEF_SOURCE_BUILD"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
		   ["1", "true", "yes", "on"].contains(envValue) {
			cefSourceBuild = true
		}
		if cefSourceForce == false,
		   let envValue = env["CEF_SOURCE_FORCE"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
		   ["1", "true", "yes", "on"].contains(envValue) {
			cefSourceForce = true
		}
		if appPath == nil, let fallbackAppPath = env["APP_BUNDLE_PATH"] {
			let expanded = expandPlaceholders(fallbackAppPath.trimmingCharacters(in: .whitespacesAndNewlines), env: env)
			if !expanded.contains("$(") {
				appPath = URL(fileURLWithPath: expanded)
			}
		}
		if repoRoot.path.contains("DerivedData"), let fallbackRepoRoot = parseEnvPath("REPO_ROOT", env: env) ??
			parseEnvPath("SRCROOT", env: env) ??
			parseEnvPath("PROJECT_DIR", env: env) {
			let resolved = resolveRepoRoot(from: fallbackRepoRoot)
			if !resolved.path.contains("DerivedData") {
				repoRoot = resolved
			}
		}
		if teamID == nil { teamID = env["APPLE_TEAM_ID"] }

		return CLIConfig(
			mode: mode,
			repoRoot: repoRoot,
			cefArchiveURL: cefArchiveURL,
			cefArchivePath: cefArchivePath,
			cefClientArchiveURL: cefClientArchiveURL,
			cefClientArchivePath: cefClientArchivePath,
			cefBuildSpecPath: cefBuildSpecPath,
			cefSourceBuild: cefSourceBuild,
			cefSourceWorkDir: cefSourceWorkDir,
			cefSourceArtifactsDir: cefSourceArtifactsDir,
			cefSourceForce: cefSourceForce,
			appPath: appPath,
			buildApp: buildApp,
			appScheme: appScheme,
			appConfiguration: appConfiguration,
			teamID: teamID?.trimmingCharacters(in: .whitespacesAndNewlines),
			appleID: appleID?.trimmingCharacters(in: .whitespacesAndNewlines),
			notaryProfile: notaryProfile?.trimmingCharacters(in: .whitespacesAndNewlines),
			notaryPassword: notaryPassword?.trimmingCharacters(in: .whitespacesAndNewlines),
			signIdentity: signIdentity?.trimmingCharacters(in: .whitespacesAndNewlines),
			shouldSign: shouldSign,
			shouldNotarize: shouldNotarize,
			strictMode: strictMode,
			skipFetch: skipFetch,
			verbose: verbose
		)
	}
}

enum RunnerError: Error, CustomStringConvertible {
	case invalidArgument(String)
	case missing(String)
	case shellFailure(String, Int, String)

	var description: String {
		switch self {
		case .invalidArgument(let message):
			return message
		case .missing(let message):
			return message
		case .shellFailure(let command, let code, let output):
			if output.isEmpty {
				return "command failed (\(code)): \(command)"
			}
			return "command failed (\(code)): \(command)\n\(output)"
		}
	}
}

func printUsage() {
	print("""
	Usage:
	  swift Tools/CEFPackager/main.swift [options]

	Options:
	  --mode all|fetch|stage|package|sign|notarize
	  --repo-root <path>
	  --cef-archive-url <url>
	  --cef-archive-path <path>
	  --cef-client-archive-url <url>
	  --cef-client-archive-path <path>
	    (required for Release mode)
	  --cef-build-spec <path>
	  --cef-source-build
	  --cef-source-work-dir <path>
	  --cef-source-output-dir <path>
	  --cef-source-force
	  --app-bundle-path <path>
	  --build-app
	  --app-scheme <name>
	  --app-configuration <name>
	  --team-id <id>
	  --notary-profile <name>
	  --apple-id <id>
	  --notary-password <password>
	  --sign-identity <identity>
	  --sign / --no-sign
	  --notarize / --skip-notarize
	  --strict
	    Force Release-like helper strictness even for non-Release builds
	  --skip-fetch
	  --verbose, -v
	  --no-verbose
	  --help, -h

	Environment:
	  CEF_ARCHIVE_URL=<url>
	  CEFPACKAGER_CEF_ARCHIVE_URL=<url>
	  CEF_CLIENT_ARCHIVE_URL=<url>
	  CEFPACKAGER_CEF_CLIENT_ARCHIVE_URL=<url>
	  CEF_CLIENT_ARCHIVE_PATH=<path>
	  CEFPACKAGER_CEF_CLIENT_ARCHIVE_PATH=<path>
	  CEF_BUILD_SPEC=<path>
	  CEF_BUILD_SPEC_PATH=<path>
	  CEF_SOURCE_BUILD=1|true|yes|on
	  CEF_SOURCE_WORK_DIR=<path>
	  CEF_SOURCE_OUTPUT_DIR=<path>
	  CEF_SOURCE_ARTIFACTS_DIR=<path>
	  CEF_SOURCE_FORCE=1|true|yes|on
	  CEF_STAGING_DIR=<path>
	  CEF_RESOURCES_STAGING_DIR=<path>
	  CEF_HELPERS_STAGING_DIR=<path>
	  CEF_RUNTIME_MODE=app|package
	  CEF_RUNTIME_PACKAGE_DIR=<path>
	  CEF_RUNTIME_APP_EXECUTABLE_NAME=<name>
	  CEF_ALLOW_MISSING_HELPERS=1
	  CEFPACKAGER_VERBOSE=1|true|yes|0|false|no
	""")
}

@discardableResult
func runShell(
	_ command: String,
	_ arguments: [String],
	workingDirectory: URL? = nil,
	environment: [String: String] = [:],
	captureOutput: Bool = false,
	verbose: Bool = verboseLoggingEnabled,
	logPrefix: String = "[shell]",
	logCommandToStdErrWhenNotCapturingOutput: Bool = false,
	logCommandToStdOutWhenNotCapturingOutput: Bool = true,
	streamOutput: Bool = true,
	logTiming: Bool = true
) throws -> String {
	return try CEFShared.Shell.run(
		command,
		arguments,
		cwd: workingDirectory,
		environment: environment,
		captureOutput: captureOutput,
		verbose: verbose,
		logPrefix: logPrefix,
		logCommandToStdErrWhenNotCapturingOutput: logCommandToStdErrWhenNotCapturingOutput,
		logCommandToStdOutWhenNotCapturingOutput: logCommandToStdOutWhenNotCapturingOutput,
		streamOutput: streamOutput,
		logTiming: logTiming
	)
}

@discardableResult
func runShell(
	_ command: String,
	arguments: [String] = [],
	workingDirectory: URL? = nil,
	environment: [String: String] = [:],
	captureOutput: Bool = false
) throws -> String {
	return try runShell(
		command,
		arguments,
		workingDirectory: workingDirectory,
		environment: environment,
		captureOutput: captureOutput,
		verbose: verboseLoggingEnabled
	)
}

func runShellSilent(
	_ command: String,
	arguments: [String] = [],
	workingDirectory: URL? = nil,
	environment: [String: String] = [:]
) throws -> String {
	return try runShell(
		command,
		arguments,
		workingDirectory: workingDirectory,
		environment: environment,
		captureOutput: true
	)
}

func ensureDirectory(_ url: URL) throws {
	try CEFShared.ensureDirectory(url)
}

func extractFirstJSONObject(_ text: String) -> String? {
	guard let start = text.firstIndex(of: "{"),
	      let end = text.lastIndex(of: "}"),
	      start <= end else { return nil }
	return String(text[start...end])
}

func removeIfPresent(_ url: URL) throws {
	try CEFShared.removeIfPresent(url)
}

func copyItem(_ source: URL, to destination: URL) throws {
	try removeIfPresent(destination)
	try ensureDirectory(destination.deletingLastPathComponent())
	try runShell("/usr/bin/ditto", arguments: [source.path, destination.path])
}

func findFiles(
	named target: String,
	under root: URL,
	includeDirectories: Bool,
	extensionFilter: String? = nil
) -> [URL] {
	var found = [URL]()
	let fm = FileManager.default
	guard let enumerator = fm.enumerator(
		at: root,
		includingPropertiesForKeys: [.isDirectoryKey],
		options: [.skipsHiddenFiles, .skipsPackageDescendants]
	) else {
		return []
	}

	for case let item as URL in enumerator {
		let name = item.lastPathComponent
		guard name == target else { continue }
		do {
			let values = try item.resourceValues(forKeys: [.isDirectoryKey])
			let isDirectory = values.isDirectory ?? false
			if includeDirectories ? isDirectory : !isDirectory {
				if let extensionFilter {
					if item.pathExtension == extensionFilter {
						found.append(item)
					}
				}
				else {
					found.append(item)
				}
			}
		}
		catch {
			continue
		}
	}
	return found
}

func extractArchiveTypeHint(from url: URL) -> String? {
	let filename = url.lastPathComponent.lowercased()
	if filename.contains("symbols") {
		return "symbols"
	}
	if filename.contains("debug") {
		return "debug"
	}
	if filename.contains("release") {
		return "release"
	}
	return nil
}

enum HelperRole: String {
	case base = "Base"
	case renderer = "Renderer"
	case gpu = "GPU"
	case plugin = "Plugin"

	static let requiredRoles: [HelperRole] = [.base, .renderer, .gpu]
	static let allRoles: [HelperRole] = [.base, .renderer, .gpu, .plugin]
}

func betterHelperCandidate(_ a: URL, _ b: URL, preferredRoot: URL) -> URL {
	let preferredRootPath = preferredRoot.standardizedFileURL.path
	let aParentPath = a.deletingLastPathComponent().standardizedFileURL.path
	let bParentPath = b.deletingLastPathComponent().standardizedFileURL.path
	let preferredPrefix = preferredRootPath.hasSuffix("/") ? preferredRootPath : preferredRootPath + "/"

	let aInPreferredRoot = aParentPath == preferredRootPath || aParentPath.hasPrefix(preferredPrefix)
	let bInPreferredRoot = bParentPath == preferredRootPath || bParentPath.hasPrefix(preferredPrefix)
	let aScore = aInPreferredRoot ? 0 : 1
	let bScore = bInPreferredRoot ? 0 : 1
	if aScore != bScore {
		return aScore < bScore ? a : b
	}

	if a.path.count != b.path.count {
		return a.path.count < b.path.count ? a : b
	}

	return a.path < b.path ? a : b
}

func expectedHelperBundleName(for role: HelperRole, appExecutableName: String) -> String {
	switch role {
	case .base:
		"\(appExecutableName) Helper.app"
	case .renderer:
		"\(appExecutableName) Helper (Renderer).app"
	case .gpu:
		"\(appExecutableName) Helper (GPU).app"
	case .plugin:
		"\(appExecutableName) Helper (Plugin).app"
	}
}

func expectedHelperExecutableName(for role: HelperRole, appExecutableName: String) -> String {
	switch role {
	case .base:
		"\(appExecutableName) Helper"
	case .renderer:
		"\(appExecutableName) Helper (Renderer)"
	case .gpu:
		"\(appExecutableName) Helper (GPU)"
	case .plugin:
		"\(appExecutableName) Helper (Plugin)"
	}
}

func expectedHelperBundleIdentifier(for role: HelperRole, appBundleIdentifier: String) -> String {
	let base = appBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
	guard !base.isEmpty else { return "" }
	switch role {
	case .base:
		return "\(base).helper"
	case .renderer:
		return "\(base).helper.renderer"
	case .gpu:
		return "\(base).helper.gpu"
	case .plugin:
		return "\(base).helper.plugin"
	}
}

func helperNameFallback(for config: CLIConfig, fallbackExecutableName: String = "Chromium") -> String {
	if let appPath = config.appPath {
		if FileManager.default.fileExists(atPath: appPath.path), let executable = try? bundleExecutableName(in: appPath),
		   !executable.isEmpty {
			return executable
		}
		return appPath.deletingPathExtension().lastPathComponent
	}

	if !config.appScheme.isEmpty {
		return config.appScheme
	}

	return fallbackExecutableName
}

func helperRole(from name: String) -> HelperRole? {
	let lower = name.lowercased()
	guard lower.contains("helper") else {
		return nil
	}
	if lower.contains("(renderer)") {
		return .renderer
	}
	if lower.contains("(gpu)") {
		return .gpu
	}
	if lower.contains("(plugin)") {
		return .plugin
	}
	return .base
}

func discoverHelperBundlesByRole(under root: URL, preferredRoot: URL) throws -> [HelperRole: URL] {
	var helpers = [HelperRole: URL]()
	let fm = FileManager.default
	guard let enumerator = fm.enumerator(
		at: root,
		includingPropertiesForKeys: [.isDirectoryKey],
		options: [.skipsHiddenFiles, .skipsPackageDescendants]
	) else {
		throw RunnerError.missing("Cannot enumerate helper apps under \(root.path)")
	}

	for case let item as URL in enumerator {
		if item.pathExtension != "app" { continue }
		guard let role = helperRole(from: item.lastPathComponent) else { continue }
		if let existing = helpers[role] {
			helpers[role] = betterHelperCandidate(item, existing, preferredRoot: preferredRoot)
		}
		else {
			helpers[role] = item
		}
	}
	return helpers
}

func helperExecutableNameFromInfoPlist(in helperBundle: URL) throws -> String {
	let infoPlist = helperBundle.appendingPathComponent("Contents/Info.plist")
	guard FileManager.default.fileExists(atPath: infoPlist.path) else {
		throw RunnerError.missing("Missing helper Info.plist at \(infoPlist.path)")
	}

	let data = try Data(contentsOf: infoPlist)
	guard
		let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
		let name = plist["CFBundleExecutable"] as? String,
		!name.isEmpty
	else {
		throw RunnerError.missing("CFBundleExecutable missing from \(infoPlist.path)")
	}

	return name
}

func loadHelperInfoPlist(in helperBundle: URL) throws -> (url: URL, plist: [String: Any]) {
	let infoPlist = helperBundle.appendingPathComponent("Contents/Info.plist")
	guard FileManager.default.fileExists(atPath: infoPlist.path) else {
		throw RunnerError.missing("Missing helper Info.plist at \(infoPlist.path)")
	}

	let data = try Data(contentsOf: infoPlist)
	guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
		throw RunnerError.missing("Unable to parse helper Info.plist at \(infoPlist.path)")
	}

	return (infoPlist, plist)
}

func writeHelperInfoPlist(_ plist: [String: Any], to infoPlist: URL) throws {
	let updated = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
	try updated.write(to: infoPlist, options: .atomic)
}

func applyRequiredPrivacyUsageDescriptions(to plist: inout [String: Any]) -> Bool {
	var needsWrite = false
	for key in requiredPrivacyUsageDescriptions.keys.sorted() {
		guard let expectedValue = requiredPrivacyUsageDescriptions[key] else { continue }
		if (plist[key] as? String) != expectedValue {
			plist[key] = expectedValue
			needsWrite = true
		}
	}
	return needsWrite
}

func missingRequiredPrivacyUsageDescriptions(in plist: [String: Any]) -> [String] {
	requiredPrivacyUsageDescriptions.keys.sorted().filter { key in
		guard let expectedValue = requiredPrivacyUsageDescriptions[key] else { return false }
		return (plist[key] as? String) != expectedValue
	}
}

func ensureRequiredPrivacyUsageDescriptions(in helperBundle: URL) throws {
	let loaded = try loadHelperInfoPlist(in: helperBundle)
	let infoPlist = loaded.url
	var plist = loaded.plist
	guard applyRequiredPrivacyUsageDescriptions(to: &plist) else { return }
	try writeHelperInfoPlist(plist, to: infoPlist)
}

func verifyRequiredPrivacyUsageDescriptions(in helperPlist: [String: Any], infoPlist: URL) throws {
	let missingKeys = missingRequiredPrivacyUsageDescriptions(in: helperPlist)
	guard missingKeys.isEmpty else {
		throw RunnerError.missing(
			"missing or unexpected helper privacy usage descriptions in \(infoPlist.path): \(missingKeys.joined(separator: ", "))"
		)
	}
}

func normalizeHelperPrivacyUsageDescriptionsInRelease(
	releaseRoot: URL,
	allowMissingHelpers: Bool
) throws {
	let discovered = try discoverHelperBundlesByRole(under: releaseRoot, preferredRoot: releaseRoot)
	if discovered.isEmpty {
		if allowMissingHelpers {
			print("warning: no helper apps found under \(releaseRoot.path)")
			return
		}
		throw RunnerError.missing("no helper apps found under \(releaseRoot.path)")
	}

	for role in HelperRole.requiredRoles {
		guard let helperBundle = discovered[role] else {
			if allowMissingHelpers {
				print("warning: missing required helper role \(role.rawValue) under \(releaseRoot.path)")
				continue
			}
			throw RunnerError.missing("missing required helper role \(role.rawValue) under \(releaseRoot.path)")
		}
		try ensureRequiredPrivacyUsageDescriptions(in: helperBundle)
	}

	if let pluginBundle = discovered[.plugin] {
		try ensureRequiredPrivacyUsageDescriptions(in: pluginBundle)
	}
}

func verifyHelperPrivacyUsageDescriptionsInRelease(
	releaseRoot: URL,
	allowMissingHelpers: Bool
) throws {
	let discovered = try discoverHelperBundlesByRole(under: releaseRoot, preferredRoot: releaseRoot)
	if discovered.isEmpty {
		if allowMissingHelpers {
			print("warning: no helper apps found under \(releaseRoot.path)")
			return
		}
		throw RunnerError.missing("no helper apps found under \(releaseRoot.path)")
	}

	for role in HelperRole.requiredRoles {
		guard let helperBundle = discovered[role] else {
			if allowMissingHelpers {
				print("warning: missing required helper role \(role.rawValue) under \(releaseRoot.path)")
				continue
			}
			throw RunnerError.missing("missing required helper role \(role.rawValue) under \(releaseRoot.path)")
		}

		let (infoPlist, helperPlist) = try loadHelperInfoPlist(in: helperBundle)
		try verifyRequiredPrivacyUsageDescriptions(in: helperPlist, infoPlist: infoPlist)
	}

	if let pluginBundle = discovered[.plugin] {
		let (infoPlist, helperPlist) = try loadHelperInfoPlist(in: pluginBundle)
		try verifyRequiredPrivacyUsageDescriptions(in: helperPlist, infoPlist: infoPlist)
	}
}

func ensureHelperExecutableName(
	in helperBundle: URL,
	expectedExecutableName: String,
	expectedBundleIdentifier: String? = nil
) throws {
	let binaryDir = helperBundle.appendingPathComponent("Contents/MacOS")
	guard FileManager.default.fileExists(atPath: binaryDir.path) else {
		throw RunnerError.missing("helper bundle has no Contents/MacOS: \(helperBundle.path)")
	}

	let currentExecutableName = try helperExecutableNameFromInfoPlist(in: helperBundle)
	let currentBinary = binaryDir.appendingPathComponent(currentExecutableName)
	guard FileManager.default.fileExists(atPath: currentBinary.path) else {
		throw RunnerError.missing("helper bundle executable missing: \(currentExecutableName) in \(binaryDir.path)")
	}

	let expectedBundleName = helperBundle.deletingPathExtension().lastPathComponent
	let loaded = try loadHelperInfoPlist(in: helperBundle)
	let infoPlist = loaded.url
	var plist = loaded.plist

	let expectedBinary = binaryDir.appendingPathComponent(expectedExecutableName)
	var needsPlistWrite = false
	if currentExecutableName != expectedExecutableName {
		print(
			"Renaming helper executable from \(currentExecutableName) to \(expectedExecutableName) in \(helperBundle.lastPathComponent)"
		)
		if FileManager.default.fileExists(atPath: expectedBinary.path) {
			try removeIfPresent(expectedBinary)
		}
		if currentBinary != expectedBinary {
			try FileManager.default.moveItem(at: currentBinary, to: expectedBinary)
		}
		plist["CFBundleExecutable"] = expectedExecutableName
		needsPlistWrite = true
	}

	if let permissions = (try? FileManager.default
		.attributesOfItem(atPath: expectedBinary.path)[.posixPermissions] as? NSNumber),
		(permissions.uint16Value & 0o111) == 0 {
		try runShell("/bin/chmod", arguments: ["+x", expectedBinary.path])
	}

	if (plist["CFBundleName"] as? String) != expectedBundleName {
		plist["CFBundleName"] = expectedBundleName
		needsPlistWrite = true
	}
	if (plist["CFBundleDisplayName"] as? String) != expectedBundleName {
		plist["CFBundleDisplayName"] = expectedBundleName
		needsPlistWrite = true
	}
	if let expectedBundleIdentifier, !expectedBundleIdentifier.isEmpty {
		if (plist["CFBundleIdentifier"] as? String) != expectedBundleIdentifier {
			plist["CFBundleIdentifier"] = expectedBundleIdentifier
			needsPlistWrite = true
		}
	}
	if applyRequiredPrivacyUsageDescriptions(to: &plist) {
		needsPlistWrite = true
	}

	if needsPlistWrite {
		try writeHelperInfoPlist(plist, to: infoPlist)
	}

	guard FileManager.default.fileExists(atPath: expectedBinary.path) else {
		throw RunnerError.missing("Expected helper executable missing after staging: \(expectedBinary.path)")
	}
}

func resolveExpectedHelperBundleNames(
	under root: URL,
	appExecutableName: String,
	preferredRoot: URL? = nil,
	requireRequiredRoles: Bool = true
) throws -> [HelperRole: URL] {
	var resolved = [HelperRole: URL]()
	let discovered = try discoverHelperBundlesByRole(under: root, preferredRoot: preferredRoot ?? root)

	if discovered.isEmpty {
		if !requireRequiredRoles {
			print("warning: no helper apps found under \(root.path)")
			return resolved
		}
		throw RunnerError.missing("no helper apps found under \(root.path)")
	}

	var named = [String: URL]()
	for item in discovered.values {
		named[item.lastPathComponent.lowercased()] = item
	}

	for role in HelperRole.requiredRoles {
		let expectedName = expectedHelperBundleName(for: role, appExecutableName: appExecutableName)
		if let exact = named[expectedName.lowercased()] {
			resolved[role] = exact
			continue
		}
		if let fallback = discovered[role] {
			resolved[role] = fallback
			print("warning: using non-canonical helper bundle \(fallback.lastPathComponent) for \(role.rawValue)")
			continue
		}
		if !requireRequiredRoles {
			print("warning: optional helper role \(role.rawValue) missing in \(root.path)")
			continue
		}
		throw RunnerError.missing("missing required helper bundle role \(role.rawValue) in \(root.path)")
	}

	if let pluginNamed = named[expectedHelperBundleName(for: .plugin, appExecutableName: appExecutableName).lowercased()] {
		resolved[.plugin] = pluginNamed
	}
	else if let pluginFallback = discovered[.plugin] {
		resolved[.plugin] = pluginFallback
		if pluginFallback.lastPathComponent.lowercased() != expectedHelperBundleName(
			for: .plugin,
			appExecutableName: appExecutableName
		).lowercased() {
			print("warning: using non-canonical plugin helper bundle \(pluginFallback.lastPathComponent)")
		}
	}

	return resolved
}

func frameworkResourceDirectory(in framework: URL) -> URL? {
	let versionsA = framework.appendingPathComponent("Versions/A/Resources")
	let legacyCurrent = framework.appendingPathComponent("Versions/Current/Resources")
	let topLevel = framework.appendingPathComponent("Resources")

	if FileManager.default.fileExists(atPath: versionsA.path) {
		return versionsA
	}
	if FileManager.default.fileExists(atPath: legacyCurrent.path) {
		return legacyCurrent
	}
	if FileManager.default.fileExists(atPath: topLevel.path) {
		return topLevel
	}
	return nil
}

func validateCEFFrameworkResources(_ framework: URL) throws {
	guard let resourceDirectory = frameworkResourceDirectory(in: framework) else {
		throw RunnerError.missing("Could not locate Resources in framework at \(framework.path)")
	}

	let icudtl = resourceDirectory.appendingPathComponent("icudtl.dat")
	guard FileManager.default.fileExists(atPath: icudtl.path) else {
		throw RunnerError.missing("Missing required resource: \(icudtl.path)")
	}

	let topLevelPakItems = try FileManager.default.contentsOfDirectory(atPath: resourceDirectory.path)
		.filter { $0.hasSuffix(".pak") }
	if topLevelPakItems.isEmpty {
		let recursivePakItems = try FileManager.default.subpathsOfDirectory(atPath: resourceDirectory.path)
			.filter { $0.hasSuffix(".pak") }
		guard !recursivePakItems.isEmpty else {
			throw RunnerError.missing("Missing required *.pak files under \(resourceDirectory.path)")
		}
	}

	let localesDir = resourceDirectory.appendingPathComponent("locales")
	if FileManager.default.fileExists(atPath: localesDir.path) {
		let localePaks = try FileManager.default.contentsOfDirectory(atPath: localesDir.path).filter { $0.hasSuffix(".pak") }
		if localePaks.isEmpty {
			throw RunnerError.missing("Missing required locale .pak files in: \(localesDir.path)")
		}
	}
	else {
		print("Warning: locales directory not present (using fallback packaging/runtime resolution): \(localesDir.path)")
	}
}

func ensureFrameworkLocalesIfAvailable(from sourceFramework: URL, to framework: URL) throws {
	guard let destinationResourceDirectory = frameworkResourceDirectory(in: framework) else { return }

	let destinationLocales = destinationResourceDirectory.appendingPathComponent("locales")
	if FileManager.default.fileExists(atPath: destinationLocales.path) {
		return
	}

	let siblingResources = sourceFramework.deletingLastPathComponent().appendingPathComponent("Resources")
	let candidateLocaleSources = [
		siblingResources.appendingPathComponent("locales"),
		sourceFramework.appendingPathComponent("Versions/A/Resources/locales"),
		sourceFramework.appendingPathComponent("Versions/Current/Resources/locales"),
		sourceFramework.appendingPathComponent("Resources/locales"),
	]

	for sourceLocales in candidateLocaleSources {
		if FileManager.default.fileExists(atPath: sourceLocales.path) {
			print("Copying Chromium Embedded Framework locales from \(sourceLocales.path) to \(destinationLocales.path)")
			try copyItem(sourceLocales, to: destinationLocales)
			return
		}
	}
}

func resolveHelperBundlesForSigning(under root: URL, appExecutableName: String) throws -> [URL] {
	let discovered = try resolveExpectedHelperBundleNames(
		under: root,
		appExecutableName: appExecutableName,
		preferredRoot: root,
		requireRequiredRoles: false
	)
	var ordered = [URL]()
	for role in HelperRole.allRoles {
		if let helper = discovered[role] {
			ordered.append(helper)
		}
	}
	return ordered
}

func resolveHelperExecutable(in helperBundle: URL) throws -> URL {
	let binaryDir = helperBundle.appendingPathComponent("Contents/MacOS")
	guard FileManager.default.fileExists(atPath: binaryDir.path) else {
		throw RunnerError.missing("helper bundle has no Contents/MacOS: \(helperBundle.path)")
	}

	let executableName = try helperExecutableNameFromInfoPlist(in: helperBundle)
	let executable = binaryDir.appendingPathComponent(executableName)
	guard FileManager.default.fileExists(atPath: executable.path) else {
		throw RunnerError.missing("helper executable not found at \(executable.path) for bundle \(helperBundle.path)")
	}

	return executable
}

func extractArchive(_ archiveURL: URL, to destination: URL) throws {
	if archiveURL.pathExtension.lowercased() == "zip" {
		print("Extracting zip archive \(archiveURL.lastPathComponent)...")
		try runShell("/usr/bin/unzip", arguments: ["-q", archiveURL.path, "-d", destination.path])
	}
	else {
		print("Extracting archive \(archiveURL.lastPathComponent)...")
		try runShell("/usr/bin/tar", arguments: ["-xf", archiveURL.path, "-C", destination.path])
	}
}

func bundleIdentifier(in app: URL) throws -> String {
	let infoPlist = app.appendingPathComponent("Contents/Info.plist")
	guard FileManager.default.fileExists(atPath: infoPlist.path) else {
		throw RunnerError.missing("missing Info.plist at \(infoPlist.path)")
	}
	let data = try Data(contentsOf: infoPlist)
	let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
	guard
		let dict = plist as? [String: Any],
		let bundleIdentifier = dict["CFBundleIdentifier"] as? String,
		!bundleIdentifier.isEmpty
	else {
		throw RunnerError.missing("CFBundleIdentifier missing from \(infoPlist.path)")
	}
	return bundleIdentifier
}

func ensureHelpersInRelease(
	releaseRoot: URL,
	helperSource: URL,
	appExecutableName: String,
	appBundleIdentifier: String? = nil,
	allowMissingHelpers: Bool
) throws {
	let discovered = try discoverHelperBundlesByRole(under: helperSource, preferredRoot: helperSource)
	for role in HelperRole.requiredRoles {
		guard let source = discovered[role] else {
			if allowMissingHelpers {
				print("warning: missing required helper role \(role.rawValue) under \(helperSource.path)")
				continue
			}
			throw RunnerError.missing("missing required helper role \(role.rawValue) under \(helperSource.path)")
		}

		let destinationName = expectedHelperBundleName(for: role, appExecutableName: appExecutableName)
		let expectedExecutableName = expectedHelperExecutableName(for: role, appExecutableName: appExecutableName)
		let destination = releaseRoot.appendingPathComponent(destinationName)
		if source.lastPathComponent != destinationName {
			print("Copying helper (renamed) \(source.lastPathComponent) -> \(destinationName)")
			try copyItem(source, to: destination)
		}
		else {
			print("Copying helper \(source.lastPathComponent)")
			if source != destination {
				try copyItem(source, to: destination)
			}
		}

		let expectedBundleIdentifier = appBundleIdentifier.flatMap {
			expectedHelperBundleIdentifier(for: role, appBundleIdentifier: $0)
		}
		try ensureHelperExecutableName(
			in: destination,
			expectedExecutableName: expectedExecutableName,
			expectedBundleIdentifier: expectedBundleIdentifier
		)
	}

	if let pluginSource = discovered[.plugin] {
		let destinationName = expectedHelperBundleName(for: .plugin, appExecutableName: appExecutableName)
		let expectedExecutableName = expectedHelperExecutableName(for: .plugin, appExecutableName: appExecutableName)
		let destination = releaseRoot.appendingPathComponent(destinationName)
		if pluginSource.lastPathComponent != destinationName {
			print("Copying optional plugin helper (renamed) \(pluginSource.lastPathComponent) -> \(destinationName)")
			try copyItem(pluginSource, to: destination)
		}
		else if pluginSource != destination {
			try copyItem(pluginSource, to: destination)
		}
		let expectedBundleIdentifier = appBundleIdentifier.flatMap {
			expectedHelperBundleIdentifier(for: .plugin, appBundleIdentifier: $0)
		}
		try ensureHelperExecutableName(
			in: destination,
			expectedExecutableName: expectedExecutableName,
			expectedBundleIdentifier: expectedBundleIdentifier
		)
	}
	else {
		print("warning: optional helper role Plugin not found for \(appExecutableName)")
	}
}

func verifyCEFStaging(
	releaseRoot: URL,
	appExecutableName: String,
	appBundleIdentifier: String?,
	allowMissingHelpers: Bool
) throws {
	let framework = releaseRoot.appendingPathComponent("Chromium Embedded Framework.framework")
	try validateCEFFrameworkResources(framework)
	try verifyHelperPrivacyUsageDescriptionsInRelease(
		releaseRoot: releaseRoot,
		allowMissingHelpers: allowMissingHelpers
	)

	for role in HelperRole.requiredRoles {
		let helperPath = releaseRoot.appendingPathComponent(expectedHelperBundleName(
			for: role,
			appExecutableName: appExecutableName
		))
		guard FileManager.default.fileExists(atPath: helperPath.path) else {
			if allowMissingHelpers {
				continue
			}
			throw RunnerError.missing("missing helper bundle \(helperPath.lastPathComponent)")
		}

		let helperExecutable = helperPath.appendingPathComponent("Contents/MacOS")
		guard FileManager.default.fileExists(atPath: helperExecutable.path) else {
			throw RunnerError.missing("missing helper executable directory in \(helperPath.lastPathComponent)")
		}
		let helperInfo = helperPath.appendingPathComponent("Contents/Info.plist")
		guard FileManager.default.fileExists(atPath: helperInfo.path) else {
			throw RunnerError.missing("missing helper Info.plist in \(helperPath.lastPathComponent)")
		}

		let data = try Data(contentsOf: helperInfo)
		guard let helperPlist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
			throw RunnerError.missing("unable to parse helper Info.plist at \(helperInfo.path)")
		}
		try verifyRequiredPrivacyUsageDescriptions(in: helperPlist, infoPlist: helperInfo)

		guard let executableName = helperPlist["CFBundleExecutable"] as? String, !executableName.isEmpty else {
			throw RunnerError.missing("missing CFBundleExecutable in \(helperInfo.path)")
		}
		let executablePath = helperExecutable.appendingPathComponent(executableName)
		if !FileManager.default.fileExists(atPath: executablePath.path) {
			throw RunnerError.missing("missing helper executable \(executableName) in \(helperPath.lastPathComponent)")
		}

		if let appBundleIdentifier {
			let expectedIdentifier = expectedHelperBundleIdentifier(for: role, appBundleIdentifier: appBundleIdentifier)
			if (helperPlist["CFBundleIdentifier"] as? String) != expectedIdentifier {
				throw RunnerError
					.missing("unexpected helper bundle identifier in \(helperPath.lastPathComponent), expected \(expectedIdentifier)")
			}
		}
	}
}

func normalizeHelpersInRelease(
	releaseRoot: URL,
	appExecutableName: String,
	appBundleIdentifier: String,
	allowMissingHelpers: Bool
) throws {
	for role in HelperRole.requiredRoles {
		let helperPath = releaseRoot.appendingPathComponent(expectedHelperBundleName(
			for: role,
			appExecutableName: appExecutableName
		))
		guard FileManager.default.fileExists(atPath: helperPath.path) else {
			if allowMissingHelpers {
				continue
			}
			throw RunnerError.missing("missing helper bundle \(helperPath.lastPathComponent)")
		}
		let expectedExecutable = expectedHelperExecutableName(for: role, appExecutableName: appExecutableName)
		let expectedIdentifier = expectedHelperBundleIdentifier(for: role, appBundleIdentifier: appBundleIdentifier)
		try ensureHelperExecutableName(
			in: helperPath,
			expectedExecutableName: expectedExecutable,
			expectedBundleIdentifier: expectedIdentifier
		)
	}

	let pluginPath = releaseRoot.appendingPathComponent(expectedHelperBundleName(
		for: .plugin,
		appExecutableName: appExecutableName
	))
	if FileManager.default.fileExists(atPath: pluginPath.path) {
		let expectedExecutable = expectedHelperExecutableName(for: .plugin, appExecutableName: appExecutableName)
		let expectedIdentifier = expectedHelperBundleIdentifier(for: .plugin, appBundleIdentifier: appBundleIdentifier)
		try ensureHelperExecutableName(
			in: pluginPath,
			expectedExecutableName: expectedExecutable,
			expectedBundleIdentifier: expectedIdentifier
		)
	}
}

func copyCEFTopLevelResources(from framework: URL, destination: URL) throws {
	let topLevelSource = framework.deletingLastPathComponent().appendingPathComponent("Resources")
	if FileManager.default.fileExists(atPath: topLevelSource.path) {
		print("Copying selective CEF top-level resources")
		try ensureDirectory(destination)
		let fm = FileManager.default
		for item in try fm.contentsOfDirectory(atPath: topLevelSource.path) where
			item.hasSuffix(".pak") ||
			item == "icudtl.dat" ||
			item == "snapshot_blob.bin" ||
			item == "v8_context_snapshot.bin" ||
			item == "v8_context_snapshot.arm64.bin" ||
			item == "gpu_shader_cache.bin" {
			let sourcePath = topLevelSource.appendingPathComponent(item)
			let destinationPath = destination.appendingPathComponent(item)
			if FileManager.default.fileExists(atPath: sourcePath.path) {
				try copyItem(sourcePath, to: destinationPath)
			}
		}
		return
	}

	guard let frameworkResources = frameworkResourceDirectory(in: framework) else {
		throw RunnerError.missing("Missing Resources directory in framework: \(framework.path)")
	}

	try ensureDirectory(destination)
	let fm = FileManager.default
	for item in try fm.contentsOfDirectory(atPath: frameworkResources.path) where
		item.hasSuffix(".pak") ||
		item == "icudtl.dat" ||
		item == "snapshot_blob.bin" ||
		item == "v8_context_snapshot.bin" ||
		item == "v8_context_snapshot.arm64.bin" ||
		item == "gpu_shader_cache.bin" {
		let sourcePath = frameworkResources.appendingPathComponent(item)
		let destinationPath = destination.appendingPathComponent(item)
		if FileManager.default.fileExists(atPath: sourcePath.path) {
			try copyItem(sourcePath, to: destinationPath)
		}
	}
}

func copyCEFHeaders(from sourceRoot: URL, vendorRoot: URL) throws {
	let candidates: [URL] = [
		sourceRoot.appendingPathComponent("include"),
		sourceRoot.deletingLastPathComponent().appendingPathComponent("include"),
	]
	let fileManager = FileManager.default
	guard let sourceInclude = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
		throw RunnerError
			.missing(
				"CEF include directory missing at \(sourceRoot.path)/include or \(sourceRoot.deletingLastPathComponent().path)/include"
			)
	}
	let targetInclude = vendorRoot.appendingPathComponent("include")
	try copyItem(sourceInclude, to: targetInclude)
}

func copyFrameworkIntoRelease(_ source: URL, to releaseRoot: URL) throws -> URL {
	let frameworkSource = source
	let frameworkDestination = releaseRoot.appendingPathComponent("Chromium Embedded Framework.framework")
	try copyItem(frameworkSource, to: frameworkDestination)
	try ensureFrameworkLocalesIfAvailable(from: frameworkSource, to: frameworkDestination)
	try validateCEFFrameworkResources(frameworkDestination)
	return frameworkDestination
}

func fetchAndExtractCEF(
	config: CLIConfig,
	appBundleIdentifier: String? = nil,
	appExecutableName: String? = nil,
	allowMissingHelpers: Bool
) throws -> URL {
	if config.skipFetch {
		let vendorRelease = config.repoRoot.appendingPathComponent("Vendor/CEF/Release")
		guard FileManager.default.fileExists(atPath: vendorRelease.path) else {
			throw RunnerError.missing("missing Vendor/CEF/Release and --skip-fetch was used")
		}
		return vendorRelease
	}

	if !allowMissingHelpers, config.cefClientArchiveURL == nil, config.cefClientArchivePath == nil {
		let modeLabel = config.strictMode ? "strict mode" : "Release"
		throw RunnerError
			.missing(
				"\(modeLabel) requires a CEF client archive for helpers. Provide --cef-client-archive-url or --cef-client-archive-path."
			)
	}

	let tempRoot = config.repoRoot.appendingPathComponent("tmp")
	try ensureDirectory(tempRoot)
	let tempDir = tempRoot.appendingPathComponent("cef_packager_\(UUID().uuidString)")
	try ensureDirectory(tempDir)

	let archiveURL: URL
	if let localArchive = config.cefArchivePath {
		try ensureGitLFSArchiveAvailable(localArchive, repoRoot: config.repoRoot, label: "CEF runtime archive")
		archiveURL = localArchive
	}
	else if let remote = config.cefArchiveURL {
		try ensureGitLFSArchiveAvailable(remote, repoRoot: config.repoRoot, label: "CEF runtime archive URL")
		let ext = remote.pathExtension.isEmpty ? "zip" : remote.pathExtension
		let downloaded = tempDir.appendingPathComponent("cef.\(ext)")
		print("Downloading CEF archive from \(remote.absoluteString)")
		try runShell("/usr/bin/curl", arguments: ["-L", "-f", remote.absoluteString, "-o", downloaded.path])
		archiveURL = downloaded
	}
	else {
		throw RunnerError.missing("CEF artifact missing. Set --cef-archive-url, --cef-archive-path, or --skip-fetch")
	}

	let extracted = tempDir.appendingPathComponent("extracted")
	try ensureDirectory(extracted)
	try extractArchive(archiveURL, to: extracted)

	let candidates = findFiles(
		named: "Chromium Embedded Framework.framework",
		under: extracted,
		includeDirectories: true
	)
	guard let frameworkPath = candidates.first else {
		if let archiveType = extractArchiveTypeHint(from: archiveURL) {
			switch archiveType {
			case "symbols":
				throw RunnerError
					.missing(
						"couldn't find Chromium Embedded Framework.framework inside extracted artifact; archive appears to be a symbols build. Use a _release[_arm64].tar.bz2 runtime archive instead of _release_symbols.tar.bz2"
					)
			case "debug":
				throw RunnerError
					.missing(
						"couldn't find Chromium Embedded Framework.framework inside extracted artifact; use a release runtime archive for packaging"
					)
			default:
				break
			}
		}
		throw RunnerError.missing("couldn't find Chromium Embedded Framework.framework inside extracted artifact")
	}

	let sourceRoot = frameworkPath.deletingLastPathComponent()
	let releaseRoot = config.repoRoot.appendingPathComponent("Vendor/CEF/Release")
	try ensureDirectory(releaseRoot.deletingLastPathComponent())
	try removeIfPresent(releaseRoot)
	try ensureDirectory(releaseRoot)

	print("Staging framework into \(releaseRoot.path)")
	_ = try copyFrameworkIntoRelease(frameworkPath, to: releaseRoot)
	try copyCEFHeaders(from: sourceRoot, vendorRoot: config.repoRoot.appendingPathComponent("Vendor/CEF"))

	let executableName = appExecutableName ??
		(config.appScheme.isEmpty ? helperNameFallback(for: config) : config.appScheme)
	var helperSource = sourceRoot

	func helperSourceFromClientArchive(at clientExtracted: URL) throws -> URL? {
		let cefClientApps = findFiles(
			named: "cefclient.app",
			under: clientExtracted,
			includeDirectories: true,
			extensionFilter: "app"
		)
		if let cefClientApp = cefClientApps.first {
			return cefClientApp.appendingPathComponent("Contents/Frameworks")
		}

		let discovered = try discoverHelperBundlesByRole(under: clientExtracted, preferredRoot: clientExtracted)
		if discovered.isEmpty {
			return nil
		}

		let preferred =
			discovered[.base] ??
			discovered[.renderer] ??
			discovered[.gpu] ??
			discovered[.plugin]
		guard let preferred else { return nil }

		let fallbackRoot = preferred.deletingLastPathComponent()
		print(
			"Could not find cefclient.app in client archive; discovered helper bundles under \(clientExtracted.path), using \(fallbackRoot.path)"
		)
		return fallbackRoot
	}

	if let clientArchivePath = config.cefClientArchivePath {
		print("Using local CEF client archive for helper extraction: \(clientArchivePath.path)")
		try ensureGitLFSArchiveAvailable(clientArchivePath, repoRoot: config.repoRoot, label: "CEF client archive")
		let clientArchiveURL = clientArchivePath
		let clientExtracted = tempDir.appendingPathComponent("client_extracted")
		try ensureDirectory(clientExtracted)
		try extractArchive(clientArchiveURL, to: clientExtracted)
		if let resolved = try helperSourceFromClientArchive(at: clientExtracted) {
			helperSource = resolved
		}
		else if allowMissingHelpers {
			print(
				"warning: CEF client archive did not contain cefclient.app or helper bundles at \(clientArchiveURL.lastPathComponent)"
			)
		}
		else {
			throw RunnerError
				.missing("CEF client archive missing cefclient.app or helper bundles at \(clientArchiveURL.lastPathComponent)")
		}
	}
	else if let clientArchiveURL = config.cefClientArchiveURL {
		try ensureGitLFSArchiveAvailable(clientArchiveURL, repoRoot: config.repoRoot, label: "CEF client archive URL")
		print("Downloading and extracting CEF client archive from \(clientArchiveURL.absoluteString)")
		let ext = clientArchiveURL.pathExtension.isEmpty ? "zip" : clientArchiveURL.pathExtension
		let downloaded = tempDir.appendingPathComponent("cef_client.\(ext)")
		try runShell("/usr/bin/curl", arguments: ["-L", "-f", clientArchiveURL.absoluteString, "-o", downloaded.path])
		let clientExtracted = tempDir.appendingPathComponent("client_extracted")
		try ensureDirectory(clientExtracted)
		try extractArchive(downloaded, to: clientExtracted)
		if let resolved = try helperSourceFromClientArchive(at: clientExtracted) {
			helperSource = resolved
		}
		else if allowMissingHelpers {
			print("warning: cefclient.app not found in downloaded archive")
		}
		else {
			throw RunnerError
				.missing("CEF client archive missing cefclient.app or helper bundles at \(clientArchiveURL.absoluteString)")
		}
	}

	try ensureHelpersInRelease(
		releaseRoot: releaseRoot,
		helperSource: helperSource,
		appExecutableName: executableName,
		appBundleIdentifier: appBundleIdentifier,
		allowMissingHelpers: allowMissingHelpers
	)

	// Release/CEFResourcesStaging is intentional packaging staging; runtime resources are copied by BundleCEFRuntime.sh.
	try copyCEFTopLevelResources(
		from: frameworkPath,
		destination: releaseRoot.appendingPathComponent("CEFResourcesStaging")
	)
	try verifyCEFStaging(
		releaseRoot: releaseRoot,
		appExecutableName: executableName,
		appBundleIdentifier: appBundleIdentifier,
		allowMissingHelpers: allowMissingHelpers
	)
	print("CEF payload staged to \(releaseRoot.path)")
	return releaseRoot
}

func runCEFBuilderIfRequested(_ config: CLIConfig) throws -> (runtime: URL, client: URL?)? {
	guard config.cefSourceBuild else { return nil }
	guard !config.skipFetch else { return nil }
	guard let buildSpecPath = config.cefBuildSpecPath else {
		throw RunnerError.missing("--cef-build-spec is required when --cef-source-build is set")
	}
	if !config.cefSourceForce {
		if config.cefArchivePath != nil || config.cefClientArchivePath != nil {
			return nil
		}
	}

	let defaultBuilderPath = config.repoRoot.appendingPathComponent("Tools/CEFBuilder/main.swift").standardizedFileURL
	let fallbackBuilderPath = packagerSourceRoot().appendingPathComponent("Tools/CEFBuilder/main.swift")
		.standardizedFileURL
	let builderPath: URL
	if FileManager.default.fileExists(atPath: defaultBuilderPath.path) {
		builderPath = defaultBuilderPath
	}
	else if FileManager.default.fileExists(atPath: fallbackBuilderPath.path) {
		builderPath = fallbackBuilderPath
	}
	else {
		throw RunnerError.missing("CEFBuilder script not found at \(defaultBuilderPath.path) or \(fallbackBuilderPath.path)")
	}

	let outputDir = config.cefSourceArtifactsDir ?? config.repoRoot.appendingPathComponent("Vendor/CEF/Artifacts")
	try ensureDirectory(outputDir)

	var args = ["--spec", buildSpecPath.path, "--output-dir", outputDir.path]
	if let workDir = config.cefSourceWorkDir {
		args += ["--work-dir", workDir.path]
	}
	if config.verbose {
		args.append("--verbose")
	}
	if config.cefSourceForce {
		args.append("--force")
	}

	let builderOutput = try runShellSilent(
		"/usr/bin/swift",
		arguments: [builderPath.path] + args,
		workingDirectory: config.repoRoot
	)
	guard let jsonText = extractFirstJSONObject(builderOutput),
	      let data = jsonText.data(using: .utf8),
	      let obj = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
		throw RunnerError.missing("CEFBuilder did not return JSON paths. Output:\n\(builderOutput)")
	}

	guard let runtimePath = obj["runtime"] else {
		throw RunnerError.missing("CEFBuilder JSON missing runtime path")
	}
	let runtimeURL = URL(fileURLWithPath: runtimePath).standardizedFileURL
	guard [".tar.bz2", ".zip"].contains(where: { runtimeURL.path.lowercased().hasSuffix($0) }) else {
		throw RunnerError.invalidArgument("CEFBuilder runtime artifact must be .tar.bz2 or .zip: \(runtimeURL.path)")
	}
	guard FileManager.default.fileExists(atPath: runtimeURL.path) else {
		throw RunnerError.missing("CEFBuilder runtime artifact missing at \(runtimeURL.path)")
	}

	let clientURL = obj["client"].map { URL(fileURLWithPath: $0).standardizedFileURL }
	if let clientURL {
		guard [".tar.bz2", ".zip"].contains(where: { clientURL.path.lowercased().hasSuffix($0) }) else {
			throw RunnerError.invalidArgument("CEFBuilder client artifact must be .tar.bz2 or .zip: \(clientURL.path)")
		}
		guard FileManager.default.fileExists(atPath: clientURL.path) else {
			throw RunnerError.missing("CEFBuilder client artifact missing at \(clientURL.path)")
		}
	}

	return (
		runtime: runtimeURL,
		client: clientURL
	)
}

func stageFromExistingRelease(config: CLIConfig) throws -> URL {
	let releaseRoot = config.repoRoot.appendingPathComponent("Vendor/CEF/Release")
	guard FileManager.default.fileExists(atPath: releaseRoot.path) else {
		throw RunnerError.missing("missing \(releaseRoot.path). Provide --skip-fetch false and a valid archive URL/path.")
	}

	let framework = releaseRoot.appendingPathComponent("Chromium Embedded Framework.framework")
	guard FileManager.default.fileExists(atPath: framework.path) else {
		throw RunnerError.missing("missing framework at \(framework.path)")
	}
	let vendorHeaders = config.repoRoot.appendingPathComponent("Vendor/CEF/include")
	let cefApiHash = vendorHeaders.appendingPathComponent("cef_api_hash.h")
	guard FileManager.default.fileExists(atPath: cefApiHash.path) else {
		throw RunnerError
			.missing(
				"missing CEF headers at \(vendorHeaders.path). Re-run CEFPackager with --skip-fetch false to repopulate headers."
			)
	}
	try validateCEFFrameworkResources(framework)
	try normalizeHelperPrivacyUsageDescriptionsInRelease(
		releaseRoot: releaseRoot,
		allowMissingHelpers: allowMissingHelpers(for: config)
	)
	try verifyHelperPrivacyUsageDescriptionsInRelease(
		releaseRoot: releaseRoot,
		allowMissingHelpers: allowMissingHelpers(for: config)
	)
	return releaseRoot
}

func bundleExecutableName(in app: URL) throws -> String {
	let infoPlist = app.appendingPathComponent("Contents/Info.plist")
	guard FileManager.default.fileExists(atPath: infoPlist.path) else {
		throw RunnerError.missing("missing Info.plist at \(infoPlist.path)")
	}
	let data = try Data(contentsOf: infoPlist)
	let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
	guard
		let dict = plist as? [String: Any],
		let name = dict["CFBundleExecutable"] as? String,
		!name.isEmpty
	else {
		throw RunnerError.missing("CFBundleExecutable missing from \(infoPlist.path)")
	}
	return name
}

func packagedCEFRuntimePath(_ repoRoot: URL) -> URL {
	repoRoot.appendingPathComponent("Vendor/CEF/Release/ChromiumEmbeddedRuntime.framework")
}

func packageCEFRuntime(
	repoRoot: URL,
	appExecutableName: String,
	signIdentity: String?,
	allowMissingHelpers: Bool
) throws {
	let packagedRepoRoot = resolveRepoRoot(from: repoRoot)
	let scriptPath = packagedRepoRoot.appendingPathComponent("BundleCEFRuntime.sh")
		.standardizedFileURL
	let fallbackScriptPath = packagerSourceRoot().appendingPathComponent("BundleCEFRuntime.sh")
		.standardizedFileURL
	let resolvedScriptPath: URL
	if FileManager.default.fileExists(atPath: scriptPath.path) {
		resolvedScriptPath = scriptPath
	}
	else if FileManager.default.fileExists(atPath: fallbackScriptPath.path) {
		resolvedScriptPath = fallbackScriptPath
	}
	else {
		throw RunnerError.missing("BundleCEFRuntime.sh missing at \(scriptPath.path)")
	}
	var env = ProcessInfo.processInfo.environment
	env["PROJECT_DIR"] = packagedRepoRoot.path
	let cefStagingDir = packagedRepoRoot.appendingPathComponent("Vendor/CEF/Release")
	env["CEF_STAGING_DIR"] = cefStagingDir.path
	env["CEF_RESOURCES_STAGING_DIR"] = cefStagingDir.appendingPathComponent("CEFResourcesStaging").path
	env["CEF_HELPERS_STAGING_DIR"] = cefStagingDir.path
	env["CEF_RUNTIME_MODE"] = "package"
	env["CEF_RUNTIME_PACKAGE_DIR"] = packagedCEFRuntimePath(packagedRepoRoot).path
	env["CEF_RUNTIME_APP_EXECUTABLE_NAME"] = appExecutableName
	if let signIdentity {
		env["CODE_SIGN_IDENTITY"] = signIdentity
	}
	env["CEF_ALLOW_MISSING_HELPERS"] = allowMissingHelpers ? "1" : "0"
	print("Packaging CEF runtime artifact to: \(packagedCEFRuntimePath(packagedRepoRoot).path)")
	try runShell(resolvedScriptPath.path, arguments: [], workingDirectory: packagedRepoRoot, environment: env)
}

func runVerify(_ appPath: URL, repoRoot: URL, allowMissingHelpers: Bool) {
	let script = repoRoot.appendingPathComponent("scripts/verify_runtime.sh")
	guard FileManager.default.fileExists(atPath: script.path) else {
		print("verification script missing at \(script.path)")
		return
	}
	var env = ProcessInfo.processInfo.environment
	env["CEF_ALLOW_MISSING_HELPERS"] = allowMissingHelpers ? "1" : "0"
	_ = try? runShell(script.path, arguments: [appPath.path], workingDirectory: repoRoot, environment: env)
}

func notaryProfileID(_ config: CLIConfig) -> String? {
	if let profile = config.notaryProfile?.trimmingCharacters(in: .whitespacesAndNewlines), !profile.isEmpty {
		return profile
	}
	return nil
}

func extractNotaryRequestID(from output: String) -> String? {
	do {
		let pattern = #"\b(?i)request\s+id[:\s]+([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})"#
		let regex = try NSRegularExpression(pattern: pattern)
		let range = NSRange(output.startIndex..<output.endIndex, in: output)
		if let match = regex.firstMatch(in: output, options: [], range: range) {
			if match.numberOfRanges >= 2,
			   let idRange = Range(match.range(at: 1), in: output) {
				return String(output[idRange])
			}
		}
	}
	catch {
		return nil
	}

	if let fallbackStart = output.range(of: "request id:", options: [.caseInsensitive]) {
		let start = fallbackStart.upperBound
		let tail = output[start...]
		let token = tail.split { $0.isWhitespace || $0 == "," }.first
		if let token {
			let value = String(token).trimmingCharacters(in: .whitespacesAndNewlines)
			return value.isEmpty ? nil : value
		}
	}
	return nil
}

func notarizeLogArguments(for requestID: String, config: CLIConfig) -> [String] {
	var args = ["notarytool", "log", requestID]
	if let profile = notaryProfileID(config) {
		args += ["--keychain-profile", profile]
		return args
	}
	guard
		let teamID = config.teamID,
		let appleID = config.appleID,
		let notaryPassword = config.notaryPassword
	else {
		return args
	}
	args += [
		"--apple-id",
		appleID,
		"--password",
		notaryPassword,
		"--team-id",
		teamID,
	]
	return args
}

func signBundle(_ path: String, identity: String, entitlementsPath: URL?) throws {
	var args = ["--force", "--timestamp", "--options", "runtime", "--sign", identity]
	if let entitlementsPath, FileManager.default.fileExists(atPath: entitlementsPath.path) {
		args += ["--entitlements", entitlementsPath.path]
	}
	args.append(path)
	try runShell("/usr/bin/codesign", arguments: args)
}

func verifyCodeSignature(_ path: URL, deep: Bool = false) throws {
	var arguments = ["--verify", "--strict", "--verbose=2"]
	if deep { arguments.append("--deep") }
	arguments.append(path.path)
	try runShell("/usr/bin/codesign", arguments: arguments)
}

func isMachOBinary(_ path: String) -> Bool {
	guard let output = try? runShell("/usr/bin/file", arguments: [path], captureOutput: true) else {
		return false
	}
	return output.contains("Mach-O")
}

func signMachOBinaries(under root: URL, identity: String, entitlementsPath: URL? = nil) throws {
	let fm = FileManager.default
	guard let enumerator = fm.enumerator(
		at: root,
		includingPropertiesForKeys: [.isRegularFileKey],
		options: [.skipsHiddenFiles]
	) else { return }

	for case let fileURL as URL in enumerator {
		let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
		guard resourceValues.isRegularFile == true, resourceValues.isSymbolicLink != true else { continue }
		let path = fileURL.path
		if path.contains("/.dSYM/") {
			continue
		}
		if path.hasSuffix(".dSYM") {
			continue
		}
		if path.contains("/Resources/") {
			continue
		}
		let lower = path.lowercased()
		if lower.hasSuffix(".map") || lower.hasSuffix(".plist") {
			continue
		}
		if isMachOBinary(path) {
			print("Signing framework binary artifact: \(fileURL.path)")
			try signBundle(fileURL.path, identity: identity, entitlementsPath: entitlementsPath)
		}
	}
}

func existingEntitlements(_ path: URL?) -> URL? {
	guard let path else { return nil }
	return FileManager.default.fileExists(atPath: path.path) ? path : nil
}

func signFrameworkAndHelpers(appPath: URL, signIdentity: String, repoRoot: URL) throws {
	let frameworksDir = appPath.appendingPathComponent("Contents/Frameworks")
	let framework = frameworksDir.appendingPathComponent("Chromium Embedded Framework.framework")
	guard FileManager.default.fileExists(atPath: framework.path) else {
		throw RunnerError.missing("missing framework at \(framework.path)")
	}

	let appExecutableName = try bundleExecutableName(in: appPath)
	let executable = appPath
		.appendingPathComponent("Contents")
		.appendingPathComponent("MacOS")
		.appendingPathComponent(appExecutableName)

	let appEntitlements = existingEntitlements(repoRoot.appendingPathComponent("scripts/entitlements/app.plist"))
		?? existingEntitlements(repoRoot.appendingPathComponent("scripts/entitlements.plist"))
	let helperEntitlements = existingEntitlements(repoRoot.appendingPathComponent("scripts/entitlements/helper.plist"))
	let helperRendererEntitlements = existingEntitlements(repoRoot
		.appendingPathComponent("scripts/entitlements/helper_renderer.plist"))
	let helperGPUEntitlements = existingEntitlements(repoRoot
		.appendingPathComponent("scripts/entitlements/helper_gpu.plist"))
	let helperPluginEntitlements = existingEntitlements(repoRoot
		.appendingPathComponent("scripts/entitlements/helper_plugin.plist"))

	print("Signing framework Mach-O payload")
	let frameworkPayloadRoot = framework.appendingPathComponent("Versions/A")
	if FileManager.default.fileExists(atPath: frameworkPayloadRoot.path) {
		try signMachOBinaries(under: frameworkPayloadRoot, identity: signIdentity)
	}

	print("Signing framework bundle")
	try signBundle(framework.path, identity: signIdentity, entitlementsPath: nil)
	print("Verifying framework signature (strict)")
	try verifyCodeSignature(framework)
	if ProcessInfo.processInfo.environment["VERIFY_DEEP_CODESIGN"] == "1" {
		print("Verifying framework signature (deep)")
		try verifyCodeSignature(framework, deep: true)
	}

	var helperApps = HelperRole.requiredRoles.map {
		frameworksDir.appendingPathComponent(expectedHelperBundleName(for: $0, appExecutableName: appExecutableName))
	}
	let pluginPath = frameworksDir.appendingPathComponent(expectedHelperBundleName(
		for: .plugin,
		appExecutableName: appExecutableName
	))
	if FileManager.default.fileExists(atPath: pluginPath.path) {
		helperApps.append(pluginPath)
	}

	for helper in helperApps {
		guard FileManager.default.fileExists(atPath: helper.path) else {
			throw RunnerError.missing("missing helper bundle \(helper.lastPathComponent) in \(frameworksDir.path)")
		}
		let name = helper.lastPathComponent
		let role = helperRole(from: name)
		let entitlements: URL? = switch role {
		case .some(.renderer):
			helperRendererEntitlements
		case .some(.gpu):
			helperGPUEntitlements
		case .some(.plugin):
			helperPluginEntitlements
		default:
			helperEntitlements
		}
		let helperExecutable = try resolveHelperExecutable(in: helper)

		print("Signing helper executable: \(helperExecutable.path)")
		try signBundle(helperExecutable.path, identity: signIdentity, entitlementsPath: entitlements)

		print("Signing helper bundle: \(name)")
		try signBundle(helper.path, identity: signIdentity, entitlementsPath: nil)
		print("Verifying helper signature (strict): \(name)")
		try verifyCodeSignature(helper)
		if ProcessInfo.processInfo.environment["VERIFY_DEEP_CODESIGN"] == "1" {
			print("Verifying helper signature (deep): \(name)")
			try verifyCodeSignature(helper, deep: true)
		}
	}

	print("Signing app executable")
	if FileManager.default.fileExists(atPath: executable.path) {
		try signBundle(executable.path, identity: signIdentity, entitlementsPath: appEntitlements)
	}

	print("Signing app bundle")
	try signBundle(appPath.path, identity: signIdentity, entitlementsPath: nil)
}

func notarize(_ appPath: URL, config: CLIConfig) throws {
	let dateFormatter = DateFormatter()
	dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
	let timestamp = dateFormatter.string(from: Date())
	let zipName = "\(appPath.deletingPathExtension().lastPathComponent)-CEF-\(timestamp).zip"
	let zipPath = appPath.deletingLastPathComponent().appendingPathComponent(zipName)

	print("Creating notarization archive \(zipPath.path)")
	try runShell("/usr/bin/ditto", arguments: ["-c", "-k", "--keepParent", appPath.path, zipPath.path])

	let submitArguments: [String]
	if let profile = notaryProfileID(config) {
		print("Submitting notarization using keychain profile \(profile)")
		submitArguments = [
			"notarytool",
			"submit",
			zipPath.path,
			"--keychain-profile",
			profile,
			"--wait",
		]
	}
	else {
		guard let teamID = config.teamID else {
			throw RunnerError.missing("TEAM_ID required when using --apple-id/--notary-password")
		}
		guard let appleID = config.appleID, let notaryPassword = config.notaryPassword else {
			throw RunnerError.missing("APPLE_ID and NOTARY_PASSWORD required when --notary-profile is not provided")
		}
		print("Submitting notarization request")
		submitArguments = [
			"notarytool",
			"submit",
			zipPath.path,
			"--apple-id",
			appleID,
			"--password",
			notaryPassword,
			"--team-id",
			teamID,
			"--wait",
		]
	}

	do {
		_ = try runShell("/usr/bin/xcrun", arguments: submitArguments, captureOutput: true)
	}
	catch CEFShared.ShellError.commandFailed(let command, let code, let output) {
		print("Notary submit failed with exit code \(code)")
		if let requestID = extractNotaryRequestID(from: output) {
			print("Request ID: \(requestID)")
			print("Fetching notary log...")
			_ = try? runShell("/usr/bin/xcrun", arguments: notarizeLogArguments(for: requestID, config: config))
		}
		if output.isEmpty == false {
			print(output)
		}
		throw RunnerError.missing("Notary submit failed with command \(command) code \(code)\n\(output)")
	}

	print("Stapling notarization ticket")
	try runShell("/usr/bin/xcrun", arguments: ["stapler", "staple", appPath.path])
	print("Validating stapled ticket")
	try runShell("/usr/bin/xcrun", arguments: ["stapler", "validate", appPath.path])
	print("Running spctl assessment")
	try runShell("/usr/sbin/spctl", arguments: ["-a", "--assess", "--type", "execute", "--verbose", appPath.path])
}

func verifyCodesign(_ appPath: URL) {
	print("Verifying codesign (non-deep)")
	_ = try? runShell("/usr/bin/codesign", arguments: ["--verify", "--strict", "--verbose=2", appPath.path])
	let runDeep = ProcessInfo.processInfo.environment["VERIFY_DEEP_CODESIGN"] == "1"
	if runDeep {
		print("Verifying codesign (deep)")
		_ = try? runShell("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", "--verbose=2", appPath.path])
	}
	_ = try? runShell("/usr/sbin/spctl", arguments: ["-a", "-vvv", appPath.path])
}

func buildApp(scheme: String, configuration: String, repoRoot: URL) throws -> URL {
	let productDir = repoRoot.appendingPathComponent("build/Products/\(configuration)")
	let command = [
		"xcodebuild",
		"-project", repoRoot.appendingPathComponent("Navigator.xcodeproj").path,
		"-scheme", scheme,
		"-configuration", configuration,
		"CONFIGURATION_BUILD_DIR=" + productDir.path,
	]
	print("Building \(scheme)...")
	try runShell("/usr/bin/xcrun", arguments: command, workingDirectory: repoRoot)
	let appPath = productDir.appendingPathComponent("\(scheme).app")
	guard FileManager.default.fileExists(atPath: appPath.path) else {
		throw RunnerError.missing("App build did not produce \(appPath.path)")
	}
	return appPath
}

func allowMissingHelpers(for config: CLIConfig) -> Bool {
	if config.strictMode {
		return false
	}
	return config.appConfiguration.lowercased() != "release"
}

do {
	let args = Set(CommandLine.arguments.dropFirst())
	if args.contains("--help") || args.contains("-h") {
		printUsage()
		exit(0)
	}
	var config = try CLIConfig.make()
	verboseLoggingEnabled = config.verbose

	if config.mode == .all || config.mode == .fetch || config.mode == .stage,
	   let built = try runCEFBuilderIfRequested(config) {
		config.cefArchivePath = built.runtime
		config.cefClientArchivePath = built.client
		config.cefArchiveURL = nil
		config.cefClientArchiveURL = nil
	}

	print("CEF Packager mode: \(config.mode.rawValue)")
	verboseLog(
		"Parsed config: mode=\(config.mode.rawValue), repoRoot=\(config.repoRoot.path), skipFetch=\(config.skipFetch), shouldSign=\(config.shouldSign), shouldNotarize=\(config.shouldNotarize), skipSign=\(!config.shouldSign), signIdentityProvided=\(config.signIdentity != nil)"
	)
	let fm = FileManager.default

	let allowMissing = allowMissingHelpers(for: config)

	switch config.mode {
	case .all:
		var resolvedAppPath = config.appPath
		if config.buildApp {
			resolvedAppPath = try buildApp(
				scheme: config.appScheme,
				configuration: config.appConfiguration,
				repoRoot: config.repoRoot
			)
		}
		let hasResolvedAppPath = resolvedAppPath.flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil }

		var appExecutableName = config.appScheme.isEmpty ? helperNameFallback(for: config) : config.appScheme
		var appBundleIdentifier: String? = nil
		if let appPath = hasResolvedAppPath {
			if let executable = try? bundleExecutableName(in: appPath), !executable.isEmpty {
				appExecutableName = executable
			}
			appBundleIdentifier = try? bundleIdentifier(in: appPath)
		}
		let releaseRoot: URL = if config.skipFetch {
			try stageFromExistingRelease(config: config)
		}
		else {
			try fetchAndExtractCEF(
				config: config,
				appBundleIdentifier: appBundleIdentifier,
				appExecutableName: appExecutableName,
				allowMissingHelpers: allowMissing
			)
		}
		if let appPath = hasResolvedAppPath {
			if let resolvedAppBundleIdentifier = try? bundleIdentifier(in: appPath) {
				try normalizeHelpersInRelease(
					releaseRoot: releaseRoot,
					appExecutableName: appExecutableName,
					appBundleIdentifier: resolvedAppBundleIdentifier,
					allowMissingHelpers: allowMissing
				)
				try verifyCEFStaging(
					releaseRoot: releaseRoot,
					appExecutableName: appExecutableName,
					appBundleIdentifier: resolvedAppBundleIdentifier,
					allowMissingHelpers: allowMissing
				)
			}
		}
		else if resolvedAppPath != nil {
			print("App bundle missing at \(resolvedAppPath!.path). Skipping app-specific helper normalization and verification.")
		}
		else {
			print("No --app-bundle-path provided. Packaging runtime artifact only.")
		}
		try packageCEFRuntime(
			repoRoot: config.repoRoot,
			appExecutableName: appExecutableName,
			signIdentity: config.shouldSign ? config.signIdentity : nil,
			allowMissingHelpers: allowMissing
		)
		if let appPath = hasResolvedAppPath {
			runVerify(appPath, repoRoot: config.repoRoot, allowMissingHelpers: allowMissing)
			if config.shouldSign, let signIdentity = config.signIdentity {
				try signFrameworkAndHelpers(appPath: appPath, signIdentity: signIdentity, repoRoot: config.repoRoot)
			}
			verifyCodesign(appPath)
			if config.shouldNotarize {
				try notarize(appPath, config: config)
			}
		}
		else {
			print("No --app-bundle-path provided. Notary/sign verification are app-target only.")
		}
	case .fetch, .stage:
		var fetchAppBundleIdentifier: String? = nil
		if let appPath = config.appPath {
			fetchAppBundleIdentifier = try? bundleIdentifier(in: appPath)
		}

		var fetchAppExecutableName: String? = nil
		if let appPath = config.appPath,
		   FileManager.default.fileExists(atPath: appPath.path),
		   let executable = try? bundleExecutableName(in: appPath),
		   !executable.isEmpty {
			fetchAppExecutableName = executable
		}

		if config.skipFetch {
			_ = try stageFromExistingRelease(config: config)
		}
		else {
			_ = try fetchAndExtractCEF(
				config: config,
				appBundleIdentifier: fetchAppBundleIdentifier,
				appExecutableName: fetchAppExecutableName,
				allowMissingHelpers: allowMissing
			)
		}
	case .package:
		_ = try stageFromExistingRelease(config: config)
		var appExecutableName = config.appScheme.isEmpty ? helperNameFallback(for: config) : config.appScheme
		if let appPath = config.appPath,
		   FileManager.default.fileExists(atPath: appPath.path),
		   let executable = try? bundleExecutableName(in: appPath),
		   !executable.isEmpty {
			appExecutableName = executable
		}

		if let appPath = config.appPath,
		   FileManager.default.fileExists(atPath: appPath.path),
		   let appBundleIdentifier = try? bundleIdentifier(in: appPath) {
			let vendorRelease = config.repoRoot.appendingPathComponent("Vendor/CEF/Release")
			let baseHelperPath = vendorRelease.appendingPathComponent(
				expectedHelperBundleName(for: .base, appExecutableName: appExecutableName)
			)
			if !allowMissing || FileManager.default.fileExists(atPath: baseHelperPath.path) {
				try normalizeHelpersInRelease(
					releaseRoot: vendorRelease,
					appExecutableName: appExecutableName,
					appBundleIdentifier: appBundleIdentifier,
					allowMissingHelpers: allowMissing
				)
			}
		}

		try packageCEFRuntime(
			repoRoot: config.repoRoot,
			appExecutableName: appExecutableName,
			signIdentity: config.shouldSign ? config.signIdentity : nil,
			allowMissingHelpers: allowMissing
		)

		if let appPath = config.appPath {
			runVerify(appPath, repoRoot: config.repoRoot, allowMissingHelpers: allowMissing)
		}
	case .sign:
		guard let appPath = config.appPath else {
			throw RunnerError.missing("--app-bundle-path is required for --mode sign")
		}
		guard let signIdentity = config.signIdentity else {
			throw RunnerError.missing("--sign-identity is required for --mode sign")
		}
		try signFrameworkAndHelpers(appPath: appPath, signIdentity: signIdentity, repoRoot: config.repoRoot)
		verifyCodesign(appPath)
	case .notarize:
		guard let appPath = config.appPath else {
			throw RunnerError.missing("--app-bundle-path is required for --mode notarize")
		}
		try notarize(appPath, config: config)
	}
}
catch {
	fputs("[CEFPackager] \(error)\n", stderr)
	exit(1)
}
