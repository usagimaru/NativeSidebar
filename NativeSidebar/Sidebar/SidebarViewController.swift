import Cocoa


@MainActor
protocol SidebarViewControllerDelegate: AnyObject {

	func sidebarViewControllerDidChangeSelection(_ viewController: SidebarViewController)

}


final class SidebarViewController: NSViewController {

	weak var delegate: SidebarViewControllerDelegate?

	let sidebarController: SidebarController

	/// アニメーションの見せ方は画面側から与える。基盤に特定の意匠を持ち込まないため
	var rowAnimationDuration = 0.25
	var rowAnimationTiming = CAMediaTimingFunction(name: .easeInEaseOut)
	var rowInsertAnimation = NSTableView.AnimationOptions.slideDown
	var rowRemoveAnimation = NSTableView.AnimationOptions.slideUp

	var keepsSelectionUnemphasized = false {
		didSet {
			self.applySelectionEmphasisStyle()
		}
	}

	private(set) var outlineView: SidebarOutlineView!
	private var scrollView: NSScrollView!

	private var proxies = [SidebarElement.ID: SidebarRowProxy]()
	private var isSyncingSelection = false

	var editingNameID: SidebarElement.ID?
	var editingOriginalName: String?
	/// 行の挿入アニメーションの完了が編集を打ち切るため、追加直後の編集は完了まで待たせる
	var pendingEditID: SidebarElement.ID?
	var pendingDropPlan: DropPlan?

	struct DropPlan {
		enum Operation {
			case reorder
			case addChild
		}

		let parentID: SidebarElement.ID?
		let index: Int
		let operation: Operation
	}

	static let rowPasteboardType = NSPasteboard.PasteboardType("com.clickandmagic.NativeSidebar.row")

	init(store: SidebarStore) {
		self.sidebarController = SidebarController(store: store)
		super.init(nibName: nil, bundle: nil)
		self.sidebarController.delegate = self
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func loadView() {
		// 保存済みの分割位置が無い初回に備え、初期分割位置として与える
		self.view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 0))
		self.buildOutlineView()
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		self.sidebarController.reload()
		self.restoreInitialSelection()
		self.expandAllContainers()
		self.observeRowSizeChanges()
	}

	private func observeRowSizeChanges() {
		NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
											   object: nil,
											   queue: .main) { [weak self] _ in
			MainActor.assumeIsolated {
				guard let outlineView = self?.outlineView else {
					return
				}
				outlineView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0 ..< outlineView.numberOfRows))
			}
		}
	}

}


// MARK: - 組み立て

extension SidebarViewController {

	private func buildOutlineView() {
		let outlineView = SidebarOutlineView()
		outlineView.style = .sourceList
		outlineView.rowSizeStyle = .default
		outlineView.headerView = nil
		outlineView.allowsMultipleSelection = true
		outlineView.allowsEmptySelection = false
		outlineView.floatsGroupRows = false
		outlineView.dataSource = self
		outlineView.delegate = self
		outlineView.contextMenuItemsProvider = { [weak self] row in
			self?.contextMenuItems(forClickedRow: row) ?? []
		}
		outlineView.renameRequestHandler = { [weak self] item in
			self?.beginNameEditing(item: item)
		}
		outlineView.deleteRequestHandler = { [weak self] sender in
			self?.deleteSelection(sender ?? outlineView)
		}
		outlineView.verticalMotionCanBeginDrag = false
		outlineView.registerForDraggedTypes([Self.rowPasteboardType, .string])
		outlineView.setDraggingSourceOperationMask(.move, forLocal: true)

		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SidebarColumn"))
		column.resizingMask = .autoresizingMask
		outlineView.addTableColumn(column)
		outlineView.outlineTableColumn = column

		let scrollView = NSScrollView()
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.documentView = outlineView
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = false
		scrollView.automaticallyAdjustsContentInsets = true
		self.view.addSubview(scrollView)

		NSLayoutConstraint.activate([
			scrollView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
			scrollView.topAnchor.constraint(equalTo: self.view.topAnchor),
			scrollView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
		])

		self.outlineView = outlineView
		self.scrollView = scrollView
	}

