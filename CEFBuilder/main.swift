#!/usr/bin/env swift

import CEFShared
import CryptoKit
import Foundation

// MARK: - Models

struct BuildSpec: Codable {
	struct Cef: Codable {
		var channel: String?
		var branch: String?
		var commit: String?
	}

	struct Chromium: Codable {
		var commit: String?
	}

	struct DepotTools: Codable {
		var commit: String?
	}

	struct GN: Codable {
		var defines: [String] = []
		var extraArgs: [String] = []
		var buildTargets: [String] = []

		private enum CodingKeys: String, CodingKey {
			case defines
			case extraArgs
			case buildTargets
		}

		init() {
			self.defines = []
			self.extraArgs = []
			self.buildTargets = []
		}

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			defines = try container.decodeIfPresent([String].self, forKey: .defines) ?? []
			extraArgs = try container.decodeIfPresent([String].self, forKey: .extraArgs) ?? []
			buildTargets = try container.decodeIfPresent([String].self, forKey: .buildTargets) ?? []
		}
	}

	struct Export: Codable {
		var includeClient: Bool = true
		var tarFormat: String = "tar.bz2"
	}

	var name: String
	var platform: String
	var arch: String
	var buildType: String
	var cef: Cef
	var chromium: Chromium = .init(commit: nil)
	var depotTools: DepotTools = .init(commit: nil)
	var gn: GN = .init()
	var export: Export = .init()
}

struct BuilderConfig {
	let specPath: URL
	let workDir: URL
	let outputDir: URL
	let cacheDir: URL
	let verbose: Bool
	let forceRebuild: Bool
	let repoRoot: URL
}

enum BuilderError: Error, CustomStringConvertible {
	case invalid(String)
	case missing(String)
	case shell(String, Int, String)
	case invalidArchive(String)

	var description: String {
		switch self {
		case .invalid(let message):
			return message
		case .missing(let message):
			return message
		case .shell(let command, let code, let output):
			return "command failed (\(code)): \(command)\n\(output)"
		case .invalidArchive(let message):
			return "invalid archive: \(message)"
		}
	}
}

// MARK: - Utilities

func log(_ message: String) {
	FileHandle.standardError.write(Data("\(message)\n".utf8))
}

func log(_ message: String, _ verbose: Bool) {
	if verbose {
		log(message)
	}
}

