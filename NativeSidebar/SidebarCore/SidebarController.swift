import Foundation


enum SidebarMutation {
	case insert(SidebarElement,
				parentID: SidebarElement.ID?,
				index: Int,
				description: SidebarItemDescription)
	case update(SidebarElement.ID, description: SidebarItemDescription)
	case move(SidebarElement.ID, from: SidebarElement.ID?, to: SidebarElement.ID?, index: Int)
	case remove(SidebarElement.ID)
}


@MainActor
protocol SidebarControllerDelegate: AnyObject {

	func sidebarController(_ controller: SidebarController, didProduce difference: SidebarDifference)
	func sidebarControllerDidChangeSelection(_ controller: SidebarController)
	func sidebarController(_ controller: SidebarController, didFailToCommit error: Error)

}


@MainActor
final class SidebarController {

	weak var delegate: SidebarControllerDelegate?

	private(set) var snapshot = SidebarSnapshot()
	private(set) var selection = SidebarSelection()

	var presentation = SidebarPresentation() {
		didSet {
			self.refresh()
		}
	}

	let store: SidebarStore

	private var tree = SidebarTree()
	private var descriptions = [SidebarElement.ID: SidebarItemDescription]()
	private var presentedDescriptions = [SidebarElement.ID: SidebarItemDescription]()

	private var storeObserver: NSObjectProtocol?
	/// 自分が確定させた分の通知は、同じ内容を二度当てることになるので読み飛ばす
	private var pendingOwnCommits = 0

	init(store: SidebarStore) {
		self.store = store
		self.observeStore()
	}

	deinit {
		if let storeObserver = self.storeObserver {
			NotificationCenter.default.removeObserver(storeObserver)
		}
	}

	private func observeStore() {
		self.storeObserver = NotificationCenter.default.addObserver(forName: .sidebarStoreContentsDidChange,
																	object: nil,
																	queue: .main) { [weak self] _ in
			MainActor.assumeIsolated {
				guard let self else {
					return
				}
				guard self.pendingOwnCommits == 0 else {
					self.pendingOwnCommits -= 1
					return
				}
				self.reload()
			}
		}
	}

}


// MARK: - 読み込み

extension SidebarController {

	func reload() {
		guard let contents = try? self.store.load() else {
			return
		}
		self.tree = contents.tree
		self.descriptions = contents.descriptions
		self.refresh()
	}

	func description(for id: SidebarElement.ID) -> SidebarItemDescription {
		self.descriptions[id] ?? SidebarItemDescription(name: "")
	}

	func name(for id: SidebarElement.ID) -> String {
		self.description(for: id).name
	}

	func element(_ id: SidebarElement.ID) -> SidebarElement? {
		self.snapshot.element(id)
	}

}


// MARK: - 選択

extension SidebarController {

	func select(_ ids: [SidebarElement.ID]) {
		var updated = self.selection
		updated.update(ids)
		updated.normalize(within: self.snapshot)

		guard updated.ids != self.selection.ids else {
			return
		}
		self.selection = updated
		self.delegate?.sidebarControllerDidChangeSelection(self)
	}

}


// MARK: - 編集操作

extension SidebarController {

	func canRename(_ ids: [SidebarElement.ID]) -> Bool {
		ids.count == 1 && ids.allSatisfy { self.element($0)?.kind.isRenamable == true }
	}

	func canRemove(_ ids: [SidebarElement.ID]) -> Bool {
		!ids.isEmpty && ids.allSatisfy { self.element($0)?.kind.isRemovable == true }
	}

	func canMove(_ ids: [SidebarElement.ID]) -> Bool {
		!ids.isEmpty && ids.allSatisfy { self.element($0)?.kind.isMovable == true }
	}

	private func affectsReferences(_ ids: [SidebarElement.ID]) -> Bool {
		ids.contains { self.element($0)?.kind == .note }
	}

	func canAdd(kind: SidebarElement.Kind, near referenceID: SidebarElement.ID?) -> Bool {
		self.insertionPoint(for: kind, near: referenceID) != nil
	}

	func accepts(kind: SidebarElement.Kind, in containerID: SidebarElement.ID) -> Bool {
		self.tree.element(containerID)?.accepts(kind) == true
	}

