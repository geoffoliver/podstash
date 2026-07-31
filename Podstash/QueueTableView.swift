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
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        
        context.coordinator.parent = self
        context.coordinator.episodes = episodes
        
        tableView.reloadData()
        
        // Update selection
        let selectedRows = episodes.enumerated().filter { selection.contains($0.element.id) }.map { $0.offset }
        tableView.selectRowIndexes(IndexSet(selectedRows), byExtendingSelection: false)
    }
    
    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var parent: QueueTableView
        var episodes: [Episode] = []
        
        init(_ parent: QueueTableView) {
            self.parent = parent
            self.episodes = parent.episodes
        }
        
        func numberOfRows(in tableView: NSTableView) -> Int {
            episodes.count
        }
        
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let episode = episodes[row]
            
            let view = NSHostingView(
                rootView: QueueEpisodeRow(
                    episode: episode,
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
            let rowView = HoverableTableRowView()
            return rowView
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
            
            // Only show actions on trailing edge (swipe from right to left)
            guard edge == .trailing else { return [] }
            
            let episode = episodes[row]
            
            // Mark as Played action (regular)
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
            
            // Remove from Queue action (destructive, like Mail's delete)
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
            
            // Return actions in order: first appears closest to edge
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
        
        let selectedEpisodes = parent.selection.compactMap { id in
            episodes.first { $0.id == id }
        }
        
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
        if let episode = parent.selection.compactMap({ id in episodes.first { $0.id == id } }).first {
            parent.onDoubleClick(episode)
        }
    }
    
    @objc func markSelectedAsPlayed() {
        let selectedEpisodes = parent.selection.compactMap { id in
            episodes.first { $0.id == id }
        }
        parent.onMarkPlayed(selectedEpisodes)
    }
    
    @objc func removeSelectedFromQueue() {
        let selectedEpisodes = parent.selection.compactMap { id in
            episodes.first { $0.id == id }
        }
        parent.onRemove(selectedEpisodes)
    }
    
    // MARK: - Drag and Drop Support
    
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row >= 0, row < episodes.count else { return nil }
        
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(String(row), forType: .string)
        return pasteboardItem
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
        
        var newRow = row
        
        // Adjust destination for items being dragged from before the drop location
        for index in oldIndices {
            if index < row {
                newRow -= 1
            }
        }
        
        // Call the parent's onMove callback
        let indexSet = IndexSet(oldIndices)
        parent.onMove(indexSet, newRow)
        
        return true
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Hoverable Table Row View

/// A custom table row view that shows a subtle background tint on hover
class HoverableTableRowView: NSTableRowView {
    private var trackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet {
            if isHovering != oldValue {
                needsDisplay = true
            }
        }
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovering = true
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
    }
    
    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        
        // Only show hover effect if not selected
        if isHovering && !isSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
            bounds.fill()
        }
    }
}

#endif
