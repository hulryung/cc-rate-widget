# Manual QA — 1.7

Pre-release smoke checklist. All items must pass on a clean macOS 14.4+ build.

1. **Home folder access denied.** Deny the access prompt on first launch. Confirm the Dashboard shows the Setup Guide with a "Grant access" button. Click it → confirm the panel reopens and access works after granting.
2. **JSONL ingest.** Append a new assistant line to any file under `~/.claude/projects/`. Wait up to 5 minutes (or open Settings → it refreshes). Confirm the 5-hour token count increases.
3. **Absolute accuracy.** Confirm the dashboard shows real token counts and USD cost for Session (5h), Weekly (7d), and Weekly Sonnet — and that **no percentage** is displayed anywhere. Cross-check the weekly token total against `ccusage` or your own estimate; it should be in the right ballpark, not a constant ~95%.
4. **Rolling window across ticks.** Trigger two refreshes a minute apart without new activity. Confirm the windows stay stable (don't collapse toward zero) — this guards the rolling-window regression.
5. **Per-project view.** Confirm the Projects tab lists multiple projects with token totals and $ cost. Confirm Top 3 appear on the Large widget with `tokens · $cost`.
6. **Menu-bar mode toggle.** Toggle "Run in menu bar". Click "Quit and reopen". Confirm a "CC" status-bar item appears with Refresh / Open / Quit.
7. **No local data.** With `~/.claude/projects` absent, confirm the widget shows the "Setup Required" state and the source badge reads "SETUP".
