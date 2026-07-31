//
//  RefreshStatusBar.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import SwiftUI

/// A subtle status bar that shows refresh progress at the bottom of the window
struct RefreshStatusBar: View {
    let currentPodcastTitle: String?
    let progress: (current: Int, total: Int)?
    let onCancel: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Spinner
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.8)
            
            // Status text
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Refreshing Feeds")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    if let progress = progress {
                        Text("(\(progress.current)/\(progress.total))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let title = currentPodcastTitle {
                    Text(title)
                        .font(.caption2)
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
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .help("Cancel Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(.separator),
            alignment: .top
        )
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
