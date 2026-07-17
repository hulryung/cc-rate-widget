# Claude Rate Widget

**[Homepage](https://rate.huconn.xyz/)** | **[Download](https://github.com/hulryung/cc-rate-widget/releases/latest)**

A free, open-source native macOS widget that monitors your Claude Code rate limits at a glance. Never hit a rate limit unexpectedly again.

## Screenshots

| Small (1x1) | Medium (2x1) | Large (2x2) |
|:---:|:---:|:---:|
| ![Small Widget](screenshots/widget-small.png) | ![Medium Widget](screenshots/widget-medium.png) | ![Large Widget](screenshots/widget-large.png) |

## Features

- **Local-first** — reads `~/.claude/projects/**/*.jsonl` on your Mac; no network round-trip required
- **Accurate token & cost tracking** — real 5-hour, 7-day, and 7-day Sonnet token counts and USD cost, not estimates
- **Per-project view** — see which projects burned which share of your 5-hour and 7-day windows
- **Optional percentage** — enter your plan's token limits in Settings to see a % against them; left blank, the widget shows absolute usage only
- **Three widget sizes** — Small, Medium, Large (Top-3 project strip on Large)
- **Opt-in menu bar mode** — keep the app alive in the background
- **Honest by design** — counts deduplicated events and matches `ccusage` on cost; official quota percentage is available only as an experimental opt-in because Anthropic does not provide a supported public usage API for third-party apps

## Install

### Homebrew (recommended)

```bash
brew install hulryung/tap/claude-rate-widget
```

### Manual

1. **Download** the latest DMG from [Releases](https://github.com/hulryung/cc-rate-widget/releases/latest)
2. **Drag** Claude Rate Widget to your Applications folder

### After install

1. **Launch** the app (Claude Code must already be installed and signed in to use the experimental official-usage option)
2. **Add widget** — Right-click your desktop > Edit Widgets > search "Claude Rate Monitor"

### Requirements

- macOS 14.0 (Sonoma) or later
- Active Claude Code / Claude Max subscription

## Anthropic usage API support

The widget's primary, supported data source is local Claude Code JSONL logs. This path does not call Anthropic's usage API or require the widget to manage your Claude credentials.

The optional **official usage percentage** is experimental. It reads Claude Code's existing OAuth access token from the macOS Keychain and calls the same internal `/api/oauth/usage` endpoint used by Claude Code. The endpoint still exists, but it is not a documented public API, and Anthropic states that subscription OAuth credentials are intended for Anthropic's own applications rather than third-party products.

As a result, this integration is not officially supported or guaranteed. It may return `401` or `403`, change response format, or stop working without notice. The widget never refreshes or stores Claude Code's OAuth token; when the request is unavailable, it falls back to local usage data. See Anthropic's [Claude Code legal and compliance documentation](https://code.claude.com/docs/en/legal-and-compliance) for the current authentication policy.

## Changelog

### v1.7.0

- **Local-first, absolute-centric.** Reads `~/.claude/projects/**/*.jsonl` and reports real token counts and USD cost for the 5-hour, 7-day, and 7-day Sonnet windows.
- **Per-project attribution.** New Projects tab in the main app; Large widget shows Top 3 projects.
- **Optional percentage.** Enter your plan's 5-hour/weekly token limits in Settings to calculate a percentage from local usage, or explicitly enable the experimental internal-API integration to display Anthropic's official quota percentage when available.
- **Accurate cost.** Cache-aware pricing and event de-duplication; weekly cost matches `ccusage` within a few percent.
- **Opt-in menu bar mode.** Keep the app alive in the background.
- **App Sandbox dropped on main app** (widget extension remains sandboxed). Enables reading `~/.claude/`.

### v1.5.0

- Fix API compatibility: handle nullable `extra_usage.utilization` field in Anthropic usage API response
- Update OAuth endpoints from `console.anthropic.com` to `platform.claude.com` following Anthropic's domain migration (Jan 2026)
- Add `forbidden` status handling for Anthropic's third-party OAuth restrictions
- Improve error logging for easier debugging of token refresh and API failures

---

## Development

### Prerequisites

- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Build from source

```bash
xcodegen generate
xcodebuild build -project CCRateWidget.xcodeproj -scheme CCRateWidget -configuration Release
```

The built app will be at:
```
~/Library/Developer/Xcode/DerivedData/CCRateWidget-*/Build/Products/Release/Claude Rate Widget.app
```

### Project structure

```
CCRateWidget/          # Main app (login UI, rate display)
RateWidgetExtension/   # Widget extension
Shared/                # Shared code (models, API, storage)
docs/                  # Landing page (Jekyll, GitHub Pages)
project.yml            # XcodeGen project spec
```
