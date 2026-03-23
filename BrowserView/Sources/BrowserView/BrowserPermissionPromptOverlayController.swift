import AppKit
import ModelKit

enum BrowserPermissionPromptLocalizationKey: String {
	case remember = "browser_permission_prompt_remember"
	case notNow = "browser_permission_prompt_not_now"
	case deny = "browser_permission_prompt_deny"
	case allow = "browser_permission_prompt_allow"
	case titleSameOrigin = "browser_permission_prompt_title_same_origin"
	case titleCrossOrigin = "browser_permission_prompt_title_cross_origin"
	case subtitleMedia = "browser_permission_prompt_subtitle_media"
	case subtitlePermission = "browser_permission_prompt_subtitle_permission"
	case kindCamera = "browser_permission_prompt_kind_camera"
	case kindMicrophone = "browser_permission_prompt_kind_microphone"
	case kindLocation = "browser_permission_prompt_kind_location"
}

@MainActor
final class BrowserPermissionPromptOverlayController {
	private static let promptInset: CGFloat = 16

	let hostView = NSView()

	private let localize: (BrowserPermissionPromptLocalizationKey) -> String
	private var promptView: NSView?
	private var decisionHandler: ((BrowserPermissionPromptDecision, BrowserPermissionPersistence) -> Void)?
	private var cancelHandler: (() -> Void)?
	private weak var rememberButton: NSButton?

	init() {
		localize = {
			Bundle.module.localizedString(forKey: $0.rawValue, value: $0.rawValue, table: nil)
		}
		hostView.translatesAutoresizingMaskIntoConstraints = false
		hostView.isHidden = true
	}

	init(
		localize: @escaping (BrowserPermissionPromptLocalizationKey) -> String
	) {
		self.localize = localize
		hostView.translatesAutoresizingMaskIntoConstraints = false
		hostView.isHidden = true
	}

	func setPrompt(
		_ session: BrowserPermissionSession?,
		onDecision: ((BrowserPermissionPromptDecision, BrowserPermissionPersistence) -> Void)?,
		onCancel: (() -> Void)?
	) {
		decisionHandler = onDecision
		cancelHandler = onCancel
		promptView?.removeFromSuperview()
		promptView = nil
		rememberButton = nil

		guard let session else {
			hostView.isHidden = true
			return
		}

		let nextPromptView = makePromptView(for: session)
		nextPromptView.translatesAutoresizingMaskIntoConstraints = false
		hostView.addSubview(nextPromptView)
		NSLayoutConstraint.activate([
			nextPromptView.topAnchor.constraint(
				equalTo: hostView.topAnchor,
				constant: Self.promptInset
			),
			nextPromptView.leadingAnchor.constraint(
				equalTo: hostView.leadingAnchor,
				constant: Self.promptInset
			),
			nextPromptView.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
		])
		hostView.isHidden = false
		promptView = nextPromptView
	}

