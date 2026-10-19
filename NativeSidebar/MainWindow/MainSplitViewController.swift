import Cocoa


final class MainSplitViewController: NSSplitViewController {

	let sidebarViewController: SidebarViewController
	let noteEditorViewController: NoteEditorViewController

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
		let selected = self.sidebarViewController.selectedIDs.first
		let isNote = selected.flatMap { self.sidebarViewController.sidebarController.element($0) }?.kind == .note
		self.noteEditorViewController.present(noteID: isNote ? selected : nil)
	}

}
