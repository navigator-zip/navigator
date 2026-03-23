import Foundation

enum BrowserSidebarTabSection {
	case pinned
	case unpinned
}

struct BrowserSidebarDisplayedTabs {
	let pinned: [BrowserTabViewModel]
	let unpinned: [BrowserTabViewModel]

	func tabs(in section: BrowserSidebarTabSection) -> [BrowserTabViewModel] {
		switch section {
		case .pinned:
			pinned
		case .unpinned:
			unpinned
		}
	}

	func translatedSourceIndexes(
		for section: BrowserSidebarTabSection,
		from source: IndexSet
	) -> IndexSet? {
		let sectionTabs = tabs(in: section)
		guard source.allSatisfy(sectionTabs.indices.contains) else { return nil }
		let offset = sectionOffset(for: section)
		return IndexSet(source.map { $0 + offset })
	}

	func translatedDestinationIndex(
		for section: BrowserSidebarTabSection,
		destination: Int
	) -> Int {
		let sectionTabs = tabs(in: section)
		let clampedDestination = min(max(destination, 0), sectionTabs.count)
		return sectionOffset(for: section) + clampedDestination
	}

	private func sectionOffset(for section: BrowserSidebarTabSection) -> Int {
		switch section {
		case .pinned:
			0
		case .unpinned:
			pinned.count
		}
	}
}
