import Cocoa


final class MainWindowController: NSWindowController {

	private let splitViewController: MainSplitViewController
	private let toolbarController: ToolbarController

	/// AppKit 側の保存が働かなくなるため、autosave 名に "Window" を含めない
	private static let frameAutosaveName = NSWindow.FrameAutosaveName("MainW.i.n.d.o.w")

	init(sidebarStore: SidebarStore, noteStore: NoteStore) {
		let splitViewController = MainSplitViewController(sidebarStore: sidebarStore, noteStore: noteStore)
		self.splitViewController = splitViewController
		self.toolbarController = ToolbarController(splitViewController: splitViewController)

		let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
							  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
							  backing: .buffered,
							  defer: false)
		window.title = String(localized: "Native Sidebar")
		window.contentViewController = splitViewController
		window.toolbarStyle = .unified
		window.toolbar = self.toolbarController.makeToolbar()

		super.init(window: window)

		splitViewController.splitView.autosaveName = "MainSplitView"

		self.shouldCascadeWindows = false
		window.center()
		window.setFrameUsingName(Self.frameAutosaveName)
		window.setFrameAutosaveName(Self.frameAutosaveName)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func commitNoteEditing() {
		self.splitViewController.commitNoteEditing()
	}

}
