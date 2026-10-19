import Foundation


/// 差分に必要なのは同一性と等価比較だけなので、表示に関わる属性は持たない
struct SidebarElement: Hashable, Identifiable, Codable {

	enum Kind: String, Hashable, Codable {
		case group
		case builtIn
		case folder
		case smartFolder
		case note
	}

	let id: UUID
	let kind: Kind
	/// 同じ見出しでも受け入れるものが違うため、種別ではなく要素が持つ
	let acceptedKinds: Set<Kind>
	let allowsNewItems: Bool
	let isReference: Bool

	init(id: UUID = UUID(),
		 kind: Kind,
		 accepting acceptedKinds: Set<Kind>? = nil,
		 allowingNewItems: Bool = true,
		 isReference: Bool = false)
	{
		self.id = id
		self.kind = kind
		self.acceptedKinds = acceptedKinds ?? kind.defaultAcceptedKinds
		self.allowsNewItems = allowingNewItems
		self.isReference = isReference
	}

	var acceptsChildren: Bool {
		!self.acceptedKinds.isEmpty
	}

	func accepts(_ kind: Kind) -> Bool {
		self.acceptedKinds.contains(kind)
	}

	/// 受け入れ規則は決まりごとなので保存しない。保存すると規則を変えても古い値が残り続ける
	private enum CodingKeys: String, CodingKey {
		case id
		case kind
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.id = try container.decode(UUID.self, forKey: .id)
		self.kind = try container.decode(Kind.self, forKey: .kind)
		self.acceptedKinds = self.kind.defaultAcceptedKinds
		self.allowsNewItems = true
		self.isReference = false
	}

}


// MARK: - 種別ごとに受け付ける操作

extension SidebarElement.Kind {

	var isSelectable: Bool {
		self != .group
	}

	var isRenamable: Bool {
		self == .folder || self == .smartFolder || self == .note
	}

	var isMovable: Bool {
		self == .folder || self == .smartFolder || self == .note
	}

	var isRemovable: Bool {
		self == .folder || self == .smartFolder || self == .note
	}

	/// 見出しは受け入れる種別がそれぞれ違うため、生成時に明示する前提で空にしてある
	var defaultAcceptedKinds: Set<SidebarElement.Kind> {
		self == .folder ? [.folder, .note] : []
	}

}
