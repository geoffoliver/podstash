//
//  OrderedFallbackParser.swift
//  Podstash
//

/// Tries a fixed sequence of parsers against successive inputs, remembering whichever one last
/// succeeded and trying it first next time. Built for RSSFeedParser.parsePublishDate, where a
/// feed's pubDate format is consistent across all its items but isn't known up front - trying up
/// to 6 DateFormatters/ISO8601DateFormatters per item (each comparatively expensive) was a
/// measured ~1/3 of total parse time on real feeds. Once the first item's format is known, every
/// later item in the same feed should hit on the first try instead of re-running the full
/// cascade. Falls back to a full scan (in original order) whenever the remembered candidate
/// doesn't match, so a feed that mixes formats across items still parses correctly, just slower.
nonisolated struct OrderedFallbackParser<Input, Output> {
    private let parsers: [(Input) -> Output?]
    private var preferredIndex: Int?

    init(parsers: [(Input) -> Output?]) {
        self.parsers = parsers
    }

    mutating func parse(_ input: Input) -> Output? {
        if let preferredIndex, let result = parsers[preferredIndex](input) {
            return result
        }

        for (index, parser) in parsers.enumerated() where index != preferredIndex {
            if let result = parser(input) {
                preferredIndex = index
                return result
            }
        }

        return nil
    }
}
