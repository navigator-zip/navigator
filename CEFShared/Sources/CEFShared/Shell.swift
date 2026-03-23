import Foundation

public enum ShellError: Error, CustomStringConvertible {
	case commandFailed(String, Int, String)

	public var description: String {
		switch self {
		case let .commandFailed(command, code, output):
			return "command failed (\(code)): \(command)\n\(output)"
		}
	}
}

public enum Shell {
	@discardableResult
	public static func run(
		_ command: String,
		_ arguments: [String],
		cwd: URL? = nil,
		environment: [String: String] = [:],
		captureOutput: Bool = false,
		verbose: Bool = false,
		logPrefix: String = "[shell]",
		logCommandToStdErrWhenNotCapturingOutput: Bool = false,
		logCommandToStdOutWhenNotCapturingOutput: Bool = true,
		streamOutput: Bool = true,
		logTiming: Bool = false
	) throws -> String {
		return try runCore(
			command,
			arguments: arguments,
			workingDirectory: cwd,
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
	public static func run(
		_ command: String,
		arguments: [String] = [],
		workingDirectory: URL? = nil,
		environment: [String: String] = [:],
		captureOutput: Bool = false
	) throws -> String {
		return try runCore(
			command,
			arguments: arguments,
			workingDirectory: workingDirectory,
			environment: environment,
			captureOutput: captureOutput,
			verbose: false,
			logPrefix: "[shell]",
			logCommandToStdErrWhenNotCapturingOutput: false,
			logCommandToStdOutWhenNotCapturingOutput: true,
			streamOutput: true,
			logTiming: true
		)
	}

	public static func runSilent(
		_ command: String,
		arguments: [String] = [],
		workingDirectory: URL? = nil,
		environment: [String: String] = [:]
	) throws -> String {
		return try run(
			command,
			arguments: arguments,
			workingDirectory: workingDirectory,
			environment: environment,
			captureOutput: true
		)
	}

	@discardableResult
	private static func runCore(
		_ command: String,
		arguments: [String],
		workingDirectory: URL?,
		environment: [String: String],
		captureOutput: Bool,
		verbose: Bool,
		logPrefix: String,
		logCommandToStdErrWhenNotCapturingOutput: Bool,
		logCommandToStdOutWhenNotCapturingOutput: Bool,
		streamOutput: Bool,
		logTiming: Bool
	) throws -> String {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: command)
		process.arguments = arguments
		if let workingDirectory {
			process.currentDirectoryURL = workingDirectory
		}

		var processEnvironment = ProcessInfo.processInfo.environment
		for (key, value) in environment {
			processEnvironment[key] = value
		}
		process.environment = processEnvironment

		let stdout = Pipe()
		let stderr = Pipe()
		process.standardOutput = stdout
		process.standardError = stderr

		if verbose {
			let displayArguments = arguments
				.map { arg in arg.contains(" ") ? "\"\(arg)\"" : arg }
				.joined(separator: " ")
			let commandLine = displayArguments.isEmpty ? command : "\(command) \(displayArguments)"
			let output = "\(logPrefix) \(commandLine)\n"
			if captureOutput {
				FileHandle.standardError.write(output.data(using: .utf8)!)
			}
			else if logCommandToStdErrWhenNotCapturingOutput {
				FileHandle.standardError.write(output.data(using: .utf8)!)
			}
			else if logCommandToStdOutWhenNotCapturingOutput {
				print(output, terminator: "")
			}
		}

		try process.run()
		let startedAt = Date()
		let capturedOutput = ShellOutputCapture()

		@Sendable func appendOutput(_ data: Data, toStdout isStdout: Bool) {
			guard !data.isEmpty else { return }
			capturedOutput.append(data, toStdout: isStdout)
		}

		if captureOutput || streamOutput {
			let outHandle = stdout.fileHandleForReading
			outHandle.readabilityHandler = { handle in
				let data = handle.availableData
				guard !data.isEmpty else {
					outHandle.readabilityHandler = nil
					return
				}
				appendOutput(data, toStdout: true)
				if streamOutput {
					FileHandle.standardOutput.write(data)
				}
			}

			let errHandle = stderr.fileHandleForReading
			errHandle.readabilityHandler = { handle in
				let data = handle.availableData
				guard !data.isEmpty else {
					errHandle.readabilityHandler = nil
					return
				}
				appendOutput(data, toStdout: false)
				if streamOutput {
					FileHandle.standardError.write(data)
				}
			}
		}
		process.waitUntilExit()

		if captureOutput || streamOutput {
			let outHandle = stdout.fileHandleForReading
			let errHandle = stderr.fileHandleForReading
			let remainingOut = outHandle.readDataToEndOfFile()
			let remainingErr = errHandle.readDataToEndOfFile()
			appendOutput(remainingOut, toStdout: true)
			appendOutput(remainingErr, toStdout: false)
			outHandle.readabilityHandler = nil
			errHandle.readabilityHandler = nil
		}

		if verbose, logTiming {
			let elapsed = Date().timeIntervalSince(startedAt)
			let line = String(format: "\(logPrefix) exit=%d duration=%.2fs\n", process.terminationStatus, elapsed)
			if captureOutput {
				FileHandle.standardError.write(line.data(using: .utf8)!)
			}
			else {
				print(line, terminator: "")
			}
		}

		let (captureStdout, captureStderr) = capturedOutput.snapshot()
		let out = String(data: captureStdout, encoding: .utf8) ?? ""
		let err = String(data: captureStderr, encoding: .utf8) ?? ""

		let output = "\(out)\n\(err)".trimmingCharacters(in: .whitespacesAndNewlines)
		if process.terminationStatus != 0 {
			throw ShellError.commandFailed(
				"\(command) \(arguments.joined(separator: " "))",
				Int(process.terminationStatus),
				output
			)
		}

		guard captureOutput else { return "" }
		return out.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

public func ensureDirectory(_ url: URL) throws {
	try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
}

public func removeIfPresent(_ url: URL) throws {
	if FileManager.default.fileExists(atPath: url.path) {
		try FileManager.default.removeItem(at: url)
	}
}

private final class ShellOutputCapture: @unchecked Sendable {
	private let queue = DispatchQueue(label: "com.navigator.shell-output-state")
	private var stdout = Data()
	private var stderr = Data()

	func append(_ data: Data, toStdout isStdout: Bool) {
		queue.sync {
			if isStdout {
				stdout.append(data)
			}
			else {
				stderr.append(data)
			}
		}
	}

	func snapshot() -> (stdout: Data, stderr: Data) {
		queue.sync {
			(stdout, stderr)
		}
	}
}
