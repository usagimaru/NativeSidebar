import CryptoKit
import Foundation


struct LibrarySnapshot {

	struct SidebarRecord: Codable {
		var element: SidebarElement
		var parentID: SidebarElement.ID?
		var order: Int
		var description: SidebarItemDescription
		/// 見出しが受け入れる種別はセクションごとに違うため、ここだけは保存する
		var acceptedKinds: Set<SidebarElement.Kind>?
	}

	static let currentVersion = 2

	var version: Int?
	var sidebarRecords = [SidebarRecord]()
	var notes = [Note]()
	/// 置き場所を持つものは識別子でそのまま引けるため、条件で決まる範囲の分だけ持つ
	var scopes = [NoteContainerID: NoteScope]()

}


/// ノートは1件ずつ別のファイルへ分けるため、ここには並び順だけを持つ
private struct LibraryIndex: Codable {

	var version: Int?
	var sidebarRecords: [LibrarySnapshot.SidebarRecord]
	var scopes: [NoteContainerID: NoteScope]
	var noteOrder: [Note.ID]

}


@MainActor
final class LibraryStorage {

	private(set) var snapshot: LibrarySnapshot

	let directoryURL: URL

	private var mirrorRowIDs = [Pair: SidebarElement.ID]()
	private var mirroredNoteIDs = [SidebarElement.ID: Note.ID]()

	var indexURL: URL {
		self.directoryURL.appending(path: "index.json")
	}

	var deletedDirectoryURL: URL {
		self.directoryURL.appending(path: Self.deletedDirectoryName)
	}

	private static let deletedDirectoryName = "Deleted"

	init(directoryURL: URL = LibraryStorage.defaultDirectoryURL) {
		self.directoryURL = directoryURL
		self.snapshot = Self.loaded(from: directoryURL) ?? LibrarySnapshot.seeded()
	}

	func update(_ body: (inout LibrarySnapshot) -> Void) {
		body(&self.snapshot)
	}

	func notes(matching scope: NoteScope) -> [Note] {
		let living = self.snapshot.notes.filter { !$0.isDeleted }

		switch scope {
			case .allNotes:
				return living

			case .flagged, .shared:
				return []

			case .thisWeek:
				let threshold = Date.now.addingTimeInterval(-7 * 24 * 60 * 60)
				return living.filter { $0.modifiedAt >= threshold }

			case .recentlyDeleted:
				return self.snapshot.notes.filter(\.isDeleted)
		}
	}

	/// 同じノートが所属フォルダと条件の行の両方に出るため、条件の行の下では別の行識別子を使う
	func rowID(for note: Note.ID, under scopeID: SidebarElement.ID) -> SidebarElement.ID {
		let key = Pair(scopeID: scopeID, noteID: note)
		if let existing = self.mirrorRowIDs[key] {
			return existing
		}

		let id = Self.derivedID(from: scopeID, and: note)
		self.mirrorRowIDs[key] = id
		self.mirroredNoteIDs[id] = note
		return id
	}

	private static func derivedID(from scopeID: SidebarElement.ID, and noteID: Note.ID) -> SidebarElement.ID {
		var hasher = SHA256()
		withUnsafeBytes(of: scopeID.uuid) { hasher.update(bufferPointer: $0) }
		withUnsafeBytes(of: noteID.uuid) { hasher.update(bufferPointer: $0) }

		let digest = Array(hasher.finalize().prefix(MemoryLayout<uuid_t>.size))
		return digest.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
	}

	func noteID(forRow id: SidebarElement.ID) -> Note.ID {
		self.mirroredNoteIDs[id] ?? id
	}

	private struct Pair: Hashable {
		let scopeID: SidebarElement.ID
		let noteID: Note.ID
	}

	func save() throws {
		try FileManager.default.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: self.deletedDirectoryURL, withIntermediateDirectories: true)

		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

		let index = LibraryIndex(version: LibrarySnapshot.currentVersion,
								 sidebarRecords: self.snapshot.sidebarRecords,
								 scopes: self.snapshot.scopes,
								 noteOrder: self.snapshot.notes.map(\.id))
		try encoder.encode(index).write(to: self.indexURL, options: .atomic)

		var written = [URL: Set<String>]()
		for note in self.snapshot.notes {
			let directory = note.isDeleted ? self.deletedDirectoryURL : self.directoryURL
			let url = Self.noteURL(for: note.id, in: directory)
			written[directory, default: []].insert(url.lastPathComponent)
			try encoder.encode(note).write(to: url, options: .atomic)
		}

