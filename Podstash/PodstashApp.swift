//
//  PodstashApp.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import SwiftUI
import Foundation
import Combine
import UniformTypeIdentifiers
import SwiftData

@MainActor
class AddPodcastCoordinator: ObservableObject {
    @Published var isPresented: Bool = false
    @Published var feedURL: String = ""
    @Published var isValidating: Bool = false
    @Published var validationMessage: String? = nil
    @Published var showSuccessMessage: Bool = false
    
    private var modelContext: ModelContext?
    private var validationTask: Task<Void, Never>?

    // Callback to trigger refresh after adding
    var triggerRefreshAfterAdding: ((Podcast) -> Void)?

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func showDialog() {
        feedURL = ""
        validationMessage = nil
        isValidating = false
        showSuccessMessage = false
        isPresented = true
    }
    
    func cancel() {
        validationTask?.cancel()
        isPresented = false
        feedURL = ""
        validationMessage = nil
        isValidating = false
        showSuccessMessage = false
    }
    
    func addPodcast() {
        guard let modelContext = modelContext else {
            validationMessage = "Error: Database not available"
            return
        }
        
        let urlString = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Basic URL validation
        guard !urlString.isEmpty else {
            validationMessage = "Please enter a feed URL"
            return
        }
        
        guard let url = URL(string: urlString),
              url.scheme == "http" || url.scheme == "https" else {
            validationMessage = "Please enter a valid HTTP or HTTPS URL"
            return
        }
        
        isValidating = true
        validationMessage = nil
        
        validationTask = Task {
            // Fetch and parse the feed
            let result = await Task.detached {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let parser = RSSFeedParser()
                    
                    guard let parsedPodcast = parser.parse(data: data) else {
                        return FeedValidationResult.failure("Unable to parse feed. Please check the URL.")
                    }
                    
                    // Verify it has audio content
                    guard !parsedPodcast.episodes.isEmpty else {
                        return FeedValidationResult.failure("No episodes found in this feed.")
                    }
                    
                    return FeedValidationResult.success(parsedPodcast)
                } catch {
                    return FeedValidationResult.failure("Failed to fetch feed: \(error.localizedDescription)")
                }
            }.value
            
            guard !Task.isCancelled else {
                return
            }
            
            await MainActor.run {
                switch result {
                case .success(let parsedPodcast):
                    // Check if already subscribed
                    let subscriptionManager = SubscriptionManager(modelContext: modelContext)
                    
                    if subscriptionManager.subscribe(
                        title: parsedPodcast.title,
                        feedURL: urlString,
                        websiteURL: parsedPodcast.websiteURL,
                        description: parsedPodcast.description
                    ) {
                        // Successfully subscribed - now fetch the podcast to get it fully set up
                        Task {
                            // Get the newly created podcast
                            let descriptor = FetchDescriptor<Podcast>(
                                predicate: #Predicate { podcast in
                                    podcast.feedURL == urlString
                                }
                            )
                            
                            if let podcasts = try? modelContext.fetch(descriptor),
                               let newPodcast = podcasts.first {
                                
                                // Update podcast with parsed data and episodes
                                await updateNewPodcast(newPodcast, with: parsedPodcast)
                                
                                // Trigger refresh callback
                                triggerRefreshAfterAdding?(newPodcast)
                                
                                // Show success
                                await MainActor.run {
                                    isValidating = false
                                    showSuccessMessage = true
                                    
                                    // Auto-dismiss after 1.5 seconds
                                    Task {
                                        try? await Task.sleep(for: .seconds(1.5))
                                        await MainActor.run {
                                            cancel()
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        // Already subscribed
                        validationMessage = "You're already subscribed to this podcast"
                        isValidating = false
                    }
                    
                case .failure(let error):
                    validationMessage = error
                    isValidating = false
                }
            }
        }
    }
    
    private func updateNewPodcast(_ podcast: Podcast, with parsedPodcast: ParsedPodcast) async {
        guard let modelContext = modelContext else { return }

        // Update podcast metadata
        podcast.podcastDescription = parsedPodcast.description
        podcast.artworkURL = parsedPodcast.artworkURL
        podcast.author = parsedPodcast.author
        podcast.websiteURL = parsedPodcast.websiteURL
        podcast.lastUpdated = Date()

        // Sort episodes by publish date (most recent first)
        let sortedEpisodes = parsedPodcast.episodes.sorted { $0.publishDate > $1.publishDate }

        for parsedEpisode in sortedEpisodes {
            let episode = Episode(
                title: parsedEpisode.title,
                episodeDescription: parsedEpisode.description,
                audioURL: parsedEpisode.audioURL,
                duration: parsedEpisode.duration,
                publishDate: parsedEpisode.publishDate,
                artworkURL: parsedEpisode.artworkURL
            )
            
            episode.podcast = podcast
            modelContext.insert(episode)
        }
        
        try? modelContext.save()
    }
}

enum FeedValidationResult {
    case success(ParsedPodcast)
    case failure(String)
}

@MainActor
class OPMLImportCoordinator: ObservableObject {
    @Published var isImporting: Bool = false // Used for iOS/iPadOS FileImporter trigger
    @Published var currentFeedTitle: String? = nil
    @Published var importCompleted: String? = nil
    
    private var modelContext: ModelContext?
    private var importTask: Task<Void, Never>?
    
    // Callback to trigger refresh after import
    var triggerRefreshAfterImport: (() -> Void)?
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func cancelImport() {
        importTask?.cancel()
        isImporting = false
        currentFeedTitle = nil
        importCompleted = "Import cancelled."
        
        // Auto-clear after 2 seconds
        Task {
            try? await Task.sleep(for: .seconds(2))
            if importCompleted == "Import cancelled." {
                importCompleted = nil
            }
        }
    }
    
    func importOPML() {
#if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "opml") ?? .xml]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task { @MainActor in
                    await self.handleImportedFile(url)
                }
            }
        }
#else
        isImporting = true
#endif
    }
    
