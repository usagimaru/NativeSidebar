import Foundation


struct SidebarPresentation {

	var searchText = ""

	var isFiltering: Bool {
		!self.searchText.trimmingCharacters(in: .whitespaces).isEmpty
	}

	func apply(to tree: SidebarTree, name: (SidebarElement.ID) -> String) -> SidebarTree {
		var presented = tree

		if self.isFiltering {
			let keyword = self.searchText.trimmingCharacters(in: .whitespaces)
			presented.roots = Self.filtered(presented.roots, keyword: keyword, name: name)
		}

		return presented
	}

	private static func filtered(_ nodes: [SidebarNode],
								 keyword: String,
								 name: (SidebarElement.ID) -> String) -> [SidebarNode]
	{
		nodes.compactMap { node in
			let children = Self.filtered(node.children, keyword: keyword, name: name)
			let matches = name(node.id).localizedStandardContains(keyword)

			switch node.element.kind {
				case .group:
					return children.isEmpty ? nil : SidebarNode(node.element, children: children)

				case .builtIn, .folder, .smartFolder, .note:
					guard matches || !children.isEmpty else {
						return nil
					}
					return SidebarNode(node.element, children: children)
			}
		}
	}

}
