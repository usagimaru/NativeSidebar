import Cocoa


// MARK: - 対象の解決

extension SidebarViewController {

	func commandTarget(for sender: Any?) -> SidebarTarget {
		if let item = sender as? NSMenuItem, let target = item.sidebarTarget {
			return target
		}

		let ids = self.sidebarController.selection.ids
		return ids.isEmpty ? .background : .rows(ids)
	}

	private func contextTarget(forClickedRow row: Int) -> SidebarTarget {
		guard row >= 0, let id = self.identifier(of: self.outlineView.item(atRow: row)) else {
			return .background
		}

		if self.sidebarController.selection.contains(id) {
			return .rows(self.sidebarController.selection.ids)
		}
		return .rows([id])
	}
	
	private static let deleteAction = #selector(NSText.delete(_:))

	func canPerform(_ action: Selector?, on target: SidebarTarget) -> Bool {
		switch action {
			case Self.deleteAction:
				return self.sidebarController.canRemove(target.ids)

			case #selector(self.newNote(_:)):
				return self.sidebarController.canAdd(kind: .note, near: target.ids.last)

			case #selector(self.newFolder(_:)):
				return self.sidebarController.canAdd(kind: .folder, near: target.ids.last)

			case #selector(self.newSmartFolder(_:)):
				return self.sidebarController.canAdd(kind: .smartFolder, near: target.ids.last)

			case #selector(self.renameSelection(_:)):
				return self.sidebarController.canRename(target.ids)

			case #selector(self.deleteSelection(_:)):
				return self.sidebarController.canRemove(target.ids)

			case #selector(SidebarOutlineView.deleteItems(_:)):
				return self.sidebarController.canRemove(self.sidebarController.selection.ids)

			case #selector(self.toggleSelectionEmphasis(_:)):
				return true

			default:
				return false
		}
	}

}


// MARK: - 操作

extension SidebarViewController {

	@objc func newNote(_ sender: Any) {
		self.addElement(kind: .note,
						name: String(localized: "Untitled Note"),
						symbolName: "text.document",
						target: self.commandTarget(for: sender))
	}

	@objc func newFolder(_ sender: Any) {
		self.addElement(kind: .folder,
						name: String(localized: "Untitled Folder"),
						symbolName: "folder",
						target: self.commandTarget(for: sender))
	}

	@objc func newSmartFolder(_ sender: Any) {
		self.addElement(kind: .smartFolder,
						name: String(localized: "Untitled Smart Folder"),
						symbolName: "folder.badge.gearshape",
						target: self.commandTarget(for: sender))
	}

	@objc func renameSelection(_ sender: Any) {
		let target = self.commandTarget(for: sender)
		guard let id = target.ids.first else {
			return
		}
		self.beginNameEditing(id: id)
	}

	/// NSResponder に delete: の実体が無いため super は呼ばない
	@objc func delete(_ sender: Any?) {
		self.deleteSelection(sender ?? self)
	}

	@objc func deleteSelection(_ sender: Any) {
		let target = self.commandTarget(for: sender)
		guard self.sidebarController.canRemove(target.ids), let window = self.view.window else {
			return
		}

		// 空の項目は失うものが無いので、そのまま消す
		guard self.needsDeletionConfirmation(for: target.ids) else {
			self.sidebarController.remove(target.ids)
			return
		}

		let alert = NSAlert()
		alert.alertStyle = .warning
		alert.messageText = self.deletionMessage(for: target.ids)
		alert.informativeText = String(localized: "This cannot be undone.")
		alert.addButton(withTitle: String(localized: "Delete")).hasDestructiveAction = true
		alert.addButton(withTitle: String(localized: "Cancel"))

		alert.beginSheetModal(for: window) { [weak self] response in
			guard response == .alertFirstButtonReturn else {
				return
			}
			self?.sidebarController.remove(target.ids)
		}
	}

	func needsDeletionConfirmation(for ids: [SidebarElement.ID]) -> Bool {
		ids.contains { !self.sidebarController.snapshot.children(of: $0).isEmpty }
	}

	func deletionTitle(for ids: [SidebarElement.ID]) -> String {
		self.needsDeletionConfirmation(for: ids)
			? String(localized: "Delete…")
			: String(localized: "Delete")
	}

