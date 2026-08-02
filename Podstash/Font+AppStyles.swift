//
//  Font+AppStyles.swift
//  Podstash
//

import SwiftUI

/// The app's own content-text scale, used in place of the raw system semantic
/// styles for anything users actually read (titles, descriptions, metadata).
///
/// macOS's built-in Dynamic Type sizes are unusually compact — `.body` is
/// only 13pt, and `.footnote`/`.caption`/`.caption2` all cluster around 10pt,
/// reading as nearly identical sizes at typical window widths. That's why an
/// earlier pass swapping `.caption` for `.footnote` was barely visible on
/// desktop. These give macOS explicitly larger, more legible sizes; iOS keeps
/// using the system's own semantic styles, which are already larger and
/// respect Dynamic Type.
extension Font {
    static var appTitle: Font {
        #if os(macOS)
        .system(size: 17, weight: .semibold)
        #else
        .headline
        #endif
    }

    static var appBody: Font {
        #if os(macOS)
        .system(size: 14)
        #else
        .body
        #endif
    }

    static var appSubheadline: Font {
        #if os(macOS)
        .system(size: 13, weight: .medium)
        #else
        .subheadline
        #endif
    }

    static var appFootnote: Font {
        #if os(macOS)
        .system(size: 12)
        #else
        .footnote
        #endif
    }

    static var appCaption: Font {
        #if os(macOS)
        .system(size: 11)
        #else
        .caption
        #endif
    }
}
