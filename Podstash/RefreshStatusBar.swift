//
//  RefreshStatusBar.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import SwiftUI

/// A subtle status bar that shows refresh progress or completion message at the bottom of the window
struct RefreshStatusBar: View {
    let currentPodcastTitle: String?
    let progress: (current: Int, total: Int)?
    let onCancel: () -> Void
    let completionMessage: String?
    let onDismiss: (() -> Void)?
    
    // Convenience initializer for backward compatibility
    init(currentPodcastTitle: String?, progress: (current: Int, total: Int)?, onCancel: @escaping () -> Void) {
        self.currentPodcastTitle = currentPodcastTitle
        self.progress = progress
        self.onCancel = onCancel
        self.completionMessage = nil
        self.onDismiss = nil
    }
    
    // Full initializer with completion message support
    init(currentPodcastTitle: String? = nil, progress: (current: Int, total: Int)? = nil, onCancel: @escaping () -> Void = {}, completionMessage: String? = nil, onDismiss: (() -> Void)? = nil) {
        self.currentPodcastTitle = currentPodcastTitle
        self.progress = progress
        self.onCancel = onCancel
        self.completionMessage = completionMessage
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        HStack(spacing: 12) {
            if let message = completionMessage {
                // Completion state
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .imageScale(.large)

                Text(message)
                    .font(.appBody)
                    .fontWeight(.medium)

                Spacer()

                // Dismiss button
                Button(action: {
                    onDismiss?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.large)
                        .frame(minWidth: tapTargetSize, minHeight: tapTargetSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            } else {
                // Refreshing state
                ProgressView()
                    .controlSize(.small)

                // Status text
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Refreshing Feeds")
                            .font(.appBody)
                            .fontWeight(.medium)

                        if let progress = progress {
                            Text("(\(progress.current)/\(progress.total))")
                                .font(.appBody)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let title = currentPodcastTitle {
                        Text(title)
                            .font(.appFootnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer()

                // Cancel button
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.large)
                        .frame(minWidth: tapTargetSize, minHeight: tapTargetSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Cancel Refresh")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(.separator),
            alignment: .top
        )
    }

    // A 44pt minimum keeps the cancel/dismiss button reachable on iOS; the bar's
    // own padding already grows to fit it, so the "subtle" look survives on macOS
    // where a pointer doesn't need nearly as much forgiveness.
    private var tapTargetSize: CGFloat {
        #if os(iOS)
        44
        #else
        24
        #endif
    }
}

#Preview {
    VStack(spacing: 0) {
        Color.gray.opacity(0.2)
        
        RefreshStatusBar(
            currentPodcastTitle: "The Daily Show with Jon Stewart",
            progress: (current: 5, total: 23),
            onCancel: {}
        )
    }
    .frame(width: 400, height: 300)
}
