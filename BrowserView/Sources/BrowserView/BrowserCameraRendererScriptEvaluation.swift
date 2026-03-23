import Foundation

enum BrowserCameraRendererScriptStatus: String, Sendable {
	case installed
	case updated
	case unsupported
	case delivered
	case cleared
	case missingShim = "missing-shim"
}

enum BrowserCameraRendererScriptEvaluation {
	static func requiresBrowserProcessFallback(
		result: String?,
		error: String?
	) -> Bool {
		if let error, error.isEmpty == false {
			return true
		}
		return result == BrowserCameraRendererScriptStatus.missingShim.rawValue
	}

	static func browserProcessFallbackReason(
		result: String?,
		error: String?
	) -> String {
		if let error, error.isEmpty == false {
			return "rendererError=\(error)"
		}
		return "rendererResult=\(result ?? "none")"
	}
}