		for directory in [self.directoryURL, self.deletedDirectoryURL] {
			let keptNames = written[directory] ?? []
			for url in Self.noteFileURLs(in: directory) where !keptNames.contains(url.lastPathComponent) {
				try? FileManager.default.removeItem(at: url)
			}
		}
	}

	private static func loaded(from directory: URL) -> LibrarySnapshot? {
		guard let data = try? Data(contentsOf: directory.appending(path: "index.json")),
			  let index = try? JSONDecoder().decode(LibraryIndex.self, from: data),
			  index.version == LibrarySnapshot.currentVersion
		else {
			return nil
		}

		let fileURLs = Self.noteFileURLs(in: directory)
			+ Self.noteFileURLs(in: directory.appending(path: Self.deletedDirectoryName))
		let notes = fileURLs
			.compactMap { try? Data(contentsOf: $0) }
			.compactMap { try? JSONDecoder().decode(Note.self, from: $0) }

		// 読み込む順はファイルの並びに左右されるため、目録の並びへ戻す
		let positions = Dictionary(uniqueKeysWithValues: index.noteOrder.enumerated().map { ($0.element, $0.offset) })

		var snapshot = LibrarySnapshot()
		snapshot.version = index.version
		snapshot.sidebarRecords = index.sidebarRecords
		snapshot.scopes = index.scopes
		snapshot.notes = notes.sorted { positions[$0.id] ?? .max < positions[$1.id] ?? .max }
		return snapshot
	}

	private static func noteURL(for id: Note.ID, in directory: URL) -> URL {
		directory.appending(path: "\(id.uuidString).json")
	}

	private static func noteFileURLs(in directory: URL) -> [URL] {
		let contents = (try? FileManager.default.contentsOfDirectory(at: directory,
																	 includingPropertiesForKeys: nil)) ?? []
		return contents.filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
	}

	nonisolated static var defaultDirectoryURL: URL {
		let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
		let identifier = Bundle.main.bundleIdentifier ?? "NativeSidebar"
		return base.appending(path: identifier)
	}

}


// MARK: - 初期データ

private extension LibrarySnapshot {

	static func seeded() -> LibrarySnapshot {
		var snapshot = LibrarySnapshot()
		snapshot.version = LibrarySnapshot.currentVersion

		let library = snapshot.append(.group,
									  name: String(localized: "Library"),
									  symbolName: "books.vertical",
									  accepting: [.builtIn])
		let allNotes = snapshot.append(.builtIn,
									   name: String(localized: "All Notes"),
									   symbolName: "tray.full",
									   parentID: library)
		let shared = snapshot.append(.builtIn,
									 name: String(localized: "Shared"),
									 symbolName: "person.2",
									 parentID: library)
		let deleted = snapshot.append(.builtIn,
									  name: String(localized: "Recently Deleted"),
									  symbolName: "trash",
									  parentID: library)
		snapshot.scopes = [allNotes: .allNotes, shared: .shared, deleted: .recentlyDeleted]

		let collections = snapshot.append(.group,
										name: String(localized: "Collections"),
										symbolName: "folder",
										accepting: [.folder, .note])
		let work = snapshot.append(.folder,
								   name: String(localized: "Work"),
								   symbolName: "folder",
								   parentID: collections)
		let meetings = snapshot.append(.folder,
									   name: String(localized: "Meetings"),
									   symbolName: "folder",
									   parentID: work)
		snapshot.append(.folder,
						name: String(localized: "Invoices"),
						symbolName: "folder",
						parentID: work)
		let personal = snapshot.append(.folder,
									   name: String(localized: "Personal"),
									   symbolName: "folder",
									   parentID: collections)
		snapshot.append(.folder,
						name: String(localized: "Travel"),
						symbolName: "folder",
						parentID: collections)

		let smartFolders = snapshot.append(.group,
										   name: String(localized: "Smart Folders"),
										   symbolName: "folder.badge.gearshape",
										   accepting: [.smartFolder])
		let flagged = snapshot.append(.smartFolder,
									  name: String(localized: "Flagged"),
									  symbolName: "folder.badge.gearshape",
									  parentID: smartFolders)
		let thisWeek = snapshot.append(.smartFolder,
									   name: String(localized: "This Week"),
									   symbolName: "folder.badge.gearshape",
									   parentID: smartFolders)
		snapshot.scopes[flagged] = .flagged
		snapshot.scopes[thisWeek] = .thisWeek

		snapshot.notes = [
			Note(containerIDs: [meetings],
				 body: String(localized: "SEED_NOTE_WEEKLY_SYNC_BODY",
							  defaultValue: "Weekly Sync\nAgenda and follow-ups.")),
			Note(containerIDs: [meetings],
				 body: String(localized: "SEED_NOTE_DESIGN_REVIEW_BODY",
							  defaultValue: "Design Review\nNotes from the sidebar walkthrough.")),
			Note(containerIDs: [personal],
				 body: String(localized: "SEED_NOTE_READING_LIST_BODY",
							  defaultValue: "Reading List\n- Model-Based UI Design")),
		]

		return snapshot
	}

	@discardableResult
	mutating func append(_ kind: SidebarElement.Kind,
						 name: String,
						 symbolName: String,
						 accepting acceptedKinds: Set<SidebarElement.Kind>? = nil,
						 parentID: SidebarElement.ID? = nil) -> SidebarElement.ID
	{
		let element = SidebarElement(kind: kind, accepting: acceptedKinds)
		let order = self.sidebarRecords.filter { $0.parentID == parentID }.count
		self.sidebarRecords.append(SidebarRecord(element: element,
												 parentID: parentID,
												 order: order,
												 description: SidebarItemDescription(name: name,
																					 symbolName: symbolName),
												 acceptedKinds: acceptedKinds))
		return element.id
	}

}
