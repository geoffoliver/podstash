//
//  PodcastSearch.swift
//  Podstash
//
//  Created by Geoff Oliver on 8/10/26.
//

import SwiftUI
import Foundation
import Combine
import SwiftData

// Shared by AddPodcastSheet and PodcastSearchSheet. A `.textFieldStyle(.plain)` TextField draws
// no border, no focus ring, and - left to its own devices - no larger than its current content,
// so three things need doing by hand: a manually-drawn placeholder, a border that reacts to focus,
// and forcing the field itself (not just its background) to actually fill the row.
struct PlaceholderTextField: View {
    let placeholder: String
    @Binding var text: String
    var isURLField: Bool = false
    var onSubmit: () -> Void = {}

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                // Text(verbatim:), not Text(_:) - a bare string literal is inferred as
                // LocalizedStringKey, which runs it through SwiftUI's Markdown parser. A string
                // that looks like a URL gets auto-detected as a Markdown link and rendered in
                // link-blue, overriding .foregroundStyle below. verbatim: skips that parsing.
                Text(verbatim: placeholder)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
            }
            TextField("", text: $text)
                // Without this, the field stays sized to its (empty) content instead of the row's
                // full width - the background/border still draw full-width since those are on the
                // ZStack, but only the actual TextField's own frame is clickable/hoverable, so it
                // ends up looking clickable everywhere while only responding right at the
                // placeholder text.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .focused($isFocused)
                #if os(macOS)
                .textFieldStyle(.plain)
                #else
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
        }
        #if !os(macOS)
        .keyboardType(isURLField ? .URL : .default)
        #endif
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isFocused ? 2 : 1)
        )
        .animation(.easeOut(duration: 0.1), value: isFocused)
        .onSubmit(onSubmit)
        .submitLabel(isURLField ? .done : .search)
    }
}

struct PodcastSearchResult: Identifiable, Hashable {
    var id: String { feedURL }
    let title: String
    let author: String
    let artworkURL: String?
    let feedURL: String
}

// iTunes Search API - unauthenticated, no API key required.
// https://performance-partners.apple.com/search-api
enum PodcastSearchService {
    private struct Response: Decodable {
        let results: [Item]
    }

    private struct Item: Decodable {
        let collectionName: String?
        let artistName: String?
        let feedUrl: String?
        let artworkUrl600: String?
        let artworkUrl100: String?
    }

    static func search(term: String) async throws -> [PodcastSearchResult] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "term", value: term)
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(Response.self, from: data)

        // Feed-less results (e.g. some Apple-exclusive shows) can't be subscribed to via RSS,
        // so they're dropped rather than shown as a dead-end "Add" button.
        return response.results.compactMap { item in
            guard let feedUrl = item.feedUrl, !feedUrl.isEmpty else { return nil }
            return PodcastSearchResult(
                title: item.collectionName ?? "Unknown Podcast",
                author: item.artistName ?? "",
                artworkURL: item.artworkUrl600 ?? item.artworkUrl100,
                feedURL: feedUrl
            )
        }
    }
}

@MainActor
class PodcastSearchCoordinator: ObservableObject {
    @Published var isPresented: Bool = false
    @Published var searchTerm: String = ""
    @Published var isSearching: Bool = false
    @Published var results: [PodcastSearchResult] = []
    @Published var errorMessage: String? = nil

    // Keyed by feedURL so each result row can track its own add/remove/error state
    // independently while the list stays visible.
    @Published var addingFeedURL: String? = nil
    @Published var removingFeedURL: String? = nil
    @Published var subscribedFeedURLs: Set<String> = []
    @Published var rowErrorMessages: [String: String] = [:]

    private var modelContext: ModelContext?
    private var searchTask: Task<Void, Never>?

    var triggerRefreshAfterAdding: ((Podcast) -> Void)?

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func showDialog() {
        searchTerm = ""
        results = []
        errorMessage = nil
        isSearching = false
        addingFeedURL = nil
        removingFeedURL = nil
        subscribedFeedURLs = modelContext.map { SubscriptionManager(modelContext: $0).subscribedFeedURLs() } ?? []
        rowErrorMessages = [:]
        isPresented = true
    }

    func cancel() {
        searchTask?.cancel()
        isPresented = false
    }

    func performSearch() {
        searchTask?.cancel()

        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            results = []
            errorMessage = nil
            isSearching = false
            return
        }

        isSearching = true
        errorMessage = nil

