@testable import CEFShared
import Foundation
import XCTest

final class ShellTests: XCTestCase {
	func testShellErrorDescriptionFormatsCommandCodeAndOutput() {
		let error = ShellError.commandFailed("/bin/sh -c exit 7", 7, "boom")
		XCTAssertEqual(error.description, "command failed (7): /bin/sh -c exit 7\nboom")
	}

	func testRunConvenienceOverloadUsesWorkingDirectoryEnvironmentAndReturnsTrimmedStdout() throws {
		let directory = makeTemporaryDirectory()
		defer { try? removeIfPresent(directory) }

		let output = try Shell.run(
			"/bin/sh",
			arguments: ["-c", "printf '%s|%s' \"$(pwd -L)\" \"$TEST_ENV\""],
			workingDirectory: directory,
			environment: ["TEST_ENV": "configured"],
			captureOutput: true
		)

		let components = output.split(separator: "|", maxSplits: 1).map(String.init)
		XCTAssertEqual(components.count, 2)
		XCTAssertEqual(components.last, "configured")
		XCTAssertEqual(
			URL(fileURLWithPath: components[0]).lastPathComponent,
			directory.lastPathComponent
		)
	}

	func testRunSilentReturnsCapturedStdout() throws {
		let output = try Shell.runSilent("/bin/echo", arguments: ["hello"])
		XCTAssertEqual(output, "hello")
	}

	func testRunVerboseCaptureOutputHitsVerboseAndTimingCaptureBranches() throws {
		let output = try Shell.run(
			"/bin/sh",
			["-c", "printf 'stdout'; printf 'stderr' >&2"],
			captureOutput: true,
			verbose: true,
			logPrefix: "[cefshared-test]",
			streamOutput: false,
			logTiming: true
		)

		XCTAssertEqual(output, "stdout")
	}

	func testRunVerboseWithoutArgumentsUsesBareCommandLine() throws {
		let output = try Shell.run(
			"/bin/pwd",
			[],
			captureOutput: false,
			verbose: true,
			logPrefix: "[cefshared-test]",
			logCommandToStdErrWhenNotCapturingOutput: false,
			logCommandToStdOutWhenNotCapturingOutput: true,
			streamOutput: false,
			logTiming: false
		)

		XCTAssertEqual(output, "")
	}

	func testRunVerboseStdErrLoggingStreamingAndFailureThrowsCommandFailed() {
		XCTAssertThrowsError(
			try Shell.run(
				"/bin/sh",
				["-c", "printf 'out'; printf 'err' >&2; exit 7"],
				captureOutput: false,
				verbose: true,
				logPrefix: "[cefshared-test]",
				logCommandToStdErrWhenNotCapturingOutput: true,
				logCommandToStdOutWhenNotCapturingOutput: false,
				streamOutput: true,
				logTiming: false
			)
		) { error in
			let shellError = error as? ShellError
			XCTAssertEqual(
				shellError?.description,
				"command failed (7): /bin/sh -c printf 'out'; printf 'err' >&2; exit 7\nout\nerr"
			)
		}
	}

	func testRunVerboseStdOutLoggingNonCapturingReturnsEmptyString() throws {
		let output = try Shell.run(
			"/bin/sh",
			["-c", "printf 'stdout only'"],
			captureOutput: false,
			verbose: true,
			logPrefix: "[cefshared-test]",
			logCommandToStdErrWhenNotCapturingOutput: false,
			logCommandToStdOutWhenNotCapturingOutput: true,
			streamOutput: false,
			logTiming: true
		)

		XCTAssertEqual(output, "")
	}

	func testRunFallsBackToEmptyStringsForInvalidUTF8Output() throws {
		let output = try Shell.run(
			"/bin/sh",
			["-c", "printf '\\377'; printf '\\376' >&2"],
			captureOutput: true,
			verbose: false,
			logPrefix: "[cefshared-test]",
			logCommandToStdErrWhenNotCapturingOutput: false,
			logCommandToStdOutWhenNotCapturingOutput: true,
			streamOutput: false,
			logTiming: false
		)

		XCTAssertEqual(output, "")
	}

	func testEnsureDirectoryAndRemoveIfPresentManageFilesystem() throws {
		let root = makeTemporaryDirectory()
		let nestedDirectory = root.appendingPathComponent("nested/path", isDirectory: true)
		let file = root.appendingPathComponent("payload.txt")
		defer { try? removeIfPresent(root) }

		try ensureDirectory(nestedDirectory)
		XCTAssertTrue(FileManager.default.fileExists(atPath: nestedDirectory.path))

		try "payload".write(to: file, atomically: true, encoding: .utf8)
		try removeIfPresent(file)
		XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))

		try removeIfPresent(file)
	}
}

private func makeTemporaryDirectory() -> URL {
	let directory = FileManager.default.temporaryDirectory
		.appendingPathComponent("cefshared-\(UUID().uuidString)", isDirectory: true)
	try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	return directory
}