	private func makePromptView(for session: BrowserPermissionSession) -> NSView {
		let promptView = NSVisualEffectView()
		promptView.material = .hudWindow
		promptView.blendingMode = .withinWindow
		promptView.state = .active
		promptView.wantsLayer = true
		promptView.layer?.cornerRadius = 14
		promptView.layer?.masksToBounds = true
		promptView.layer?.borderWidth = 1
		promptView.layer?.borderColor = NSColor.separatorColor.cgColor

		let stackView = NSStackView()
		stackView.orientation = .vertical
		stackView.spacing = 10
		stackView.alignment = .leading
		stackView.translatesAutoresizingMaskIntoConstraints = false
		promptView.addSubview(stackView)

		let titleLabel = NSTextField(wrappingLabelWithString: promptTitle(for: session))
		titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
		titleLabel.maximumNumberOfLines = 0

		let subtitleLabel = NSTextField(wrappingLabelWithString: promptSubtitle(for: session))
		subtitleLabel.font = .systemFont(ofSize: 12)
		subtitleLabel.textColor = .secondaryLabelColor
		subtitleLabel.maximumNumberOfLines = 0

		stackView.addArrangedSubview(titleLabel)
		stackView.addArrangedSubview(subtitleLabel)

		let permissionsStack = NSStackView()
		permissionsStack.orientation = .vertical
		permissionsStack.spacing = 4
		permissionsStack.alignment = .leading
		for kind in session.promptKinds.kinds {
			let label = NSTextField(labelWithString: "• \(permissionKindTitle(kind))")
			label.font = .systemFont(ofSize: 12, weight: .medium)
			permissionsStack.addArrangedSubview(label)
		}
		stackView.addArrangedSubview(permissionsStack)

		let nextRememberButton = NSButton(
			checkboxWithTitle: localize(.remember),
			target: nil,
			action: nil
		)
		stackView.addArrangedSubview(nextRememberButton)
		rememberButton = nextRememberButton

		let buttonsStack = NSStackView()
		buttonsStack.orientation = .horizontal
		buttonsStack.spacing = 8
		buttonsStack.alignment = .centerY

		let cancelButton = NSButton(
			title: localize(.notNow),
			target: self,
			action: #selector(handleCancel)
		)
		let denyButton = NSButton(
			title: localize(.deny),
			target: self,
			action: #selector(handleDeny)
		)
		let allowButton = NSButton(
			title: localize(.allow),
			target: self,
			action: #selector(handleAllow)
		)
		allowButton.bezelStyle = .rounded
		denyButton.bezelStyle = .rounded
		cancelButton.bezelStyle = .rounded

		buttonsStack.addArrangedSubview(cancelButton)
		buttonsStack.addArrangedSubview(denyButton)
		buttonsStack.addArrangedSubview(allowButton)
		stackView.addArrangedSubview(buttonsStack)

		NSLayoutConstraint.activate([
			stackView.topAnchor.constraint(equalTo: promptView.topAnchor, constant: 14),
			stackView.leadingAnchor.constraint(equalTo: promptView.leadingAnchor, constant: 14),
			stackView.trailingAnchor.constraint(equalTo: promptView.trailingAnchor, constant: -14),
			stackView.bottomAnchor.constraint(equalTo: promptView.bottomAnchor, constant: -14),
		])

		return promptView
	}

	private func promptTitle(for session: BrowserPermissionSession) -> String {
		let requestingOrigin = session.origin.requestingOrigin
		let topLevelOrigin = session.origin.topLevelOrigin
		if requestingOrigin == topLevelOrigin || topLevelOrigin.isEmpty {
			return localizedFormat(.titleSameOrigin, requestingOrigin)
		}
		return localizedFormat(
			.titleCrossOrigin,
			requestingOrigin,
			topLevelOrigin
		)
	}

	private func promptSubtitle(for session: BrowserPermissionSession) -> String {
		switch session.source {
		case .mediaAccess:
			return localize(.subtitleMedia)
		case .permissionPrompt:
			return localize(.subtitlePermission)
		}
	}

	private func permissionKindTitle(_ kind: BrowserPermissionKind) -> String {
		switch kind {
		case .camera:
			localize(.kindCamera)
		case .microphone:
			localize(.kindMicrophone)
		case .geolocation:
			localize(.kindLocation)
		}
	}

	private func localizedFormat(_ key: BrowserPermissionPromptLocalizationKey, _ arguments: CVarArg...) -> String {
		String(format: localize(key), arguments: arguments)
	}

	@objc
	private func handleAllow() {
		decisionHandler?(.allow, currentPersistence())
	}

	@objc
	private func handleDeny() {
		decisionHandler?(.deny, currentPersistence())
	}

	@objc
	private func handleCancel() {
		cancelHandler?()
	}

	private func currentPersistence() -> BrowserPermissionPersistence {
		rememberButton?.state == .on ? .remember : .session
	}

	#if DEBUG
		var isVisibleForTesting: Bool {
			hostView.isHidden == false && promptView != nil
		}

		var textValuesForTesting: [String] {
			guard let promptView else { return [] }
			return collectTextValues(from: promptView)
		}

		func setRememberForTesting(_ remember: Bool) {
			rememberButton?.state = remember ? .on : .off
		}

		func performAllowForTesting() {
			handleAllow()
		}

		func performDenyForTesting() {
			handleDeny()
		}

		func performCancelForTesting() {
			handleCancel()
		}

		private func collectTextValues(from view: NSView) -> [String] {
			var values = [String]()
			if let textField = view as? NSTextField {
				values.append(textField.stringValue)
			}
			if let button = view as? NSButton {
				values.append(button.title)
			}
			for subview in view.subviews {
				values.append(contentsOf: collectTextValues(from: subview))
			}
			return values
		}
	#endif
}