	@discardableResult
	func add(kind: SidebarElement.Kind,
			 description: SidebarItemDescription,
			 near referenceID: SidebarElement.ID?) -> SidebarElement.ID?
	{
		guard let destination = self.insertionPoint(for: kind, near: referenceID) else {
			return nil
		}

		let siblings = self.tree.children(of: destination.parentID).map { self.name(for: $0.id) }
		var named = description
		named.name = Self.sequencedName(with: description.name, existingNames: siblings)

		let element = SidebarElement(kind: kind)
		self.tree.insert([SidebarNode(element)], parent: destination.parentID, at: destination.index)
		self.descriptions[element.id] = named

		self.commit([.insert(element,
							 parentID: destination.parentID,
							 index: destination.index,
							 description: named)],
					rebuilding: kind == .note)

		return self.presentedID(of: element.id, under: destination.parentID)
	}

	func rename(_ id: SidebarElement.ID, to name: String) {
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, var description = self.descriptions[id], description.name != trimmed else {
			return
		}

		description.name = trimmed
		self.descriptions[id] = description
		self.commit([.update(id, description: description)],
					rebuilding: self.affectsReferences([id]))
	}

	func remove(_ ids: [SidebarElement.ID]) {
		let targets = ids.filter { self.element($0)?.kind.isRemovable == true }
		guard !targets.isEmpty else {
			return
		}

		for id in targets {
			self.tree.remove(id)
		}
		self.commit(targets.map { .remove($0) }, rebuilding: self.affectsReferences(targets))
	}

	@discardableResult
	func move(_ ids: [SidebarElement.ID],
			  toParentID parentID: SidebarElement.ID?,
			  at index: Int) -> [SidebarElement.ID]
	{
		guard self.canMove(ids), self.canPlace(ids, in: parentID) else {
			return ids
		}

		let previousParents = Dictionary(uniqueKeysWithValues: ids.map { ($0, self.tree.location(of: $0)?.parentID) })

		// ツリーは1件が複数の置き場所へ属する状態を表せないため、末端の行はストアへ直接伝える
		if ids.allSatisfy({ self.element($0)?.kind == .note }) {
			let offset = self.noteOffset(at: index, in: parentID)
			self.commit(ids.map { .move($0, from: previousParents[$0] ?? nil, to: parentID, index: offset) },
						rebuilding: true)
			return ids.map { self.presentedID(of: $0, under: parentID) }
		}

		guard self.tree.move(ids, toParent: parentID, at: index) else {
			return ids
		}

		let mutations: [SidebarMutation] = self.tree.orderedByPosition(ids).compactMap { id in
			guard let location = self.tree.location(of: id) else {
				return nil
			}
			return .move(id, from: previousParents[id] ?? nil, to: location.parentID, index: location.index)
		}
		self.commit(mutations)
		return ids
	}

	private func presentedID(of id: SidebarElement.ID, under parentID: SidebarElement.ID?) -> SidebarElement.ID {
		let rowID = self.store.rowID(for: id, under: parentID)
		return self.snapshot.element(rowID) != nil ? rowID : id
	}

	private func noteOffset(at index: Int, in parentID: SidebarElement.ID?) -> Int {
		let children = self.snapshot.children(of: parentID)
		return children.prefix(index).filter { self.element($0)?.kind == .note }.count
	}

	static func sequencedName(with baseName: String,
							  existingNames: [String],
							  strippingSuffix: Bool = false) -> String
	{
		var resolvedBase = baseName
		if strippingSuffix,
		   let range = baseName.range(of: #" \d+$"#, options: .regularExpression) {
			resolvedBase = String(baseName[..<range.lowerBound])
		}

		guard existingNames.contains(resolvedBase) else {
			return resolvedBase
		}

		var count = 2
		while existingNames.contains("\(resolvedBase) \(count)") {
			count += 1
		}
		return "\(resolvedBase) \(count)"
	}

