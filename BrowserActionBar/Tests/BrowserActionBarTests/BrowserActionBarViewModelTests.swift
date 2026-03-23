import AppIntents
import BrowserActionBar
import Foundation
import XCTest

@MainActor
final class BrowserActionBarViewModelTests: XCTestCase {
	func testPresentCurrentTabConfiguresCurrentTabModeAndQuery() {
		let viewModel = makeViewModel()
		let initialSeed = viewModel.presentationSeed
		viewModel.presentCurrentTab(url: "https://example.test/path")

		XCTAssertTrue(viewModel.isPresented)
		XCTAssertEqual(viewModel.mode, .currentTab)
		XCTAssertEqual(viewModel.query, "https://example.test/path")
		XCTAssertNil(viewModel.placeholder)
		XCTAssertNotEqual(initialSeed, viewModel.presentationSeed)
	}

	func testUpdateQueryUpdatesObservableQueryState() {
		let viewModel = makeViewModel()
		var observedStates: [String] = []
		viewModel.onStateChange = {
			observedStates.append(viewModel.query)
		}

		viewModel.updateQuery("https://typed.example.test")

		XCTAssertEqual(viewModel.query, "https://typed.example.test")
		XCTAssertEqual(viewModel.normalizedQuery, "https://typed.example.test")
		XCTAssertEqual(viewModel.selectedValue, "https://typed.example.test")
		XCTAssertEqual(viewModel.selectedItemID, "https://typed.example.test")
		XCTAssertEqual(observedStates, ["https://typed.example.test"])
	}

	func testUpdateQueryWithUnchangedValueDoesNotNotify() {
		let viewModel = makeViewModel()
		var notificationCount = 0
		viewModel.onStateChange = {
			notificationCount += 1
		}

		viewModel.updateQuery("https://example.test/same")
		viewModel.updateQuery("https://example.test/same")

		XCTAssertEqual(notificationCount, 1)
	}

	func testUpdateQueryClassifiesDomainInputAsURLIntent() {
		let viewModel = makeViewModel()

		viewModel.updateQuery("swift.org")

		guard case let .url(resolvedURL) = viewModel.queryIntent else {
			return XCTFail("Expected URL intent for domain input")
		}
		XCTAssertEqual(resolvedURL, "https://swift.org")
	}

	func testUpdateQueryClassifiesIPv4InputAsURLIntent() {
		let viewModel = makeViewModel()

		viewModel.updateQuery("127.0.0.1")

		guard case let .url(resolvedURL) = viewModel.queryIntent else {
			return XCTFail("Expected URL intent for IPv4 input")
		}
		XCTAssertEqual(resolvedURL, "https://127.0.0.1")
	}

	func testUpdateQueryClassifiesIPv6InputAsURLIntent() {
		let viewModel = makeViewModel()

		viewModel.updateQuery("[::1]")

		guard case let .url(resolvedURL) = viewModel.queryIntent else {
			return XCTFail("Expected URL intent for IPv6 input")
		}
		XCTAssertEqual(resolvedURL, "https://[::1]")
	}

	func testUpdateQueryClassifiesLocalhostPortInputAsHTTPURLIntent() {
		let viewModel = makeViewModel()

		viewModel.updateQuery("localhost:3000")

		guard case let .url(resolvedURL) = viewModel.queryIntent else {
			return XCTFail("Expected URL intent for localhost input")
		}
		XCTAssertEqual(resolvedURL, "http://localhost:3000")
	}

	func testUpdateQueryClassifiesHostAndPortInputAsHTTPSURLIntent() {
		let viewModel = makeViewModel()

		viewModel.updateQuery("example.com:8080")

		guard case let .url(resolvedURL) = viewModel.queryIntent else {
			return XCTFail("Expected URL intent for host and port input")
		}
		XCTAssertEqual(resolvedURL, "https://example.com:8080")
	}

	func testUpdateQueryClassifiesFreeformInputAsSearchIntent() {
		let viewModel = makeViewModel()
		let searchQuery = "swift concurrency guide"

		viewModel.updateQuery(searchQuery)

		guard case let .search(searchURL) = viewModel.queryIntent else {
			return XCTFail("Expected search intent for freeform input")
		}
		assertSearchURL(searchURL, query: searchQuery)
	}

	func testPresentNewTabConfiguresNewTabMode() {
		let viewModel = makeViewModel()
		let initialSeed = viewModel.presentationSeed
		viewModel.presentNewTab()

		XCTAssertTrue(viewModel.isPresented)
		XCTAssertEqual(viewModel.mode, .newTab)
		XCTAssertEqual(viewModel.query, "")
		XCTAssertNotNil(viewModel.placeholder)
		XCTAssertFalse(viewModel.placeholder?.isEmpty == true)
		XCTAssertNotEqual(initialSeed, viewModel.presentationSeed)
	}

