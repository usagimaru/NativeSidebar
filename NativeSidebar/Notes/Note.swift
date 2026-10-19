import Foundation


typealias NoteContainerID = UUID


struct Note: Identifiable, Hashable, Codable {

	let id: UUID
	var containerIDs: Set<NoteContainerID>
	var body: String
	var modifiedAt: Date
	var deletedAt: Date?

	init(id: UUID = UUID(),
		 containerIDs: Set<NoteContainerID>,
		 body: String = "",
		 modifiedAt: Date = .now,
		 deletedAt: Date? = nil)
	{
		self.id = id
		self.containerIDs = containerIDs
		self.body = body
		self.modifiedAt = modifiedAt
		self.deletedAt = deletedAt
	}

	var isDeleted: Bool {
		self.deletedAt != nil
	}

	/// 本文との二重管理を避けるため、見出しは保持しない
	var title: String {
		let line = self.body.split(separator: "\n", omittingEmptySubsequences: false).first ?? ""
		let trimmed = line.trimmingCharacters(in: .whitespaces)
		return trimmed.isEmpty ? String(localized: "New Note") : trimmed
	}

	func replacingTitle(with title: String) -> String {
		var lines = self.body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		guard !lines.isEmpty else {
			return title
		}
		lines[0] = title
		return lines.joined(separator: "\n")
	}

	var snippet: String {
		let lines = self.body.split(separator: "\n", omittingEmptySubsequences: true).dropFirst()
		return lines.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
	}

}


enum NoteScope: String, Codable {

	case allNotes
	case shared
	case recentlyDeleted
	case flagged
	case thisWeek

}
