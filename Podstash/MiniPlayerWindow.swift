//
//  MiniPlayerWindow.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

#if os(macOS)
import SwiftUI
import AppKit

class MiniPlayerWindowController: NSWindowController, NSWindowDelegate {
    private var settings: AppSettings?
    
    convenience init(audioPlayer: AudioPlayerManager, settings: AppSettings) {
        let window = SquareMiniPlayerWindow(
            contentRect: NSRect(x: 100, y: 100, width: 300, height: 300),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = settings.miniPlayerAlwaysOnTop ? .floating : .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 150, height: 150)
        window.maxSize = NSSize(width: 600, height: 600)
        window.aspectRatio = NSSize(width: 1, height: 1) // Enforce square aspect
        
        // Set content view with simple container
        let containerView = ResizableContainerView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let hostingView = NSHostingView(rootView: MiniPlayerView(audioPlayer: audioPlayer, playbackProgress: audioPlayer.progress, windowController: nil))
        hostingView.frame = containerView.bounds
        hostingView.autoresizingMask = [.width, .height]
        containerView.hostingView = hostingView
        containerView.addSubview(hostingView)
        window.contentView = containerView
        
        self.init(window: window)
        self.settings = settings
        
        // Set delegate to enforce square aspect ratio
        window.delegate = self
        
        // Update the view with the window controller reference
        if let containerView = window.contentView as? ResizableContainerView,
           let hostingView = containerView.hostingView as? NSHostingView<MiniPlayerView> {
            hostingView.rootView = MiniPlayerView(audioPlayer: audioPlayer, playbackProgress: audioPlayer.progress, windowController: self)
        }
        
        // Force minimum size
        if window.frame.width < 150 || window.frame.height < 150 {
            window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 150, height: 150)), display: true)
        }
        
        // Observe changes to the always on top setting
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateWindowLevel()
        }
    }
    
    private func updateWindowLevel() {
        guard let settings = settings else { return }
        window?.level = settings.miniPlayerAlwaysOnTop ? .floating : .normal
    }
    
    // Enforce square aspect ratio during resize
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let size = max(frameSize.width, frameSize.height, 150) // Enforce minimum
        return NSSize(width: size, height: size)
    }
    
    func windowDidResize(_ notification: Notification) {
        // Force cursor rects to update after resize
        if let contentView = window?.contentView {
            contentView.window?.invalidateCursorRects(for: contentView)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// Custom window class with larger resize edge areas
class SquareMiniPlayerWindow: NSWindow {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        
        // Exclude this window from the Window menu to prevent menu update conflicts
        self.isExcludedFromWindowsMenu = true
        
        // Add rounded corners to the window
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.cornerRadius = 12
        self.contentView?.layer?.masksToBounds = true
    }
    
    override func contentRect(forFrameRect frameRect: NSRect) -> NSRect {
        // Return full frame as content rect since we're borderless
        return frameRect
    }
    
    override func frameRect(forContentRect contentRect: NSRect) -> NSRect {
        // Return content rect as frame rect since we're borderless
        return contentRect
    }
    
    // Prevent the constraint update loop crash
    override var isMovable: Bool {
        get { true }
        set { }
    }
}

// Custom view to handle resize cursors with larger hit areas - wraps a standard NSView
class ResizableContainerView: NSView {
    private let resizeEdgeSize: CGFloat = 15
    var hostingView: NSView?
    
    override func resetCursorRects() {
        super.resetCursorRects()
        
        discardCursorRects()
        
        let frame = bounds
        let edge = resizeEdgeSize
        
        // Corners
        addCursorRect(NSRect(x: 0, y: 0, width: edge, height: edge), cursor: NSCursor.arrow)
        addCursorRect(NSRect(x: frame.width - edge, y: 0, width: edge, height: edge), cursor: NSCursor.arrow)
        addCursorRect(NSRect(x: 0, y: frame.height - edge, width: edge, height: edge), cursor: NSCursor.arrow)
        addCursorRect(NSRect(x: frame.width - edge, y: frame.height - edge, width: edge, height: edge), cursor: NSCursor.arrow)
        
        // Edges
        addCursorRect(NSRect(x: edge, y: 0, width: frame.width - edge * 2, height: edge), cursor: NSCursor.resizeUpDown)
        addCursorRect(NSRect(x: edge, y: frame.height - edge, width: frame.width - edge * 2, height: edge), cursor: NSCursor.resizeUpDown)
        addCursorRect(NSRect(x: 0, y: edge, width: edge, height: frame.height - edge * 2), cursor: NSCursor.resizeLeftRight)
        addCursorRect(NSRect(x: frame.width - edge, y: edge, width: edge, height: frame.height - edge * 2), cursor: NSCursor.resizeLeftRight)
    }
    
    override func layout() {
        super.layout()
        hostingView?.frame = bounds
    }
}

struct MiniPlayerView: View {
    @ObservedObject var audioPlayer: AudioPlayerManager
    @ObservedObject var playbackProgress: PlaybackProgress
    weak var windowController: MiniPlayerWindowController?
    
    @State private var isHovering = false
    @State private var windowSize: CGSize = CGSize(width: 300, height: 300)
    
    // Determine if we should show minimal UI based on size
    private var isCompact: Bool {
        windowSize.width < 250
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background color
                Color.black
                
                // Artwork or placeholder
                if let episode = audioPlayer.currentEpisode {
                    if let artworkURL = episode.artworkURL ?? audioPlayer.currentPodcast?.artworkURL,
                       let url = URL(string: artworkURL) {
                        CachedAsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                        } placeholder: {
                            podcastPlaceholder
                        }
                    } else {
                        podcastPlaceholder
                    }
                } else {
                    emptyStatePlaceholder
                }
                
                // Overlay controls (visible on hover)
                controlsOverlay
                    .opacity((isHovering || !audioPlayer.isPlaying) ? 1 : 0)
                    .animation(.easeInOut(duration: 0.35), value: isHovering)
                    .animation(.easeInOut(duration: 0.35), value: audioPlayer.isPlaying)
                    .allowsHitTesting(isHovering || !audioPlayer.isPlaying)
            }
            .onAppear {
                windowSize = geometry.size
            }
            .onChange(of: geometry.size) { _, newSize in
                windowSize = newSize
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture(count: 2) {
            // Double-click to return to main window
            returnToMainWindow()
        }
    }
    
    private var podcastPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [.blue, .purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Image(systemName: "music.note")
                .font(.system(size: 80))
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    private var emptyStatePlaceholder: some View {
        ZStack {
            Color.black.opacity(0.8)
            
            VStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.6))

                Text("No Episode")
                    .font(.headline)
                    .foregroundColor(.white)
            }
        }
    }
    
    private var controlsOverlay: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.6)
            
            VStack(spacing: isCompact ? 8 : 12) {
                // Close button (top right)
                HStack {
                    Spacer()
                    Button {
                        returnToMainWindow()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: isCompact ? 24 : 28))
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .help("Return to Main Window")
                    .padding(.top, isCompact ? 8 : 12)
                    .padding(.trailing, isCompact ? 8 : 12)
                }
                
                if !isCompact {
                    Spacer()
                }
                
                // Episode title (only show if not compact)
                if !isCompact, let episode = audioPlayer.currentEpisode {
                    VStack(spacing: 4) {
                        Text(episode.title)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 16)
                        
                        if let podcast = audioPlayer.currentPodcast {
                            Text(podcast.title)
                                .font(.callout)
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(1)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                
                if isCompact {
                    // In compact mode, add flexible spacer to push content down
                    Spacer(minLength: 0)
                } else {
                    Spacer()
                }
                
                // Transport controls
                HStack(spacing: isCompact ? 12 : 24) {
                    // Only show skip buttons if not compact
                    if !isCompact {
                        Button {
                            audioPlayer.skip(by: -15)
                        } label: {
                            Image(systemName: "gobackward.15")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .help("Skip back 15 seconds")
                    }
                    
                    // Play/Pause (always shown, bigger)
                    Button {
                        audioPlayer.togglePlayPause()
                    } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: isCompact ? 44 : 56))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .help(audioPlayer.isPlaying ? "Pause" : "Play")
                    
                    // Only show skip buttons if not compact
                    if !isCompact {
                        Button {
                            audioPlayer.skip(by: 30)
                        } label: {
                            Image(systemName: "goforward.30")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .help("Skip forward 30 seconds")
                    }
                }
                .frame(maxWidth: .infinity) // Center the button in compact mode
                .padding(.bottom, isCompact ? 6 : 16)
                
                // Progress bar (with more padding from bottom)
                if playbackProgress.duration > 0 {
                    VStack(spacing: 4) {
                        InteractiveProgressSlider(
                            currentTime: playbackProgress.currentTime,
                            duration: playbackProgress.duration,
                            onSeek: { newTime in
                                audioPlayer.seek(to: newTime)
                            }
                        )

                        if !isCompact {
                            HStack {
                                Text(formatTime(playbackProgress.currentTime))
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.8))
                                    .monospacedDigit()

                                Spacer()

                                Text(formatTime(playbackProgress.duration))
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.8))
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(.horizontal, isCompact ? 12 : 20)
                    .padding(.bottom, isCompact ? 16 : 24)
                }
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    private func returnToMainWindow() {
        // Use the audioPlayer's method to properly close and restore
        audioPlayer.hideMiniPlayer()
    }
}