    func handleImportedFile(_ url: URL) async {
        guard let modelContext = modelContext else {
            self.importCompleted = "Import failed: No database context."
            return
        }
        
        self.currentFeedTitle = nil
        self.importCompleted = nil
        self.isImporting = true
        
        // Create and store the import task so it can be cancelled
        importTask = Task {
            let subscriptionManager = SubscriptionManager(modelContext: modelContext)
            
            // Parse on background thread
            let parseResult = await Task.detached {
                guard let data = try? Data(contentsOf: url) else {
                    return OPMLParseResult.failure("Failed to read file.")
                }
                
                let parser = OPMLFeedParser()
                return parser.parse(data: data)
            }.value
            
            // Check if cancelled after parsing
            guard !Task.isCancelled else {
                return
            }
            
            // Handle results on main thread
            switch parseResult {
            case .success(let feeds):
                var successCount = 0
                var skippedCount = 0
                
                for feed in feeds {
                    // Check for cancellation before processing each feed
                    guard !Task.isCancelled else {
                        await MainActor.run {
                            self.importCompleted = "Import cancelled. \(successCount) feed(s) were added before cancellation."
                            self.isImporting = false
                            self.currentFeedTitle = nil
                        }
                        return
                    }
                    
                    await MainActor.run {
                        self.currentFeedTitle = feed.title
                    }
                    
                    if subscriptionManager.subscribe(
                        title: feed.title,
                        feedURL: feed.feedURL,
                        websiteURL: feed.websiteURL,
                        description: feed.description
                    ) {
                        successCount += 1
                    } else {
                        skippedCount += 1
                    }
                }
                
                // Final check for cancellation
                guard !Task.isCancelled else {
                    return
                }
                
                await MainActor.run {
                    let message: String
                    if successCount > 0 && skippedCount > 0 {
                        message = "Imported \(successCount) feed(s), \(skippedCount) already subscribed."
                    } else if successCount > 0 {
                        message = "Import complete! Added \(successCount) feed(s)."
                    } else {
                        message = "All \(skippedCount) feed(s) were already subscribed."
                    }
                    
                    self.importCompleted = message
                    self.isImporting = false
                    self.currentFeedTitle = nil
                }
                
                // Auto-clear message after 3 seconds
                try? await Task.sleep(for: .seconds(3))
                await MainActor.run {
                    self.importCompleted = nil
                }
                
                // Trigger automatic refresh of newly imported feeds
                if successCount > 0 {
                    await MainActor.run {
                        self.triggerRefreshAfterImport?()
                    }
                }
                
            case .failure(let error):
                guard !Task.isCancelled else {
                    return
                }
                
                await MainActor.run {
                    self.importCompleted = "Import failed: \(error)"
                    self.isImporting = false
                    self.currentFeedTitle = nil
                }
                
                // Auto-clear message after 3 seconds
                try? await Task.sleep(for: .seconds(3))
                await MainActor.run {
                    self.importCompleted = nil
                }
            }
        }
        
        await importTask?.value
    }
}

struct OPMLFeed {
    let title: String
    let feedURL: String
    let websiteURL: String?
    let description: String?
}

enum OPMLParseResult {
    case success([OPMLFeed])
    case failure(String)
}

class OPMLFeedParser: NSObject, XMLParserDelegate {
    private var parser: XMLParser?
    private var feeds: [OPMLFeed] = []
    
