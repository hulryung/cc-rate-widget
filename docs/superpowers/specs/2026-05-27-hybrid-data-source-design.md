# 1.7 Hybrid Data Source — Design Spec

**Status:** Draft for review
**Date:** 2026-05-27
**Target release:** 1.7.0

## Goal

Migrate Claude Rate Widget from OAuth-only data sourcing to a **JSONL-primary** architecture, where the canonical data source is `~/.claude/projects/**/*.jsonl` parsed on-device. The existing OAuth `/api/oauth/usage` path becomes an opt-in supplement, default OFF.

## Motivation

1. **ToS hedge.** As of 2026-02-19, Anthropic's updated ToS discourages third-party use of OAuth tokens (`sk-ant-oat01-*`). The `/api/oauth/usage` endpoint is undocumented, not formally deprecated, but increasingly restricted (User-Agent gating, 403s). A widget that depends on it is one policy change away from breaking for every user.
2. **Capability gap nobody fills.** No competing tool fuses OAuth-reported quota with locally-parsed JSONL. `ccusage` owns local parsing (14.7k★); `Usage4Claude` (289★) owns OAuth quotas. None do both. The hybrid is a defensible position.
3. **New differentiators unlocked.** Per-project attribution and burn-rate forecasting against an *inferred* quota curve become possible once we own the raw events.

## Non-goals (explicit out-of-scope)

- Live Activity / Lock Screen / Apple Watch widgets (no macOS support; would require iOS app).
- Slack / Discord / webhook fan-out for alerts.
- Multi-account / multi-Claude-installation support.
- FSEvents-based incremental parsing (deferred to 1.8).
- LiteLLM pricing auto-sync (static table for 1.7).
- Cross-tool aggregation (Codex, Gemini, Copilot).

## Scope decisions

| Decision | Choice |
|---|---|
| Primary data source | Local JSONL parsing |
| OAuth role | Optional, default OFF, opt-in via Settings |
| Quota inference when no OAuth | P90 of historical max consumption |
| App shape | Windowed GUI default; opt-in menu-bar background mode |
| Per-project view | Main app window + Top-3 strip on Large (2x2) widget |
| Alert channels | macOS native (`UNUserNotificationCenter`) only |
| Per-project alerts | Out — only aggregate threshold/forecast alerts |

## Architecture

```
┌─ CCRateWidget (main app) ──────────────────────────────┐
│  AppMode                                                │
│   • windowed  (default, LSUIElement=false)              │
│   • menuBar   (opt-in, LSUIElement=true; relaunch req'd)│
│                                                         │
│  Settings UI · Project list · OAuth login (opt-in)      │
│                                                         │
│  AggregationCoordinator  ── Timer (5 min)               │
│     ↓                                                   │
│  JSONLAggregator (Shared/)                              │
│     ↓ snapshot                                          │
│  AppGroupStore (Shared/)                                │
│     • rate.json       — RateData snapshot               │
│     • projects.json   — Top-N project breakdown         │
│     • limits.json     — Inferred + cached-official      │
│     ↑                                                   │
│  AlertEngine — diffs prev vs new, fires notifications   │
│                                                         │
│  OAuthClient (opt-in)                                   │
│     • populates limits.json.official when ON            │
│     • silently skipped on failure                       │
└────────────────────────────────────────────────────────┘
                  ↓ App Group (group.com.dkkang.cc-rate-widget)
┌─ RateWidgetExtension ──────────────────────────────────┐
│  RateProvider → AppGroupStore.read() → RateWidgetViews │
│  (Small / Medium / Large — Large also reads projects)  │
└────────────────────────────────────────────────────────┘
```

### New modules

- `Shared/JSONLAggregator.swift` — walks `~/.claude/projects/`, incremental tail per file via byte offsets, 5h / 7d / 7d-Sonnet rolling-window aggregation.
- `Shared/LimitInferrer.swift` — P90-based plan-tier inference; prefers cached-official limits when present; emits `learning` state when history insufficient.
- `Shared/AppGroupStore.swift` — atomic JSON read/write of `rate.json`, `projects.json`, `limits.json` in App Group container.
- `Shared/Pricing.swift` — static `[modelGlob → {input, output, cache_write, cache_read} ($/Mtok)]` table.
- `CCRateWidget/AlertEngine.swift` — threshold-crossing detection (80%, 95%) and burn-rate forecast (ETA-to-100% from last 30 min); dedupes by window.
- `CCRateWidget/MenuBarMode.swift` — `NSStatusItem` lifecycle for opt-in menu-bar mode.

### Modified modules

- `Shared/RateFetcher.swift` → renamed `Shared/OAuthClient.swift`, demoted to optional supplement.
- `Shared/Models.swift` — add `ProjectBreakdown`, `InferredLimits`; extend `RateData` with `source: .jsonl | .oauth | .hybrid | .partial | .noLocalData`.
- `RateWidgetExtension/RateWidgetViews.swift` — Large variant gains Top-3 project strip; all variants gain "source" indicator (small dot or label).