	func testSelectValueUpdatesSelectionState() {
		let viewModel = makeViewModel()

		viewModel.selectValue("  https://selected.example.test  ")

		XCTAssertEqual(viewModel.query, "https://selected.example.test")
		XCTAssertEqual(viewModel.selectedValue, "https://selected.example.test")
		XCTAssertEqual(viewModel.selectedItemID, "https://selected.example.test")
	}

	func testSelectValueWithUnchangedNormalizedValueDoesNotNotify() {
		let viewModel = makeViewModel()
		var notificationCount = 0
		viewModel.onStateChange = {
			notificationCount += 1
		}
		viewModel.selectValue("https://selected.example.test")
		viewModel.selectValue("  https://selected.example.test  ")

		XCTAssertEqual(notificationCount, 1)
	}

	func testSelectValueNilClearsQueryAndSelection() {
		let viewModel = makeViewModel()
		viewModel.updateQuery("https://example.test/non-empty")

		viewModel.selectValue(nil)

		XCTAssertEqual(viewModel.query, "")
		XCTAssertNil(viewModel.selectedValue)
		XCTAssertNil(viewModel.selectedItemID)
	}

	func testPresentCurrentTabWhileHiddenPresentsCurrentURL() {
		let viewModel = makeViewModel()
		viewModel.presentCurrentTab(url: "https://example.test/latest")

		XCTAssertTrue(viewModel.isPresented)
		XCTAssertEqual(viewModel.mode, .currentTab)
		XCTAssertEqual(viewModel.query, "https://example.test/latest")
	}

	func testPresentCurrentTabWhileAlreadyPresentedTogglesHidden() {
		let viewModel = makeViewModel()
		var presentationStates: [Bool] = []
		viewModel.onStateChange = {
			presentationStates.append(viewModel.isPresented)
		}

		viewModel.presentCurrentTab(url: "https://example.test/original")
		viewModel.presentCurrentTab(url: "https://example.test/latest")

		XCTAssertEqual(presentationStates, [true, false])
		XCTAssertFalse(viewModel.isPresented)
		XCTAssertEqual(viewModel.query, "https://example.test/original")
	}

	func testPresentNewTabWhileHiddenPresentsEmptyQuery() {
		let viewModel = makeViewModel()
		viewModel.presentNewTab()

		XCTAssertTrue(viewModel.isPresented)
		XCTAssertEqual(viewModel.mode, .newTab)
		XCTAssertEqual(viewModel.query, "")
	}

	func testPresentNewTabWhileAlreadyPresentedTogglesHidden() {
		let viewModel = makeViewModel()
		var presentationStates: [Bool] = []
		viewModel.onStateChange = {
			presentationStates.append(viewModel.isPresented)
		}

		viewModel.presentNewTab()
		viewModel.presentNewTab()

		XCTAssertEqual(presentationStates, [true, false])
		XCTAssertFalse(viewModel.isPresented)
		XCTAssertEqual(viewModel.query, "")
	}

	func testPresentCurrentTabWhileNewTabIsPresentedSwitchesModesAndRefreshesQuery() {
		let viewModel = makeViewModel()
		viewModel.presentNewTab()
		viewModel.updateQuery("typed in new tab")
		let newTabSeed = viewModel.presentationSeed

		viewModel.presentCurrentTab(url: "https://example.test/current")

		XCTAssertTrue(viewModel.isPresented)
		XCTAssertEqual(viewModel.mode, .currentTab)
		XCTAssertEqual(viewModel.query, "https://example.test/current")
		XCTAssertNil(viewModel.placeholder)
		XCTAssertNotEqual(newTabSeed, viewModel.presentationSeed)
	}

	func testPresentNewTabWhileCurrentTabIsPresentedClearsQueryAndSelection() {
		let viewModel = makeViewModel()
		viewModel.presentCurrentTab(url: "https://example.test/current")
		viewModel.updateQuery("typed current value")
		let currentSeed = viewModel.presentationSeed

		viewModel.presentNewTab()

		XCTAssertTrue(viewModel.isPresented)
		XCTAssertEqual(viewModel.mode, .newTab)
		XCTAssertEqual(viewModel.query, "")
		XCTAssertNil(viewModel.selectedValue)
		XCTAssertNil(viewModel.selectedItemID)
		XCTAssertNotNil(viewModel.placeholder)
		XCTAssertNotEqual(currentSeed, viewModel.presentationSeed)
	}

