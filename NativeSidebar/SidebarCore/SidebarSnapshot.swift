import Foundation


struct SidebarSnapshot {

	private(set) var rootIDs = [SidebarElement.ID]()
	private(set) var orderedIDs = [SidebarElement.ID]()

	private var elements = [SidebarElement.ID: SidebarElement]()
	private var childIDs = [SidebarElement.ID: [SidebarElement.ID]]()
	private var parentIDs = [SidebarElement.ID: SidebarElement.ID]()

	init() {}

	init(tree: SidebarTree) {
		self.rootIDs = tree.roots.map(\.id)
		self.collect(tree.roots, parentID: nil)
	}

	private mutating func collect(_ nodes: [SidebarNode], parentID: SidebarElement.ID?) {
		for node in nodes {
			self.elements[node.id] = node.element
			self.childIDs[node.id] = node.children.map(\.id)
			self.parentIDs[node.id] = parentID
			self.orderedIDs.append(node.id)
			self.collect(node.children, parentID: node.id)
		}
	}

}


// MARK: - 参照

extension SidebarSnapshot {

	var allIDs: Set<SidebarElement.ID> {
		Set(self.orderedIDs)
	}

	func element(_ id: SidebarElement.ID) -> SidebarElement? {
		self.elements[id]
	}

	func contains(_ id: SidebarElement.ID) -> Bool {
		self.elements[id] != nil
	}

	func parentID(of id: SidebarElement.ID) -> SidebarElement.ID? {
		self.parentIDs[id]
	}

	func children(of parentID: SidebarElement.ID?) -> [SidebarElement.ID] {
		guard let parentID else {
			return self.rootIDs
		}
		return self.childIDs[parentID] ?? []
	}

	func childIndex(of id: SidebarElement.ID) -> Int? {
		self.children(of: self.parentID(of: id)).firstIndex(of: id)
	}

	func depth(of id: SidebarElement.ID) -> Int {
		var depth = 0
		var current = self.parentID(of: id)
		while let parentID = current {
			depth += 1
			current = self.parentID(of: parentID)
		}
		return depth
	}

	func selectableIDs() -> [SidebarElement.ID] {
		self.orderedIDs.filter { self.elements[$0]?.kind.isSelectable == true }
	}

}
