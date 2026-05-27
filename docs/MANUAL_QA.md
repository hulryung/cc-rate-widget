# Manual QA — 1.7

Pre-release smoke checklist. All items must pass on a clean macOS 14.4+ build.

1. **Home folder access denied.** Deny the NSOpenPanel prompt on first launch. Confirm Dashboard shows the Setup Guide with a "Grant access" button. Click it → confirm the panel reopens and access works after granting.
2. **JSONL ingest.** Append a new assistant line to any file under `~/.claude/projects/`. Wait up to 5 minutes. Confirm the widget's 5-hour bar increases.
3. **80% alert.** In Settings, set Plan tier to Pro. Manually generate enough activity (or temporarily edit `limits.json` in App Group container) to push utilization above 80%. Confirm one macOS notification fires. Confirm a second tick at 82% does **not** fire again.
4. **Menu-bar mode toggle.** Toggle "Run in menu bar". Click "Quit and reopen". Confirm a "CC" status-bar item appears with Refresh / Open / Quit.
5. **OAuth toggle.** Enable OAuth in Settings. Log in. Confirm the widget badge changes from "LOCAL" to "OAUTH" or "HYBRID" once a tick completes. Disable. Confirm no further OAuth calls (verify via Console.app NSLog filter).
6. **Per-project view.** Confirm the Projects tab lists projects with token totals and $ cost. Confirm Top 3 appear on the Large widget.
7. **Backfill.** On first launch after upgrade, observe `RateDataSource = .partial` briefly; confirm it flips to `.jsonl` once backfill completes (look for "Learning…" badge → "LOCAL").