	private func deletionMessage(for ids: [SidebarElement.ID]) -> String {
		guard ids.count == 1, let id = ids.first else {
			return String(localized: "Delete the selected items?")
		}
		return String(localized: "Delete “\(self.sidebarController.name(for: id))”?")
	}

	@objc func filterRows(_ sender: Any) {
		guard let field = sender as? NSSearchField else {
			return
		}
		self.sidebarController.presentation.searchText = field.stringValue
	}

	@objc func toggleSelectionEmphasis(_ sender: Any) {
		self.keepsSelectionUnemphasized.toggle()
	}

	private func addElement(kind: SidebarElement.Kind,
							name: String,
							symbolName: String,
							target: SidebarTarget)
	{
		let description = SidebarItemDescription(name: name, symbolName: symbolName)
		guard let id = self.sidebarController.add(kind: kind,
												  description: description,
												  near: target.ids.last)
		else {
			return
		}

		self.expandAncestors(of: id)
		self.sidebarController.select([id])
		self.pendingEditID = id
	}

}


// MARK: - 名称編集

extension SidebarViewController: NSTextFieldDelegate {

	func beginPendingNameEditing() {
		guard let id = self.pendingEditID else {
			return
		}
		self.pendingEditID = nil
		self.beginNameEditing(id: id)
	}

	func beginNameEditing(item: Any) {
		guard let id = self.identifier(of: item) else {
			return
		}
		self.beginNameEditing(id: id)
	}

	func beginNameEditing(id: SidebarElement.ID) {
		guard self.sidebarController.canRename([id]), !self.outlineView.isEditingRow else {
			return
		}

		// 選択の移動は進行中の編集を閉じるため、編集対象を控えるのはその後にする
		self.sidebarController.select([id])

		// 選択の反映と位置の確定を待ってから始める
		DispatchQueue.main.async { [weak self] in
			self?.startNameEditing(id: id)
		}
	}

	private func startNameEditing(id: SidebarElement.ID) {
		// 待機の間に行は組み替わりうるので、識別子から引き直す
		let row = self.outlineView.row(forItem: self.proxy(for: id))
		guard row >= 0 else {
			return
		}

		self.outlineView.scrollRowToVisible(row)
		guard let cell = self.outlineView.view(atColumn: 0, row: row, makeIfNecessary: true) as? SidebarCell,
			  cell.textField?.currentEditor() == nil
		else {
			return
		}

		cell.prepareForNameEditing()
		self.editingNameID = id
		self.editingOriginalName = self.sidebarController.name(for: id)
		self.outlineView.editColumn(0, row: row, with: nil, select: true)

		// 編集に入れなかった場合にセルが編集中のまま固まるのを防ぐ
		guard cell.textField?.currentEditor() == nil else {
			return
		}
		self.editingNameID = nil
		cell.finishNameEditing()
	}

	/// 自前の経路を通らずに始まった編集でも対象を捕まえる
	func controlTextDidBeginEditing(_ notification: Notification) {
		guard self.editingNameID == nil, let textField = notification.object as? NSTextField else {
			return
		}

		(textField.superview as? SidebarCell)?.prepareForNameEditing()
		self.editingNameID = self.rowIdentifier(of: textField)
		self.editingOriginalName = textField.stringValue
	}

	func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
		guard commandSelector == #selector(NSResponder.cancelOperation(_:)),
			  let textField = control as? NSTextField
		else {
			return false
		}