    nonisolated override init() {
        super.init()
    }
    
    nonisolated func parse(data: Data) -> OPMLParseResult {
        parser = XMLParser(data: data)
        parser?.delegate = self
        
        if parser?.parse() ?? false {
            return .success(feeds)
        } else {
            return .failure("XML parsing error")
        }
    }
    
    // XMLParserDelegate methods
    
    nonisolated func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        if elementName.lowercased() == "outline" {
            // OPML feeds have type="rss" and xmlUrl attribute
            // Some OPML files nest feeds under categories, so we check for xmlUrl presence
            guard let feedURL = attributeDict["xmlUrl"], !feedURL.isEmpty else {
                return
            }
            
            let title = (attributeDict["title"] ?? attributeDict["text"] ?? "Untitled Feed").decodingBasicHTMLEntities()
            let websiteURL = attributeDict["htmlUrl"]
            let description = attributeDict["description"]?.decodingBasicHTMLEntities()
            
            let feed = OPMLFeed(
                title: title,
                feedURL: feedURL,
                websiteURL: websiteURL,
                description: description
            )
            
            feeds.append(feed)
        }
    }
    
    nonisolated func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        // Could handle or log errors here if needed
    }
}

#if os(macOS)
// Global reference to audio player for menu validation
// This avoids capturing @StateObject in the commands block
@MainActor
class MenuCoordinator {
    static let shared = MenuCoordinator()
    weak var audioPlayer: AudioPlayerManager?
    var openWindow: OpenWindowAction?

    private init() {}

    // WindowGroup allows multiple simultaneous instances, so a bare openWindow(id:) would
    // spawn a duplicate if the main window is already open - bring the existing one forward
    // instead, and only open a new one if it was actually closed.
    func showMainWindow() {
        if let existing = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindow?(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

// App delegate to configure menu behavior
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Control+click didn't reliably show context menus (only actual right-click did),
        // even though AppKit is supposed to translate a control-modified left click into a
        // right click automatically. Do that translation ourselves so both gestures work
        // everywhere in the app - this is basic macOS functionality users expect.
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard event.modifierFlags.contains(.control), let window = event.window else {
                return event
            }
            if let rightMouseDown = NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: event.locationInWindow,
                modifierFlags: event.modifierFlags,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                eventNumber: event.eventNumber,
                clickCount: event.clickCount,
                pressure: event.pressure
            ) {
                window.sendEvent(rightMouseDown)
                return nil
            }
            return event
        }
    }

    // WindowGroup's default "New Window" command (Cmd+N) is replaced by "Add Podcast by
    // URL...", so once the user closes the last window there's otherwise no way to get it
    // back short of relaunching. Reopen it when the Dock icon is clicked with no windows open.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MenuCoordinator.shared.showMainWindow()
        }
        return true
    }
}
#endif