	func testPresentCurrentTabAfterNewTabRestoresLocationQueryOnceHidden() {
		let viewModel = makeViewModel()
		viewModel.presentNewTab()
		viewModel.updateQuery("typed in new tab")
		let newTabSeed = viewModel.presentationSeed
		viewModel.dismiss()

		viewModel.presentCurrentTab(url: "https://example.test/current")

		XCTAssertEqual(viewModel.mode, .currentTab)
		XCTAssertEqual(viewModel.query, "https://example.test/current")
		XCTAssertNotEqual(newTabSeed, viewModel.presentationSeed)
	}

	func testTypingDoesNotTriggerNavigationUntilPrimaryAction() {
		var didOpenCurrentTab = ""
		var didOpenNewTab = ""
		let viewModel = makeViewModel(
			onOpenCurrentTab: { didOpenCurrentTab = $0 },
			onOpenNewTab: { didOpenNewTab = $0 }
		)

		viewModel.presentCurrentTab(url: "https://example.test/current")
		viewModel.updateQuery("https://typed.example.test")

		XCTAssertTrue(viewModel.isPresented)
		XCTAssertEqual(viewModel.query, "https://typed.example.test")
		XCTAssertEqual(didOpenCurrentTab, "")
		XCTAssertEqual(didOpenNewTab, "")
	}

	func testDismissWhileHiddenDoesNotNotify() {
		let viewModel = makeViewModel()
		var notificationCount = 0
		viewModel.onStateChange = {
			notificationCount += 1
		}

		viewModel.dismiss()

		XCTAssertEqual(notificationCount, 0)
		XCTAssertFalse(viewModel.isPresented)
	}

	func testPerformPrimaryActionForCurrentTabCallsCurrentTabHandler() {
		var didOpenCurrentTab = ""
		var didOpenNewTab = ""
		let viewModel = makeViewModel(
			onOpenCurrentTab: { didOpenCurrentTab = $0 },
			onOpenNewTab: { didOpenNewTab = $0 }
		)

		viewModel.presentCurrentTab(url: "https://example.test/current")
		viewModel.performPrimaryAction(with: "  https://example.test/final  ")

		XCTAssertEqual(didOpenCurrentTab, "https://example.test/final")
		XCTAssertEqual(didOpenNewTab, "")
		XCTAssertEqual(viewModel.query, "https://example.test/final")
		XCTAssertEqual(viewModel.selectedValue, "https://example.test/final")
		XCTAssertFalse(viewModel.isPresented)
	}

	func testPerformPrimaryActionWithEmptyInputDoesNothing() {
		var didOpenCurrentTab = ""
		let viewModel = makeViewModel(
			onOpenCurrentTab: { didOpenCurrentTab = $0 },
			onOpenNewTab: { _ in }
		)
		viewModel.presentCurrentTab(url: "https://example.test/current")

		viewModel.performPrimaryAction(with: "   \n")

		XCTAssertEqual(didOpenCurrentTab, "")
		XCTAssertTrue(viewModel.isPresented)
	}

	func testPerformPrimaryActionForNewTabCallsNewTabHandler() {
		var didOpenCurrentTab = ""
		var didOpenNewTab = ""
		let viewModel = makeViewModel(
			onOpenCurrentTab: { didOpenCurrentTab = $0 },
			onOpenNewTab: { didOpenNewTab = $0 }
		)

		viewModel.presentNewTab()
		viewModel.performPrimaryAction(with: "https://example.test/new")

		XCTAssertEqual(didOpenNewTab, "https://example.test/new")
		XCTAssertEqual(didOpenCurrentTab, "")
		XCTAssertEqual(viewModel.query, "https://example.test/new")
		XCTAssertEqual(viewModel.selectedValue, "https://example.test/new")
		XCTAssertFalse(viewModel.isPresented)
	}

	func testPerformPrimaryActionForCurrentTabRoutesSearchInputToSearchEngine() {
		var didOpenCurrentTab = ""
		let viewModel = makeViewModel(
			onOpenCurrentTab: { didOpenCurrentTab = $0 },
			onOpenNewTab: { _ in }
		)
		let searchQuery = "swift testing patterns"

		viewModel.presentCurrentTab(url: "https://example.test/current")
		viewModel.performPrimaryAction(with: searchQuery)

		assertSearchURL(didOpenCurrentTab, query: searchQuery)
		XCTAssertEqual(viewModel.query, searchQuery)
		XCTAssertEqual(viewModel.selectedValue, searchQuery)
		XCTAssertFalse(viewModel.isPresented)
	}

	func testPerformPrimaryActionForNewTabRoutesDomainInputToHTTPSURL() {
		var didOpenNewTab = ""
		let viewModel = makeViewModel(
			onOpenCurrentTab: { _ in },
			onOpenNewTab: { didOpenNewTab = $0 }
		)

		viewModel.presentNewTab()
		viewModel.performPrimaryAction(with: "developer.apple.com")

		XCTAssertEqual(didOpenNewTab, "https://developer.apple.com")
		XCTAssertFalse(viewModel.isPresented)
	}

