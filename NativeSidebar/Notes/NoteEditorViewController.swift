import Cocoa


final class NoteEditorViewController: NSViewController {

	enum Content {
		case none
		case multipleSelection
		case note(Note.ID)
	}

	let noteStore: NoteStore

	private var textView: NSTextView!
	private var placeholderLabel: NSTextField!
	private var editingNoteID: Note.ID?

	init(noteStore: NoteStore) {
		self.noteStore = noteStore
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func loadView() {
		self.view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 420))
		self.build()
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		NotificationCenter.default.addObserver(forName: .noteStoreDidChange,
											   object: nil,
											   queue: .main) { [weak self] _ in
			MainActor.assumeIsolated {
				self?.refreshFromStore()
			}
		}
	}

}


// MARK: - 表示と確定

extension NoteEditorViewController {

	func present(_ content: Content) {
		self.commit()

		switch content {
		case .none:
			self.showPlaceholder(String(localized: "No Note Selected"))
		case .multipleSelection:
			self.showPlaceholder(String(localized: "Multiple Notes Selected"))
		case .note(let id):
			guard let note = self.noteStore.note(id) else {
				self.showPlaceholder(String(localized: "No Note Selected"))
				return
			}
			self.editingNoteID = id
			self.textView.string = note.body
			self.textView.isEditable = true
			self.placeholderLabel.isHidden = true
		}
	}

	func commit() {
		guard let id = self.editingNoteID else {
			return
		}
		self.noteStore.updateBody(id, body: self.textView.string)
	}

	private func refreshFromStore() {
		guard let id = self.editingNoteID else {
			return
		}

		guard let note = self.noteStore.note(id) else {
			self.showPlaceholder(String(localized: "No Note Selected"))
			return
		}

		// 打ち込んだ内容を失わないよう、入力中は差し替えない
		guard self.view.window?.firstResponder !== self.textView, self.textView.string != note.body else {
			return
		}
		self.textView.string = note.body
	}

	private func showPlaceholder(_ text: String) {
		self.editingNoteID = nil
		self.textView.string = ""
		self.textView.isEditable = false
		self.placeholderLabel.stringValue = text
		self.placeholderLabel.isHidden = false
	}

}


// MARK: - 組み立て

private extension NoteEditorViewController {

	func build() {
		let scrollView = NSTextView.scrollableTextView()
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = false

		guard let textView = scrollView.documentView as? NSTextView else {
			return
		}
		textView.font = .systemFont(ofSize: NSFont.systemFontSize)
		textView.isRichText = false
		textView.allowsUndo = true
		textView.textContainerInset = NSSize(width: 16, height: 16)
		textView.drawsBackground = false

		let placeholderLabel = NSTextField(labelWithString: "")
		placeholderLabel.font = .systemFont(ofSize: NSFont.systemFontSize * 1.4, weight: .medium)
		placeholderLabel.textColor = .secondaryLabelColor
		placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

		self.view.addSubview(scrollView)
		self.view.addSubview(placeholderLabel)

		NSLayoutConstraint.activate([
			scrollView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
			scrollView.topAnchor.constraint(equalTo: self.view.topAnchor),
			scrollView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
			placeholderLabel.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
			placeholderLabel.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
		])

		self.textView = textView
		self.placeholderLabel = placeholderLabel
	}

}
