import Foundation


struct SidebarSelection {

	private(set) var ids = [SidebarElement.ID]()

	var first: SidebarElement.ID? {
		self.ids.first
	}

	var isEmpty: Bool {
		self.ids.isEmpty
	}

	init(ids: [SidebarElement.ID] = []) {
		self.ids = ids
	}

	func contains(_ id: SidebarElement.ID) -> Bool {
		self.ids.contains(id)
	}

	mutating func update(_ ids: [SidebarElement.ID]) {
		self.ids = ids
	}

	mutating func normalize(within snapshot: SidebarSnapshot) {
		let selectable = snapshot.selectableIDs()
		let kept = selectable.filter { self.ids.contains($0) }

		if kept.isEmpty {
			self.ids = selectable.first.map { [$0] } ?? []
		}
		else {
			self.ids = kept
		}
	}

}