	func proxy(for id: SidebarElement.ID) -> SidebarRowProxy {
		if let existing = self.proxies[id] {
			return existing
		}
		let proxy = SidebarRowProxy(id: id)
		self.proxies[id] = proxy
		return proxy
	}

	func identifier(of item: Any?) -> SidebarElement.ID? {
		(item as? SidebarRowProxy)?.id
	}

	private static let rowViewIdentifier = NSUserInterfaceItemIdentifier("SidebarRow")

	func rowView(for item: Any) -> NSTableRowView? {
		let rowView = self.outlineView.makeView(withIdentifier: Self.rowViewIdentifier,
												owner: self) as? SidebarRowView ?? {
			let created = SidebarRowView()
			created.identifier = Self.rowViewIdentifier
			return created
		}()

		rowView.keepsUnemphasized = self.keepsSelectionUnemphasized
		return rowView
	}

	/// ファーストレスポンダーが別のビューにあってもグレーへ寄らないよう、既定の強調を使わない
	func applySelectionEmphasisStyle() {
		self.outlineView.selectionHighlightStyle = .regular
		self.outlineView.reloadData()
		self.expandAllContainers()
		self.syncSelectionRows()
	}

	func expandAllContainers() {
		for id in self.sidebarController.snapshot.orderedIDs {
			guard self.sidebarController.element(id)?.acceptsChildren == true
					|| !self.sidebarController.snapshot.children(of: id).isEmpty
			else {
				continue
			}
			self.outlineView.expandItem(self.proxy(for: id))
		}
	}

}


// MARK: - 選択

extension SidebarViewController {

	var selectedIDs: [SidebarElement.ID] {
		self.sidebarController.selection.ids
	}

	private static let lastSelectionKey = "SidebarLastSelection"

	/// 永続化するのは「次に開くウインドウの初期値」としての直近の選択だけで、開いているウインドウへは反映しない
	private func restoreInitialSelection() {
		let saved = UserDefaults.standard.stringArray(forKey: Self.lastSelectionKey) ?? []
		let ids = saved.compactMap(UUID.init(uuidString:))
		if !ids.isEmpty {
			self.sidebarController.select(ids)
		}
		self.syncSelectionRows()
	}

	private func storeLastSelection() {
		let ids = self.sidebarController.selection.ids.map(\.uuidString)
		UserDefaults.standard.set(ids, forKey: Self.lastSelectionKey)
	}

	private func syncSelectionRows() {
		for id in self.sidebarController.selection.ids {
			self.expandAncestors(of: id)
		}

		let rows = self.sidebarController.selection.ids.compactMap { id -> Int? in
			let row = self.outlineView.row(forItem: self.proxy(for: id))
			return row >= 0 ? row : nil
		}
		let indexes = IndexSet(rows)
		guard indexes != self.outlineView.selectedRowIndexes else {
			return
		}

		self.isSyncingSelection = true
		self.outlineView.selectRowIndexes(indexes, byExtendingSelection: false)
		self.isSyncingSelection = false
	}

	func expandAncestors(of id: SidebarElement.ID) {
		var ancestors = [SidebarElement.ID]()
		var current = self.sidebarController.snapshot.parentID(of: id)
		while let parentID = current {
			ancestors.insert(parentID, at: 0)
			current = self.sidebarController.snapshot.parentID(of: parentID)
		}
		for ancestorID in ancestors {
			self.outlineView.expandItem(self.proxy(for: ancestorID))
		}
	}

}


// MARK: - SidebarControllerDelegate

extension SidebarViewController: SidebarControllerDelegate {

	func sidebarController(_ controller: SidebarController, didProduce difference: SidebarDifference) {
		guard !difference.isEmpty else {
			return
		}

		self.outlineView.cancelRenameRequest()

		NSAnimationContext.runAnimationGroup({ context in
			context.duration = self.rowAnimationDuration
			context.timingFunction = self.rowAnimationTiming

			self.outlineView.beginUpdates()
			for operation in difference.operations {
				self.apply(operation)
			}
			self.outlineView.endUpdates()
		}, completionHandler: { [weak self] in
			self?.beginPendingNameEditing()
		})

		let reloadedRows = difference.reloadedIDs.compactMap { id -> Int? in
			let row = self.outlineView.row(forItem: self.proxy(for: id))
			return row >= 0 ? row : nil
		}
		if !reloadedRows.isEmpty {
			self.outlineView.reloadData(forRowIndexes: IndexSet(reloadedRows),
										columnIndexes: IndexSet(integer: 0))
		}

		self.syncSelectionRows()
	}