func resolveWidevineStorageIDKey(
	defines: [String],
	environment: [String: String],
	verbose: Bool
) throws -> [String] {
	let widevineEnabled = defines.contains("enable_widevine=true")
	guard widevineEnabled else { return defines }

	let placeholderValue = "\"__SET_ME__\""
	let prefix = "alternate_cdm_storage_id_key="
	let secretKey = environment["MIUM_WIDEVINE_STORAGE_ID_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
	let rawSecret = secretKey.flatMap { value in
		value.isEmpty ? nil : value
	}

	return try defines.map { define in
		guard define.hasPrefix(prefix) else {
			return define
		}

		let value = String(define.dropFirst(prefix.count))
		let isPlaceholder = value == placeholderValue || value == "__SET_ME__"
		guard isPlaceholder else {
			return define
		}

		guard let key = rawSecret else {
			throw BuilderError.invalid(
				"""
				MIUM_WIDEVINE_STORAGE_ID_KEY is required when enable_widevine=true and
				alternate_cdm_storage_id_key is set to \"__SET_ME__\". Set a non-empty
				secret in MIUM_WIDEVINE_STORAGE_ID_KEY and retry.
				"""
			)
		}

		let escaped = key
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")
		log("Replacing alternate_cdm_storage_id_key placeholder with MIUM_WIDEVINE_STORAGE_ID_KEY", verbose)
		return "alternate_cdm_storage_id_key=\"\(escaped)\""
	}
}

func isAutomateLog(_ url: URL) -> Bool {
	let name = url.lastPathComponent.lowercased()
	return name.hasPrefix("build-") && name.hasSuffix(".log")
}

func mostRecentAutomateLog(in directory: URL) throws -> URL? {
	let fm = FileManager.default
	let entries = try fm.contentsOfDirectory(
		at: directory,
		includingPropertiesForKeys: [.contentModificationDateKey],
		options: [.skipsHiddenFiles]
	)
	let logs = entries.filter(isAutomateLog)
	guard !logs.isEmpty else { return nil }

	return logs.max(by: { lhs, rhs in
		let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ??
			.distantPast
		let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ??
			.distantPast
		return lhsDate < rhsDate
	})
}

func shellCommandLine(_ command: String, _ arguments: [String]) -> String {
	let displayArguments = arguments.map { arg in
		arg.contains(" ") ? "\"\(arg)\"" : arg
	}
	return "\(command) \(displayArguments.joined(separator: " "))"
}

func runShell(
	_ command: String,
	_ arguments: [String],
	cwd: URL? = nil,
	environment: [String: String] = [:],
	verbose: Bool,
	captureOutput: Bool? = nil,
	phaseLabel: String? = nil,
	logTiming: Bool = true
) throws -> String {
	let shouldCaptureOutput = captureOutput ?? !verbose
	if let phaseLabel {
		log("  [shell] \(phaseLabel)", verbose)
	}
	let commandLine = shellCommandLine(command, arguments)
	if verbose {
		log("  [shell] command: \(commandLine)", verbose)
	}
	return try BuilderShell.run(
		command,
		arguments,
		cwd: cwd,
		environment: environment,
		captureOutput: shouldCaptureOutput,
		verbose: verbose,
		logCommandToStdErrWhenNotCapturingOutput: false,
		streamOutput: verbose,
		logTiming: logTiming
	)
}

func looksLikeGoogleSourceRateLimitError(_ output: String) -> Bool {
	let lower = output.lowercased()
	return lower.contains("resource_exhausted") ||
		lower.contains("short term server-time rate limit exceeded") ||
		lower.contains("rate limit") ||
		lower.contains("too many requests") ||
		lower.contains(" 429")
}

func needsChromiumHistoryRepair(_ output: String) -> Bool {
	let lower = output.lowercased()
	return lower.contains("current chromium checkout with --no-chromium-history is incorrect") ||
		lower.contains("add --force-clean or --force-update")
}

func removeMatchingChildren(
	at directory: URL,
	prefix: String,
	verbose: Bool
) throws {
	guard FileManager.default.fileExists(atPath: directory.path) else {
		return
	}
	let children = try FileManager.default.contentsOfDirectory(atPath: directory.path)
	for child in children where child.hasPrefix(prefix) {
		let url = directory.appendingPathComponent(child)
		log("Removing stale path: \(url.path)", verbose)
		try removeIfPresent(url)
	}
}

func removeStaleOpenscreenBuildtoolsArtifacts(downloadRoot: URL, verbose: Bool) throws {
	let chromiumRoot = downloadRoot.appendingPathComponent("chromium")
	let exactBuildtools = chromiumRoot.appendingPathComponent("src/third_party/openscreen/src/buildtools")
	let gclientBuildtoolsRoot = chromiumRoot.appendingPathComponent("src/third_party/openscreen/src")
	let badScmRoot = chromiumRoot.appendingPathComponent("_bad_scm/src/third_party/openscreen/src")

	log("Cleaning potentially partial openscreen/buildtools checkouts in \(downloadRoot.path)", verbose)
	try removeIfPresent(exactBuildtools)
	try removeMatchingChildren(at: gclientBuildtoolsRoot, prefix: "_gclient_buildtools_", verbose: verbose)
	try removeMatchingChildren(at: badScmRoot, prefix: "buildtools", verbose: verbose)
}

func runAutomateGit(
	automateScript: URL,
	cefCheckout: URL,
	downloadRoot: URL,
	buildEnv: [String: String],
	args: [String],
	verbose: Bool
) throws -> String {
	let maxAttempts = 3
	var attempt = 1
	var delaySeconds: UInt32 = 30
	var currentArgs = args
	while true {
		do {
			return try runShell(
				"/usr/bin/python3",
				currentArgs,
				cwd: cefCheckout,
				environment: buildEnv,
				verbose: verbose,
				captureOutput: true,
				phaseLabel: "automate-git.py invocation"
			)
		}
		catch {
			let output: String = switch error {
			case let shellError as ShellError:
				if case .commandFailed(_, _, let captured) = shellError {
					captured
				}
				else {
					String(describing: shellError)
				}
			default:
				String(describing: error)
			}
			let isRateLimitError = looksLikeGoogleSourceRateLimitError(output)
			let needsHistoryRepair = needsChromiumHistoryRepair(output)
			guard isRateLimitError || needsHistoryRepair,
			      attempt < maxAttempts else {
				throw error
			}
			if needsHistoryRepair, !currentArgs.contains("--force-update") {
				log(
					"automate-git.py failed with Chromium no-history checkout mismatch. Retrying with --force-update on attempt \(attempt + 1).",
					verbose
				)
				currentArgs.append("--force-update")
				attempt += 1
				continue
			}
			else if attempt == 1, currentArgs.contains("--no-chromium-history"), !currentArgs.contains("--force-update") {
				log(
					"automate-git.py failed on first attempt with no clear recovery signal; retrying with --force-update as a Chromium checkout consistency fallback on attempt \(attempt + 1).",
					verbose
				)
				currentArgs.append("--force-update")
				attempt += 1
				continue
			}
			else if isRateLimitError {
				let failureDescription = "automate-git.py failed with Google Source rate limit signal on attempt \(attempt)."
				log("\(failureDescription) Retrying with stale state cleanup after \(delaySeconds)s.", verbose)
				try removeStaleOpenscreenBuildtoolsArtifacts(downloadRoot: downloadRoot, verbose: verbose)
				attempt += 1
				sleep(delaySeconds)
				delaySeconds = min(delaySeconds * 2, 240)
				continue
			}

			throw error
		}
	}
}

func withBuildPhase<T>(
	_ index: Int,
	_ total: Int,
	_ name: String,
	verbose: Bool,
	_ block: () throws -> T
) rethrows -> T {
	let phasePrefix = "[phase \(index)/\(total)]"
	let start = Date()
	log("\(phasePrefix) START: \(name)", verbose)
	let result = try block()
	let elapsed = Date().timeIntervalSince(start)
	log(String(format: "\(phasePrefix) DONE: \(name) (%.2fs)", elapsed), verbose)
	return result
}

typealias BuilderShell = CEFShared.Shell

func ensureDirectory(_ url: URL) throws {
	try CEFShared.ensureDirectory(url)
}

func removeIfPresent(_ url: URL) throws {
	try CEFShared.removeIfPresent(url)
}

func sha256Hex(_ data: Data) -> String {
	let digest = SHA256.hash(data: data)
	return digest.map { String(format: "%02x", $0) }.joined()
}

func readSpec(_ path: URL, verbose: Bool) throws -> BuildSpec {
	log("Reading build spec from \(path.path)", verbose)
	let data = try Data(contentsOf: path)
	let spec = try JSONDecoder().decode(BuildSpec.self, from: data)
	log("Loaded spec '\(spec.name)' (\(spec.platform)/\(spec.arch))", verbose)
	return spec
}

func copyItem(_ source: URL, to destination: URL, verbose: Bool = false) throws {
	log("Copying item: \(source.path) -> \(destination.path)", verbose)
	try copyFile(source, to: destination, verbose: verbose)
}

func copyFile(_ source: URL, to destination: URL, verbose: Bool = false) throws {
	log("Copying file: \(source.path) -> \(destination.path)", verbose)
	try removeIfPresent(destination)
	try ensureDirectory(destination.deletingLastPathComponent())
	_ = try runShell(
		"/usr/bin/ditto",
		[source.path, destination.path],
		verbose: verbose,
		phaseLabel: "copy file"
	)
}

func copyTree(_ source: URL, to destination: URL, verbose: Bool) throws {
	log("Copying tree: \(source.path) -> \(destination.path)", verbose)
	try removeIfPresent(destination)
	try ensureDirectory(destination.deletingLastPathComponent())
	_ = try runShell(
		"/usr/bin/ditto",
		[source.path, destination.path],
		verbose: verbose,
		phaseLabel: "copy tree"
	)
}

func normalizeArchiveSuffix(_ value: String) -> String {
	let normalized = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
	switch normalized {
	case "zip":
		return "zip"
	case "tar.bz2", "tbz2", "tb2":
		return "tar.bz2"
	default:
		return "tar.bz2"
	}
}

func makeArchive(from folder: URL, output: URL, format: String, verbose: Bool) throws {
	log("Creating \(format) archive: \(folder.path) -> \(output.path)", verbose)
	try removeIfPresent(output)
	try ensureDirectory(output.deletingLastPathComponent())
	let normalized = normalizeArchiveSuffix(format)
	if normalized == "zip" {
		_ = try runShell(
			"/usr/bin/ditto",
			["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, output.path],
			verbose: verbose,
			phaseLabel: "create zip archive"
		)
		return
	}

	_ = try runShell(
		"/usr/bin/tar",
		["-cjf", output.path, "-C", folder.path, "."],
		verbose: verbose,
		phaseLabel: "create tar archive"
	)
	log("Archive created: \(output.path)", verbose)
}

func findFirst(named name: String, under root: URL, isDir: Bool) throws -> URL? {
	let fm = FileManager.default
	guard let enumerator = fm.enumerator(
		at: root,
		includingPropertiesForKeys: [.isDirectoryKey],
		options: [.skipsHiddenFiles]
	) else {
		return nil
	}
	for case let item as URL in enumerator {
		if item.lastPathComponent != name {
			continue
		}
		let values = try item.resourceValues(forKeys: [.isDirectoryKey])
		if (values.isDirectory ?? false) == isDir {
			return item
		}
	}
	return nil
}

func findFirstKnown(named name: String, under root: URL, isDir: Bool) throws -> URL? {
	let fm = FileManager.default
	let prefixes: [[String]] = [
		[],
		["chromium", "src", "out", "Release"],
		["chromium", "src", "out", "Debug"],
		["src", "out", "Release"],
		["src", "out", "Debug"],
		["out", "Release"],
		["out", "Debug"],
	]

	for prefix in prefixes {
		var candidate = root
		for component in prefix {
			candidate = candidate.appendingPathComponent(component)
		}
		candidate = candidate.appendingPathComponent(name)
		var isDirectory: ObjCBool = false
		if fm.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue == isDir {
			return candidate
		}
	}

	return try findFirst(named: name, under: root, isDir: isDir)
}

func findCandidateHelpers(under root: URL, verbose: Bool) throws -> [URL] {
	var helpers: [URL] = []
	let fm = FileManager.default
	guard let enumerator = fm.enumerator(
		at: root,
		includingPropertiesForKeys: [.isDirectoryKey],
		options: [.skipsHiddenFiles, .skipsPackageDescendants]
	) else {
		return []
	}
	for case let item as URL in enumerator {
		let values = try item.resourceValues(forKeys: [.isDirectoryKey])
		if values.isDirectory != true {
			continue
		}
		guard item.pathExtension == "app" else {
			continue
		}
		let name = item.lastPathComponent
		if name.contains("Helper") || name == "cefclient.app" {
			helpers.append(item)
		}
		else {
			log("Skipping non-helper app candidate: \(item.path)", verbose)
		}
	}
	return helpers
}

func archiveContains(_ archive: URL, required fragments: [String], verbose: Bool) throws -> Bool {
	let command: String
	let arguments: [String]
	if archive.path.lowercased().hasSuffix(".zip") {
		command = "/usr/bin/unzip"
		arguments = ["-l", archive.path]
	}
	else {
		command = "/usr/bin/tar"
		arguments = ["-tf", archive.path]
	}

	let listing = try runShell(
		command,
		arguments,
		verbose: verbose,
		captureOutput: true,
		phaseLabel: "archive inspection"
	)
	return fragments.allSatisfy { fragment in
		listing.contains(fragment)
	}
}

func ensureValidTar(_ archive: URL, required fragments: [String], kind: String, verbose: Bool) throws {
	log("Validating \(kind) archive at \(archive.path)", verbose)
	guard FileManager.default.fileExists(atPath: archive.path) else {
		throw BuilderError.missing("\(kind) archive missing at \(archive.path)")
	}
	guard try archiveContains(archive, required: fragments, verbose: verbose) else {
		throw BuilderError.invalidArchive("failed to validate \(kind) archive at \(archive.path)")
	}
	log("Archive validation passed: \(kind) -> \(archive.path)", verbose)
}

func ensureValidTarAny(_ archive: URL, required fragments: [String], kind: String, verbose: Bool) throws {
	log("Validating any-of fragment for \(kind) archive at \(archive.path)", verbose)
	let command: String
	let arguments: [String]
	if archive.path.lowercased().hasSuffix(".zip") {
		command = "/usr/bin/unzip"
		arguments = ["-l", archive.path]
	}
	else {
		command = "/usr/bin/tar"
		arguments = ["-tf", archive.path]
	}
	let listing = try runShell(
		command,
		arguments,
		verbose: verbose,
		captureOutput: true,
		phaseLabel: "archive inspection (any-of)"
	)
	let hasAny = fragments.contains { listing.contains($0) }
	guard hasAny else {
		throw BuilderError.invalidArchive("failed to validate \(kind) archive at \(archive.path)")
	}
	log("Archive validation passed (any-of): \(kind) -> \(archive.path)", verbose)
}

func ensureDepotTools(at depotToolsDir: URL, commit: String?, verbose: Bool) throws {
	if FileManager.default.fileExists(atPath: depotToolsDir.appendingPathComponent(".git").path) {
		log("Reusing cached depot_tools at \(depotToolsDir.path)", verbose)
		_ = try? runShell(
			"/usr/bin/git",
			["-C", depotToolsDir.path, "fetch", "--quiet"],
			verbose: verbose,
			phaseLabel: "depot_tools fetch (cached)"
		)
		if let commit, !commit.isEmpty {
			_ = try runShell(
				"/usr/bin/git",
				["-C", depotToolsDir.path, "checkout", commit],
				verbose: verbose,
				phaseLabel: "depot_tools checkout \(commit)"
			)
		}
		log("depot_tools prepared at \(depotToolsDir.path)", verbose)
		return
	}

	log("Cloning depot_tools to \(depotToolsDir.path)", verbose)
	try ensureDirectory(depotToolsDir.deletingLastPathComponent())
	_ = try runShell(
		"/usr/bin/git",
		["clone", "https://chromium.googlesource.com/chromium/tools/depot_tools.git", depotToolsDir.path],
		verbose: verbose,
		phaseLabel: "depot_tools clone"
	)
	if let commit, !commit.isEmpty {
		log("Checking out depot_tools commit '\(commit)'", verbose)
		_ = try runShell(
			"/usr/bin/git",
			["-C", depotToolsDir.path, "checkout", commit],
			verbose: verbose,
			phaseLabel: "depot_tools checkout \(commit)"
		)
	}
	log("depot_tools prepared at \(depotToolsDir.path)", verbose)
}

func ensureCefCheckout(at cefDir: URL, commit: String?, verbose: Bool) throws -> Bool {
	if FileManager.default.fileExists(atPath: cefDir.appendingPathComponent(".git").path) {
		log("Reusing cached CEF checkout at \(cefDir.path)", verbose)
		_ = try runShell(
			"/usr/bin/git",
			["-C", cefDir.path, "fetch", "--all", "--prune"],
			verbose: verbose,
			phaseLabel: "cef fetch (cached)"
		)
		if let commit, !commit.isEmpty {
			_ = try runShell(
				"/usr/bin/git",
				["-C", cefDir.path, "checkout", commit],
				verbose: verbose,
				phaseLabel: "cef checkout \(commit)"
			)
		}
		log("CEF checkout prepared at \(cefDir.path)", verbose)
		return true
	}

	log("Cloning Chromium Embedded Framework source", verbose)
	try ensureDirectory(cefDir.deletingLastPathComponent())
	_ = try runShell(
		"/usr/bin/git",
		["clone", "https://github.com/chromiumembedded/cef.git", cefDir.path],
		verbose: verbose,
		phaseLabel: "cef clone"
	)
	if let commit, !commit.isEmpty {
		_ = try runShell(
			"/usr/bin/git",
			["-C", cefDir.path, "checkout", commit],
			verbose: verbose,
			phaseLabel: "cef checkout \(commit)"
		)
	}
	log("CEF checkout prepared at \(cefDir.path)", verbose)
	return false
}

func ensureChromiumCommit(in cefDir: URL, commit: String?, verbose: Bool) throws {
	guard let commit, !commit.isEmpty else { return }

	let candidates = [
		cefDir.appendingPathComponent("chromium/src"),
		cefDir.appendingPathComponent("src"),
	]
	for root in candidates {
		log("Checking Chromium checkout candidate: \(root.path)", verbose)
		guard FileManager.default.fileExists(atPath: root.path),
		      FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) else {
			continue
		}

		log("Applying chromium commit \(commit) at \(root.path)", verbose)
		_ = try? runShell(
			"/usr/bin/git",
			["-C", root.path, "fetch", "--all", "--prune"],
			verbose: verbose,
			phaseLabel: "chromium commit fetch"
		)
		_ = try runShell(
			"/usr/bin/git",
			["-C", root.path, "checkout", commit],
			verbose: verbose,
			phaseLabel: "chromium checkout \(commit)"
		)
		log("Chromium commit \(commit) checked out at \(root.path)", verbose)
		return
	}

	log("Chromium commit was requested but no chromium src checkout directory was found", verbose)
}

func normalizeToolVersion(_ output: String) -> String {
	let firstLine = output
		.split(separator: "\n", omittingEmptySubsequences: true)
		.first
		.flatMap { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
		.flatMap { $0.isEmpty ? nil : $0 }

	guard let line = firstLine else { return "swift-unknown" }
	for piece in line.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
		let token = String(piece).trimmingCharacters(in: .whitespacesAndNewlines)
		if token.first?.isNumber == true, token.contains(".") {
			let numericPrefix = token.prefix { ch in
				ch.isNumber || ch == "."
			}
			if !numericPrefix.isEmpty {
				return String(numericPrefix)
			}
		}
	}

	return line
}

func verifyExpectedBranding(in frameworkRoot: URL, verbose: Bool) {
	let frameworkBinary = frameworkRoot
		.appendingPathComponent("Chromium Embedded Framework.framework/Chromium Embedded Framework")
	guard FileManager.default.fileExists(atPath: frameworkBinary.path) else { return }

	guard let strings = try? runShell(
		"/usr/bin/strings",
		[frameworkBinary.path],
		verbose: verbose,
		captureOutput: true,
		phaseLabel: "verify branding strings",
		logTiming: false
	),
		strings.contains("Chrome") else {
		log("warning: framework strings did not contain expected branding hints; verify GN_DEFINES were applied")
		return
	}
}

func runtimeArchiveName(for spec: BuildSpec) -> String {
	let suffix = normalizeArchiveSuffix(spec.export.tarFormat)
	let archSuffix = spec.arch.lowercased() == "arm64" ? "macosarm64" : "macosx64"
	return "cef_binary_\(spec.name)_\(archSuffix).\(suffix)"
}

func clientArchiveName(for spec: BuildSpec) -> String {
	let suffix = normalizeArchiveSuffix(spec.export.tarFormat)
	let archSuffix = spec.arch.lowercased() == "arm64" ? "macosarm64" : "macosx64"
	return "cef_binary_\(spec.name)_\(archSuffix)_client.\(suffix)"
}

func buildAndExportArtifacts(config: BuilderConfig, spec: BuildSpec) throws -> (runtime: URL, client: URL?) {
	log(
		"[build] Starting build for spec '\(spec.name)' (platform=\(spec.platform), arch=\(spec.arch), buildType=\(spec.buildType))",
		config.verbose
	)
	let encoder = JSONEncoder()
	encoder.outputFormatting = [.sortedKeys]
	let specData = try encoder.encode(spec)
	let specHash = sha256Hex(specData)
	let toolVersion = normalizeToolVersion(
		(try? runShell(
			"/usr/bin/swift",
			["--version"],
			verbose: false,
			captureOutput: true,
			phaseLabel: "swift version"
		)) ?? "swift-unknown"
	)
	let cacheInput = "\(specHash)-\(toolVersion)".data(using: .utf8) ?? Data()
	let cacheKey = sha256Hex(cacheInput)
	let cacheRoot = config.cacheDir.appendingPathComponent(cacheKey)
	let runtimeCachePath = cacheRoot.appendingPathComponent(runtimeArchiveName(for: spec))
	let clientCachePath = cacheRoot.appendingPathComponent(clientArchiveName(for: spec))
	log("Cache key: \(cacheKey)", config.verbose)
	log("Cache root: \(cacheRoot.path)", config.verbose)
	log("Runtime cache path: \(runtimeCachePath.path)", config.verbose)
	log("Client cache path: \(clientCachePath.path)", config.verbose)

	let runtimeOutputPath = config.outputDir.appendingPathComponent(runtimeArchiveName(for: spec))
	let clientOutputPath = config.outputDir.appendingPathComponent(clientArchiveName(for: spec))
	log("Runtime output path: \(runtimeOutputPath.path)", config.verbose)
	log("Client output path: \(clientOutputPath.path)", config.verbose)

	if !config.forceRebuild,
	   FileManager.default.fileExists(atPath: runtimeCachePath.path),
	   spec.export.includeClient == false || FileManager.default.fileExists(atPath: clientCachePath.path) {
		log("Cache hit. Copying artifacts from \(cacheRoot.path)", config.verbose)
		try ensureValidTar(
			runtimeCachePath,
			required: ["Chromium Embedded Framework.framework/"],
			kind: "cached runtime",
			verbose: config.verbose
		)
		if spec.export.includeClient {
			let clientRequired = ["cefclient.app/", "Chromium Helper.app/", "Chromium Helper (Renderer).app/"]
			try ensureValidTarAny(clientCachePath, required: clientRequired, kind: "cached client", verbose: config.verbose)
		}

		try copyItem(runtimeCachePath, to: runtimeOutputPath, verbose: config.verbose)
		var clientOutput: URL?
		if spec.export.includeClient {
			try copyItem(clientCachePath, to: clientOutputPath, verbose: config.verbose)
			clientOutput = clientOutputPath
		}
		log("Returning cached artifacts from previous build", config.verbose)
		return (runtime: runtimeOutputPath, client: clientOutput)
	}
	log("Cache miss or force rebuild requested; executing full build path", config.verbose)
	let totalPhases = 5
	log("Full build will execute \(totalPhases) phases", config.verbose)

	let depotToolsDir = config.workDir.appendingPathComponent("depot_tools")
	let cefCheckout = config.workDir.appendingPathComponent("cef")
	let downloadRoot = config.workDir.appendingPathComponent("download")
	let exportRoot = config.workDir.appendingPathComponent("export/\(spec.name)")
	log(
		"Work dirs: workDir=\(config.workDir.path), depotTools=\(depotToolsDir.path), cef=\(cefCheckout.path), download=\(downloadRoot.path), export=\(exportRoot.path)",
		config.verbose
	)

	if config.forceRebuild {
		log("Force rebuild is enabled", config.verbose)
	}
	try withBuildPhase(1, totalPhases, "Resolve toolchain and source checkout", verbose: config.verbose) {
		try removeIfPresent(exportRoot)
		if config.forceRebuild {
			log("Removing download cache at \(downloadRoot.path)", config.verbose)
			try? removeIfPresent(downloadRoot)
		}
		try ensureDirectory(downloadRoot)
		try ensureDirectory(exportRoot)
		try ensureDirectory(config.outputDir)
		try ensureDirectory(config.cacheDir)

		try ensureDepotTools(at: depotToolsDir, commit: spec.depotTools.commit, verbose: config.verbose)
		_ = try ensureCefCheckout(at: cefCheckout, commit: spec.cef.commit, verbose: config.verbose)
		try ensureChromiumCommit(in: cefCheckout, commit: spec.chromium.commit, verbose: config.verbose)
	}

	var buildEnv = ProcessInfo.processInfo.environment
	let depotToolsPath = depotToolsDir.path
	let currentPath = buildEnv["PATH"] ?? ""
	buildEnv["PATH"] = "\(depotToolsPath):\(currentPath)"
	let resolvedDefines = try resolveWidevineStorageIDKey(
		defines: spec.gn.defines,
		environment: buildEnv,
		verbose: config.verbose
	)
	let gnDefines = resolvedDefines.joined(separator: " ")
	let redactedGNDefines = resolvedDefines.map { define in
		define.hasPrefix("alternate_cdm_storage_id_key=") ? "alternate_cdm_storage_id_key=***REDACTED***" : define
	}.joined(separator: " ")
	log("GN_DEFINES=\(redactedGNDefines)", config.verbose)
	if !gnDefines.isEmpty {
		buildEnv["GN_DEFINES"] = gnDefines
	}
	if let nodePath = buildEnv["NODE_PATH"], !nodePath.isEmpty {
		log("Inherited NODE_PATH=\(nodePath)", config.verbose)
	}
	log("Effective PATH set for build:\n\(buildEnv["PATH"] ?? "<unset>")", config.verbose)

	let resolveAutomateScript = [
		cefCheckout.appendingPathComponent("tools/automate/automate-git.py"),
		cefCheckout.appendingPathComponent("automate/automate-git.py"),
	].first(where: { FileManager.default.fileExists(atPath: $0.path) })
	guard let automateScript = resolveAutomateScript else {
		throw BuilderError.missing(
			"""
			Missing automate-git.py in CEF checkout at:
			\(cefCheckout.appendingPathComponent("tools/automate/automate-git.py").path)
			\(cefCheckout.appendingPathComponent("automate/automate-git.py").path)
			"""
		)
	}
	log("Using automate script: \(automateScript.path)", config.verbose)
	let previousAutomateLog = try mostRecentAutomateLog(in: downloadRoot)

	let buildType = spec.buildType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
	var args: [String] = [
		automateScript.path,
		"--download-dir=\(downloadRoot.path)",
		"--no-distrib",
	]
	switch buildType {
	case "release":
		args.append("--no-debug-build")
	case "debug":
		args.append("--no-release-build")
	case "both", "":
		break
	default:
		throw BuilderError.invalid("Unsupported buildType '\(spec.buildType)'. Expected Release, Debug, or Both.")
	}
	let buildTargetArgs = spec.gn.buildTargets.compactMap { rawTarget -> String? in
		let target = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
		if target.isEmpty { return nil }
		if target.hasPrefix("--build-target=") {
			return target
		}
		return "--build-target=\(target)"
	}
	let hasExplicitBuildTarget = !buildTargetArgs.isEmpty ||
		spec.gn.extraArgs.contains(where: { $0.hasPrefix("--build-target=") })
	args += hasExplicitBuildTarget ? buildTargetArgs : ["--build-target=cefclient"]
	if spec.arch.lowercased() == "arm64" {
		args.append("--arm64-build")
	}
	let cefCheckoutURL = (try? runShell(
		"/usr/bin/git",
		["-C", cefCheckout.path, "config", "--get", "remote.origin.url"],
		verbose: config.verbose,
		captureOutput: true,
		phaseLabel: "read cef checkout origin URL"
	).trimmingCharacters(in: .whitespacesAndNewlines))?.trimmingCharacters(in: .whitespacesAndNewlines)
	if let cefCheckoutURL, !cefCheckoutURL.isEmpty {
		args.append("--url=\(cefCheckoutURL)")
	}
	if let commit = spec.cef.commit, !commit.isEmpty {
		args.append("--checkout=\(commit)")
	}
	let chromiumCheckoutOverride = spec.chromium.commit?.trimmingCharacters(in: .whitespacesAndNewlines)
	if let chromiumCheckoutOverride, !chromiumCheckoutOverride.isEmpty {
		if chromiumCheckoutOverride.starts(with: "refs/") {
			args.append("--chromium-checkout=\(chromiumCheckoutOverride)")
		}
		else {
			log(
				"Skipping Chromium override '\(chromiumCheckoutOverride)' because automate expects a refs/<...> value (for example, refs/tags/145.0.7632.117) in --chromium-checkout.",
				config.verbose
			)
		}
	}
	log(
		"Automate pinning: cefCheckoutURL=\(cefCheckoutURL ?? "<none>"), cefCommit=\(spec.cef.commit ?? "<none>"), chromiumCommit=\(spec.chromium.commit ?? "<none>")",
		config.verbose
	)
	log("Build target args: \(buildTargetArgs.joined(separator: ", "))", config.verbose)
	if let branch = spec.cef.branch, !branch.isEmpty {
		let normalizedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		if normalizedBranch == "master" || normalizedBranch == "trunk" {
			args.append("--branch=\(normalizedBranch)")
			log("Using branch argument: \(normalizedBranch)", config.verbose)
		}
		else if let branchInt = Int(normalizedBranch) {
			if branchInt >= 5060 {
				args.append("--branch=\(branchInt)")
				log("Using branch argument: \(branchInt)", config.verbose)
			}
			else {
				log("Ignoring legacy cef.branch \(branch) (minimum supported is 5060). Using default branch.", config.verbose)
			}
		}
		else {
			log("Ignoring invalid cef.branch \(branch). Using default branch.", config.verbose)
		}
	}
	if let channel = spec.cef.channel, !channel.isEmpty {
		log("Ignoring unsupported cef.channel value: \(channel)", config.verbose)
	}
	args += spec.gn.extraArgs
	if !args.contains(where: { $0 == "--verbose-build" || $0.hasPrefix("--verbose-build=") }) {
		args.append("--verbose-build")
	}
	if !args.contains("--no-chromium-history") {
		args.append("--no-chromium-history")
	}
	if !args.contains(where: { $0 == "--build-log-file" || $0.hasPrefix("--build-log-file=") }) {
		args.append("--build-log-file")
	}
	log("Automate args: \(args.map { String($0) }.joined(separator: " "))", config.verbose)
	log("Automate log will be written into: \(downloadRoot.path)", config.verbose)

	log("Running automate-git.py", config.verbose)
	try withBuildPhase(2, totalPhases, "Run automate-git.py (sync/build)", verbose: config.verbose) {
		_ = try runAutomateGit(
			automateScript: automateScript,
			cefCheckout: cefCheckout,
			downloadRoot: downloadRoot,
			buildEnv: buildEnv,
			args: args,
			verbose: config.verbose
		)
		log("automate-git.py completed", config.verbose)
	}
	let currentAutomateLog = try mostRecentAutomateLog(in: downloadRoot)
	switch (previousAutomateLog, currentAutomateLog) {
	case let (before?, after?) where before.path != after.path:
		log("Automate log file: \(after.path)", config.verbose)
	case (nil, let after?):
		log("Automate log file: \(after.path)", config.verbose)
	case let (_, after?):
		log("Automate log file (pre-existing candidate): \(after.path)", config.verbose)
	case (_, nil):
		log("No automate log file found yet in \(downloadRoot.path)", config.verbose)
	}

	let exportedFrameworkRoot = try withBuildPhase(3, totalPhases, "Collect framework output", verbose: config.verbose) {
		let framework = try findFirstKnown(named: "Chromium Embedded Framework.framework", under: downloadRoot, isDir: true)
		guard let frameworkPath = framework else {
			throw BuilderError.missing("Could not locate Chromium Embedded Framework.framework under \(downloadRoot.path)")
		}

		let exportedFrameworkRoot = exportRoot.appendingPathComponent("runtime")
		try ensureDirectory(exportedFrameworkRoot)
		log("Copying framework into \(exportedFrameworkRoot.path)", config.verbose)
		try copyTree(
			frameworkPath,
			to: exportedFrameworkRoot.appendingPathComponent("Chromium Embedded Framework.framework"),
			verbose: config.verbose
		)
		return exportedFrameworkRoot
	}

	let clientBundle: URL? = try withBuildPhase(4, totalPhases, "Build client artifacts", verbose: config.verbose) {
		guard spec.export.includeClient else {
			log("Client export disabled by spec", config.verbose)
			return nil
		}
		let clientExportRoot = exportRoot.appendingPathComponent("client")
		log("Client export enabled. Export root: \(clientExportRoot.path)", config.verbose)
		try ensureDirectory(clientExportRoot)
		if let cefclient = try findFirstKnown(named: "cefclient.app", under: downloadRoot, isDir: true) {
			log("Found cefclient.app at \(cefclient.path)", config.verbose)
			try copyTree(
				cefclient,
				to: clientExportRoot.appendingPathComponent("cefclient.app"),
				verbose: config.verbose
			)
			let clientTar = clientOutputPath
			log("Creating client archive at \(clientTar.path)", config.verbose)
			try makeArchive(
				from: clientExportRoot,
				output: clientTar,
				format: spec.export.tarFormat,
				verbose: config.verbose
			)
			try ensureValidTarAny(
				clientTar,
				required: ["cefclient.app/", "Chromium Helper.app/", "Chromium Helper (Renderer).app/"],
				kind: "client",
				verbose: config.verbose
			)
			log("Caching client archive to \(clientCachePath.path)", config.verbose)
			try copyItem(clientTar, to: clientCachePath, verbose: config.verbose)
			return clientOutputPath
		}

		let helperApps = try findCandidateHelpers(under: downloadRoot, verbose: config.verbose)
		log("Found \(helperApps.count) helper app candidates", config.verbose)
		for helper in helperApps {
			try copyTree(
				helper,
				to: clientExportRoot.appendingPathComponent(helper.lastPathComponent),
				verbose: config.verbose
			)
		}
		guard !helperApps.isEmpty || config.forceRebuild else {
			throw BuilderError.missing("Client export did not produce cefclient.app or helper bundles")
		}
		if !helperApps.isEmpty {
			let clientTar = clientOutputPath
			log("Creating client archive at \(clientTar.path)", config.verbose)
			try makeArchive(
				from: clientExportRoot,
				output: clientTar,
				format: spec.export.tarFormat,
				verbose: config.verbose
			)
			try ensureValidTarAny(
				clientTar,
				required: ["cefclient.app/", "Chromium Helper.app/", "Chromium Helper (Renderer).app/"],
				kind: "client",
				verbose: config.verbose
			)
			log("Caching client archive to \(clientCachePath.path)", config.verbose)
			try copyItem(clientTar, to: clientCachePath, verbose: config.verbose)
			return clientOutputPath
		}
		if !config.forceRebuild {
			log("No cefclient or helper apps discovered. Continuing if optional in this build.", config.verbose)
		}
		return nil
	}

	let runtimeTar: URL = try withBuildPhase(
		5,
		totalPhases,
		"Create and validate runtime archive",
		verbose: config.verbose
	) {
		let runtimeTar = runtimeOutputPath
		log("Creating runtime archive at \(runtimeTar.path)", config.verbose)
		try makeArchive(
			from: exportedFrameworkRoot,
			output: runtimeTar,
			format: spec.export.tarFormat,
			verbose: config.verbose
		)
		verifyExpectedBranding(in: exportedFrameworkRoot, verbose: config.verbose)
		try ensureValidTar(
			runtimeTar,
			required: ["Chromium Embedded Framework.framework/"],
			kind: "runtime",
			verbose: config.verbose
		)
		log("Caching runtime archive to \(runtimeCachePath.path)", config.verbose)
		try copyItem(runtimeTar, to: runtimeCachePath, verbose: config.verbose)
		return runtimeTar
	}

	return (runtime: runtimeTar, client: clientBundle)
}

func parseArguments() throws -> BuilderConfig {
	let args = Array(CommandLine.arguments.dropFirst())
	let env = ProcessInfo.processInfo.environment

	func value(after flag: String) -> String? {
		guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
		return args[index + 1]
	}

	func boolFlag(_ key: String) -> Bool {
		guard let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
		return ["1", "true", "yes", "on"].contains(value)
	}

	guard let specPath = value(after: "--spec") else {
		throw BuilderError.invalid("Missing --spec <path>")
	}

	let repoRoot = (env["REPO_ROOT"].flatMap { URL(fileURLWithPath: $0) }
		?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
		.standardizedFileURL
	let workDir = URL(fileURLWithPath: value(after: "--work-dir") ?? "\(repoRoot.path)/Build/CEF")
	let outputDir = URL(fileURLWithPath: value(after: "--output-dir") ?? repoRoot
		.appendingPathComponent("Vendor/CEF/Artifacts").path)
	let cacheDir =
		URL(fileURLWithPath: value(after: "--cache-dir") ?? "\(NSHomeDirectory())/Library/Caches/Navigator/CEFBuilds")
	let verbose = args.contains("--verbose") || boolFlag("CEF_BUILDER_VERBOSE")
	let force = args.contains("--force") || boolFlag("CEF_SOURCE_FORCE")

	return BuilderConfig(
		specPath: URL(fileURLWithPath: specPath),
		workDir: workDir,
		outputDir: outputDir,
		cacheDir: cacheDir,
		verbose: verbose,
		forceRebuild: force,
		repoRoot: repoRoot
	)
}

func runBuilderCLI() {
	do {
		let config = try parseArguments()
		log(
			"Parsed config: spec=\(config.specPath.path), workDir=\(config.workDir.path), outputDir=\(config.outputDir.path), cacheDir=\(config.cacheDir.path), verbose=\(config.verbose), forceRebuild=\(config.forceRebuild), repoRoot=\(config.repoRoot.path)",
			config.verbose
		)
		let spec = try readSpec(config.specPath, verbose: config.verbose)
		log(
			"Using spec: name=\(spec.name), platform=\(spec.platform), arch=\(spec.arch), buildType=\(spec.buildType), includeClient=\(spec.export.includeClient), tarFormat=\(spec.export.tarFormat)",
			config.verbose
		)

		let result = try buildAndExportArtifacts(config: config, spec: spec)
		log("Build completed. runtime=\(result.runtime.path), client=\(result.client?.path ?? "<none>")", config.verbose)

		var response: [String: String] = ["runtime": result.runtime.path]
		if let client = result.client {
			response["client"] = client.path
		}
		let data = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys, .prettyPrinted])
		print(String(data: data, encoding: .utf8) ?? "{}")
	}
	catch {
		fputs("[CEFBuilder] \(error)\n", stderr)
		exit(1)
	}
}

runBuilderCLI()