// Interactive progress slider for seeking
struct InteractiveProgressSlider: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void
    
    @State private var isDragging = false
    @State private var dragValue: Double?
    
    private var displayValue: Double {
        if isDragging, let dragValue = dragValue {
            return dragValue
        }
        return currentTime
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 4)
                    .cornerRadius(2)
                
                // Filled track
                // CRITICAL FIX: Use drawingGroup() to optimize rendering
                Rectangle()
                    .fill(Color.white)
                    .frame(width: geometry.size.width * CGFloat(displayValue / max(duration, 1)), height: 4)
                    .cornerRadius(2)
                    .drawingGroup() // Reduces CPU usage for frequently updating views
            }
            .frame(height: 20) // Larger hit area
            .contentShape(Rectangle()) // Make entire area tappable
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let percentage = max(0, min(1, value.location.x / geometry.size.width))
                        dragValue = duration * percentage
                    }
                    .onEnded { value in
                        let percentage = max(0, min(1, value.location.x / geometry.size.width))
                        let newTime = duration * percentage
                        onSeek(newTime)
                        isDragging = false
                        dragValue = nil
                    }
            )
        }
        .frame(height: 20) // Ensure consistent height
    }
}

#Preview {
    let audioPlayer = AudioPlayerManager()
    MiniPlayerView(audioPlayer: audioPlayer, playbackProgress: audioPlayer.progress, windowController: nil)
        .frame(width: 300, height: 300)
}

#endif
