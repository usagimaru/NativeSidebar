import Cocoa


final class SidebarRowView: NSTableRowView {

	var keepsUnemphasized = false

	override var isEmphasized: Bool {
		get {
			self.keepsUnemphasized ? false : super.isEmphasized
		}
		set {
			super.isEmphasized = newValue
		}
	}

	private var hoverArea: NSTrackingArea?

	override func updateTrackingAreas() {
		super.updateTrackingAreas()

		// mouseExited を取りこぼさないよう、inVisibleRect を付けた領域は作り直さない
		guard self.hoverArea == nil else {
			return
		}

		let area = NSTrackingArea(rect: .zero,
								  options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
								  owner: self)
		self.addTrackingArea(area)
		self.hoverArea = area
		self.refreshHover()
	}

	override func mouseEntered(with event: NSEvent) {
		self.refreshHover()
	}

	override func mouseMoved(with event: NSEvent) {
		self.refreshHover()
	}

	override func mouseExited(with event: NSEvent) {
		self.notifyHover(false)
	}

	/// 行を使い回すと出入りの通知が届かないまま別の項目として現れるため、位置から状態を補う
	func refreshHover() {
		self.notifyHover(self.isPointerInside(self.hoverRect))
	}

	/// ディスクロージャの表示切り替えは行の左右に余白を残した領域で判定されるため、アウトラインビューが持つその領域に合わせる
	private var hoverRect: NSRect {
		guard let outlineView = self.superview as? NSOutlineView else {
			return self.bounds
		}
		let rowRect = self.convert(self.bounds, to: outlineView)
		let systemRect = outlineView.trackingAreas
			.map(\.rect)
			.first { !$0.isEmpty && rowRect.contains($0) }
		guard let systemRect else {
			return self.bounds
		}
		return self.convert(systemRect, from: outlineView)
	}

	private func notifyHover(_ hovered: Bool) {
		for subview in self.subviews {
			(subview as? SidebarCell)?.setShowsAccessory(hovered)
		}
	}

	private func isPointerInside(_ rect: NSRect) -> Bool {
		guard let window = self.window else {
			return false
		}
		return rect.contains(self.convert(window.mouseLocationOutsideOfEventStream, from: nil))
	}

}


final class SidebarHeaderButton: NSButton {

	var menuProvider: (() -> NSMenu?)?
	var interactionStateDidChange: (() -> Void)?
	var didFinishInteractiveLoop: (() -> Void)?

	private(set) var isPressed = false
	private(set) var isShowingMenu = false

	var isInteracting: Bool {
		self.isPressed || self.isShowingMenu
	}

	override func mouseDown(with event: NSEvent) {
		self.beginInteraction()
	}

	/// 押下のイベントを伴わない経路からも開く
	override func performClick(_ sender: Any?) {
		self.beginInteraction()
	}

	private func beginInteraction() {
		let wasFirstResponder = self.window?.firstResponder === self

		self.isPressed = true
		self.highlight(true)
		self.interactionStateDidChange?()

		// 対象の状態で項目が変わるため、開く直前に組み立てる
		if let menu = self.menuProvider?() {
			if menu.items.count == 1, let item = menu.items.first, let action = item.action {
				NSApp.sendAction(action, to: item.target, from: item)
			}
			else {
				menu.delegate = self
				self.isShowingMenu = true
				menu.popUp(positioning: nil, at: NSPoint(x: 0, y: self.bounds.height + 4), in: self)
			}
		}

		self.isPressed = false
		self.highlight(false)

		if wasFirstResponder {
			self.window?.makeFirstResponder(self)
		}
		self.interactionStateDidChange?()
		self.didFinishInteractiveLoop?()
	}

}


extension SidebarHeaderButton: NSMenuDelegate {

	func menuDidClose(_ menu: NSMenu) {
		self.isShowingMenu = false
		self.interactionStateDidChange?()
	}

}
