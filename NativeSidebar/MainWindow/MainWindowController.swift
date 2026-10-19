import Cocoa


final class MainWindowController: NSWindowController {

	private let splitViewController: MainSplitViewController
	private let toolbarController: ToolbarController
	private var subtitleObservation: NSKeyValueObservation?

	/// AppKit 側の保存が働かなくなるため、autosave 名に "Window" を含めない
	private static let frameAutosaveName = NSWindow.FrameAutosaveName("MainW.i.n.d.o.w")

	init(sidebarStore: SidebarStore, noteStore: NoteStore, cascadingFrom reference: NSWindow? = nil) {
		let splitViewController = MainSplitViewController(sidebarStore: sidebarStore, noteStore: noteStore)
		self.splitViewController = splitViewController
		self.toolbarController = ToolbarController(splitViewController: splitViewController)

		let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
							  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
							  backing: .buffered,
							  defer: false)
		window.contentViewController = splitViewController
		// contentViewController の代入ではタイトルは連動しないため、明示的に束縛する
		window.bind(.title,
					to: splitViewController,
					withKeyPath: #keyPath(NSViewController.title),
					options: [.nullPlaceholder: String(localized: "Native Sidebar")])
		window.toolbarStyle = .unified
		window.toolbar = self.toolbarController.makeToolbar()

		super.init(window: window)

		self.subtitleObservation = splitViewController.observe(\.subtitle, options: [.initial, .new]) { [weak window] controller, _ in
			window?.subtitle = controller.subtitle
		}

		splitViewController.splitView.autosaveName = "MainSplitView"

		self.shouldCascadeWindows = false
		window.center()
		window.setFrameAutosaveName(Self.frameAutosaveName)
		if let reference {
			window.setFrame(reference.frame, display: false)
			let nextTopLeft = window.cascadeTopLeft(from: .zero)
			window.cascadeTopLeft(from: nextTopLeft)
		}
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func commitNoteEditing() {
		self.splitViewController.commitNoteEditing()
	}

}
