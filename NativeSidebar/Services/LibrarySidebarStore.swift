import Foundation


@MainActor
final class LibrarySidebarStore: SidebarStore {

	private let storage: LibraryStorage

	init(storage: LibraryStorage) {
		self.storage = storage
	}

}


// MARK: - SidebarStore

extension LibrarySidebarStore {

	func load() throws -> SidebarContents {
		var contents = SidebarContents(tree: SidebarTree(), descriptions: [:])
		contents.tree.roots = self.nodes(parentID: nil)

		for record in self.storage.snapshot.sidebarRecords {
			contents.descriptions[record.element.id] = record.description
		}
		for note in self.storage.snapshot.notes {
			contents.descriptions[note.id] = Self.description(of: note)
		}
		for scopeID in self.storage.snapshot.scopes.keys {
			for note in self.storage.notes(under: scopeID) {
				let rowID = self.storage.rowID(for: note.id, under: scopeID)
				contents.descriptions[rowID] = Self.description(of: note)
			}
		}

		return contents
	}

	func insert(_ element: SidebarElement,
				parentID: SidebarElement.ID?,
				index: Int,
				description: SidebarItemDescription) throws
	{
		self.storage.update { snapshot in
			if element.kind == .note {
				var containerIDs = Set<NoteContainerID>()
				if let parentID, snapshot.scopes[parentID] == nil {
					containerIDs.insert(parentID)
				}

				snapshot.notes.append(Note(id: element.id,
										   containerIDs: containerIDs,
										   body: description.name))
			}
			else {
				let accepted = element.acceptedKinds.isEmpty ? nil : element.acceptedKinds
				snapshot.sidebarRecords.append(LibrarySnapshot.SidebarRecord(element: element,
																			 parentID: parentID,
																			 order: index,
																			 description: description,
																			 acceptedKinds: accepted))
			}
		}
	}

	func update(_ id: SidebarElement.ID, description: SidebarItemDescription) throws {
		let noteID = self.storage.noteID(forRow: id)
		self.storage.update { snapshot in
			if let note = snapshot.notes.firstIndex(where: { $0.id == noteID }) {
				snapshot.notes[note].body = snapshot.notes[note].replacingTitle(with: description.name)
				snapshot.notes[note].modifiedAt = .now
				return
			}
			guard let index = snapshot.sidebarRecords.firstIndex(where: { $0.element.id == id }) else {
				return
			}
			snapshot.sidebarRecords[index].description = description
		}
	}

	func move(_ id: SidebarElement.ID,
			  from previousParentID: SidebarElement.ID?,
			  to parentID: SidebarElement.ID?,
			  index: Int) throws
	{
		let noteID = self.storage.noteID(forRow: id)
		self.storage.update { snapshot in
			if let note = snapshot.notes.firstIndex(where: { $0.id == noteID }) {
				guard let parentID else {
					return
				}

				if snapshot.scopes[parentID] == .recentlyDeleted {
					snapshot.notes[note].deletedAt = snapshot.notes[note].deletedAt ?? .now
					return
				}
				snapshot.notes[note].deletedAt = nil

				if snapshot.scopes[parentID] != nil {
					snapshot.notes[note].containerIDs = []
				}
				// 条件で集めた行から引いた場合は、外す元がどれか決まらないので移動先だけにする
				else if let previousParentID, snapshot.scopes[previousParentID] == nil {
					snapshot.notes[note].containerIDs.remove(previousParentID)
					snapshot.notes[note].containerIDs.insert(parentID)
				}
				else {
					snapshot.notes[note].containerIDs = [parentID]
				}

				Self.reposition(noteID, under: parentID, to: index, in: &snapshot)
				return
			}
			guard let position = snapshot.sidebarRecords.firstIndex(where: { $0.element.id == id }) else {
				return
			}
			snapshot.sidebarRecords[position].parentID = parentID
			snapshot.sidebarRecords[position].order = index
		}
	}

	func remove(_ id: SidebarElement.ID) throws {
		let noteID = self.storage.noteID(forRow: id)
		if self.storage.snapshot.notes.contains(where: { $0.id == noteID }) {
			self.storage.update { snapshot in
				guard let note = snapshot.notes.firstIndex(where: { $0.id == noteID }) else {
					return
				}

				guard snapshot.notes[note].isDeleted else {
					snapshot.notes[note].deletedAt = .now
					return
				}
				snapshot.notes.remove(at: note)
			}
			return
		}

		let descendants = self.descendantIDs(of: id).union([id])
		self.storage.update { snapshot in
			snapshot.sidebarRecords.removeAll { descendants.contains($0.element.id) }
			snapshot.notes.removeAll { descendants.contains($0.id) }
			for index in snapshot.notes.indices {
				snapshot.notes[index].containerIDs.subtract(descendants)
			}
			for identifier in descendants {
				snapshot.scopes[identifier] = nil
			}
		}
	}

