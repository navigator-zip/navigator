@testable import TrackpadGestures
import XCTest

final class MultitouchBridgeLoaderTests: XCTestCase {
	func testLoaderReportsFrameworkUnavailableWhenNoCandidatesOpen() {
		let loader = MultitouchBridgeLoader(
			frameworkCandidates: ["/tmp/does-not-exist"],
			dynamicLibraryClient: DynamicLibraryClient(
				open: { _ in nil },
				symbol: { _, _ in nil },
				close: { _ in }
			)
		)
		var diagnostics = [GestureDiagnosticEvent.Kind]()
		let result = loader.load { diagnostics.append($0) }
		switch result {
		case let .failure(error):
			XCTAssertEqual(error, .frameworkUnavailable("/tmp/does-not-exist"))
		case .success:
			XCTFail("Expected framework load failure")
		}
		XCTAssertEqual(diagnostics.last, .frameworkLoadFailed("/tmp/does-not-exist"))
		XCTAssertEqual(diagnostics.first, .frameworkOpenAttempt("/tmp/does-not-exist"))
	}

	func testLoaderFallsBackWhenFirstCandidateMissesSymbol() {
		let handleAddressA = Int(bitPattern: UnsafeMutableRawPointer(bitPattern: 0xA1))
		let handleAddressB = Int(bitPattern: UnsafeMutableRawPointer(bitPattern: 0xB1))
		let closeCounter = CloseCounter()
		let loader = MultitouchBridgeLoader(
			frameworkCandidates: ["/tmp/bad-framework", "/tmp/good-framework"],
			dynamicLibraryClient: DynamicLibraryClient(
				open: { path in
					if path == "/tmp/bad-framework" {
						return UnsafeMutableRawPointer(bitPattern: handleAddressA)
					}
					return UnsafeMutableRawPointer(bitPattern: handleAddressB)
				},
				symbol: { handle, name in
					if Int(bitPattern: handle) == handleAddressA {
						if name == "MTDeviceCreateList" {
							return UnsafeRawPointer(bitPattern: 0xF1)
						}
						return nil
					}
					return UnsafeRawPointer(bitPattern: 0xF2)
				},
				close: { _ in
					closeCounter.count += 1
				}
			)
		)
		var diagnostics = [GestureDiagnosticEvent.Kind]()
		let result = loader.load { diagnostics.append($0) }
		switch result {
		case .failure(let error):
			XCTFail("Expected candidate fallback success, got \(error)")
		case .success:
			break
		}
		XCTAssertEqual(closeCounter.count, 1)
		XCTAssertTrue(diagnostics.contains(.frameworkOpenAttempt("/tmp/bad-framework")))
		XCTAssertTrue(diagnostics.contains(.frameworkOpened("/tmp/bad-framework")))
		XCTAssertTrue(diagnostics.contains(.symbolMissing("MTRegisterContactFrameCallback")))
		XCTAssertTrue(diagnostics.contains(.frameworkOpenAttempt("/tmp/good-framework")))
		XCTAssertTrue(diagnostics.contains(.frameworkOpened("/tmp/good-framework")))
		XCTAssertTrue(diagnostics.contains(.frameworkReady("/tmp/good-framework")))
	}

	func testLoaderPropagatesMissingSymbolFailureWhenNoAlternateCandidateSucceeds() {
		let handleAddress = Int(bitPattern: UnsafeMutableRawPointer(bitPattern: 1))
		let loader = MultitouchBridgeLoader(
			frameworkCandidates: ["/tmp/framework"],
			dynamicLibraryClient: DynamicLibraryClient(
				open: { _ in
					UnsafeMutableRawPointer(bitPattern: handleAddress)
				},
				symbol: { _, name in
					// intentionally missing register callback symbol only
					switch name {
					case "MTDeviceCreateList":
						return UnsafeRawPointer(bitPattern: 0xA1)
					case "MTRegisterContactFrameCallback":
						return nil
					default:
						return UnsafeRawPointer(bitPattern: 0xB1)
					}
				},
				close: { _ in }
			)
		)
		var diagnostics = [GestureDiagnosticEvent.Kind]()
		let result = loader.load { diagnostics.append($0) }
		switch result {
		case let .failure(error):
			XCTAssertEqual(error, .symbolMissing("MTRegisterContactFrameCallback"))
		case .success:
			XCTFail("Expected symbol miss failure")
		}
		XCTAssertTrue(diagnostics.contains(.frameworkOpenAttempt("/tmp/framework")))
		XCTAssertTrue(diagnostics.contains(.frameworkOpened("/tmp/framework")))
		XCTAssertTrue(diagnostics.contains(.symbolResolved("MTDeviceCreateList")))
		XCTAssertTrue(diagnostics.contains(.symbolMissing("MTRegisterContactFrameCallback")))
	}
}

private final class CloseCounter: @unchecked Sendable {
	var count = 0
}
