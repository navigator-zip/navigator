import Foundation
import Observation

public enum BrowserActionBarMode: Equatable, Sendable {
	case currentTab
	case newTab
}

public enum BrowserActionBarQueryIntent: Equatable, Sendable {
	case empty
	case url(String)
	case search(String)
}

@MainActor
@Observable
public final class BrowserActionBarViewModel {
	public private(set) var isPresented = false
	public private(set) var mode: BrowserActionBarMode = .currentTab
	public private(set) var presentationSeed = UUID()
	public private(set) var query = ""
	public private(set) var selectedValue: String?
	public private(set) var selectedItemID: String?
	public private(set) var queryIntent: BrowserActionBarQueryIntent = .empty
	public var onStateChange: (() -> Void)?

	private let onOpenCurrentTab: (String) -> Void
	private let onOpenNewTab: (String) -> Void

	public init(
		onOpenCurrentTab: @escaping (String) -> Void,
		onOpenNewTab: @escaping (String) -> Void
	) {
		self.onOpenCurrentTab = onOpenCurrentTab
		self.onOpenNewTab = onOpenNewTab
	}

	public var normalizedQuery: String? {
		Self.normalize(query)
	}

	public var placeholder: String? {
		switch mode {
		case .currentTab:
			nil
		case .newTab:
			localized(.placeholderNewTab)
		}
	}

	public func updateQuery(_ query: String) {
		guard self.query != query else { return }
		self.query = query
		syncQueryIntent()

		let normalizedValue = Self.normalize(query)
		if selectedValue != normalizedValue {
			selectedValue = normalizedValue
			selectedItemID = normalizedValue
		}

		notifyStateChange()
	}

	public func selectValue(_ value: String?) {
		let normalizedValue = value.flatMap(Self.normalize)
		guard selectedValue != normalizedValue || selectedItemID != normalizedValue else { return }
		selectedValue = normalizedValue
		selectedItemID = normalizedValue
		if query != (normalizedValue ?? "") {
			query = normalizedValue ?? ""
		}
		syncQueryIntent()
		notifyStateChange()
	}

	public func presentCurrentTab(url: String) {
		guard !(isPresented && mode == .currentTab) else {
			dismiss()
			return
		}
		present(mode: .currentTab, query: url)
	}

	public func presentNewTab() {
		guard !(isPresented && mode == .newTab) else {
			dismiss()
			return
		}
		present(mode: .newTab, query: "")
	}

	public func dismiss() {
		guard isPresented else { return }
		isPresented = false
		notifyStateChange()
	}

	public func performPrimaryAction(with value: String) {
		guard let normalizedValue = Self.normalize(value) else { return }
		let resolvedNavigationURL = Self.resolvedNavigationURL(from: normalizedValue)

		isPresented = false
		query = normalizedValue
		selectedValue = normalizedValue
		selectedItemID = normalizedValue
		queryIntent = Self.resolveQueryIntent(from: normalizedValue)
		notifyStateChange()

		switch mode {
		case .currentTab:
			onOpenCurrentTab(resolvedNavigationURL)
		case .newTab:
			onOpenNewTab(resolvedNavigationURL)
		}
	}

	private func present(mode: BrowserActionBarMode, query: String) {
		let normalizedValue = Self.normalize(query)

		self.mode = mode
		self.query = query
		selectedValue = normalizedValue
		selectedItemID = normalizedValue
		queryIntent = Self.resolveQueryIntent(from: query)
		presentationSeed = UUID()
		isPresented = true

		notifyStateChange()
	}

	private func syncQueryIntent() {
		queryIntent = Self.resolveQueryIntent(from: query)
	}

	private func notifyStateChange() {
		onStateChange?()
	}

	private func localized(_ key: BrowserActionBarLocalizationKey) -> String {
		Self.localized(key)
	}

	private static func localized(_ key: BrowserActionBarLocalizationKey) -> String {
		String(localized: key.resource)
	}

	private static func normalize(_ value: String) -> String? {
		let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? nil : trimmed
	}

	private static func resolveQueryIntent(from value: String) -> BrowserActionBarQueryIntent {
		guard let normalizedValue = normalize(value) else { return .empty }
		if let resolvedURL = resolvedURL(from: normalizedValue) {
			return .url(resolvedURL)
		}
		return .search(searchURL(for: normalizedValue))
	}

	private static func resolvedNavigationURL(from normalizedValue: String) -> String {
		resolvedURL(from: normalizedValue) ?? searchURL(for: normalizedValue)
	}

	private static func resolvedURL(from normalizedValue: String) -> String? {
		if let implicitWebURL = implicitWebURL(from: normalizedValue) {
			return implicitWebURL
		}

		if hasExplicitScheme(normalizedValue) {
			return URL(string: normalizedValue) == nil ? nil : normalizedValue
		}

		return nil
	}

	private static func implicitWebURL(from normalizedValue: String) -> String? {
		guard !normalizedValue.contains("://") else { return nil }
		guard !normalizedValue.contains(where: { $0.isWhitespace }) else { return nil }
		let candidateURL = "https://\(normalizedValue)"
		guard var components = URLComponents(string: candidateURL),
		      components.user == nil,
		      components.password == nil,
		      let host = components.host,
		      !host.isEmpty else { return nil }
		guard isIPAddress(host) || host.contains(".") || isLocalhostHost(host) else {
			return nil
		}
		components.scheme = isLocalhostHost(host) ? "http" : "https"
		return components.string
	}

	private static func hasExplicitScheme(_ value: String) -> Bool {
		guard let separatorIndex = value.firstIndex(of: ":"),
		      separatorIndex > value.startIndex else {
			return false
		}

		let scheme = value[..<separatorIndex]
		guard let firstCharacter = scheme.first, firstCharacter.isLetter else { return false }
		return scheme.dropFirst().allSatisfy { character in
			character.isLetter || character.isNumber || character == "+" || character == "-" || character == "."
		}
	}

	private static func isIPAddress(_ host: String) -> Bool {
		if host.contains(":") {
			return true
		}

		let components = host.split(separator: ".", omittingEmptySubsequences: false)
		guard components.count == 4 else { return false }
		return components.allSatisfy { component in
			guard let octet = Int(component), (0...255).contains(octet) else { return false }
			return String(octet) == component
		}
	}

	private static func isLocalhostHost(_ host: String) -> Bool {
		let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
		return normalizedHost == "localhost" || normalizedHost.hasSuffix(".localhost")
	}

	private static func searchURL(for query: String) -> String {
		var components = URLComponents(string: "https://www.google.com/search")!
		components.queryItems = [URLQueryItem(name: "q", value: query)]
		return components.url!.absoluteString
	}
}

private enum BrowserActionBarLocalizationKey: String {
	case placeholderNewTab = "browser.actionBar.placeholder.newTab"
}

private extension BrowserActionBarLocalizationKey {
	var resource: LocalizedStringResource {
		LocalizedStringResource(String.LocalizationValue(rawValue), bundle: .module)
	}
}
