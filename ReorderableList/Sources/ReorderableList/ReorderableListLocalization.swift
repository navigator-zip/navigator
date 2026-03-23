import Foundation

private enum ReorderableListLocalizationKey: String {
	case reorderStarted = "reorderableList.announcement.reorderStarted"
	case reorderDestination = "reorderableList.announcement.reorderDestination"
	case reorderCompleted = "reorderableList.announcement.reorderCompleted"
	case reorderCancelled = "reorderableList.announcement.reorderCancelled"
}

private extension String.LocalizationValue {
	init(_ key: ReorderableListLocalizationKey) {
		self.init(key.rawValue)
	}
}

private func reorderableListLocalized(_ key: ReorderableListLocalizationKey) -> String {
	String(localized: String.LocalizationValue(key), bundle: .module)
}

func reorderableListReorderStartedAnnouncement(position: Int, totalCount: Int) -> String {
	String(
		format: reorderableListLocalized(.reorderStarted),
		locale: Locale.current,
		position,
		totalCount
	)
}

func reorderableListDestinationAnnouncement(position: Int, totalCount: Int) -> String {
	String(
		format: reorderableListLocalized(.reorderDestination),
		locale: Locale.current,
		position,
		totalCount
	)
}

func reorderableListCompletedAnnouncement(from: Int, to: Int) -> String {
	String(
		format: reorderableListLocalized(.reorderCompleted),
		locale: Locale.current,
		from,
		to
	)
}

func reorderableListCancelledAnnouncement() -> String {
	reorderableListLocalized(.reorderCancelled)
}
