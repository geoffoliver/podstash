# Instructions for Claude / AI agents working in this repo

## Mandatory: Test-Driven Development

**Every change to `Podstash/` behavior — new features, bug fixes, refactors — must follow strict TDD. No exceptions, no "I'll add tests after."**

The cycle, in order, every time:

1. **Write a failing test first**, in `PodstashTests/`, that captures the behavior being added or the bug being fixed. Follow the existing style in that directory (e.g. `PlaybackProgressPolicyTests.swift`, `RSSFeedParserTests.swift`, `DownloadPruningPolicyTests.swift`) — plain `XCTest`/Swift Testing, one file per subject under test.
2. **Run it and confirm it fails** for the expected reason. A test that passes before the implementation exists is not testing anything — don't skip this step, and don't write the implementation first and the test after just to "save time."
3. **Write the minimum implementation code** to make the test pass.
4. **Run the full test suite** and confirm everything is green.
5. Refactor if needed, keeping tests green throughout.

Run tests with:

```
xcodebuild test -project Podstash.xcodeproj -scheme Podstash -destination 'platform=macOS'
```

(Swap the destination for an iOS simulator if the change is iOS-specific.)

### Why this rule exists

The project owner (Geoff) has explicitly asked for this to be a standing, permanent rule for the project — not a suggestion, not something to apply "when convenient." Bug fixes especially: a fix without a regression test isn't considered done, because it gives no protection against the same bug coming back.

### What this means in practice

- If a task looks like "fix bug X," the first tool calls should be writing/running a test that reproduces X and fails, *before* touching the code that has the bug.
- If a task looks like "add feature Y," write tests for Y's expected behavior first, watch them fail, then implement.
- Pure UI layout/styling tweaks with no testable logic are the practical exception (there's nothing to unit test about a padding value) — but any logic backing a UI change (view models, policy/decision functions, parsing, state transitions) still gets tests first.
- If asked to skip this (e.g. "just make it work quickly, skip tests"), flag that this contradicts the standing TDD rule and confirm before proceeding — don't silently drop it.
- Don't retroactively write tests after the fact and call it TDD. If code was written before its test, say so rather than presenting it as if the cycle was followed.