        searchTask = Task {
            do {
                let found = try await PodcastSearchService.search(term: term)
                guard !Task.isCancelled else { return }
                results = found
                isSearching = false
                errorMessage = found.isEmpty ? "No podcasts found." : nil
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                isSearching = false
                errorMessage = "Search failed: \(error.localizedDescription)"
            }
        }
    }

    func addPodcast(_ result: PodcastSearchResult) {
        guard let modelContext = modelContext, addingFeedURL == nil, removingFeedURL == nil else { return }

        rowErrorMessages[result.feedURL] = nil
        addingFeedURL = result.feedURL

        Task {
            let outcome = await PodcastSubscriber.subscribe(feedURLString: result.feedURL, modelContext: modelContext)
            addingFeedURL = nil

            switch outcome {
            case .success(let newPodcast):
                subscribedFeedURLs.insert(result.feedURL)
                triggerRefreshAfterAdding?(newPodcast)

            case .alreadySubscribed:
                subscribedFeedURLs.insert(result.feedURL)
                rowErrorMessages[result.feedURL] = "Already subscribed"

            case .failure(let message):
                rowErrorMessages[result.feedURL] = message
            }
        }
    }

    func removePodcast(_ result: PodcastSearchResult) {
        guard let modelContext = modelContext, addingFeedURL == nil, removingFeedURL == nil else { return }

        rowErrorMessages[result.feedURL] = nil
        removingFeedURL = result.feedURL

        Task {
            let manager = SubscriptionManager(modelContext: modelContext)
            let didUnsubscribe = manager.unsubscribe(feedURL: result.feedURL)
            removingFeedURL = nil

            if didUnsubscribe {
                subscribedFeedURLs.remove(result.feedURL)
            } else {
                rowErrorMessages[result.feedURL] = "Couldn't unsubscribe"
            }
        }
    }
}

struct PodcastSearchSheet: View {
    @ObservedObject var coordinator: PodcastSearchCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search Podcasts")
                .font(.headline)

            Text("Search Apple Podcasts to find and subscribe to a show.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            PlaceholderTextField(placeholder: "Search by name…", text: $coordinator.searchTerm) {
                coordinator.performSearch()
            }

            Group {
                if coordinator.isSearching {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 12)
                } else if let errorMessage = coordinator.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else if !coordinator.results.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(coordinator.results) { result in
                                PodcastSearchResultRow(result: result, coordinator: coordinator)
                                if result.id != coordinator.results.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 360)
                }
            }

            HStack {
                Spacer()
                Button("Close") {
                    coordinator.cancel()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(maxWidth: 460)
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(radius: 20)
        .padding(.horizontal, 20)
    }
}

private struct PodcastSearchResultRow: View {
    let result: PodcastSearchResult
    @ObservedObject var coordinator: PodcastSearchCoordinator
    @State private var showingUnsubscribeAlert = false

    private var rowState: PodcastSearchRowState {
        PodcastSearchRowStatePolicy.state(
            forFeedURL: result.feedURL,
            subscribedFeedURLs: coordinator.subscribedFeedURLs,
            addingFeedURL: coordinator.addingFeedURL,
            removingFeedURL: coordinator.removingFeedURL
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let artworkURL = result.artworkURL, let url = URL(string: artworkURL) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.primary.opacity(0.06)
                    }
                } else {
                    Color.primary.opacity(0.06)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if !result.author.isEmpty {
                    Text(result.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let message = coordinator.rowErrorMessages[result.feedURL] {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Spacer(minLength: 8)

            switch rowState {
            case .adding, .removing:
                ProgressView()
                    .controlSize(.small)
            case .subscribed:
                // Icon-only (not a text "Unsubscribe" button) - the word doesn't fit this row's
                // available width on narrow screens and wraps the button to two lines.
                Button(role: .destructive) {
                    showingUnsubscribeAlert = true
                } label: {
                    Label("Unsubscribe", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .disabled(coordinator.addingFeedURL != nil || coordinator.removingFeedURL != nil)
            case .notSubscribed:
                Button("Add") {
                    coordinator.addPodcast(result)
                }
                .buttonStyle(.bordered)
                .disabled(coordinator.addingFeedURL != nil || coordinator.removingFeedURL != nil)
            }
        }
        .padding(.vertical, 8)
        .alert("Unsubscribe from Podcast?", isPresented: $showingUnsubscribeAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Unsubscribe", role: .destructive) {
                coordinator.removePodcast(result)
            }
        } message: {
            Text("Are you sure you want to unsubscribe from \"\(result.title)\"? This will delete all downloaded episodes and playback history for this show.")
        }
    }
}
