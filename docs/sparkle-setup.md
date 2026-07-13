# Sparkle Auto-Update Setup

This guide explains how to integrate [Sparkle 2](https://sparkle-project.org/) for automatic updates in NetMonitor.

## Why Sparkle?

For apps distributed outside the Mac App Store (GitHub Releases, Homebrew Cask), Sparkle is the standard way to provide automatic update checks and seamless upgrades.

## Quick Start

### 1. Add Sparkle to Package.swift

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
],
targets: [
    .executableTarget(
        name: "NetMonitor",
        dependencies: [
            "NetMonitorCore",
            .product(name: "Sparkle", package: "Sparkle"),
        ]
    ),
]
```

### 2. Configure Info.plist

Add to `Resources/Info.plist`:

```xml
<key>SUFeedURL</key>
<string>https://github.com/pangziqiang/NetMonitor/releases/latest/download/appcast.xml</string>
<key>SUEnableAutomaticChecks</key>
<true/>
```

### 3. Initialize in App Delegate

```swift
import Sparkle

// In NetworkMonitorApp.swift
let updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
)

// Add menu item:
// "Check for Updates..." → updaterController.checkForUpdates(nil)
```

### 4. Generate Appcast

Use the `generate_appcast` tool (included in Sparkle distribution):

```bash
# After creating a release DMG
./bin/generate_appcast /path/to/releases/
```

Upload the generated `appcast.xml` to your GitHub Releases page.

## Signing Requirements

For Sparkle to work securely, your app should be signed with a Developer ID certificate and the update DMGs must include an EdDSA signature. For open-source projects, Sparkle also supports unsigned mode (less secure).

## Alternatives

- **GitHub Releases only**: Users manually download new versions (current approach)
- **Homebrew Cask**: `brew upgrade --cask netmonitor` handles updates via Homebrew
- **Sparkle**: Fully automatic in-app updates (best UX)

## Decision

For now, NetMonitor does **not** include Sparkle. Users can:
1. Watch GitHub Releases for new versions
2. Use Homebrew Cask for managed updates

Sparkle integration is planned for a future release.
