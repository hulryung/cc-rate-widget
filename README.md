# Claude Rate Widget

**[Homepage](https://rate.huconn.xyz/)** | **[Download](https://github.com/hulryung/cc-rate-widget/releases/latest)**

A free, open-source native macOS app that monitors your Claude Code token usage and cost at a glance. Never hit a rate limit unexpectedly again.

> **v1.8 replaces the desktop widget with a menu-bar popover and a global shortcut.** See [Why the widget is gone](#why-the-widget-is-gone) if you're upgrading.

## Screenshots

> Being re-shot for v1.8. The previous images showed the desktop widget, which no longer exists.

## How you check your usage

- **Menu bar** — your weekly percentage is always visible. Click it for the full summary; click away or press <kbd>Esc</kbd> to dismiss.
- **Global shortcut** — <kbd>⌥</kbd><kbd>⌘</kbd><kbd>U</kbd> shows the same summary anywhere, including over full-screen apps, and fades out on its own. It waits if your pointer is over it.
- **Main window** — the dashboard, plus a per-project breakdown of the last 7 days.

## Features

- **Local-first** — reads `~/.claude/projects/**/*.jsonl` on your Mac; no network round-trip required
- **Accurate token & cost tracking** — real 5-hour, 7-day, and 7-day Sonnet token counts and USD cost, not estimates. Prices the current Claude 5 generation (Opus 5, Sonnet 5, Fable 5) and bills 1-hour cache writes at their true 2× rate
- **Per-project view** — see which projects burned which share of your windows
- **Optional percentage** — enter your plan's token limits in Settings to see a % against them; left blank, the app shows absolute usage only
- **Honest by design** — counts deduplicated events and matches `ccusage` on cost; the official quota percentage is an experimental opt-in, because Anthropic does not provide a supported public usage API for third-party apps

## Install

### Homebrew (recommended)

```bash
brew install hulryung/tap/claude-rate-widget
```

### Manual

1. **Download** the latest DMG from [Releases](https://github.com/hulryung/cc-rate-widget/releases/latest)
2. **Drag** Claude Rate Widget to your Applications folder

### After install

1. **Launch** the app and grant access to `~/.claude` when asked
2. **Enable the menu bar** in Settings (<kbd>⌘</kbd><kbd>,</kbd>) if you want the always-visible percentage. The <kbd>⌥</kbd><kbd>⌘</kbd><kbd>U</kbd> shortcut is on by default

Claude Code must already be installed and signed in to use the experimental official-usage option.

### Requirements

- macOS 14.0 (Sonoma) or later
- Active Claude Code / Claude Max subscription

## Why the widget is gone

A macOS widget extension must be sandboxed, and a sandboxed process carrying the App Group entitlement is killed at launch unless a provisioning profile validates that entitlement. Removing the sandbox instead makes WidgetKit refuse to register the extension at all. Both directions are closed, so the widget could only ever be built on a machine with the distribution profiles installed — and when it wasn't, it silently rendered "Setup required" instead of your usage.

The main app was never affected, because it isn't sandboxed. Dropping the widget removed the App Group, the entitlement, and the provisioning requirement altogether, so the project now builds with plain Developer ID signing and no profiles.

Your data and settings migrate automatically on first launch of v1.8.

## Anthropic usage API support

The app's primary, supported data source is local Claude Code JSONL logs. This path does not call Anthropic's usage API or require the app to manage your Claude credentials.

The optional **official usage percentage** is experimental. It reads Claude Code's existing OAuth access token from the macOS Keychain and calls the same internal `/api/oauth/usage` endpoint used by Claude Code. The endpoint still exists, but it is not a documented public API, and Anthropic states that subscription OAuth credentials are intended for Anthropic's own applications rather than third-party products.

As a result, this integration is not officially supported or guaranteed. It may return `401` or `403`, change response format, or stop working without notice. The app never refreshes or stores Claude Code's OAuth token; when the request is unavailable, it falls back to local usage data. See Anthropic's [Claude Code legal and compliance documentation](https://code.claude.com/docs/en/legal-and-compliance) for the current authentication policy.

## Changelog

### v1.8.0

**Breaking: the desktop widget is removed.** See [Why the widget is gone](#why-the-widget-is-gone). Data and settings migrate automatically; storage moves from the App Group container to `~/Library/Application Support/Claude Rate Widget/`.

- **Corrected pricing.** The rate table only knew the Claude 4 generation, so every Claude 5 model — Opus 5, Sonnet 5, Fable 5 — was costed at $0. Cache writes were also billed at a flat 1.25× input, but current Claude Code writes almost entirely 1-hour cache entries, which bill at 2×. Together these under-reported cost by **35%** on a real 7-day sample. Unknown future models now fall back to their family's rate instead of silently costing nothing.
- **Menu-bar popover and <kbd>⌥</kbd><kbd>⌘</kbd><kbd>U</kbd> shortcut** replace the widget as the at-a-glance surfaces.
- **Plan label restored.** It read a credentials file Claude Code no longer writes, so it had been blank; the tier now comes from the Keychain read the official-usage path already performs, with no extra permission prompt.
- **UI pass.** Shared design tokens across every surface; usage colour is neutral at rest rather than saturated green, so a warning can actually stand out. Token abbreviation no longer renders 1,400 as "1K", and costs get locale grouping.
- **Real Settings window** (<kbd>⌘</kbd><kbd>,</kbd>), and the Anthropic-terms notice is now visible rather than buried in a footer.

### v1.7.0

- **Local-first, absolute-centric.** Reads `~/.claude/projects/**/*.jsonl` and reports real token counts and USD cost for the 5-hour, 7-day, and 7-day Sonnet windows.
- **Per-project attribution.** New Projects tab in the main app; Large widget shows Top 3 projects.
- **Optional percentage.** Enter your plan's 5-hour/weekly token limits in Settings to calculate a percentage from local usage, or explicitly enable the experimental internal-API integration to display Anthropic's official quota percentage when available.
- **Accurate cost.** Cache-aware pricing and event de-duplication.
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

No provisioning profiles are needed — the app is unsandboxed and holds no entitlements beyond network access, so a Developer ID certificate alone is enough.

### Run the tests

```bash
xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget \
  -destination 'platform=macOS' -configuration Debug \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""
```

### Project structure

```
CCRateWidget/    # App: window, menu-bar popover, hotkey HUD, settings
Shared/          # Aggregation, pricing, storage, design tokens
CCRateWidgetTests/
docs/            # Landing page (Jekyll, GitHub Pages)
project.yml      # XcodeGen project spec
```