	private func insertionPoint(for kind: SidebarElement.Kind,
								near referenceID: SidebarElement.ID?) -> SidebarTree.Location?
	{
		guard let referenceID, let element = self.tree.element(referenceID) else {
			guard let container = self.tree.firstNode(where: { Self.allowsCreating(kind, in: $0.element) }) else {
				return nil
			}
			return (container.id, container.children.count)
		}

		if Self.allowsCreating(kind, in: element) {
			return (referenceID, self.tree.children(of: referenceID).count)
		}

		guard let location = self.tree.location(of: referenceID),
			  let parentID = location.parentID,
			  let parent = self.tree.element(parentID),
			  Self.allowsCreating(kind, in: parent)
		else {
			return nil
		}
		return (parentID, location.index + 1)
	}

	private static func allowsCreating(_ kind: SidebarElement.Kind, in element: SidebarElement) -> Bool {
		element.allowsNewItems && element.accepts(kind)
	}

	func canPlace(_ ids: [SidebarElement.ID], in parentID: SidebarElement.ID?) -> Bool {
		guard let parentID, let parent = self.tree.element(parentID) else {
			return false
		}
		return ids.allSatisfy { id in
			guard let kind = self.tree.element(id)?.kind else {
				return false
			}
			return parent.accepts(kind)
		}
	}

}


// MARK: - 確定と反映

extension SidebarController {

	private func commit(_ mutations: [SidebarMutation], rebuilding: Bool = false) {
		do {
			// 移動元が生きている必要があるため、削除は最後に適用する
			for mutation in Self.ordered(mutations) {
				switch mutation {
					case let .insert(element, parentID, index, description):
						try self.store.insert(element,
											  parentID: parentID,
											  index: index,
											  description: description)

					case let .update(id, description):
						try self.store.update(id, description: description)

					case let .move(id, previousParentID, parentID, index):
						try self.store.move(id, from: previousParentID, to: parentID, index: index)

					case let .remove(id):
						try self.store.remove(id)
				}
			}
			self.pendingOwnCommits += 1
			try self.store.commit(tree: self.tree)
		}
		catch {
			self.pendingOwnCommits = max(self.pendingOwnCommits - 1, 0)
			self.recover(from: error)
			return
		}

		if rebuilding {
			self.reload()
			return
		}
		self.refresh()
	}

	private func recover(from error: Error) {
		if let contents = try? self.store.load() {
			self.tree = contents.tree
			self.descriptions = contents.descriptions
		}
		self.refresh()
		self.delegate?.sidebarController(self, didFailToCommit: error)
	}

	private func refresh() {
		let presented = self.presentation.apply(to: self.tree) { self.name(for: $0) }
		let updated = SidebarSnapshot(tree: presented)
		let difference = SidebarDifference.between(self.snapshot,
												   updated,
												   reloadedIDs: self.restatedIDs(in: updated))

		self.snapshot = updated
		self.delegate?.sidebarController(self, didProduce: difference)

		var normalized = self.selection
		normalized.normalize(within: updated)
		if normalized.ids != self.selection.ids {
			self.selection = normalized
		}
		self.delegate?.sidebarControllerDidChangeSelection(self)
	}

	/// 同じ実体が複数の行として現れるため、書き換えた行だけでなく表示中の全行を突き合わせる
	private func restatedIDs(in updated: SidebarSnapshot) -> [SidebarElement.ID] {
		var restated = [SidebarElement.ID]()
		var presentedDescriptions = [SidebarElement.ID: SidebarItemDescription]()

		for id in updated.allIDs {
			let description = self.description(for: id)
			presentedDescriptions[id] = description
			if let previous = self.presentedDescriptions[id], previous != description {
				restated.append(id)
			}
		}

		self.presentedDescriptions = presentedDescriptions
		return restated
	}

	private static func ordered(_ mutations: [SidebarMutation]) -> [SidebarMutation] {
		var inserts = [SidebarMutation]()
		var updates = [SidebarMutation]()
		var moves = [SidebarMutation]()
		var removals = [SidebarMutation]()

		for mutation in mutations {
			switch mutation {
				case .insert:
					inserts.append(mutation)

				case .update:
					updates.append(mutation)

				case .move:
					moves.append(mutation)

				case .remove:
					removals.append(mutation)
			}
		}

		return inserts + updates + moves + removals
	}

}