	func sidebarControllerDidChangeSelection(_ controller: SidebarController) {
		self.syncSelectionRows()
		self.storeLastSelection()
		self.delegate?.sidebarViewControllerDidChangeSelection(self)
		self.view.window?.toolbar?.validateVisibleItems()
	}

	func sidebarController(_ controller: SidebarController, didFailToCommit error: Error) {
		guard let window = self.view.window else {
			return
		}
		NSAlert(error: error).beginSheetModal(for: window)
	}

	private func apply(_ operation: SidebarDifference.Operation) {
		switch operation {
			case let .remove(_, parentID, index):
				self.outlineView.removeItems(at: IndexSet(integer: index),
											 inParent: parentID.map { self.proxy(for: $0) },
											 withAnimation: self.rowRemoveAnimation)

			case let .insert(_, parentID, index):
				self.outlineView.insertItems(at: IndexSet(integer: index),
											 inParent: parentID.map { self.proxy(for: $0) },
											 withAnimation: self.rowInsertAnimation)

			case let .move(_, fromParentID, fromIndex, toParentID, toIndex):
				self.outlineView.moveItem(at: fromIndex,
										  inParent: fromParentID.map { self.proxy(for: $0) },
										  to: toIndex,
										  inParent: toParentID.map { self.proxy(for: $0) })
		}
	}

}


// MARK: - NSOutlineViewDataSource

extension SidebarViewController: NSOutlineViewDataSource {

	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		self.sidebarController.snapshot.children(of: self.identifier(of: item)).count
	}

	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		let children = self.sidebarController.snapshot.children(of: self.identifier(of: item))
		return self.proxy(for: children[index])
	}

	/// 子を持てる行は、中身が空でも展開可能な項目として扱い、受け入れ先であることを示す
	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		guard let id = self.identifier(of: item) else {
			return false
		}
		return self.sidebarController.element(id)?.acceptsChildren == true
			|| !self.sidebarController.snapshot.children(of: id).isEmpty
	}

}


// MARK: - NSOutlineViewDelegate

extension SidebarViewController: NSOutlineViewDelegate {

	func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
		self.rowView(for: item)
	}

	func outlineView(_ outlineView: NSOutlineView, didAdd rowView: NSTableRowView, forRow row: Int) {
		(rowView as? SidebarRowView)?.refreshHover()
	}

	func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
		guard let id = self.identifier(of: item) else {
			return false
		}
		return self.sidebarController.element(id)?.kind == .group
	}

	func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
		guard let id = self.identifier(of: item) else {
			return false
		}
		return self.sidebarController.element(id)?.kind.isSelectable == true
	}

	func outlineView(_ outlineView: NSOutlineView,
					 viewFor tableColumn: NSTableColumn?,
					 item: Any) -> NSView?
	{
		guard let id = self.identifier(of: item), let element = self.sidebarController.element(id) else {
			return nil
		}

		let isGroup = element.kind == .group
		let identifier = isGroup ? SidebarCell.groupIdentifier : SidebarCell.rowIdentifier

		let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? SidebarCell
			?? {
				let cell = SidebarCell(style: isGroup ? .group : .row)
				cell.identifier = identifier
				cell.textField?.delegate = self
				return cell
			}()

		cell.configure(with: self.sidebarController.description(for: id), kind: element.kind)
		let hasSectionCommands = isGroup && !self.sectionCommands(for: id).isEmpty
		cell.accessoryMenuProvider = hasSectionCommands ? { [weak self] in self?.sectionMenu(for: id) } : nil
		return cell
	}

	func outlineViewSelectionDidChange(_ notification: Notification) {
		guard !self.isSyncingSelection else {
			return
		}

		self.outlineView.cancelRenameRequest()
		let ids = self.outlineView.selectedRowIndexes.compactMap { row in
			self.identifier(of: self.outlineView.item(atRow: row))
		}
		self.sidebarController.select(ids)
	}

}
