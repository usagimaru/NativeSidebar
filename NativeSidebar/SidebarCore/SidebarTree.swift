import Foundation


struct SidebarNode: Hashable, Identifiable {

	var element: SidebarElement
	var children: [SidebarNode]

	var id: SidebarElement.ID {
		self.element.id
	}

	init(_ element: SidebarElement, children: [SidebarNode] = []) {
		self.element = element
		self.children = children
	}

}


/// UI 操作はここだけを書き換え、ビューの状態からは組み立てない
struct SidebarTree: Hashable {

	var roots: [SidebarNode]

	init(roots: [SidebarNode] = []) {
		self.roots = roots
	}

}


// MARK: - 探索

extension SidebarTree {

	typealias Location = (parentID: SidebarElement.ID?, index: Int)

	func node(_ id: SidebarElement.ID) -> SidebarNode? {
		Self.node(id, in: self.roots)
	}

	func element(_ id: SidebarElement.ID) -> SidebarElement? {
		self.node(id)?.element
	}

	func contains(_ id: SidebarElement.ID) -> Bool {
		self.node(id) != nil
	}

	func location(of id: SidebarElement.ID) -> Location? {
		Self.location(of: id, in: self.roots, parentID: nil)
	}

	func children(of parentID: SidebarElement.ID?) -> [SidebarNode] {
		guard let parentID else {
			return self.roots
		}
		return self.node(parentID)?.children ?? []
	}

	func isDescendant(_ id: SidebarElement.ID, of ancestorID: SidebarElement.ID) -> Bool {
		guard let ancestor = self.node(ancestorID) else {
			return false
		}
		return Self.node(id, in: ancestor.children) != nil
	}

	/// 複数選択の移動で元の並びを保つために使う
	func orderedByPosition(_ ids: [SidebarElement.ID]) -> [SidebarElement.ID] {
		let targets = Set(ids)
		var ordered = [SidebarElement.ID]()
		Self.traverse(self.roots) { node in
			if targets.contains(node.id) {
				ordered.append(node.id)
			}
		}
		return ordered
	}

	func firstNode(where predicate: (SidebarNode) -> Bool) -> SidebarNode? {
		var found: SidebarNode?
		Self.traverse(self.roots) { node in
			if found == nil, predicate(node) {
				found = node
			}
		}
		return found
	}

	private static func node(_ id: SidebarElement.ID, in nodes: [SidebarNode]) -> SidebarNode? {
		for node in nodes {
			if node.id == id {
				return node
			}
			if let found = Self.node(id, in: node.children) {
				return found
			}
		}
		return nil
	}

	private static func location(of id: SidebarElement.ID,
								 in nodes: [SidebarNode],
								 parentID: SidebarElement.ID?) -> Location?
	{
		for (index, node) in nodes.enumerated() {
			if node.id == id {
				return (parentID, index)
			}
			if let found = Self.location(of: id, in: node.children, parentID: node.id) {
				return found
			}
		}
		return nil
	}

	private static func traverse(_ nodes: [SidebarNode], _ body: (SidebarNode) -> Void) {
		for node in nodes {
			body(node)
			Self.traverse(node.children, body)
		}
	}

}


// MARK: - 変更

extension SidebarTree {

	mutating func insert(_ nodes: [SidebarNode], parent parentID: SidebarElement.ID?, at index: Int) {
		self.withChildren(of: parentID) { children in
			children.insert(contentsOf: nodes, at: min(max(index, 0), children.count))
		}
	}

	@discardableResult
	mutating func remove(_ id: SidebarElement.ID) -> SidebarNode? {
		Self.remove(id, in: &self.roots)
	}

	@discardableResult
	mutating func move(_ ids: [SidebarElement.ID],
					   toParent parentID: SidebarElement.ID?,
					   at index: Int) -> Bool
	{
		let movable = ids.filter { id in
			guard self.element(id)?.kind.isMovable == true else {
				return false
			}
			guard let parentID else {
				return true
			}
			return id != parentID && !self.isDescendant(parentID, of: id)
		}
		guard !movable.isEmpty else {
			return false
		}

		let ordered = self.orderedByPosition(movable)
		var destination = index
		for id in ordered {
			guard let location = self.location(of: id) else {
				continue
			}
			if location.parentID == parentID && location.index < index {
				destination -= 1
			}
		}

		let detached = ordered.compactMap { self.remove($0) }
		self.insert(detached, parent: parentID, at: destination)
		return true
	}

	private mutating func withChildren(of parentID: SidebarElement.ID?,
									   _ body: (inout [SidebarNode]) -> Void)
	{
		guard let parentID else {
			body(&self.roots)
			return
		}
		Self.withNode(parentID, in: &self.roots) { node in
			body(&node.children)
		}
	}

	@discardableResult
	private static func withNode(_ id: SidebarElement.ID,
								 in nodes: inout [SidebarNode],
								 _ body: (inout SidebarNode) -> Void) -> Bool
	{
		for index in nodes.indices {
			if nodes[index].id == id {
				body(&nodes[index])
				return true
			}
			if Self.withNode(id, in: &nodes[index].children, body) {
				return true
			}
		}
		return false
	}

	private static func remove(_ id: SidebarElement.ID, in nodes: inout [SidebarNode]) -> SidebarNode? {
		for index in nodes.indices {
			if nodes[index].id == id {
				return nodes.remove(at: index)
			}
			if let removed = Self.remove(id, in: &nodes[index].children) {
				return removed
			}
		}
		return nil
	}

}
