import AppKit
import Foundation
import UniformTypeIdentifiers

struct NavigatorDefaultBrowserClient {
	var isDefaultBrowser: (_ bundleIdentifier: String) -> Bool
	var setAsDefaultBrowser: (_ bundle: Bundle) async throws -> Void
}

extension NavigatorDefaultBrowserClient {
	nonisolated static let live = makeLiveClient()

	private nonisolated static func makeLiveClient() -> Self {
		Self(
			isDefaultBrowser: liveIsDefaultBrowser(_:),
			setAsDefaultBrowser: liveSetAsDefaultBrowserEntry(_:)
		)
	}

	private nonisolated static func liveSetAsDefaultBrowserEntry(_ bundle: Bundle) async throws {
		try await liveSetAsDefaultBrowser(
			bundle,
			setDefaultApplicationForURLScheme: setDefaultApplicationAtURL(_:toOpenURLsWithScheme:completionHandler:),
			setDefaultApplicationForContentType: setDefaultApplicationAtURL(_:toOpenContentType:completionHandler:)
		)
	}

	nonisolated static func liveIsDefaultBrowser(_ bundleIdentifier: String) -> Bool {
		isDefaultBrowser(
			bundleIdentifier: bundleIdentifier,
			copyDefaultHandlerForURLScheme: liveCopyDefaultHandlerForURLScheme(_:)
		)
	}

	nonisolated static func liveSetAsDefaultBrowser(
		_ bundle: Bundle,
		setDefaultApplicationForURLScheme: @escaping (URL, String, @escaping (Error?) -> Void) -> Void,
		setDefaultApplicationForContentType: @escaping (URL, UTType, @escaping (Error?) -> Void) -> Void
	) async throws {
		try await setAsDefaultBrowser(
			bundle: bundle,
			setDefaultApplicationForURLScheme: setDefaultApplicationForURLScheme,
			setDefaultApplicationForContentType: setDefaultApplicationForContentType
		)
	}

	nonisolated static func isDefaultBrowser(
		bundleIdentifier: String,
		copyDefaultHandlerForURLScheme: (String) -> String?
	) -> Bool {
		guard bundleIdentifier.isEmpty == false else { return false }
		return supportedURLSchemes.allSatisfy { scheme in
			guard let handler = copyDefaultHandlerForURLScheme(scheme) else {
				return false
			}
			return handler == bundleIdentifier
		}
	}

	nonisolated static func setAsDefaultBrowser(
		bundle: Bundle,
		setDefaultApplicationForURLScheme: @escaping (URL, String, @escaping (Error?) -> Void) -> Void,
		setDefaultApplicationForContentType: @escaping (URL, UTType, @escaping (Error?) -> Void) -> Void
	) async throws {
		let bundleIdentifier = bundle.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		guard bundleIdentifier.isEmpty == false else {
			throw NavigatorDefaultBrowserClientError.missingBundleIdentifier
		}
		let applicationURL = bundle.bundleURL

		for scheme in supportedURLSchemes {
			try await performDefaultApplicationUpdate(target: scheme) { completion in
				setDefaultApplicationForURLScheme(applicationURL, scheme, completion)
			}
		}

		for contentType in supportedContentTypes {
			try await performDefaultApplicationUpdate(target: contentType.identifier) { completion in
				setDefaultApplicationForContentType(applicationURL, contentType, completion)
			}
		}
	}

	private nonisolated static let supportedURLSchemes = [
		"http",
		"https",
	]

	private nonisolated static let supportedContentTypes = [
		UTType.html,
		UTType(importedAs: "public.xhtml"),
	]

	private nonisolated static func liveCopyDefaultHandlerForURLScheme(_ scheme: String) -> String? {
		copyDefaultHandlerForURLScheme(scheme)
	}

	nonisolated static func copyDefaultHandlerForURLScheme(_ scheme: String) -> String? {
		guard let schemeURL = URL(string: "\(scheme)://") else {
			return nil
		}
		guard let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: schemeURL) else {
			return nil
		}
		return Bundle(url: applicationURL)?.bundleIdentifier
	}

	private nonisolated static func performDefaultApplicationUpdate(
		target: String,
		operation: @escaping (@escaping (Error?) -> Void) -> Void
	) async throws {
		let stream = AsyncThrowingStream<Void, Error> { continuation in
			operation { error in
				if let error {
					continuation.finish(throwing: NavigatorDefaultBrowserClientError.updateFailed(target: target, error: error))
					return
				}
				continuation.yield(())
				continuation.finish()
			}
		}
		var iterator = stream.makeAsyncIterator()
		_ = try await iterator.next()
	}

	private nonisolated static func setDefaultApplicationAtURL(
		_ applicationURL: URL,
		toOpenURLsWithScheme scheme: String,
		completionHandler: @escaping (Error?) -> Void
	) {
		NSWorkspace.shared.setDefaultApplication(
			at: applicationURL,
			toOpenURLsWithScheme: scheme,
			completion: completionHandler
		)
	}

	private nonisolated static func setDefaultApplicationAtURL(
		_ applicationURL: URL,
		toOpenContentType contentType: UTType,
		completionHandler: @escaping (Error?) -> Void
	) {
		NSWorkspace.shared.setDefaultApplication(
			at: applicationURL,
			toOpen: contentType,
			completion: completionHandler
		)
	}
}

enum NavigatorDefaultBrowserClientError: Error {
	case missingBundleIdentifier
	case updateFailed(target: String, error: any Error)
}