	func testPerformPrimaryActionForCurrentTabRoutesLocalhostInputToHTTPURL() {
		var didOpenCurrentTab = ""
		let viewModel = makeViewModel(
			onOpenCurrentTab: { didOpenCurrentTab = $0 },
			onOpenNewTab: { _ in }
		)

		viewModel.presentCurrentTab(url: "https://example.test/current")
		viewModel.performPrimaryAction(with: "localhost:3000")

		XCTAssertEqual(didOpenCurrentTab, "http://localhost:3000")
		XCTAssertFalse(viewModel.isPresented)
	}

	func testPerformPrimaryActionWithInvalidSchemeTreatsInputAsSearch() {
		var didOpenCurrentTab = ""
		let viewModel = makeViewModel(
			onOpenCurrentTab: { didOpenCurrentTab = $0 },
			onOpenNewTab: { _ in }
		)
		let input = "1abc://test"

		viewModel.presentCurrentTab(url: "https://example.test/current")
		viewModel.performPrimaryAction(with: input)

		assertSearchURL(didOpenCurrentTab, query: input)
	}

	func testPerformPrimaryActionWithMalformedExplicitURLTreatsInputAsSearch() {
		var didOpenCurrentTab = ""
		let viewModel = makeViewModel(
			onOpenCurrentTab: { didOpenCurrentTab = $0 },
			onOpenNewTab: { _ in }
		)
		let input = "https://exa mple.test"

		viewModel.presentCurrentTab(url: "https://example.test/current")
		viewModel.performPrimaryAction(with: input)

		assertSearchURL(didOpenCurrentTab, query: input)
	}

	func testPerformPrimaryActionAcceptsExtendedSchemeCharacters() {
		var didOpenCurrentTab = ""
		let viewModel = makeViewModel(
			onOpenCurrentTab: { didOpenCurrentTab = $0 },
			onOpenNewTab: { _ in }
		)
		let input = "a1+-.://example.test/path"

		viewModel.presentCurrentTab(url: "https://example.test/current")
		viewModel.performPrimaryAction(with: input)

		XCTAssertEqual(didOpenCurrentTab, input)
	}

	func testPerformPrimaryActionWithInvalidSchemeCharacterTreatsInputAsSearch() {
		var didOpenCurrentTab = ""
		let viewModel = makeViewModel(
			onOpenCurrentTab: { didOpenCurrentTab = $0 },
			onOpenNewTab: { _ in }
		)
		let input = "a!://example.test/path"

		viewModel.presentCurrentTab(url: "https://example.test/current")
		viewModel.performPrimaryAction(with: input)

		assertSearchURL(didOpenCurrentTab, query: input)
	}

	func testUpdateQueryTreatsHostlessCandidateAsSearchIntent() {
		let viewModel = makeViewModel()

		viewModel.updateQuery("/")

		guard case let .search(searchURL) = viewModel.queryIntent else {
			return XCTFail("Expected search intent for hostless candidate")
		}
		assertSearchURL(searchURL, query: "/")
	}

	func testUpdateQueryTreatsOutOfRangeIPv4AsURLIntent() {
		let viewModel = makeViewModel()
		let input = "256.1.1.1"

		viewModel.updateQuery(input)

		guard case let .url(resolvedURL) = viewModel.queryIntent else {
			return XCTFail("Expected URL intent for dotted host input")
		}
		XCTAssertEqual(resolvedURL, "https://\(input)")
	}

	private func makeViewModel(
		onOpenCurrentTab: @escaping (String) -> Void = { _ in },
		onOpenNewTab: @escaping (String) -> Void = { _ in }
	) -> BrowserActionBarViewModel {
		BrowserActionBarViewModel(
			onOpenCurrentTab: onOpenCurrentTab,
			onOpenNewTab: onOpenNewTab
		)
	}

	private func assertSearchURL(_ urlString: String, query: String, file: StaticString = #filePath, line: UInt = #line) {
		guard let components = URLComponents(string: urlString) else {
			return XCTFail("Invalid URL: \(urlString)", file: file, line: line)
		}
		XCTAssertEqual(components.scheme, "https", file: file, line: line)
		XCTAssertEqual(components.host, "www.google.com", file: file, line: line)
		XCTAssertEqual(components.path, "/search", file: file, line: line)
		XCTAssertEqual(
			components.queryItems?.first(where: { $0.name == "q" })?.value,
			query,
			file: file,
			line: line
		)
	}
}
