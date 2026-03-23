import BrowserSidebar
import Foundation
import Observation

@MainActor
@Observable
final class BrowserTabHostViewModel {
	struct HostedTab: Equatable {
		let id: BrowserTabID
		let initialURL: String
	}

	struct SyncResult: Equatable {
		let tabsToAdd: [HostedTab]
		let tabIDsToRemove: [BrowserTabID]
		let selectedTabID: BrowserTabID?
	}

	private var hostedTabsByID = [BrowserTabID: HostedTab]()

	func sync(
		tabs: [BrowserTabViewModel],
		selectedTabID: BrowserTabID?
	) -> SyncResult {
		let desiredTabs = tabs.map { HostedTab(id: $0.id, initialURL: $0.currentURL) }
		let desiredTabIDs = Set(desiredTabs.map(\.id))
		let existingTabIDs = Set(hostedTabsByID.keys)

		let tabsToAdd = desiredTabs.filter { hostedTabsByID[$0.id] == nil }
		let tabIDsToRemove = existingTabIDs.subtracting(desiredTabIDs).sorted(by: compareTabIDs)

		for hostedTab in tabsToAdd {
			hostedTabsByID[hostedTab.id] = hostedTab
		}
		for tabID in tabIDsToRemove {
			hostedTabsByID.removeValue(forKey: tabID)
		}

		return SyncResult(
			tabsToAdd: tabsToAdd,
			tabIDsToRemove: tabIDsToRemove,
			selectedTabID: selectedTabID
		)
	}

	private func compareTabIDs(_ lhs: BrowserTabID, _ rhs: BrowserTabID) -> Bool {
		lhs.uuidString < rhs.uuidString
	}
}
