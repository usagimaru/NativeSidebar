import Foundation


extension Notification.Name {

	static let noteStoreDidChange = Notification.Name("NoteStoreDidChange")

}


/// 行としての見え方はサイドバー側が決めるため、ここでは扱わない
@MainActor
final class NoteStore {

	private let storage: LibraryStorage

	init(storage: LibraryStorage) {
		self.storage = storage
	}

	func note(_ id: Note.ID) -> Note? {
		let resolved = self.storage.noteID(forRow: id)
		return self.storage.snapshot.notes.first { $0.id == resolved }
	}

	func updateBody(_ id: Note.ID, body: String) {
		let resolved = self.storage.noteID(forRow: id)
		var didChange = false
		self.storage.update { snapshot in
			guard let index = snapshot.notes.firstIndex(where: { $0.id == resolved }),
				  snapshot.notes[index].body != body
			else {
				return
			}
			snapshot.notes[index].body = body
			snapshot.notes[index].modifiedAt = .now
			didChange = true
		}

		guard didChange else {
			return
		}
		self.commit()
	}

	func save() {
		try? self.storage.save()
	}

	private func commit() {
		self.save()
		NotificationCenter.default.post(name: .noteStoreDidChange, object: self)
		NotificationCenter.default.post(name: .sidebarStoreContentsDidChange, object: nil)
	}

}
