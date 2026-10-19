import Foundation


struct SidebarItemDescription: Hashable, Codable {

	var name: String
	var symbolName: String

	init(name: String, symbolName: String = "folder") {
		self.name = name
		self.symbolName = symbolName
	}

}


struct SidebarContents {

	var tree: SidebarTree
	var descriptions: [SidebarElement.ID: SidebarItemDescription]

}


@MainActor
protocol SidebarStore: AnyObject {

	func load() throws -> SidebarContents

	func insert(_ element: SidebarElement,
				parentID: SidebarElement.ID?,
				index: Int,
				description: SidebarItemDescription) throws
	func update(_ id: SidebarElement.ID, description: SidebarItemDescription) throws
	func move(_ id: SidebarElement.ID,
			  from previousParentID: SidebarElement.ID?,
			  to parentID: SidebarElement.ID?,
			  index: Int) throws
	func remove(_ id: SidebarElement.ID) throws

	/// 1件ごとの移動だけでは動いていない兄弟の並び順が古い値のまま残るため、確定のたびにツリー全体を渡す
	func commit(tree: SidebarTree) throws

	func rowID(for id: SidebarElement.ID, under parentID: SidebarElement.ID?) -> SidebarElement.ID

}


extension SidebarStore {

	func rowID(for id: SidebarElement.ID, under parentID: SidebarElement.ID?) -> SidebarElement.ID {
		id
	}

}


extension Notification.Name {

	static let sidebarStoreContentsDidChange = Notification.Name("SidebarStoreContentsDidChange")

}
