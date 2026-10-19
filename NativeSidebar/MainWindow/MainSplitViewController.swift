import Cocoa


final class MainSplitViewController: NSSplitViewController {

	let sidebarViewController: SidebarViewController
	let noteEditorViewController: NoteEditorViewController

	@objc dynamic private(set) var subtitle = ""

	private let noteStore: NoteStore

	init(sidebarStore: SidebarStore, noteStore: NoteStore) {
		self.sidebarViewController = SidebarViewController(store: sidebarStore)
		self.noteEditorViewController = NoteEditorViewController(noteStore: noteStore)
		self.noteStore = noteStore
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		let sidebarItem = NSSplitViewItem(sidebarWithViewController: self.sidebarViewController)
		// 畳んだときにツールバーのトグルボタンがオーバーフローへ落ちない幅を確保する
		sidebarItem.minimumThickness = 220
		sidebarItem.maximumThickness = 420
		sidebarItem.canCollapse = true
		self.addSplitViewItem(sidebarItem)

		let editorItem = NSSplitViewItem(viewController: self.noteEditorViewController)
		editorItem.minimumThickness = 320
		self.addSplitViewItem(editorItem)

		self.sidebarViewController.delegate = self
		self.updateEditor()

		// 見出しは本文の先頭行なので、本文の確定に合わせてウインドウタイトルを追従させる
		NotificationCenter.default.addObserver(forName: .noteStoreDidChange,
											   object: nil,
											   queue: .main) { [weak self] _ in
			MainActor.assumeIsolated {
				self?.updateTitle()
			}
		}
	}

	func commitNoteEditing() {
		self.noteEditorViewController.commit()
	}

	/// レスポンダーチェーンにはフォーカスのあるペインしか並ばないため、隣のペインの操作をここから届ける
	override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
		if self.sidebarViewController.responds(to: action) {
			return self.sidebarViewController
		}
		return super.supplementalTarget(forAction: action, sender: sender)
	}

}


// MARK: - SidebarViewControllerDelegate

extension MainSplitViewController: SidebarViewControllerDelegate {

	func sidebarViewControllerDidChangeSelection(_ viewController: SidebarViewController) {
		self.updateEditor()
	}

	private func updateEditor() {
		let content: NoteEditorViewController.Content
		switch self.selectedNoteID {
		case .some(let id):
			content = .note(id)
		case .none where self.sidebarViewController.selectedIDs.count > 1:
			content = .multipleSelection
		case .none:
			content = .none
		}
		self.noteEditorViewController.present(content)
		self.updateTitle()
	}

	private func updateTitle() {
		let note = self.selectedNoteID.flatMap { self.noteStore.note($0) }
		self.title = note?.title
		self.subtitle = note?.isDeleted == true ? String(localized: "Recently Deleted") : ""
	}

	/// 複数選択はノートを含んでいても編集対象にしない
	private var selectedNoteID: Note.ID? {
		let selected = self.sidebarViewController.selectedIDs
		guard selected.count == 1, let id = selected.first,
			  self.sidebarViewController.sidebarController.element(id)?.kind == .note
		else {
			return nil
		}
		return id
	}

}