## Sandbox posture (critical change)

The current `CCRateWidget.entitlements` has `com.apple.security.app-sandbox = true`. A sandboxed app cannot read `~/.claude/projects/` even with Full Disk Access granted — sandboxed file reads require either user-selected security-scoped bookmarks (clunky for a hidden dot-directory) or a temporary-exception entitlement.

**Decision:** drop the App Sandbox on the main app for 1.7. Distribution is via Homebrew DMG + Developer ID signing — not Mac App Store — so sandboxing is not a store requirement. The widget extension stays sandboxed (it only reads the App Group container, never `~/.claude/`).

Entitlement changes:

- `CCRateWidget/CCRateWidget.entitlements`:
  - Remove `com.apple.security.app-sandbox`.
  - Keep `com.apple.security.network.client` (for opt-in OAuth).
  - Keep `com.apple.security.application-groups = [group.com.dkkang.cc-rate-widget]`.
- `RateWidgetExtension/RateWidgetExtension.entitlements`: unchanged.

User-visible impact: macOS may show a "Claude Rate Widget would like to access files in your home folder" prompt on first read of `~/.claude/`. The setup guide explains this in advance. No Full Disk Access required.

## Data flow (one tick)

1. `AggregationCoordinator` fires (app launch + every 5 min).
2. `JSONLAggregator.run()`:
   - List `~/.claude/projects/**/*.jsonl`.
   - For each file: load cached byte offset; read from offset to EOF; parse JSONL line-by-line; on parse error, skip line and log; on file shrink, reset offset to 0 and re-read; persist new EOF as the cached offset.
   - For each `type == "assistant"` event extract `(timestamp, sessionId, cwd, model, usage)` and accumulate into 5h / 7d / 7d-Sonnet windows.
3. `LimitInferrer.infer(history:)`:
   - `weeklyMaxObserved` from `limits.json` is updated rolling.
   - Suggested 7d limit = `max(weeklyMaxObserved * 1.05, P90(weeklyHistory) * 1.2)` where `weeklyHistory` covers the stored 6 weeks.
   - Suggested 5h limit = same shape on 5h history.
   - If user has manual plan-tier override → use Pro/Max5/Max20 standard values.
   - If OAuth official cached → that wins over all of the above.
4. Build `RateData`:
   - `utilization = consumption / inferredLimit` (allowed to exceed 1.0).
   - `resetsAt = earliestEventInWindow + windowLength` (sliding-window semantics, converges with OAuth values when both are present).
   - `status`: `active` / `warning` (≥0.8) / `rateLimited` (≥1.0) / `error` / `noLocalData` / `unauthorized` (OAuth ON only).
   - `source` reflects which paths participated.
5. `AppGroupStore.write(rate.json, projects.json, limits.json)` — atomic temp+rename.
6. `AlertEngine.evaluate(prev, new)`:
   - 80% / 95% threshold crossings → notification; dedupe within window via `forecastFiredAt`/`thresholdFiredAt` on snapshot.
   - Burn-rate forecast: from last-30-min tokens-per-minute, compute ETA to 100%; if `ETA < (resetsAt - now) - 30min` → notification, also deduped per window.
7. `WidgetCenter.shared.reloadAllTimelines()`.
8. `RateProvider.getTimeline()` → reads from App Group → views render.

## JSONL parsing details

### Event of interest

```json
{
  "type": "assistant",
  "timestamp": "2026-05-27T08:14:22.103Z",
  "sessionId": "...",
  "cwd": "/Users/dkkang/dev/cc-rate-widget",
  "message": {
    "model": "claude-opus-4-7",
    "usage": {
      "input_tokens": 412,
      "cache_creation_input_tokens": 1839,
      "cache_read_input_tokens": 27431,
      "output_tokens": 286
    }
  }
}
```

Only `type == "assistant"` lines are read. Other lines (user, tool, system) are skipped without parsing the inner payload.

### Project identity

`project = lastPathComponent(cwd)`. Aliases editable in main app, persisted in `projects.json.aliases: [cwd → displayName]`.

### Pricing (static, `Shared/Pricing.swift`)

```
opus-4.x   → input 15.00 / output 75.00 / cache_write 18.75 / cache_read 1.50   ($/Mtok)
sonnet-4.x → input  3.00 / output 15.00 / cache_write  3.75 / cache_read 0.30
haiku-4.x  → input  1.00 / output  5.00 / cache_write  1.25 / cache_read 0.10
```

Unknown models → bucketed under `"unknown"`, cost = 0, tokens still counted.

### Window definitions

