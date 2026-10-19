import Cocoa


final class ToolbarController: NSObject {

	private enum ItemIdentifier {
		static let addElement = NSToolbarItem.Identifier("AddElement")
		static let removeElement = NSToolbarItem.Identifier("RemoveElement")
		static let search = NSToolbarItem.Identifier("Search")
	}

	private let splitViewController: MainSplitViewController

	init(splitViewController: MainSplitViewController) {
		self.splitViewController = splitViewController
	}

	func makeToolbar() -> NSToolbar {
		let toolbar = NSToolbar(identifier: "MainToolbar")
		toolbar.delegate = self
		toolbar.displayMode = .iconOnly
		toolbar.allowsUserCustomization = true
		toolbar.autosavesConfiguration = true
		return toolbar
	}

}


// MARK: - NSToolbarDelegate

extension ToolbarController: NSToolbarDelegate {

	func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		[.toggleSidebar,
		 .sidebarTrackingSeparator,
		 ItemIdentifier.addElement,
		 ItemIdentifier.removeElement,
		 .flexibleSpace,
		 ItemIdentifier.search]
	}

	func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		self.toolbarDefaultItemIdentifiers(toolbar) + [.space, .flexibleSpace]
	}

	func toolbar(_ toolbar: NSToolbar,
				 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
				 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem?
	{
		switch itemIdentifier {
			case .sidebarTrackingSeparator:
				return NSTrackingSeparatorToolbarItem(identifier: itemIdentifier,
													  splitView: self.splitViewController.splitView,
													  dividerIndex: 0)

			case ItemIdentifier.addElement:
				return self.makeMenuItem(identifier: itemIdentifier,
										 label: String(localized: "Add"),
										 symbolName: "plus")

			case ItemIdentifier.removeElement:
				return self.makeButtonItem(identifier: itemIdentifier,
										   label: String(localized: "Remove"),
										   symbolName: "minus",
										   action: #selector(SidebarViewController.deleteSelection(_:)))

			case ItemIdentifier.search:
				let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
				item.searchField.target = nil
				item.searchField.action = #selector(SidebarViewController.filterRows(_:))
				item.searchField.sendsWholeSearchString = false
				item.searchField.sendsSearchStringImmediately = true
				return item

			default:
				return nil
		}
	}

	private func makeButtonItem(identifier: NSToolbarItem.Identifier,
								label: String,
								symbolName: String,
								action: Selector) -> NSToolbarItem
	{
		let item = NSToolbarItem(itemIdentifier: identifier)
		item.label = label
		item.paletteLabel = label
		item.toolTip = label
		item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
		item.target = nil
		item.action = action
		item.isBordered = true
		return item
	}

	private func makeMenuItem(identifier: NSToolbarItem.Identifier,
							  label: String,
							  symbolName: String) -> NSMenuToolbarItem
	{
		let item = NSMenuToolbarItem(itemIdentifier: identifier)
		item.label = label
		item.paletteLabel = label
		item.toolTip = label
		item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
		item.showsIndicator = false

		let menu = NSMenu()
		menu.identifier = NSUserInterfaceItemIdentifier(identifier.rawValue)
		menu.delegate = self
		self.rebuild(menu)
		item.menu = menu
		return item
	}

}


// MARK: - NSMenuDelegate

extension ToolbarController: NSMenuDelegate {

	func menuNeedsUpdate(_ menu: NSMenu) {
		self.rebuild(menu)
	}

	private func rebuild(_ menu: NSMenu) {
		switch menu.identifier?.rawValue {
			case ItemIdentifier.addElement.rawValue:
				menu.items = self.nameItem(String(localized: "Add")) + [
					NSMenuItem(title: String(localized: "New Note"),
							   action: #selector(SidebarViewController.newNote(_:)),
							   keyEquivalent: ""),
					NSMenuItem(title: String(localized: "New Folder"),
							   action: #selector(SidebarViewController.newFolder(_:)),
							   keyEquivalent: ""),
					NSMenuItem(title: String(localized: "New Smart Folder"),
							   action: #selector(SidebarViewController.newSmartFolder(_:)),
							   keyEquivalent: ""),
				]

			default:
				break
		}
	}

	private func nameItem(_ label: String) -> [NSMenuItem] {
		[NSMenuItem(title: label, action: nil, keyEquivalent: "")]
	}

}
