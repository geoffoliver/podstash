//
//  QueueTableView.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

#if os(macOS)
import SwiftUI
import AppKit

struct QueueTableView: NSViewRepresentable {
    let episodes: [Episode]
    @Binding var selection: Set<UUID>
    let onDoubleClick: (Episode) -> Void
    let onRemove: ([Episode]) -> Void
    let onMarkPlayed: ([Episode]) -> Void
    let onMove: (IndexSet, Int) -> Void // NEW: Callback for reordering
    let onShowInfo: ((Episode) -> Void)? // NEW: Callback for showing episode info
    let currentlyPlayingID: UUID?
    let isPlaying: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()
        
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.style = .plain
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = [] // No grid lines
        
        // CRITICAL: Set action to nil to prevent single-click activation
        tableView.action = nil
        
        // Enable double-click ONLY
        tableView.doubleAction = #selector(Coordinator.tableViewDoubleClicked(_:))
        tableView.target = context.coordinator
        
        // Enable row actions (swipe actions)
        tableView.selectionHighlightStyle = .regular
        
        // Set up context menu
        tableView.menu = context.coordinator.createContextMenu()
        
        // ENABLE DRAG AND DROP REORDERING
        tableView.registerForDraggedTypes([.string])
        
        // Add columns
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("EpisodeColumn"))
        column.width = 500
        tableView.addTableColumn(column)
        tableView.headerView = nil // No header
        
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        context.coordinator.tableView = tableView

        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        
        let oldParent = context.coordinator.parent
        context.coordinator.parent = self
        
        // CRITICAL: Only reload if episodes list actually changed
        let episodesChanged = !areEpisodesEqual(oldParent.episodes, episodes)
        
        if episodesChanged {
            // Episodes list changed - do a full reload
            context.coordinator.episodes = episodes
            tableView.reloadData()
        } else if oldParent.currentlyPlayingID != currentlyPlayingID || 
                  oldParent.isPlaying != isPlaying {
            // Only playback state changed - update affected rows
            if let oldPlayingRow = episodes.firstIndex(where: { $0.id == oldParent.currentlyPlayingID }) {
                tableView.reloadData(forRowIndexes: IndexSet(integer: oldPlayingRow), columnIndexes: IndexSet(integer: 0))
            }
            if let newPlayingRow = episodes.firstIndex(where: { $0.id == currentlyPlayingID }) {
                tableView.reloadData(forRowIndexes: IndexSet(integer: newPlayingRow), columnIndexes: IndexSet(integer: 0))
            }
        }
        
        // Update selection
        let selectedRows = episodes.enumerated().filter { selection.contains($0.element.id) }.map { $0.offset }
        tableView.selectRowIndexes(IndexSet(selectedRows), byExtendingSelection: false)
    }
    
    // Helper to compare episode arrays by ID only
    private func areEpisodesEqual(_ lhs: [Episode], _ rhs: [Episode]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (left, right) in zip(lhs, rhs) {
            if left.id != right.id {
                return false
            }
        }
        return true
    }
    
    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var parent: QueueTableView
        var episodes: [Episode] = []
        weak var tableView: NSTableView?

        init(_ parent: QueueTableView) {
            self.parent = parent
            self.episodes = parent.episodes
        }

        // Right-clicking a row does NOT change `selectedRowIndexes` in stock
        // NSTableView (that's what the blue outline-but-white-background is:
        // a "clicked" indicator, not a selection) -- it only sets
        // `clickedRow`. So building the menu from `selectedRowIndexes` (or
        // the even-more-stale `parent.selection` binding) misses the common
        // case of right-clicking with nothing selected. Mirror Finder/Mail:
        // if the clicked row is part of the existing selection, act on the
        // whole selection; otherwise act on just the clicked row.
        var selectedEpisodesForMenu: [Episode] {
            guard let tableView = tableView else {
                return parent.selection.compactMap { id in episodes.first { $0.id == id } }
            }
            let clickedRow = tableView.clickedRow
            if clickedRow >= 0 {
                if tableView.selectedRowIndexes.contains(clickedRow) {
                    return tableView.selectedRowIndexes.compactMap { episodes[safe: $0] }
                }
                return episodes[safe: clickedRow].map { [$0] } ?? []
            }
            return tableView.selectedRowIndexes.compactMap { episodes[safe: $0] }
        }
        
        func numberOfRows(in tableView: NSTableView) -> Int {
            episodes.count
        }
        
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let episode = episodes[row]
            
            let view = NSHostingView(
                rootView: QueueEpisodeRow(
                    episode: episode,
                    onShowInfo: { [weak self] in self?.parent.onShowInfo?($0) },
                    isCurrentlyPlaying: episode.id == parent.currentlyPlayingID,
                    isPlaying: parent.isPlaying
                )
            )
            return view
        }
        
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            return 70
        }
        
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            // Use standard row view without hover effects
            return nil  // Let the table view create default row views
        }
        
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            
            let selectedRows = tableView.selectedRowIndexes
            let selectedIDs = Set(selectedRows.compactMap { episodes[safe: $0]?.id })
            
            DispatchQueue.main.async {
                self.parent.selection = selectedIDs
            }
        }
        
        // MARK: - Swipe Actions (just like Mail and Music!)
        
        func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
            guard row >= 0, row < episodes.count else { return [] }

            // AppKit only ever invokes this for `.trailing` in practice --
            // `.leading` swipe-to-reveal does not fire via trackpad, so both
            // actions have to live on the trailing (right-swipe) edge.
            guard edge == .trailing else { return [] }

            // Remove from Queue action (destructive, like Mail's delete).
            let removeAction = NSTableViewRowAction(
                style: .destructive,
                title: ""
            ) { [weak self] action, row in
                guard let self = self, row < self.episodes.count else { return }
                let episode = self.episodes[row]
                self.parent.onRemove([episode])
            }
            removeAction.backgroundColor = .systemRed
            if let trashImage = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: "Delete") {
                removeAction.image = trashImage
            }

            // Mark as Played action (regular), matching the blue tint used
            // for the equivalent swipe action in the podcast sidebar list.
            let markPlayedAction = NSTableViewRowAction(
                style: .regular,
                title: ""
            ) { [weak self] action, row in
                guard let self = self, row < self.episodes.count else { return }
                let episode = self.episodes[row]
                self.parent.onMarkPlayed([episode])
            }
            markPlayedAction.backgroundColor = .systemBlue
            if let checkImage = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Mark Played") {
                markPlayedAction.image = checkImage
            }

            // The LAST action in this array ends up closest to the edge, so
            // Remove is listed last to sit at the edge (full swipe = delete),
            // matching the sidebar's trash-at-the-edge convention.
            return [markPlayedAction, removeAction]
        }
        
        @objc func tableViewDoubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < episodes.count else { return }
            
            parent.onDoubleClick(episodes[row])
        }
        
        func createContextMenu() -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self
            return menu
        }
    }
}

