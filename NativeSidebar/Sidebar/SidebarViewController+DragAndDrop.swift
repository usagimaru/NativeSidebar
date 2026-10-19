import Cocoa


extension SidebarViewController {

	func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
		guard let id = self.identifier(of: item), self.sidebarController.canMove([id]) else {
			return nil
		}

		let pasteboardItem = NSPasteboardItem()
		pasteboardItem.setString(id.uuidString, forType: Self.rowPasteboardType)
		pasteboardItem.setString(self.sidebarController.name(for: id), forType: .string)
		return pasteboardItem
	}

	func outlineView(_ outlineView: NSOutlineView,
					 validateDrop info: NSDraggingInfo,
					 proposedItem item: Any?,
					 proposedChildIndex index: Int) -> NSDragOperation
	{
		self.pendingDropPlan = nil

		let draggedIDs = self.draggedIDs(from: info)
		if !draggedIDs.isEmpty {
			return self.validateReorder(draggedIDs, proposedItem: item, proposedChildIndex: index)
		}

		if info.draggingPasteboard.string(forType: .string) != nil {
			return self.validateTextDrop(proposedItem: item)
		}

		return []
	}

	func outlineView(_ outlineView: NSOutlineView,
					 acceptDrop info: NSDraggingInfo,
					 item: Any?,
					 childIndex index: Int) -> Bool
	{
		// 提案位置を書き換えた場合は書き換え後の値が渡るため、ここで解き直すと二重に読み替えてしまう
		guard let plan = self.pendingDropPlan else {
			return false
		}
		self.pendingDropPlan = nil

		switch plan.operation {
			case .reorder:
				let ids = self.draggedIDs(from: info)
				guard !ids.isEmpty else {
					return false
				}
				let moved = self.sidebarController.move(ids, toParentID: plan.parentID, at: plan.index)
				self.sidebarController.select(moved)
				return true

			case .addChild:
				guard let text = info.draggingPasteboard.string(forType: .string) else {
					return false
				}
				let description = SidebarItemDescription(name: text, symbolName: "folder")
				guard let id = self.sidebarController.add(kind: .folder,
														  description: description,
														  near: plan.parentID)
				else {
					return false
				}
				self.expandAncestors(of: id)
				self.sidebarController.select([id])
				return true
		}
	}

	func outlineView(_ outlineView: NSOutlineView,
					 draggingSession session: NSDraggingSession,
					 willBeginAt screenPoint: NSPoint,
					 forItems draggedItems: [Any])
	{
		self.outlineView.noteDraggingSessionWillBegin()
	}

	func outlineView(_ outlineView: NSOutlineView,
					 draggingSession session: NSDraggingSession,
					 endedAt screenPoint: NSPoint,
					 operation: NSDragOperation)
	{
		self.pendingDropPlan = nil
	}

}


// MARK: - 投下位置の解決

private extension SidebarViewController {

	func draggedIDs(from info: NSDraggingInfo) -> [SidebarElement.ID] {
		let items = info.draggingPasteboard.pasteboardItems ?? []
		return items.compactMap { item in
			item.string(forType: Self.rowPasteboardType).flatMap(UUID.init(uuidString:))
		}
	}

	func validateReorder(_ draggedIDs: [SidebarElement.ID],
						 proposedItem item: Any?,
						 proposedChildIndex index: Int) -> NSDragOperation
	{
		guard self.sidebarController.canMove(draggedIDs) else {
			return []
		}
		// 絞り込み中は表示上の位置とモデル上の位置が一対一にならないため、受け付けない
		guard !self.sidebarController.presentation.isFiltering else {
			return []
		}

		let proposedID = self.identifier(of: item)
		guard !self.isInsideDraggedRows(draggedIDs, candidateID: proposedID) else {
			return []
		}

		var parentID = proposedID
		var childIndex = index
		var dropsIntoItem = false

		if index == NSOutlineViewDropOnItemIndex {
			if let proposedID, self.sidebarController.canPlace(draggedIDs, in: proposedID) {
				childIndex = self.sidebarController.snapshot.children(of: proposedID).count
				dropsIntoItem = true
			}
			else if let proposedID {
				parentID = self.sidebarController.snapshot.parentID(of: proposedID)
				childIndex = (self.sidebarController.snapshot.childIndex(of: proposedID) ?? 0) + 1
			}
			else {
				childIndex = self.sidebarController.snapshot.rootIDs.count
			}
		}

		guard self.sidebarController.canPlace(draggedIDs, in: parentID) else {
			return []
		}

		// 畳んだ親では挿入位置のインジケータを描けないため、項目の行を強調して示す
		let isCollapsedParent = parentID.map { !self.outlineView.isItemExpanded(self.proxy(for: $0)) } ?? false

		if dropsIntoItem || isCollapsedParent, let parentID {
			self.outlineView.setDropItem(self.proxy(for: parentID), dropChildIndex: NSOutlineViewDropOnItemIndex)
		}
		else {
			self.outlineView.setDropItem(parentID.map { self.proxy(for: $0) }, dropChildIndex: childIndex)
		}

		self.pendingDropPlan = DropPlan(parentID: parentID, index: childIndex, operation: .reorder)
		return .move
	}

	func validateTextDrop(proposedItem item: Any?) -> NSDragOperation {
		guard let containerID = self.nearestContainer(accepting: .folder,
													  from: self.identifier(of: item))
		else {
			return []
		}

		self.outlineView.setDropItem(self.proxy(for: containerID),
									 dropChildIndex: NSOutlineViewDropOnItemIndex)
		self.pendingDropPlan = DropPlan(parentID: containerID,
										index: self.sidebarController.snapshot.children(of: containerID).count,
										operation: .addChild)
		return .copy
	}

	func nearestContainer(accepting kind: SidebarElement.Kind,
						  from id: SidebarElement.ID?) -> SidebarElement.ID?
	{
		var current = id
		while let candidate = current {
			if self.sidebarController.element(candidate)?.accepts(kind) == true {
				return candidate
			}
			current = self.sidebarController.snapshot.parentID(of: candidate)
		}
		return self.sidebarController.snapshot.rootIDs.first {
			self.sidebarController.element($0)?.accepts(kind) == true
		}
	}

	func isInsideDraggedRows(_ draggedIDs: [SidebarElement.ID], candidateID: SidebarElement.ID?) -> Bool {
		var current = candidateID
		while let candidate = current {
			if draggedIDs.contains(candidate) {
				return true
			}
			current = self.sidebarController.snapshot.parentID(of: candidate)
		}
		return false
	}

}