@main
struct PodstashApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    
    @StateObject private var settings = AppSettings()
    @StateObject private var addPodcastCoordinator = AddPodcastCoordinator()
    @StateObject private var opmlCoordinator = OPMLImportCoordinator()
    @StateObject private var refreshCoordinator = RefreshCoordinator()
    @StateObject private var audioPlayer = AudioPlayerManager()
    @StateObject private var downloadManager = DownloadManager()
    
    @State private var autoRefreshManager: AutoRefreshManager?

    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Podcast.self,
            Episode.self,
        ])
        
        // CloudKit requires a paid Apple Developer Program membership (the com.apple.developer.icloud-*
        // entitlements can't be provisioned on a free/personal team) and Podstash.entitlements currently
        // has no iCloud container configured. Requesting .automatic without that entitlement still makes
        // SwiftData enable Core Data's persistent history tracking, but nothing ever consumes/trims it since
        // sync can never complete - the history tables grow unbounded and every modelContext.save() gets
        // slower over time. Flip this once real iCloud entitlements are added.
        let cloudKitEntitlementsConfigured = false

        // Respect the user's iCloud sync preference (defaults to true, matching AppSettings.iCloudSyncEnabled).
        // Read directly from UserDefaults since this runs before AppSettings is constructed.
        let iCloudSyncEnabled = UserDefaults.standard.object(forKey: "iCloudSyncEnabled") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: (cloudKitEntitlementsConfigured && iCloudSyncEnabled) ? .automatic : .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    @ViewBuilder
    private var mainContent: some View {
        ContentView()
            .environmentObject(addPodcastCoordinator)
            .environmentObject(opmlCoordinator)
            .environmentObject(refreshCoordinator)
            .environmentObject(audioPlayer)
            .environmentObject(downloadManager)
            .environmentObject(settings)
            .onAppear {
                let context = sharedModelContainer.mainContext
                addPodcastCoordinator.setModelContext(context)
                opmlCoordinator.setModelContext(context)
                refreshCoordinator.setModelContext(context)
                refreshCoordinator.setSettings(settings)
                refreshCoordinator.setDownloadManager(downloadManager)
                audioPlayer.setModelContext(context)
                audioPlayer.setSettings(settings)
                downloadManager.setModelContext(context)

                // Set up callback to refresh feeds after adding a podcast
                addPodcastCoordinator.triggerRefreshAfterAdding = { podcast in
                    refreshCoordinator.refreshFeed(for: podcast)
                }

                // Set up callback to refresh feeds after OPML import
                opmlCoordinator.triggerRefreshAfterImport = {
                    refreshCoordinator.refreshAllFeeds()
                }

                // Initialize and start auto-refresh
                Task { @MainActor in
                    if autoRefreshManager == nil {
                        autoRefreshManager = AutoRefreshManager(settings: settings, refreshCoordinator: refreshCoordinator)
                        autoRefreshManager?.startAutoRefresh()
                    }
                }

                #if os(macOS)
                // Register audio player for menu validation
                MenuCoordinator.shared.audioPlayer = audioPlayer
                // Register openWindow so the Window menu / Dock-reopen can bring back a closed main window
                MenuCoordinator.shared.openWindow = openWindow
                #endif
            }
            .sheet(isPresented: $addPodcastCoordinator.isPresented) {
                AddPodcastSheet(coordinator: addPodcastCoordinator)
            }
    }

    @CommandsBuilder
    private var fileCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Podcast by URL…") {
                addPodcastCoordinator.showDialog()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Import OPML…") {
                opmlCoordinator.importOPML()
            }
            .keyboardShortcut("i", modifiers: .command)

            Divider()

            Button("Refresh All Feeds") {
                refreshCoordinator.refreshAllFeeds()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(refreshCoordinator.isRefreshing)
        }
    }

    #if os(macOS)
    @CommandsBuilder
    private var windowCommands: some Commands {
        CommandGroup(before: .windowList) {
            // Lets the main window be reopened from the Window menu after being closed,
            // matching how "Mini Player" already works.
            Button("Main Window") {
                MenuCoordinator.shared.showMainWindow()
            }

            Divider()

            Button("Mini Player") {
                MenuCoordinator.shared.audioPlayer?.showMiniPlayer()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Divider()
        }
    }
    #endif

    var body: some Scene {
        #if os(macOS)
        // WindowGroup, not a singleton Window: closing the one open window of a singleton
        // Window scene tears the whole scene down and quits the app (learned that the hard
        // way). WindowGroup survives with zero windows open, and "Main Window" below
        // (openWindow(id:)) brings it back - it just also has to guard against spawning a
        // second instance if one's already open, since WindowGroup allows multiple.
        WindowGroup(id: "main") {
            mainContent
        }
        .modelContainer(sharedModelContainer)
        .commands {
            fileCommands
            windowCommands
        }

        Settings {
            SettingsView(settings: settings, autoRefreshManager: autoRefreshManager)
        }
        #else
        WindowGroup {
            mainContent
        }
        .modelContainer(sharedModelContainer)
        .commands {
            fileCommands
        }
        #endif
    }
}

// MARK: - Add Podcast Sheet

struct AddPodcastSheet: View {
    @ObservedObject var coordinator: AddPodcastCoordinator
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            if coordinator.showSuccessMessage {
                // Success state
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                    
                    Text("Subscribed to Podcast!")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Downloading episodes…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                // Input state
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add Podcast by URL")
                        .font(.headline)
                    
                    Text("Enter the RSS feed URL of the podcast you want to subscribe to.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    TextField("https://example.com/feed.rss", text: $coordinator.feedURL)
                        .textFieldStyle(.roundedBorder)
                        #if os(macOS)
                        .frame(width: 400)
                        #endif
                        .disabled(coordinator.isValidating)
                        .onSubmit {
                            coordinator.addPodcast()
                        }
                    
                    if let message = coordinator.validationMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
                
                HStack {
                    Button("Cancel") {
                        coordinator.cancel()
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(coordinator.isValidating)
                    
                    Spacer()
                    
                    Button(action: {
                        coordinator.addPodcast()
                    }) {
                        HStack {
                            if coordinator.isValidating {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(coordinator.isValidating ? "Validating…" : "Add Podcast")
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(coordinator.feedURL.isEmpty || coordinator.isValidating)
                }
                .padding([.horizontal, .bottom])
            }
        }
        #if os(macOS)
        .frame(width: 500)
        #endif
    }
}