extension QueueTableView.Coordinator: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let selectedEpisodes = selectedEpisodesForMenu

        if selectedEpisodes.count == 1 {
            // Single episode menu
            let playItem = NSMenuItem(
                title: "Play",
                action: #selector(playSelectedEpisode),
                keyEquivalent: ""
            )
            playItem.target = self
            menu.addItem(playItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let infoItem = NSMenuItem(
                title: "Show Details",
                action: #selector(showEpisodeInfo),
                keyEquivalent: ""
            )
            infoItem.target = self
            menu.addItem(infoItem)
            
            menu.addItem(NSMenuItem.separator())
        }
        
        let markPlayedTitle = selectedEpisodes.count > 1 ? "Mark \(selectedEpisodes.count) as Played" : "Mark as Played"
        let markPlayedItem = NSMenuItem(
            title: markPlayedTitle,
            action: #selector(markSelectedAsPlayed),
            keyEquivalent: ""
        )
        markPlayedItem.target = self
        menu.addItem(markPlayedItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let removeTitle = selectedEpisodes.count > 1 ? "Remove \(selectedEpisodes.count) from Queue" : "Remove from Queue"
        let removeItem = NSMenuItem(
            title: removeTitle,
            action: #selector(removeSelectedFromQueue),
            keyEquivalent: ""
        )
        removeItem.target = self
        menu.addItem(removeItem)
    }
    
    @objc func playSelectedEpisode() {
        if let episode = selectedEpisodesForMenu.first {
            parent.onDoubleClick(episode)
        }
    }

    @objc func showEpisodeInfo() {
        if let episode = selectedEpisodesForMenu.first {
            parent.onShowInfo?(episode)
        }
    }

    @objc func markSelectedAsPlayed() {
        parent.onMarkPlayed(selectedEpisodesForMenu)
    }

    @objc func removeSelectedFromQueue() {
        parent.onRemove(selectedEpisodesForMenu)
    }
    
    // MARK: - Drag and Drop Support
    
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row >= 0, row < episodes.count else { return nil }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(String(row), forType: .string)
        return pasteboardItem
    }

    // AppKit's default drag image for view-based table rows is only
    // partially opaque, so a selected row's white text can end up nearly
    // invisible over whatever's underneath. Rather than trying to recapture
    // the row's SwiftUI-backed NSHostingView (cacheDisplay on it turned out
    // to not yield a reliably-opaque bitmap), draw a simple opaque pill with
    // the episode title directly, guaranteeing full opacity.
    func tableView(_ tableView: NSTableView, updateDraggingItemsForDrag draggingInfo: NSDraggingInfo) {
        draggingInfo.enumerateDraggingItems(options: [], for: tableView, classes: [NSPasteboardItem.self], searchOptions: [:]) { draggingItem, _, _ in
            guard let pasteboardItem = draggingItem.item as? NSPasteboardItem,
                  let rowString = pasteboardItem.string(forType: .string),
                  let row = Int(rowString),
                  row >= 0, row < self.episodes.count else { return }

            let episode = self.episodes[row]
            let size = draggingItem.draggingFrame.size
            guard size.width > 0, size.height > 0 else { return }

            let image = NSImage(size: size)
            image.lockFocus()

            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let textRect = NSRect(x: 16, y: (size.height - 18) / 2, width: size.width - 32, height: 18)
            (episode.title as NSString).draw(in: textRect, withAttributes: attributes)

            image.unlockFocus()

            // setDraggingFrame(_:contents:) sets the image directly, unlike
            // imageComponentsProvider which gets AppKit's automatic drag
            // translucency baked on top regardless of the image's own alpha.
            draggingItem.setDraggingFrame(draggingItem.draggingFrame, contents: image)
        }
    }
    
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        // Only allow dropping between rows, not on rows
        if dropOperation == .above {
            return .move
        }
        return []
    }
    
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        // Get the dragged row indices
        guard let items = info.draggingPasteboard.pasteboardItems else { return false }
        
        var oldIndices: [Int] = []
        for item in items {
            if let rowString = item.string(forType: .string),
               let rowIndex = Int(rowString) {
                oldIndices.append(rowIndex)
            }
        }
        
        guard !oldIndices.isEmpty else { return false }

        // Sort indices to handle multiple selections properly
        oldIndices.sort()

        // `row` is already in the same "original index space" that
        // Array.move(fromOffsets:toOffset:) expects (it performs its own
        // adjustment for removed items internally), so pass it through as-is.
        let indexSet = IndexSet(oldIndices)
        parent.onMove(indexSet, row)
        
        return true
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#endif
