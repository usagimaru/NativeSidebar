import Foundation


struct SidebarDifference {

	enum Operation {
		case remove(SidebarElement.ID, parentID: SidebarElement.ID?, index: Int)
		case insert(SidebarElement.ID, parentID: SidebarElement.ID?, index: Int)
		case move(SidebarElement.ID,
				  fromParentID: SidebarElement.ID?,
				  fromIndex: Int,
				  toParentID: SidebarElement.ID?,
				  toIndex: Int)
	}

	private(set) var operations = [Operation]()
	private(set) var reloadedIDs = [SidebarElement.ID]()

	var isEmpty: Bool {
		self.operations.isEmpty && self.reloadedIDs.isEmpty
	}

}


// MARK: - 差分の導出

extension SidebarDifference {

	static func between(_ old: SidebarSnapshot,
						_ new: SidebarSnapshot,
						reloadedIDs: [SidebarElement.ID] = []) -> SidebarDifference
	{
		var difference = SidebarDifference()
		var working = WorkingStructure(snapshot: old)

		let oldIDs = old.allIDs
		let newIDs = new.allIDs
		// 新しい親ごと現れる行は親の挿入に伴って読み込まれるため、古い位置からは消しておく
		let vanished = oldIDs.subtracting(newIDs).union(Self.adopted(by: newIDs.subtracting(oldIDs),
																	 in: new,
																	 among: oldIDs))
		let survived = oldIDs.subtracting(vanished)

		difference.operations += Self.removals(from: old, vanished: vanished, working: &working)
		difference.operations += Self.reconciliation(to: new, survived: survived, working: &working)
		difference.reloadedIDs = reloadedIDs.filter { survived.contains($0) }

		return difference
	}

	private static func adopted(by insertedIDs: Set<SidebarElement.ID>,
								in new: SidebarSnapshot,
								among oldIDs: Set<SidebarElement.ID>) -> Set<SidebarElement.ID>
	{
		guard !insertedIDs.isEmpty else {
			return []
		}
		return oldIDs.filter { id in
			var ancestorID = new.parentID(of: id)
			while let current = ancestorID {
				if insertedIDs.contains(current) {
					return true
				}
				ancestorID = new.parentID(of: current)
			}
			return false
		}
	}

	/// 消える部分木は根だけを取り除く。子まで出すと一覧ビュー側で二重に消える
	private static func removals(from old: SidebarSnapshot,
								 vanished: Set<SidebarElement.ID>,
								 working: inout WorkingStructure) -> [Operation]
	{
		let removed = vanished
		let roots = removed.filter { id in
			guard let parentID = old.parentID(of: id) else {
				return true
			}
			return !removed.contains(parentID)
		}

		let ordered = roots.sorted { (old.childIndex(of: $0) ?? 0) > (old.childIndex(of: $1) ?? 0) }

		var operations = [Operation]()
		for id in ordered {
			guard let location = working.location(of: id) else {
				continue
			}
			operations.append(.remove(id, parentID: location.parentID, index: location.index))
			working.removeSubtree(id)
		}
		return operations
	}

	private static func reconciliation(to new: SidebarSnapshot,
									   survived: Set<SidebarElement.ID>,
									   working: inout WorkingStructure) -> [Operation]
	{
		var operations = [Operation]()
		var parents: [SidebarElement.ID?] = [nil]
		var visited = 0

		while visited < parents.count {
			let parentID = parents[visited]
			visited += 1

			let desired = new.children(of: parentID)
			for (index, id) in desired.enumerated() {
				if survived.contains(id) {
					if let location = working.location(of: id),
					   location.parentID != parentID || location.index != index {
						operations.append(.move(id,
												fromParentID: location.parentID,
												fromIndex: location.index,
												toParentID: parentID,
												toIndex: index))
					}
					working.move(id, toParentID: parentID, at: index)
					parents.append(id)
				}
				else {
					operations.append(.insert(id, parentID: parentID, index: index))
					working.insertSubtree(id, from: new, parentID: parentID, at: index)
					// 新しい行の子は一覧ビューが親の挿入に伴って読み込むため、個別には出さない
				}
			}
		}
		return operations
	}

}


// MARK: - 適用途中の構造

private struct WorkingStructure {

	private var childIDs = [SidebarElement.ID?: [SidebarElement.ID]]()
	private var parentIDs = [SidebarElement.ID: SidebarElement.ID]()

	init(snapshot: SidebarSnapshot) {
		self.childIDs[nil] = snapshot.rootIDs
		for id in snapshot.orderedIDs {
			self.childIDs[id] = snapshot.children(of: id)
			self.parentIDs[id] = snapshot.parentID(of: id)
		}
	}

	func location(of id: SidebarElement.ID) -> SidebarTree.Location? {
		let parentID = self.parentIDs[id]
		guard let index = self.childIDs[parentID]?.firstIndex(of: id) else {
			return nil
		}
		return (parentID, index)
	}

	mutating func move(_ id: SidebarElement.ID, toParentID parentID: SidebarElement.ID?, at index: Int) {
		self.detach(id)
		self.attach(id, parentID: parentID, at: index)
	}

	mutating func insertSubtree(_ id: SidebarElement.ID,
								from snapshot: SidebarSnapshot,
								parentID: SidebarElement.ID?,
								at index: Int)
	{
		self.detach(id)
		self.attach(id, parentID: parentID, at: index)
		self.childIDs[id] = []
		for (childIndex, childID) in snapshot.children(of: id).enumerated() {
			self.insertSubtree(childID, from: snapshot, parentID: id, at: childIndex)
		}
	}

	mutating func removeSubtree(_ id: SidebarElement.ID) {
		for child in self.childIDs[id] ?? [] {
			self.removeSubtree(child)
		}
		self.detach(id)
		self.childIDs[id] = nil
	}

	private mutating func detach(_ id: SidebarElement.ID) {
		let parentID = self.parentIDs[id]
		if let position = self.childIDs[parentID]?.firstIndex(of: id) {
			self.childIDs[parentID]?.remove(at: position)
		}
		self.parentIDs[id] = nil
	}

	private mutating func attach(_ id: SidebarElement.ID, parentID: SidebarElement.ID?, at index: Int) {
		var children = self.childIDs[parentID] ?? []
		children.insert(id, at: min(max(index, 0), children.count))
		self.childIDs[parentID] = children
		self.parentIDs[id] = parentID
	}

}
