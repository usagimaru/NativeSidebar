import Cocoa


/// 経路ごとに決まり方が違うので、解決した結果をこの形へ揃える
enum SidebarTarget {

	case rows([SidebarElement.ID])
	case background

	var ids: [SidebarElement.ID] {
		switch self {
			case let .rows(ids):
				return ids

			case .background:
				return []
		}
	}

}


final class SidebarCommandContext: NSObject {

	let target: SidebarTarget

	init(target: SidebarTarget) {
		self.target = target
	}

}


extension NSMenuItem {

	/// 判定と実行で対象の決まり方がずれないよう、経路の違いは項目へ持たせる
	var sidebarTarget: SidebarTarget? {
		(self.representedObject as? SidebarCommandContext)?.target
	}

	func withSidebarTarget(_ target: SidebarTarget) -> NSMenuItem {
		self.representedObject = SidebarCommandContext(target: target)
		return self
	}

}


enum SidebarMenuAssembler {

	static func pruned(_ items: [NSMenuItem], isEnabled: (NSMenuItem) -> Bool) -> [NSMenuItem] {
		var kept = items.filter { $0.isSeparatorItem || isEnabled($0) }

		while let first = kept.first, first.isSeparatorItem {
			kept.removeFirst()
		}
		while let last = kept.last, last.isSeparatorItem {
			kept.removeLast()
		}

		var collapsed = [NSMenuItem]()
		for item in kept {
			if item.isSeparatorItem, collapsed.last?.isSeparatorItem == true {
				continue
			}
			collapsed.append(item)
		}

		return collapsed.contains(where: { !$0.isSeparatorItem }) ? collapsed : []
	}

}
