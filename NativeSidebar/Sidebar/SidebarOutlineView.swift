import Cocoa


/// NSOutlineView は参照の同一性で行を追跡するため、識別子ごとに1つだけ作る
final class SidebarRowProxy: NSObject {

	let id: SidebarElement.ID

	init(id: SidebarElement.ID) {
		self.id = id
	}

	override var hash: Int {
		self.id.hashValue
	}

	override func isEqual(_ object: Any?) -> Bool {
		(object as? SidebarRowProxy)?.id == self.id
	}

}


final class SidebarOutlineView: NSOutlineView {

	var contextMenuItemsProvider: ((Int) -> [NSMenuItem])?
	var renameRequestHandler: ((Any) -> Void)?
	var deleteRequestHandler: ((Any?) -> Void)?
	var renameRequestDelay = 0.7

	private var pendingRenameRequest: Task<Void, Never>?
	private var mouseMonitor: Any?
	private var isDraggingRows = false

	deinit {
		if let mouseMonitor = self.mouseMonitor {
			NSEvent.removeMonitor(mouseMonitor)
		}
	}

	/// 対象行の強調は NSTableView 自身のメニュー提供処理に伴って描かれるため、必ず super を通す
	override func menu(for event: NSEvent) -> NSMenu? {
		let row = self.row(at: self.convert(event.locationInWindow, from: nil))
		let items = self.contextMenuItemsProvider?(row) ?? []
		guard !items.isEmpty else {
			return nil
		}

		let menu = NSMenu()
		menu.items = items
		self.menu = menu
		return super.menu(for: event) ?? menu
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		self.observeMouseDown()
	}

	var isEditingRow: Bool {
		(self.window?.firstResponder as? NSText)?.isDescendant(of: self) ?? false
	}

	func cancelRenameRequest() {
		self.pendingRenameRequest?.cancel()
		self.pendingRenameRequest = nil
	}

	func noteDraggingSessionWillBegin() {
		self.isDraggingRows = true
		self.cancelRenameRequest()
	}

}


// MARK: - 削除の受け口

extension SidebarOutlineView {

	@objc func deleteItems(_ sender: Any?) {
		self.deleteRequestHandler?(sender)
	}

	override func keyDown(with event: NSEvent) {
		self.cancelRenameRequest()

		// NSTableView は Delete キーを doCommand(by:) へ流さないため、ここで受ける
		if !self.isEditingRow, let key = event.specialKey, key == .delete || key == .deleteForward {
			self.deleteItems(self)
			return
		}
		super.keyDown(with: event)
	}

	override func doCommand(by selector: Selector) {
		if selector == #selector(NSStandardKeyBindingResponding.deleteBackward(_:))
			|| selector == #selector(NSStandardKeyBindingResponding.deleteForward(_:))
		{
			self.deleteItems(self)
			return
		}
		super.doCommand(by: selector)
	}

	override func scrollWheel(with event: NSEvent) {
		self.cancelRenameRequest()
		super.scrollWheel(with: event)
	}

}


// MARK: - 間を置いてから編集へ入る

private extension SidebarOutlineView {

	/// mouseDown を上書きするとテーブルのジェスチャ認識が無効になるため、押下はイベントモニタで受ける
	func observeMouseDown() {
		if let mouseMonitor = self.mouseMonitor {
			NSEvent.removeMonitor(mouseMonitor)
			self.mouseMonitor = nil
		}
		guard self.window != nil else {
			return
		}

		self.mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
			self?.noteMouseDown(event)
			return event
		}
	}

	func noteMouseDown(_ event: NSEvent) {
		self.cancelRenameRequest()

		if self.endNameEditing(for: event) {
			return
		}
		guard let item = self.renameCandidate(for: event) else {
			return
		}

		self.isDraggingRows = false
		self.scheduleRenameRequest(for: item)

		// 押下の処理がドラッグを消化して戻ってくる場合があるため、戻った時点でも確かめる
		DispatchQueue.main.async { [weak self] in
			guard let self, self.isDraggingRows else {
				return
			}
			self.cancelRenameRequest()
		}
	}

	func renameCandidate(for event: NSEvent) -> Any? {
		guard event.window === self.window,
			  event.clickCount == 1,
			  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
			  !self.isEditingRow,
			  let hitView = self.window?.contentView?.hitTest(event.locationInWindow),
			  hitView.isDescendant(of: self)
		else {
			return nil
		}

		let point = self.convert(event.locationInWindow, from: nil)
		let row = self.row(at: point)
		guard row >= 0, self.selectedRowIndexes == IndexSet(integer: row) else {
			return nil
		}

		// ラベルは hitTest に応じないため、名前の領域かどうかは座標で見る
		guard let cell = self.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
			  let textField = cell.textField,
			  textField.convert(textField.bounds, to: self).contains(point)
		else {
			return nil
		}

		return self.item(atRow: row)
	}

	func scheduleRenameRequest(for item: Any) {
		let delay = self.renameRequestDelay
		self.pendingRenameRequest = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(delay))
			guard !Task.isCancelled else {
				return
			}

			self?.pendingRenameRequest = nil
			self?.renameRequestHandler?(item)
		}
	}

	func endNameEditing(for event: NSEvent) -> Bool {
		guard self.isEditingRow,
			  let window = self.window,
			  let fieldEditor = window.firstResponder as? NSText,
			  let hitView = window.contentView?.hitTest(event.locationInWindow),
			  hitView.isDescendant(of: self),
			  !hitView.isDescendant(of: fieldEditor)
		else {
			return false
		}

		window.endEditing(for: nil)
		return true
	}

}
