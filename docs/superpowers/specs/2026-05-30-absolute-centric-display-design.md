# Absolute-Centric Display — Design Spec

**Status:** Approved, implementing
**Date:** 2026-05-30
**Supersedes:** the %-estimation parts of `2026-05-27-hybrid-data-source-design.md`

## Why

Running the 1.7 build revealed two problems:

1. **Rolling-window bug** (fixed separately, commit `831a444`): incremental tailing summed per-tick deltas, not the true window.
2. **The % itself is unknowable from JSONL.** JSONL gives token *counts*; Anthropic's rate-limit *percentage* is computed server-side and cannot be derived from token sums. The P90/ratchet estimate calibrated the "limit" to the user's own peak usage (`limit = maxObserved × 1.05`), so every heavy user showed a constant `1/1.05 = 95.2%` on first run regardless of their true remaining quota. A user who had actually used ~5% saw "95%".

Dropping OAuth as the primary source (the 1.7 ToS hedge) removed the only accurate source of the real %. Estimating it from local data is fundamentally misleading.

## Decision

Pivot to an **absolute-centric** display. Show what JSONL can report accurately — tokens, cost, per-project breakdown, reset countdowns — and do not display any percentage until a real limit is available (future opt-in OAuth, which reports Anthropic's true utilization directly).

Confirmed choices:
- **Remove % bars entirely.** No progress bars, no 80/95% warning coloring.
- **Main numbers: tokens + cost, both.** Each window renders `X.XM tok · $Y`.
- **No alerts in this release.** Threshold/forecast alerts were percentage-based; they return with OAuth %.
- **OAuth stays opt-in and dormant** — the future path for a real %.

## Removed (the unreliable %-estimation subsystem)

- `Shared/LimitInferrer.swift` + `LimitInferrerTests`
- `CCRateWidget/Backfill.swift` (weeklySamples population)
- `InferredLimits` type; `limits.json`; `AppGroupStore.readLimits/writeLimits/mutateLimits`
- `Shared/AlertEngine.swift` + `AlertEngineTests`; `AlertState`; `alert_state.json` + its store methods + `AlertStateRoundTripTests`
- `Shared/OAuthClient.swift` (dead fetch logic that built the old RateData; no live callers)
- `CredentialManager.CachedRateData` + `save/loadCachedRateData` (dead)
- Settings plan-tier picker
- `RateData.overage` and widget overage rows; `CategoryData.utilization`; `OverallStatus.warning/.rateLimited`

## Kept

- JSONL → `events.json` rolling store → `JSONLAggregator.computeSnapshot` (the corrected aggregation)
- Per-project breakdown (Projects tab + Large widget Top-3)
- `CredentialManager` token/PKCE machinery + `OAuthLoginView` (dormant login, future % path)
- OAuth response models in `Models.swift` (document the shape for future revival)
- Source badge (LOCAL / SETUP)

## New shape

```swift
struct CategoryData {
    let tokens: Int
    let cost: Double
    let resetsAt: Date?
}

struct RateData {
    let session: CategoryData        // 5h
    let weekly: CategoryData         // 7d
    let weeklySonnet: CategoryData   // 7d sonnet
    let fetchedAt: Date
    let status: OverallStatus        // active | partial | noLocalData | error (others dormant)
    let source: RateDataSource
}
```

`AggregationSnapshot` already carries `fiveHourTokens/sevenDayTokens/sevenDaySonnetTokens`, `fiveHourCost/sevenDayCost`, `earliestInFiveHour/earliestInSevenDay`, and `projects`. The coordinator maps these straight into `RateData` (resetsAt = earliest + window length). No inference step.

Sonnet cost is not currently tracked separately by the snapshot; `weeklySonnet.cost` is reported as 0 for now (tokens are accurate). This is acceptable — Sonnet is a secondary line; adding per-window sonnet cost is a small follow-up if wanted.

## UI

- **Dashboard:** each window row shows `tokens` (formatted e.g. `2.4M`) · `$cost` · `resets in …`. No bar.
- **Widgets (S/M/L):** tokens + cost per window. Small = 7-day headline + cost; Medium = three windows; Large = three windows + Top-3 projects. Source badge retained.
- **Status color:** neutral/green while tracking; red only for `noLocalData`/`error`.

## Testing

- Reshape `computeSnapshot`/coordinator mapping is covered by existing aggregator tests (token math unchanged) plus updated `ModelsTests` for the new `CategoryData`/`RateData` shape and `PersistedRate` round-trip.
- Delete obsolete tests for removed subsystems.
- Manual verification: run the app against real `~/.claude/projects`, confirm dashboard/widget show accurate per-window tokens+cost and 34 projects, with no misleading %.
