# Podstash

A fast, native podcast app for Mac, iPhone, and iPad. Queue-first listening — no subscriptions, no ads, no nonsense.

[**Website**](https://geoffoliver.github.io/podstash/) · [**Documentation**](https://geoffoliver.github.io/podstash/docs.html) · [**Latest release**](https://github.com/geoffoliver/podstash/releases/latest)

## Features

- **Queue-first** — build a single queue across every show you follow, instead of hunting through separate feeds.
- **Truly native** — built with SwiftUI for Mac and iPhone, sharing one codebase.
- **Smart downloads** — auto-download new episodes, auto-delete played ones, and keep only what you actually need offline.
- **Synced library** — subscriptions and queue stay in sync across your devices via iCloud.
- **Scriptable on Mac** — Podstash exposes an AppleScript dictionary (see `Podstash/Podstash.sdef`) for automation.

## Download

Signed, notarized macOS builds (universal — Apple Silicon & Intel) are published on the [releases page](https://github.com/geoffoliver/podstash/releases/latest). Unzip and drag `Podstash.app` to `/Applications`.

iOS is not currently distributed publicly (see [Roadmap](#roadmap)); building from source is the only way to run it on a device today.

## Requirements

- macOS 26 or later (Mac)
- iOS 26 or later (iPhone/iPad)

## Building from source

Podstash is a single Xcode project targeting macOS and iOS from one codebase — there are no external package dependencies.

```
git clone https://github.com/geoffoliver/podstash.git
cd podstash
open Podstash.xcodeproj
```

Select the `Podstash` scheme and a macOS or iOS destination, then build and run (⌘R). You'll need to point code signing at your own team in the project's Signing & Capabilities settings.

`build-dist.sh` reproduces the release pipeline locally (archives, signs, and notarizes a macOS build and produces a dev-signed iOS `.ipa`) — it expects a Developer ID signing identity and a `notarytool` keychain profile named `podstash-notary` to be configured on your machine. Tagged pushes (`vX.Y.Z`) run the same macOS pipeline in CI via [`.github/workflows/release.yml`](.github/workflows/release.yml) and publish the result as a GitHub release.

## Roadmap

See [`Podstash/TODO.md`](Podstash/TODO.md) for what's in progress and what's next (TestFlight, App Store, etc).

## License

Public domain — see [LICENSE](LICENSE). Do whatever you want with it.
