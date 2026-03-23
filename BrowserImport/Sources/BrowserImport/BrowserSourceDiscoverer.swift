import Foundation
import ModelKit

public struct BrowserSourceDiscoverer {
	private let homeDirectory: URL
	private let fileManager: FileManager

	public init(homeDirectory: URL) {
		self.init(homeDirectory: homeDirectory, fileManager: .default)
	}

	init(homeDirectory: URL, fileManager: FileManager) {
		self.homeDirectory = homeDirectory
		self.fileManager = fileManager
	}

	public func discoverInstallations() -> [BrowserInstallation] {
		BrowserImportSource.allCases.compactMap { source in
			discoverInstallation(for: source)
		}
	}

	private func discoverInstallation(for source: BrowserImportSource) -> BrowserInstallation? {
		let rootURL = rootURL(for: source)
		guard fileManager.fileExists(atPath: rootURL.path) else {
			return nil
		}

		let profiles = profiles(for: source, rootURL: rootURL)
		guard profiles.isEmpty == false else {
			return nil
		}

		return BrowserInstallation(
			source: source,
			displayName: source.displayName,
			profileRootURL: rootURL,
			profiles: profiles
		)
	}

	private func rootURL(for source: BrowserImportSource) -> URL {
		switch source {
		case .arc:
			homeDirectory
				.appendingPathComponent("Library", isDirectory: true)
				.appendingPathComponent("Application Support", isDirectory: true)
				.appendingPathComponent("Arc", isDirectory: true)
				.appendingPathComponent("User Data", isDirectory: true)
		case .chrome:
			homeDirectory
				.appendingPathComponent("Library", isDirectory: true)
				.appendingPathComponent("Application Support", isDirectory: true)
				.appendingPathComponent("Google", isDirectory: true)
				.appendingPathComponent("Chrome", isDirectory: true)
		case .safari:
			homeDirectory
				.appendingPathComponent("Library", isDirectory: true)
				.appendingPathComponent("Safari", isDirectory: true)
		}
	}

	private func profiles(
		for source: BrowserImportSource,
		rootURL: URL
	) -> [BrowserProfile] {
		switch source {
		case .arc, .chrome:
			chromiumProfiles(at: rootURL)
		case .safari:
			safariProfiles(at: rootURL)
		}
	}

	private func chromiumProfiles(at rootURL: URL) -> [BrowserProfile] {
		guard let children = try? fileManager.contentsOfDirectory(
			at: rootURL,
			includingPropertiesForKeys: [.isDirectoryKey],
			options: [.skipsHiddenFiles]
		) else {
			return []
		}

		return children
			.filter { isChromiumProfileDirectory($0) }
			.sorted { lhs, rhs in
				sortOrder(for: lhs.lastPathComponent) < sortOrder(for: rhs.lastPathComponent)
			}
			.map { url in
				let folderName = url.lastPathComponent
				return BrowserProfile(
					id: folderName,
					displayName: displayName(forChromiumProfileDirectoryName: folderName),
					profileURL: url,
					isDefault: folderName == "Default"
				)
			}
	}

	private func safariProfiles(at rootURL: URL) -> [BrowserProfile] {
		let bookmarksURL = rootURL.appendingPathComponent("Bookmarks.plist")
		let historyURL = rootURL.appendingPathComponent("History.db")
		guard
			fileManager.fileExists(atPath: bookmarksURL.path) ||
			fileManager.fileExists(atPath: historyURL.path)
		else {
			return []
		}

		return [
			BrowserProfile(
				id: "Safari",
				displayName: "Safari",
				profileURL: rootURL,
				isDefault: true
			),
		]
	}

	private func isChromiumProfileDirectory(_ url: URL) -> Bool {
		let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
		guard resourceValues?.isDirectory == true else {
			return false
		}

		let name = url.lastPathComponent
		return name == "Default" || name.hasPrefix("Profile ")
	}

	private func displayName(forChromiumProfileDirectoryName folderName: String) -> String {
		if folderName == "Default" {
			return "Default"
		}

		if folderName.hasPrefix("Profile ") {
			let suffix = folderName.dropFirst("Profile ".count)
			return "Profile \(suffix)"
		}

		return folderName
	}

	private func sortOrder(for profileDirectoryName: String) -> String {
		if profileDirectoryName == "Default" {
			return "0"
		}
		return "1-\(profileDirectoryName)"
	}
}
