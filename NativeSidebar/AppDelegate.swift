//
//  AppDelegate.swift
//  NativeSidebar
//
//  Created by usagimaru on 2026/10/17.
//

import Cocoa
import MainMenuTemplate

@main
class AppDelegate: NSObject, NSApplicationDelegate {

	private let storage = LibraryStorage()
	private lazy var sidebarStore = LibrarySidebarStore(storage: self.storage)
	private lazy var noteStore = NoteStore(storage: self.storage)
	private var windowControllers = [MainWindowController]()


	static func main() {
		runAppDelegate(AppDelegate.self)
	}

	func applicationDidFinishLaunching(_ aNotification: Notification) {
		self.openWindow()
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		true
	}

	func applicationWillTerminate(_ aNotification: Notification) {
		for windowController in self.windowControllers {
			windowController.commitNoteEditing()
		}
		self.noteStore.save()
	}

	func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
		return true
	}

	@IBAction func newDocument(_ sender: Any) {
		self.openWindow()
	}

	@objc func revealDataFile(_ sender: Any) {
		// 一度も保存していないと見せる相手がいないため、先に書き出す
		try? self.storage.save()
		NSWorkspace.shared.activateFileViewerSelecting([self.storage.indexURL])
	}


	// MARK: - Main Menu

	@objc func setupMainMenu() {
		MainMenuBuilder.buildAndApply {
			[
				MainMenuBuilder.applicationMenuTemplate(),
				self.fileMenuItem(),
				MainMenuBuilder.editMenuTemplate(),
				self.viewMenuItem(),
				MainMenuBuilder.windowMenuTemplate(),
				MainMenuBuilder.helpMenuTemplate(),
			]
		}
	}

	private func fileMenuItem() -> NSMenuItem {
		let fileMenuItem = MainMenuBuilder.fileMenuTemplate()
		guard let fileMenu = fileMenuItem.submenu else {
			return fileMenuItem
		}

		if let newItem = fileMenu.firstItem(withSelector: #selector(NSDocumentController.newDocument(_:)))?.item {
			newItem.title = String(localized: "New Window")
			newItem.keyEquivalentModifierMask = [.command, .option]
		}

		fileMenu.insertItems(.init({
			[
				.init(title: String(localized: "New Note"),
					  action: #selector(SidebarViewController.newNote(_:)),
					  keyEquivalent: "n",
					  modifierMask: .command),
				.init(title: String(localized: "New Folder"),
					  action: #selector(SidebarViewController.newFolder(_:)),
					  keyEquivalent: "N",
					  modifierMask: [.command, .shift]),
				.init(title: String(localized: "New Smart Folder"),
					  action: #selector(SidebarViewController.newSmartFolder(_:)),
					  keyEquivalent: "n",
					  modifierMask: [.command, .control]),
				.separator(),
			]
		}), at: 0)

		fileMenu.replaceFirstItem(.init(NSMenuItem(title: String(localized: "Rename…"),
												   action: #selector(SidebarViewController.renameSelection(_:)))),
								  matchingSelector: #selector(NSDocument.rename(_:)))

		fileMenu.addItems(.init({
			[
				.separator(),
				.init(title: String(localized: "Open Data Folder"),
					  action: #selector(self.revealDataFile(_:)),
					  target: self),
			]
		}))

		return fileMenuItem
	}

	private func viewMenuItem() -> NSMenuItem {
		let viewMenuItem = MainMenuBuilder.viewMenuTemplate()
		viewMenuItem.submenu?.addItems(.init({
			[
				.separator(),
				.init(title: String(localized: "Use Subdued Selection Color"),
					  action: #selector(SidebarViewController.toggleSelectionEmphasis(_:))),
			]
		}))
		return viewMenuItem
	}


	// MARK: -

	private func openWindow() {
		let reference = NSApp.mainWindow ?? self.windowControllers.last?.window
		let windowController = MainWindowController(sidebarStore: self.sidebarStore,
													noteStore: self.noteStore,
													cascadingFrom: reference)
		self.windowControllers.append(windowController)
		windowController.showWindow(self)

		guard let window = windowController.window else {
			return
		}
		NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
											   object: window,
											   queue: .main) { [weak self] notification in
			MainActor.assumeIsolated {
				guard let closing = notification.object as? NSWindow else {
					return
				}
				self?.windowControllers.first { $0.window === closing }?.commitNoteEditing()
				self?.windowControllers.removeAll { $0.window === closing }
			}
		}
	}

}