- `five_hour`     = `(now - 5h, now]` over all assistants.
- `seven_day`     = `(now - 7d, now]` over all assistants.
- `seven_day_sonnet` = `(now - 7d, now]` ∩ `model ~= /sonnet/i`.
- Token sum for utilization: `input + output + cache_creation_input_tokens` (cache reads are counted but priced separately, near-zero cost).

### P90 limit inference

- Maintain `weeklyMaxObserved` (single scalar) in `limits.json`, updated each tick if current 7d sum exceeds it.
- Maintain `weeklyHistory: [Date → totalTokens]` for last 6 weeks (one entry per UTC midnight) — used for P90.
- Same shape for 5h history (one entry per hour, last 6 weeks = 1008 entries; bounded).
- First install: 6-week backfill scan as one-time background job; during backfill `RateData.source = .partial`, widget label "Learning…", % bar greyed.

## Edge cases

| Case | Behavior |
|---|---|
| `~/.claude/projects/` missing | `.noLocalData` state; main app shows setup guidance; widget shows setup hint. |
| Home-folder access denied | First-run macOS prompt for `~/.claude/` access; on denial, settings page shows "Re-prompt" button which calls `NSOpenPanel` against `~/.claude` to re-trigger consent; remains `.noLocalData` until granted. |
| File rotation / deletion | `fileSize < cachedOffset` → reset to 0, re-read full. inode-change detection deferred to 1.8. |
| Corrupt / partial JSONL line | Skip line, NSLog; advance offset past the bad line. If trailing line has no `\n`, keep offset at line start so next tick reads it once complete. |
| Clock jumps / DST | All windows in UTC `Date`. Known limitation: manual system-clock changes can transiently distort windows. |
| App not running during quota approach | No alert fires. Settings page must surface this explicitly when menu-bar mode is OFF. |
| Concurrent App Group read/write | Atomic `tmp → rename`; readers never see partial. |
| Corrupted `rate.json` | Decode fail → return `RateData.placeholder` with `status = .error`; overwritten next tick. |
| Overlapping aggregator runs | Single serial `OperationQueue`, `maxConcurrent = 1`. |
| Utilization > 100% | Widget bar clamps to 100% visually; numeric label shows true value (e.g. "127%"); `weeklyMaxObserved` updates so next tick normalizes. |
| OAuth 401/403 (opt-in mode) | `limits.json.official` cleared; falls back to P90; one-time settings banner; no automatic OAuth disable. |
| Menu-bar ↔ windowed toggle | LSUIElement is plist-bound → relaunch required; main app shows a "restart now" sheet on toggle, calls `NSApp.relaunch()` on confirm. |
| Many accounts / installations | Out of scope for 1.7. |

## Testing strategy

### Targets to add

- `CCRateWidgetTests` (XCTest unit) — new target in `project.yml`.
- `CCRateWidgetUITests` (smoke) — small, optional.

### Unit coverage

| Subject | Cases |
|---|---|
| `JSONLAggregator` | golden path; corrupt line skipped; trailing partial line offset; window-boundary inclusion/exclusion; same `cwd` across two files merged. |
| `LimitInferrer` | empty history → `.learning`, nil limit; only `weeklyMaxObserved` present → 1.05× returned; manual override beats P90; OAuth official beats both. |
| `AppGroupStore` | atomic write under read pressure; corrupt JSON → placeholder, no throw; offset map round-trip. |
| `AlertEngine` | 79→81 fires 80%; 81→82 silent; window reset re-arms; ETA = ∞ when 30-min burn rate is zero. |
| `Pricing` | known models × token mix = expected USD; unknown model → cost 0, tokens still counted. |

### Fixtures

Under `CCRateWidgetTests/Fixtures/jsonl/`: small synthetic JSONL files (20–50 lines each) covering golden, corrupt, multi-project, sonnet-only, empty. Real `~/.claude/` is never read by tests.

### Integration

Deliberately deferred. The unit boundary covers the new code; full integration is paired with the FSEvents migration in 1.8.

### Manual QA checklist (added to README)

1. Deny home-folder access on first launch → confirm guidance sheet renders and "Re-prompt" button works.
2. Append a new JSONL line manually → confirm widget value updates within 5 min.
3. Lower plan-tier override below current consumption → confirm 80% alert fires once and is not repeated.
4. Toggle menu-bar mode → confirm restart sheet → confirm relaunch.
5. Enable OAuth → confirm "official" indicator appears on widget.

### CI

Append `xcodebuild test -scheme CCRateWidget` to the existing `.github/workflows/` build job on `macos-14`.

## Open items deferred to 1.8

- FSEvents-based incremental parsing.
- inode-change file-rotation detection.
- Multi-account / multi-installation aggregation.
- LiteLLM pricing auto-sync.
- Live Activity / iOS companion (separate spec).
