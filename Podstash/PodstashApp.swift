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
#if !os(macOS)
import BackgroundTasks
#endif

enum FeedValidationResult {
    case success(ParsedPodcast)
    case failure(String)
}

enum PodcastSubscribeOutcome {
    case success(Podcast)
    case alreadySubscribed
    case failure(String)
}

// Shared by AddPodcastCoordinator (manual URL entry) and PodcastSearchCoordinator (iTunes
// search results) so both flows fetch/parse/subscribe/download identically.
@MainActor
enum PodcastSubscriber {
    static func subscribe(feedURLString: String, modelContext: ModelContext) async -> PodcastSubscribeOutcome {
        let urlString = feedURLString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !urlString.isEmpty else {
            return .failure("Please enter a feed URL")
        }

        guard let url = URL(string: urlString),
              url.scheme == "http" || url.scheme == "https" else {
            return .failure("Please enter a valid HTTP or HTTPS URL")
        }

        let result = await Task.detached {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let parser = RSSFeedParser()

                guard let parsedPodcast = parser.parse(data: data) else {
                    return FeedValidationResult.failure("Unable to parse feed. Please check the URL.")
                }

                guard !parsedPodcast.episodes.isEmpty else {
                    return FeedValidationResult.failure("No episodes found in this feed.")
                }

                return FeedValidationResult.success(parsedPodcast)
            } catch {
                return FeedValidationResult.failure("Failed to fetch feed: \(error.localizedDescription)")
            }
        }.value

        guard !Task.isCancelled else {
            return .failure("Cancelled")
        }

        switch result {
        case .failure(let message):
            return .failure(message)

        case .success(let parsedPodcast):
            let subscriptionManager = SubscriptionManager(modelContext: modelContext)

            guard subscriptionManager.subscribe(
                title: parsedPodcast.title,
                feedURL: urlString,
                websiteURL: parsedPodcast.websiteURL,
                description: parsedPodcast.description
            ) else {
                return .alreadySubscribed
            }

            let descriptor = FetchDescriptor<Podcast>(
                predicate: #Predicate { podcast in
                    podcast.feedURL == urlString
                }
            )

            guard let podcasts = try? modelContext.fetch(descriptor),
                  let newPodcast = podcasts.first else {
                return .failure("Failed to save podcast")
            }

            // Only fills in podcast-level metadata for immediate UI feedback (artwork, author) -
            // episode creation is deliberately left to the caller's post-subscribe refresh
            // (FeedFetcher.fetchFeed(for:)). FeedFetcher already has the correct "new episodes
            // just created -> honor autoDownloadNewEpisodes" logic; duplicating episode creation
            // here meant that call always saw those episodes as already-existing and never
            // auto-downloaded anything.
            newPodcast.podcastDescription = parsedPodcast.description
            newPodcast.artworkURL = parsedPodcast.artworkURL
            newPodcast.author = parsedPodcast.author
            newPodcast.websiteURL = parsedPodcast.websiteURL
            newPodcast.lastUpdated = Date()
            try? modelContext.save()

            return .success(newPodcast)
        }
    }
}

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

        isValidating = true
        validationMessage = nil

        let urlString = feedURL

        validationTask = Task {
            let outcome = await PodcastSubscriber.subscribe(feedURLString: urlString, modelContext: modelContext)

            guard !Task.isCancelled else {
                return
            }

            switch outcome {
            case .success(let newPodcast):
                triggerRefreshAfterAdding?(newPodcast)

                isValidating = false
                showSuccessMessage = true

                // Auto-dismiss after 1.5 seconds
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    await MainActor.run {
                        cancel()
                    }
                }

            case .alreadySubscribed:
                validationMessage = "You're already subscribed to this podcast"
                isValidating = false

            case .failure(let message):
                validationMessage = message
                isValidating = false
            }
        }
    }
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

