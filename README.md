# Claude Rate Widget

**[Homepage](https://hulryung.github.io/cc-rate-widget/)** | **[Download](https://github.com/hulryung/cc-rate-widget/releases/latest)**

A free, open-source native macOS WidgetKit widget that monitors your Claude Code rate limits at a glance.

## Screenshots

| Small (1x1) | Medium (2x1) | Large (2x2) |
|:---:|:---:|:---:|
| ![Small Widget](screenshots/widget-small.png) | ![Medium Widget](screenshots/widget-medium.png) | ![Large Widget](screenshots/widget-large.png) |

## Features

- Displays Session (5h), Weekly, Weekly Sonnet, and Overage rate limits
- Color-coded status: green (active), orange (warning 80%+), red (rate limited)
- Reset time countdowns for each category
- Auto-refreshes every 15 minutes via WidgetKit
- Reads credentials from `~/.claude/.credentials.json`

## Requirements

- macOS 14.0+
- Xcode 16+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Active Claude Code login

## Build

```bash
xcodegen generate
xcodebuild build -project CCRateWidget.xcodeproj -scheme CCRateWidget -configuration Release -allowProvisioningUpdates
```

## Install

Copy the built app to `/Applications` and launch it once to sync credentials:

```bash
cp -R ~/Library/Developer/Xcode/DerivedData/CCRateWidget-*/Build/Products/Release/Claude\ Rate\ Widget.app /Applications/
open /Applications/Claude\ Rate\ Widget.app
```

Then right-click the desktop > **Edit Widgets** > search "Claude Rate Monitor" to add the widget.
