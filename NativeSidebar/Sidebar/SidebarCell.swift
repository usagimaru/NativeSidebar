import Cocoa


/// システム設定から得られるのは区分だけなので、実寸はここで引く
extension NSTableView.RowSizeStyle {

	var iconLength: CGFloat {
		switch self {
			case .small:
				return 14

			case .large:
				return 20

			default:
				return 16
		}
	}

	var iconSpacing: CGFloat {
		switch self {
			case .small:
				return 5

			case .large:
				return 8

			default:
				return 6
		}
	}

}


final class SidebarCell: NSTableCellView {

	enum Style {
		case row
		case group
	}

	static let rowIdentifier = NSUserInterfaceItemIdentifier("SidebarCell.row")
	static let groupIdentifier = NSUserInterfaceItemIdentifier("SidebarCell.group")

	private(set) var isEditingName = false

	private var appliedDescription: SidebarItemDescription?
	private var appliedKind: SidebarElement.Kind?
	private var iconLengthConstraint: NSLayoutConstraint?
	private var iconSpacingConstraint: NSLayoutConstraint?
	private var accessoryButton: SidebarHeaderButton?

	var accessoryMenuProvider: (() -> NSMenu?)? {
		didSet {
			self.accessoryButton?.menuProvider = self.accessoryMenuProvider
		}
	}

	override var rowSizeStyle: NSTableView.RowSizeStyle {
		didSet {
			guard oldValue != self.rowSizeStyle else {
				return
			}
			self.iconLengthConstraint?.constant = self.rowSizeStyle.iconLength
			self.iconSpacingConstraint?.constant = self.rowSizeStyle.iconSpacing
		}
	}

	init(style: Style) {
		super.init(frame: .zero)
		self.build(style: style)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

}


// MARK: - 内容の反映

extension SidebarCell {

	func configure(with description: SidebarItemDescription, kind: SidebarElement.Kind) {
		self.appliedDescription = description
		self.appliedKind = kind
		self.applyIconAppearance()

		guard !self.isEditingName else {
			return
		}
		self.textField?.stringValue = description.name
	}

	func prepareForNameEditing() {
		self.isEditingName = true
		self.textField?.isSelectable = true
		self.textField?.isEditable = true
		self.textField?.textColor = .labelColor
	}

	func finishNameEditing() {
		self.isEditingName = false
		self.textField?.isEditable = false
		self.textField?.isSelectable = false
		self.textField?.textColor = nil
	}

	func setShowsAccessory(_ visible: Bool) {
		guard let accessoryButton = self.accessoryButton else {
			return
		}
		guard self.accessoryMenuProvider != nil else {
			accessoryButton.isHidden = true
			return
		}
		// 開いているメニューの出どころを残すため、操作中は伏せない
		accessoryButton.isHidden = !(visible || accessoryButton.isInteracting)
	}

	private var enclosingRowView: SidebarRowView? {
		var view = self.superview
		while let current = view {
			if let rowView = current as? SidebarRowView {
				return rowView
			}
			view = current.superview
		}
		return nil
	}

	private func applyIconAppearance() {
		guard let description = self.appliedDescription, let kind = self.appliedKind else {
			return
		}
		self.imageView?.image = NSImage(systemSymbolName: description.symbolName,
										accessibilityDescription: nil)
		self.imageView?.contentTintColor = kind == .smartFolder ? .systemPurple : .controlAccentColor
	}

}


// MARK: - 組み立て

private extension SidebarCell {

	func build(style: Style) {
		let textField = NSTextField(labelWithString: "")
		textField.translatesAutoresizingMaskIntoConstraints = false
		textField.lineBreakMode = .byTruncatingTail
		textField.cell?.usesSingleLineMode = true
		self.addSubview(textField)
		self.textField = textField

		switch style {
			case .row:
				let imageView = NSImageView()
				imageView.translatesAutoresizingMaskIntoConstraints = false
				imageView.imageScaling = .scaleProportionallyDown
				imageView.setContentHuggingPriority(.required, for: .horizontal)
				self.addSubview(imageView)
				self.imageView = imageView

				textField.isEditable = false
				textField.isBordered = false
				textField.drawsBackground = false
				textField.focusRingType = .none

				let iconLength = imageView.widthAnchor.constraint(equalToConstant: self.rowSizeStyle.iconLength)
				let iconSpacing = textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor,
																	 constant: self.rowSizeStyle.iconSpacing)
				self.iconLengthConstraint = iconLength
				self.iconSpacingConstraint = iconSpacing

				NSLayoutConstraint.activate([
					imageView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
					imageView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
					imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),
					iconLength,
					iconSpacing,
					textField.trailingAnchor.constraint(equalTo: self.trailingAnchor),
					textField.centerYAnchor.constraint(equalTo: self.centerYAnchor),
				])

			case .group:
				let button = SidebarHeaderButton(image: NSImage(systemSymbolName: "plus.circle.fill",
																accessibilityDescription: String(localized: "Add"))!,
												 target: nil,
												 action: nil)
				button.translatesAutoresizingMaskIntoConstraints = false
				button.isBordered = false
				button.isHidden = true
				button.interactionStateDidChange = { [weak button] in
					guard let button, button.isInteracting else {
						return
					}
					button.isHidden = false
				}
				button.didFinishInteractiveLoop = { [weak self] in
					self?.enclosingRowView?.refreshHover()
				}
				self.addSubview(button)
				self.accessoryButton = button

				NSLayoutConstraint.activate([
					textField.leadingAnchor.constraint(equalTo: self.leadingAnchor),
					textField.centerYAnchor.constraint(equalTo: self.centerYAnchor),
					button.leadingAnchor.constraint(greaterThanOrEqualTo: textField.trailingAnchor, constant: 4),
					button.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -4),
					button.centerYAnchor.constraint(equalTo: self.centerYAnchor),
				])
		}
	}

}