nonisolated class OPMLFeedParser: NSObject, XMLParserDelegate {
    private var parser: XMLParser?
    private var feeds: [OPMLFeed] = []

    override init() {
        super.init()
    }

    func parse(data: Data) -> OPMLParseResult {
        parser = XMLParser(data: data)
        parser?.delegate = self

        if parser?.parse() ?? false {
            return .success(feeds)
        } else {
            return .failure("XML parsing error")
        }
    }

    // XMLParserDelegate methods

    func parser(_ parser: XMLParser, didStartElement elementName: String,
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
    
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        // Could handle or log errors here if needed
    }
}

enum OPMLExporter {
    static func generateOPML(from podcasts: [Podcast]) -> String {
        let sortedPodcasts = podcasts.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }

        let outlines = sortedPodcasts.map { podcast -> String in
            var attributes = [
                "text=\"\(podcast.title.escapingForXMLAttribute())\"",
                "title=\"\(podcast.title.escapingForXMLAttribute())\"",
                "type=\"rss\"",
                "xmlUrl=\"\(podcast.feedURL.escapingForXMLAttribute())\"",
            ]
            if let websiteURL = podcast.websiteURL, !websiteURL.isEmpty {
                attributes.append("htmlUrl=\"\(websiteURL.escapingForXMLAttribute())\"")
            }
            return "    <outline \(attributes.joined(separator: " "))/>"
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>Podstash Subscriptions</title>
          </head>
          <body>
        \(outlines)
          </body>
        </opml>
        """
    }

#if os(macOS)
    /// Presents a save panel and writes the OPML file directly - macOS has no `.fileExporter`
    /// equivalent to NSOpenPanel's `.fileImporter` counterpart used for import, so this mirrors
    /// `OPMLImportCoordinator.importOPML()`'s direct-NSPanel approach instead.
    @MainActor
    static func presentSavePanel(podcasts: [Podcast]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.opml]
        panel.nameFieldStringValue = "Podstash.opml"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let opml = generateOPML(from: podcasts)
            try? opml.write(to: url, atomically: true, encoding: .utf8)
        }
    }
#endif
}

/// Wraps OPML text for SwiftUI's `.fileExporter`, which iOS uses in place of macOS's NSSavePanel.
struct OPMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.opml] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
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
        // We already handled reopening ourselves above - returning true here would also let
        // AppKit perform its own default reopen behavior on top of that, spawning a second window.
        return false
    }
}

// Stamps the real NSWindow.identifier of the WindowGroup-created window with "main" so
// MenuCoordinator.showMainWindow() can actually find it again. SwiftUI's own generated
// identifier for a `WindowGroup(id: "main")` window is an internal restoration ID, not the
// literal string "main", so without this the existing-window check below never matches and
// every call spawns a fresh window instead of reusing one.
private struct MainWindowIdentifierAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.identifier = NSUserInterfaceItemIdentifier("main")
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

@main
struct PodstashApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var updaterViewModel = SparkleUpdaterViewModel()
    #endif

    @StateObject private var settings = AppSettings()
    @StateObject private var addPodcastCoordinator = AddPodcastCoordinator()
    @StateObject private var podcastSearchCoordinator = PodcastSearchCoordinator()
    @StateObject private var opmlCoordinator = OPMLImportCoordinator()
    @StateObject private var refreshCoordinator = RefreshCoordinator()
    @StateObject private var audioPlayer = AudioPlayerManager()
    @StateObject private var downloadManager = DownloadManager()
    
    @State private var autoRefreshManager: AutoRefreshManager?

    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #else
    @Environment(\.scenePhase) private var scenePhase
    private static let backgroundRefreshTaskIdentifier = "me.geoffoliver.Podstash.refresh"
    #endif

    var sharedModelContainer: ModelContainer = {
        // Two configurations in one container, split by what needs to leave the device: Podcast
        // (subscriptions) and PlaybackRecord (queue/queue order/played/position) are small, flat,
        // relationship-free, and CloudKit-mirrored. Episode (RSS-derived metadata - title,
        // description, audioURL, artwork, duration, publishDate) is local-only, independently
        // re-parsed by every device. This split, and specifically the absence of any relationship
        // in the synced schema, is what makes the pending-relationship-resolution storm that
        // corrupted local state impossible to reproduce - that failure mode requires a synced
        // relationship to exist. See the plan doc (data-model redesign) for the full incident writeup.
        let cloudSchema = Schema([Podcast.self, PlaybackRecord.self])
        let localSchema = Schema([Episode.self])

        // Podstash.entitlements now has the iCloud/CloudKit container (iCloud.me.geoffoliver.Podstash)
        // configured under the paid Apple Developer Program team, so it's safe to request CloudKit
        // mirroring. (Requesting .automatic without that entitlement made SwiftData enable Core Data's
        // persistent history tracking with nothing to ever consume/trim it, growing the history tables
        // unbounded - that's why this used to be hardcoded off.)
        let cloudKitEntitlementsConfigured = true

        // Respect the user's iCloud sync preference (defaults to true, matching AppSettings.iCloudSyncEnabled).
        // Read directly from UserDefaults since this runs before AppSettings is constructed.
        let iCloudSyncEnabled = UserDefaults.standard.object(forKey: "iCloudSyncEnabled") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")

        // Explicit, distinct names are required here - without them both configurations default
        // to the same identity, SwiftData silently collapses them into a single registered
        // store, and any model belonging to the "other" one (whichever lost) has no store to
        // live in: "Failed to identify a store that can hold instances of ...".
        let cloudConfiguration = ModelConfiguration(
            "cloud",
            schema: cloudSchema,
            cloudKitDatabase: (cloudKitEntitlementsConfigured && iCloudSyncEnabled) ? .automatic : .none
        )
        // Never CloudKit-mirrored, regardless of the user's iCloud sync preference - Episode is
        // always purely local.
        let localConfiguration = ModelConfiguration(
            "local",
            schema: localSchema,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(
                for: Schema([Podcast.self, PlaybackRecord.self, Episode.self]),
                configurations: [cloudConfiguration, localConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    @ViewBuilder
    private var mainContent: some View {
        // Provides PodcastDirectory (episode.podcastID -> Podcast lookups) to the whole view
        // tree, since Episode has no relationship to Podcast (see Models.swift).
        PodcastDirectoryProvider { podcastDirectory in
        ContentView()
            .environmentObject(addPodcastCoordinator)
            .environmentObject(podcastSearchCoordinator)
            .environmentObject(opmlCoordinator)
            .environmentObject(refreshCoordinator)
            .environmentObject(audioPlayer)
            .environmentObject(audioPlayer.progress)
            .environmentObject(downloadManager)
            .environmentObject(settings)
            .onAppear {
                let context = sharedModelContainer.mainContext
                addPodcastCoordinator.setModelContext(context)
                podcastSearchCoordinator.setModelContext(context)
                opmlCoordinator.setModelContext(context)
                refreshCoordinator.setModelContext(context)
                refreshCoordinator.setSettings(settings)
                refreshCoordinator.setDownloadManager(downloadManager)
                audioPlayer.setModelContext(context)
                audioPlayer.setSettings(settings)
                audioPlayer.setPodcastDirectory(podcastDirectory)
                downloadManager.setModelContext(context)

                // Collapse any PlaybackRecords duplicated by a CloudKit sync race (e.g. two
                // devices each first-touching the same episode before either's row synced to
                // the other) before anything else reads queue/played state.
                PlaybackRecordStore.deduplicate(in: context)

                // Reclaim disk space from downloaded files no live episode references anymore.
                downloadManager.pruneOrphanedDownloads()

                // Reclaim disk space from download temp files orphaned by a crash or force-quit.
                downloadManager.pruneStaleTempDownloads()

                // Set up callback to refresh feeds after adding a podcast
                addPodcastCoordinator.triggerRefreshAfterAdding = { podcast in
                    refreshCoordinator.refreshFeed(for: podcast)
                }
                podcastSearchCoordinator.triggerRefreshAfterAdding = { podcast in
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
            .overlay {
                if addPodcastCoordinator.isPresented {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .overlay(
                            AddPodcastSheet(coordinator: addPodcastCoordinator)
                        )
                        .allowsHitTesting(true)
                        .zIndex(998)
                }
            }
            .overlay {
                if podcastSearchCoordinator.isPresented {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .overlay(
                            PodcastSearchSheet(coordinator: podcastSearchCoordinator)
                        )
                        .allowsHitTesting(true)
                        .zIndex(998)
                }
            }
            #if os(macOS)
            .background(MainWindowIdentifierAccessor())
            #endif
        }
    }

    @CommandsBuilder
    private var fileCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Podcast by URL…") {
                addPodcastCoordinator.showDialog()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Search Podcasts…") {
                podcastSearchCoordinator.showDialog()
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Import OPML…") {
                opmlCoordinator.importOPML()
            }
            .keyboardShortcut("i", modifiers: .command)

            #if os(macOS)
            Button("Export OPML…") {
                let descriptor = FetchDescriptor<Podcast>()
                guard let podcasts = try? sharedModelContainer.mainContext.fetch(descriptor) else { return }
                OPMLExporter.presentSavePanel(podcasts: podcasts)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            #endif

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

    @CommandsBuilder
    private var updateCommands: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                updaterViewModel.checkForUpdates()
            }
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
            updateCommands
        }

        Settings {
            SettingsView(settings: settings, autoRefreshManager: autoRefreshManager, updaterViewModel: updaterViewModel)
        }
        .modelContainer(sharedModelContainer)
        #else
        WindowGroup {
            mainContent
        }
        .modelContainer(sharedModelContainer)
        .commands {
            fileCommands
        }
        .backgroundTask(.appRefresh(Self.backgroundRefreshTaskIdentifier)) {
            await performBackgroundRefresh()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                scheduleBackgroundRefresh()
            }
        }
        #endif
    }

    #if !os(macOS)
    // BGAppRefreshTask requests are a hint, not a guaranteed schedule - iOS decides the actual
    // timing based on usage patterns and battery state. Re-submitted every time the app
    // backgrounds and again at the top of each background refresh itself, so there's always a
    // pending request as long as the user keeps opening the app occasionally.
    private func scheduleBackgroundRefresh() {
        guard let interval = settings.refreshIntervalEnum.timeInterval else {
            // "Manual" refresh interval means the user doesn't want automatic refreshing at all.
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundRefreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func performBackgroundRefresh() async {
        // Queue up the next run regardless of how this one goes - a failed or cut-short
        // refresh shouldn't end the chain.
        scheduleBackgroundRefresh()

        let context = sharedModelContainer.mainContext
        let fetcher = FeedFetcher(modelContext: context, settings: settings, downloadManager: downloadManager)
        _ = await fetcher.fetchAllFeeds()

        PlaybackRecordStore.deduplicate(in: context)
        EpisodeCleanupManager(modelContext: context, settings: settings).cleanupEpisodes()
    }
    #endif
}

// MARK: - Add Podcast Sheet

struct AddPodcastSheet: View {
    @ObservedObject var coordinator: AddPodcastCoordinator

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

                    PlaceholderTextField(
                        placeholder: "https://example.com/feed.rss",
                        text: $coordinator.feedURL,
                        isURLField: true
                    ) {
                        coordinator.addPodcast()
                    }
                    #if os(macOS)
                    .frame(width: 400)
                    #endif
                    .disabled(coordinator.isValidating)

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
        .frame(maxWidth: 420)
        .padding(24)
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(radius: 20)
        .padding(.horizontal, 20)
    }
}