		self.cancelNameEditing(in: textField)
		return true
	}

	func controlTextDidEndEditing(_ notification: Notification) {
		guard let textField = notification.object as? NSTextField else {
			return
		}

		// 終了の通知だけでは確定か取り消しかを判別できないため、移動方向で見分ける
		let movement = (notification.userInfo?["NSTextMovement"] as? Int).map(NSTextMovement.init(rawValue:))
		guard movement != .cancel else {
			self.cancelNameEditing(in: textField)
			return
		}

		(textField.superview as? SidebarCell)?.finishNameEditing()

		// 行が組み替わって対象を見失った場合に備え、テキストフィールドの位置から引き直す
		let id = self.editingNameID ?? self.rowIdentifier(of: textField)
		self.editingNameID = nil
		self.editingOriginalName = nil

		guard let id else {
			return
		}
		self.sidebarController.rename(id, to: textField.stringValue)
		self.reloadRow(for: id)
	}

	/// 取り消しではモデルを書き換えず、表示だけを編集前の名前へ戻す
	private func cancelNameEditing(in textField: NSTextField) {
		if let originalName = self.editingOriginalName {
			textField.stringValue = originalName
		}
		self.editingNameID = nil
		self.editingOriginalName = nil

		(textField.superview as? SidebarCell)?.finishNameEditing()
		self.view.window?.makeFirstResponder(self.outlineView)
	}

	private func rowIdentifier(of view: NSView) -> SidebarElement.ID? {
		let row = self.outlineView.row(for: view)
		guard row >= 0 else {
			return nil
		}
		return self.identifier(of: self.outlineView.item(atRow: row))
	}

	private func reloadRow(for id: SidebarElement.ID) {
		let row = self.outlineView.row(forItem: self.proxy(for: id))
		guard row >= 0 else {
			return
		}
		self.outlineView.reloadData(forRowIndexes: IndexSet(integer: row),
									columnIndexes: IndexSet(integer: 0))
	}

}


// MARK: - メニューの組み立て

extension SidebarViewController {

	func sectionCommands(for id: SidebarElement.ID) -> [(title: String, action: Selector)] {
		let commands: [(SidebarElement.Kind, String, Selector)] = [
			(.note, String(localized: "New Note"), #selector(self.newNote(_:))),
			(.folder, String(localized: "New Folder"), #selector(self.newFolder(_:))),
			(.smartFolder, String(localized: "New Smart Folder"), #selector(self.newSmartFolder(_:))),
		]

		return commands
			.filter { self.sidebarController.accepts(kind: $0.0, in: id) }
			.map { (title: $0.1, action: $0.2) }
	}

	func sectionMenu(for id: SidebarElement.ID) -> NSMenu? {
		let commands = self.sectionCommands(for: id)
		guard !commands.isEmpty else {
			return nil
		}

		let menu = NSMenu()
		menu.items = commands.map { self.menuItem($0.title, action: $0.action, target: .rows([id])) }
		return menu
	}

	func contextMenuItems(forClickedRow row: Int) -> [NSMenuItem] {
		let target = self.contextTarget(forClickedRow: row)
		let templates = self.menuItemTemplates(for: target)
		return SidebarMenuAssembler.pruned(templates) { self.canPerform($0.action, on: target) }
	}

	private func menuItemTemplates(for target: SidebarTarget) -> [NSMenuItem] {
		var items = [NSMenuItem]()

		items.append(self.menuItem(String(localized: "New Note"),
								   action: #selector(self.newNote(_:)),
								   target: target))
		items.append(self.menuItem(String(localized: "New Folder"),
								   action: #selector(self.newFolder(_:)),
								   target: target))
		items.append(self.menuItem(String(localized: "New Smart Folder"),
								   action: #selector(self.newSmartFolder(_:)),
								   target: target))

		switch target {
			case .rows:
				items.append(.separator())
				items.append(self.menuItem(String(localized: "Rename…"),
										   action: #selector(self.renameSelection(_:)),
										   target: target))
				items.append(.separator())
				items.append(self.menuItem(self.deletionTitle(for: target.ids),
										   action: #selector(self.deleteSelection(_:)),
										   target: target))

			case .background:
				break
		}

		return items
	}

	private func menuItem(_ title: String, action: Selector, target: SidebarTarget) -> NSMenuItem {
		let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
		item.target = self
		return item.withSidebarTarget(target)
	}

}


// MARK: - 有効・無効の判定

extension SidebarViewController: NSMenuItemValidation, NSToolbarItemValidation {

	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		switch menuItem.action {
			case #selector(self.deleteSelection(_:)):
				menuItem.title = self.deletionTitle(for: self.commandTarget(for: menuItem).ids)

			case #selector(self.toggleSelectionEmphasis(_:)):
				menuItem.state = self.keepsSelectionUnemphasized ? .on : .off

			default:
				break
		}

		return self.canPerform(menuItem.action, on: self.commandTarget(for: menuItem))
	}

	func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
		self.canPerform(item.action, on: self.commandTarget(for: item))
	}

}
