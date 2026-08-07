# Claude Rate Widget

**[Homepage](https://rate.huconn.xyz/)** | **[Releases](https://github.com/hulryung/cc-rate-widget/releases)**

A free, open-source native macOS app that monitors your Claude Code token usage and cost at a glance. Never hit a rate limit unexpectedly again.

> **v1.8 is a breaking release.** Coming from v1.5.2 — the previous published build — the desktop
> widget and the main window are both gone, and usage now comes from your local logs rather than an
> Anthropic login. See [Why the widget is gone](#why-the-widget-is-gone).

## How you check your usage

The app has no main window; it lives permanently in the menu bar, with nothing to enable. There are
two ways to read your usage.

**The popover — for browsing.** The menu-bar item shows your weekly percentage — or a token count
where that window has no percentage, or the bare gauge icon where there is no weekly window to
summarise at all. Click it for the full picture: one card per rate-limit window with its token
count, cost, usage bar and reset time,
a per-project breakdown of the last 7 days, then Refresh (<kbd>⌘</kbd><kbd>R</kbd>) and Settings
(<kbd>⌘</kbd><kbd>,</kbd>). Opening it brings the app forward, so those shortcuts and <kbd>Esc</kbd>
work immediately, with no click into the popover first. It closes on <kbd>Esc</kbd> or a click
outside it. Right-click the menu-bar item instead for Refresh Now / Settings… / Quit.

**The HUD — for a five-second glance.** <kbd>⌥</kbd><kbd>⌘</kbd><kbd>U</kbd> floats a panel over
whatever you're doing, including full-screen apps, where the menu bar isn't reachable. It shows the
same windows, each led by its percentage, with the time left and the reset moment beside it; tokens
and cost drop to small type, and the project list and buttons are gone. It fades out after 5
seconds, or closes on a second <kbd>⌥</kbd><kbd>⌘</kbd><kbd>U</kbd>. If your pointer is over it when
the timer fires it waits another 5 seconds. Unlike the popover it does not bring the app forward, so
it never takes focus from what you were typing into. The trade-off: <kbd>Esc</kbd> reaches it only
when the app is already active.

## Features

- **Local-first** — reads `~/.claude/projects/**/*.jsonl` on your Mac; no network round-trip required
- **Real token & cost tracking** — real counts and USD cost from your logs, not estimates. Prices the
  current Claude 5 generation (Opus 5, Sonnet 5, Fable 5) and bills 1-hour cache writes at 2×
- **Windows that match your account** — a 7-day window, a 5-hour session window, and one per model
  family in your logs. With official usage enabled the list is Anthropic's instead: whatever windows
  it reports, including scoped per-model ones that come and go
- **Per-project view** — see which projects burned which share of your last 7 days
- **Percentages without asking you for a limit** — enter your plan's limits in Settings and both
  windows measure against them. Leave them blank and each self-calibrates against your own history
  instead: the 5-hour window against the P90 of your past 5-hour blocks ("of your typical peak"),
  the weekly window against seven days at the pace of your heaviest whole day ("of 7 × your peak
  day"). Both are labelled by what the denominator is, so neither reads as a quota. Each needs
  three past samples — blocks, or whole days — and below three that window shows absolute usage
  only. Days are your calendar's, and the weekly pace ignores today and the oldest day in the
  window, since neither is whole
- **Honest by design** — de-duplicates events on the same `messageId:requestId` key `ccusage` uses,
  and a model id it can't place in any family contributes tokens but no cost. The official quota
  percentage is an experimental opt-in, because Anthropic provides no supported public usage API

## Install

### Homebrew

```bash
brew install hulryung/tap/claude-rate-widget
```

### Manual

Download the DMG from [Releases](https://github.com/hulryung/cc-rate-widget/releases/latest) and
drag Claude Rate Widget to Applications. The DMG and the app inside it are both signed with a
Developer ID certificate and notarized by Apple, so Gatekeeper opens it without a detour through
System Settings.

Or [build from source](#build-from-source): two commands, no Apple Developer account.

### After launching

1. **Grant access — only if you're asked.** With a normal Claude Code install `~/.claude/projects`
   is already readable and the numbers show up on their own. Only when the app can't read it does
   the popover show **Setup required** with a **Grant Access** button, which opens a file panel
   pinned to that folder; choosing it is what grants access. The same button lives in Settings under
   **Data**. Nothing is tracked until the app can read the folder.
2. Optionally open Settings (<kbd>⌘</kbd><kbd>,</kbd> in the popover) to enter your plan's token
   limits. The <kbd>⌥</kbd><kbd>⌘</kbd><kbd>U</kbd> shortcut is on by default.

### Requirements

macOS 14.4 or later, and Claude Code with usage logs under `~/.claude/projects`. That folder
existing is the only precondition — no plan, tier or entitlement is verified anywhere. A
subscription matters only for the official-usage percentage. That is off by default, and it needs
Claude Code signed in.

## Why the widget is gone

A macOS widget extension must be sandboxed, and a sandboxed extension cannot carry the App Group
entitlement it needed to read the app's data unless a provisioning profile validates it. That made
the widget buildable only on a machine with the distribution profiles installed; without them it
showed a setup prompt instead of your usage. The app itself was never affected — it isn't sandboxed.

Dropping the widget removed the App Group, the entitlement and the provisioning requirement
altogether: the app now holds one entitlement, `com.apple.security.network.client`, and builds with
plain Developer ID signing. Storage moved with it, to
`~/Library/Application Support/Claude Rate Widget/`. Your state and settings are copied across the
first time the new build runs, and only where a value isn't already there, so re-running never
clobbers anything newer.

## Anthropic usage API support

The app's primary, supported data source is local Claude Code JSONL logs — a path that never calls
Anthropic's usage API and never asks the app to manage your credentials.

The optional **official usage percentage** is experimental and off by default. It reads Claude
Code's existing OAuth access token from the macOS Keychain and calls the internal `/api/oauth/usage`
endpoint, the one behind Claude Code's own `/status` percentages. That endpoint is not a documented
public API, and Anthropic states that subscription OAuth credentials are meant for its own
applications rather than third-party products. So the integration is not supported or guaranteed: it
may return `401` or `403`, change format, or stop working without notice, and the app then falls
back to local usage data.

The app never refreshes Claude Code's OAuth token, because that could rotate Claude Code's own
refresh token and break its login. It never writes the token to disk either — it keeps it in memory,
re-reads the Keychain only near expiry or on rejection, and fetches roughly every 15 minutes.
Anthropic's [legal and compliance documentation](https://code.claude.com/docs/en/legal-and-compliance)
has the current authentication policy.

## Changelog

v1.8.0 follows **v1.5.2** directly. v1.6 and v1.7 were never published, so what v1.7 introduced —
the move off the Anthropic API onto your local logs — lands here as well, folded into the entry
below.

### v1.8.0

**Breaking: the desktop widget and the main window are both removed**, along with v1.7.0's opt-in
menu-bar toggle: the menu-bar item is now the app's only permanent surface. See
[Why the widget is gone](#why-the-widget-is-gone); data and settings migrate automatically to
`~/Library/Application Support/Claude Rate Widget/`, and everything the window carried is now in
the popover.

- **Corrected pricing.** The rate table only knew Claude 4, so every Claude 5 model was costed at
  $0, and cache writes were billed at a flat 1.25× input though Claude Code writes almost entirely
  1-hour entries, which bill at 2×. Cost was under-reported by **35%** on a real 7-day sample.
- **Rate-limit windows are no longer a fixed list.** The app used to show exactly three: 5-hour,
  7-day and 7-day Sonnet. Anthropic had stopped reporting the Sonnet one, so that card sat at 0%
  while real per-model usage went unshown. Per-family totals also recognised only some model ids.
- **Local numbers now describe Anthropic's block, not ours.** Its windows are fixed blocks with
  their own start times; ours roll. Right after a weekly reset that produced a card reading
  "99.7M tok" beside "0%".
- **The HUD is its own view**, not the popover on a floating panel with the project list and buttons
  in tow. It leads with the percentage and the time left, and stays up 5 seconds rather than 3.
- **The Keychain is read on demand, not on every refresh.** Reading it is what can raise a macOS
  permission prompt, and it was happening roughly 96 times a day for a resident app. The plan label
  now comes from that same read rather than a credentials file current Claude Code no longer writes,
  which means the pill fills in only once official usage has been enabled.
- **UI pass.** Shared design tokens everywhere, a real Settings window (<kbd>⌘</kbd><kbd>,</kbd>), and
  usage colour neutral at rest rather than saturated green, so a warning can stand out.

### v1.5.0 — released 2026-03-02

Handles a nullable `extra_usage.utilization` field, moves the OAuth endpoints from
`console.anthropic.com` to `platform.claude.com` after Anthropic's domain migration, adds
`forbidden` status handling for third-party OAuth restrictions, and improves error logging.

---

## Development

Needs Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
`CCRateWidget.xcodeproj` is generated and not committed, so `xcodegen generate` has to run before
any `xcodebuild` invocation, including opening the project in Xcode.

### Build from source

```bash
xcodegen generate
xcodebuild build -project CCRateWidget.xcodeproj -scheme CCRateWidget -configuration Release \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

That produces an unsigned build, which is what you want unless you hold this project's signing
certificate. `project.yml` pins `DEVELOPMENT_TEAM` to `XGJ87M8ZZR` with manual Developer ID signing,
so dropping the `CODE_SIGNING_*` overrides only works on a machine with that team's certificate.
No provisioning profile is needed either way.

### Run the tests

```bash
xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget \
  -destination 'platform=macOS' -configuration Debug \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""
```

### Project structure

```
CCRateWidget/       # App: menu-bar item, popover, ⌥⌘U HUD, Settings window
Shared/             # Aggregation, pricing, storage, design tokens (built into app and tests)
CCRateWidgetTests/
Assets.xcassets/    # App icon
docs/               # Landing page (Jekyll, GitHub Pages) and manual QA notes
releases/           # Release notes, one file per version — the body --publish uploads
scripts/release.sh  # Build, sign, notarize, verify, publish
.github/workflows/  # ci.yml (xcodebuild test, Debug), update-homebrew.yml (on release publish)
project.yml         # XcodeGen project spec
```

### Cutting a release

```bash
scripts/release.sh --check      # preflight only
scripts/release.sh              # build, sign, notarize, verify — publishes nothing
scripts/release.sh --install    # ...then install to /Applications and launch it
scripts/release.sh --publish    # ...then tag and create the GitHub release
```

The version comes from `CFBundleShortVersionString` in `CCRateWidget/Info.plist`, and `--publish`
needs release notes already written at `releases/v<version>.md`. Bumping the version and writing
the notes stay manual on purpose — neither should happen without someone reading them.

The step order matters and the script exists to enforce it:

```
app:  build → sign → notarize → staple
dmg:  pack (with the stapled app inside) → sign → notarize → staple
```

Notarizing only the DMG leaves the app inside without its own ticket. Gatekeeper still lets it
through while the machine is online, so the mistake surfaces only when someone who dragged the app
to Applications first opens it offline. The script verifies the finished DMG the way a browser
download is treated — it attaches `com.apple.quarantine`, runs `spctl` against the DMG and the app
inside it, and confirms the stapled ticket, the version and the presence of the icon.

`--install` strips `com.apple.quarantine` from the copy it installs. Gatekeeper's first-launch
check asks a notarization daemon whether a quarantined build is known-good, and that call can fail
by itself — this machine hit `Error checking with notarization daemon: 3` and blocked a build that
was correctly signed, notarized and stapled. Dropping the attribute skips that path, which is only
defensible because the step runs after the script has proven the artifact notarized offline. It
also cannot help anyone else: the attribute is written by whatever downloads the app on their Mac.
Prefer `brew upgrade --cask claude-rate-widget` for a released version, so Homebrew's record keeps
matching what is on disk.

Notarizing needs a `notarytool` keychain profile named `cc-rate-widget` (override with
`NOTARY_PROFILE`):

```bash
xcrun notarytool store-credentials "cc-rate-widget" --apple-id <apple-id> --team-id XGJ87M8ZZR
```

That prompts for an app-specific password from [appleid.apple.com](https://appleid.apple.com), not
the Apple ID password.
