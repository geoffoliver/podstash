//
//  CachedAsyncImage.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import SwiftUI
import AppKit

/// A view that loads and displays an image from a URL, with caching support
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @State private var image: NSImage?
    @State private var isLoading = false
    
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let image = image {
                content(Image(nsImage: image))
            } else {
                placeholder()
                    .task(id: url) {
                        await loadImage()
                    }
            }
        }
    }
    
    private func loadImage() async {
        guard let url = url else { return }
        guard !isLoading else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        let urlString = url.absoluteString
        
        // Check cache first (on main actor since ImageCacheManager is @MainActor)
        if let cachedImage = await ImageCacheManager.shared.getCachedImage(for: urlString) {
            self.image = cachedImage
            return
        }
        
        // Download and cache
        _ = await ImageCacheManager.shared.cacheImage(from: urlString)
        
        // Load from cache after download
        if let cachedImage = await ImageCacheManager.shared.getCachedImage(for: urlString) {
            self.image = cachedImage
        }
    }
}

// MARK: - Convenience Initializer

extension CachedAsyncImage where Content == Image, Placeholder == Color {
    /// Convenience initializer with default placeholder
    init(url: URL?) {
        self.url = url
        self.content = { $0 }
        self.placeholder = { Color.gray.opacity(0.2) }
    }
}

extension CachedAsyncImage where Placeholder == Color {
    /// Convenience initializer with custom content and default placeholder
    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content) {
        self.url = url
        self.content = content
        self.placeholder = { Color.gray.opacity(0.2) }
    }
}