	func rowID(for id: SidebarElement.ID, under parentID: SidebarElement.ID?) -> SidebarElement.ID {
		let noteID = self.storage.noteID(forRow: id)
		guard let parentID, self.storage.snapshot.scopes[parentID] != nil else {
			return noteID
		}
		return self.storage.rowID(for: noteID, under: parentID)
	}

	func commit(tree: SidebarTree) throws {
		self.storage.update { snapshot in
			Self.rewriteOrder(of: tree.roots, parentID: nil, in: &snapshot)
		}
		try self.storage.save()
		NotificationCenter.default.post(name: .sidebarStoreContentsDidChange, object: self)
		NotificationCenter.default.post(name: .noteStoreDidChange, object: nil)
	}

}


// MARK: - 内部

private extension LibrarySidebarStore {

	func nodes(parentID: SidebarElement.ID?) -> [SidebarNode] {
		let records = self.storage.snapshot.sidebarRecords
			.filter { $0.parentID == parentID }
			.sorted { $0.order < $1.order }
			.map { record in
				SidebarNode(SidebarElement(id: record.element.id,
										   kind: record.element.kind,
										   accepting: self.acceptedKinds(of: record),
										   allowingNewItems: self.storage.snapshot.scopes[record.element.id] != .recentlyDeleted),
							children: self.nodes(parentID: record.element.id))
			}

		guard let parentID else {
			return records
		}

		if self.storage.snapshot.scopes[parentID] != nil {
			return self.storage.notes(under: parentID).map { note in
				SidebarNode(SidebarElement(id: self.storage.rowID(for: note.id, under: parentID),
										   kind: .note,
										   isReference: true))
			}
		}

		// 本文を書くたびに行が動かないよう、更新日時では並べ替えない
		let notes = self.storage.snapshot.notes
			.filter { !$0.isDeleted && $0.containerIDs.contains(parentID) }
			.map { SidebarNode(SidebarElement(id: $0.id, kind: .note)) }

		return records + notes
	}

	func acceptedKinds(of record: LibrarySnapshot.SidebarRecord) -> Set<SidebarElement.Kind>? {
		switch self.storage.snapshot.scopes[record.element.id] {
			case .allNotes, .recentlyDeleted:
				return (record.acceptedKinds ?? []).union([.note])

			default:
				return record.acceptedKinds
		}
	}

	static func reposition(_ noteID: Note.ID,
						   under parentID: SidebarElement.ID,
						   to offset: Int,
						   in snapshot: inout LibrarySnapshot)
	{
		guard let current = snapshot.notes.firstIndex(where: { $0.id == noteID }) else {
			return
		}

		let note = snapshot.notes.remove(at: current)
		let siblings = snapshot.notes.indices.filter {
			snapshot.scopes[parentID] != nil || snapshot.notes[$0].containerIDs.contains(parentID)
		}
		let destination = offset < siblings.count ? siblings[offset] : snapshot.notes.count
		snapshot.notes.insert(note, at: destination)
	}

	static func description(of note: Note) -> SidebarItemDescription {
		SidebarItemDescription(name: note.title,
							   symbolName: "text.document")
	}

	func descendantIDs(of id: SidebarElement.ID) -> Set<SidebarElement.ID> {
		var collected = Set<SidebarElement.ID>()
		for record in self.storage.snapshot.sidebarRecords where record.parentID == id {
			collected.insert(record.element.id)
			collected.formUnion(self.descendantIDs(of: record.element.id))
		}
		return collected
	}

	/// ノートは記録を持たないため、並び順の書き戻しから外す
	static func rewriteOrder(of nodes: [SidebarNode],
							 parentID: SidebarElement.ID?,
							 in snapshot: inout LibrarySnapshot)
	{
		var order = 0
		for node in nodes where node.element.kind != .note {
			if let position = snapshot.sidebarRecords.firstIndex(where: { $0.element.id == node.id }) {
				snapshot.sidebarRecords[position].parentID = parentID
				snapshot.sidebarRecords[position].order = order
			}
			order += 1
			Self.rewriteOrder(of: node.children, parentID: node.id, in: &snapshot)
		}
	}

}
