# Manual QA — 1.8.0

Pre-release smoke checklist for the build whose `CFBundleShortVersionString` is `1.8.0`
(`CCRateWidget/Info.plist`). 1.8.0 has never been tagged or released, so this is run against a
build from source, not a downloaded DMG.

Every item states an expected result. Items are independent — run any subset.

## Build and launch

- [ ] `xcodegen generate` succeeds. (The `.xcodeproj` is gitignored, so this is required before any `xcodebuild`.)
- [ ] Without the XGJ87M8ZZR Developer ID certificate, `xcodebuild build -project CCRateWidget.xcodeproj -scheme CCRateWidget -configuration Release CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""` prints `** BUILD SUCCEEDED **`.
- [ ] `xcodebuild test -project CCRateWidget.xcodeproj -scheme CCRateWidget -destination 'platform=macOS' -configuration Debug CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""` prints `** TEST SUCCEEDED **` with 0 failures.
- [ ] Runs on macOS 14.4 or later (`MACOSX_DEPLOYMENT_TARGET` is 14.4; there is no 14.0 build).
- [ ] Launching the app opens **no window** and shows **no Dock icon** — the only thing that appears is a gauge status item in the menu bar.
- [ ] Nothing prompts for home-folder access at launch. A TCC prompt appears only after you press a grant-access affordance.

## No local data / first-run state

Rename `~/.claude/projects` away for these.

- [ ] Menu-bar title is blank — the gauge icon only, no number.
- [ ] The popover shows "Setup required", the `folder.badge.questionmark` symbol, the text "Grant access to ~/.claude to start tracking.", and a prominent **Grant Access** button. No source/updated footer line is drawn here.
- [ ] ⌥⌘U shows "No usage data yet" in the HUD — no Grant Access button there.
- [ ] Clicking **Grant Access** opens an open-panel pointed at `~/.claude/projects` with hidden files visible. Dismissing it (either way) triggers a refresh.
- [ ] Restore `~/.claude/projects`, grant access, refresh → the popover replaces the setup state with usage cards.

## Menu-bar item

- [ ] The status item is present at launch every time, and there is no setting anywhere to hide or disable it.
- [ ] With a weekly denominator available (weekly limit set, or official usage on), the title reads a percentage in monospaced digits, e.g. ` 42%`.
- [ ] With **both limits 0 and official usage off**, the title reads an abbreviated token count instead — e.g. ` 3.8M` — not `0%`.
- [ ] Below 80% the number carries no hue (label colour). Set the weekly limit low enough to push past 80% → orange; past 100% → red.
- [ ] Left-click opens the popover and the app activates as it opens, so the popover has keyboard focus immediately with no click inside it first.
- [ ] Each dismissal path closes it: left-click the status item again (and that same click must **not** reopen it), Esc, a click in another app or on the desktop, and losing focus with no click at all (⌘-Tab, Mission Control, the lock screen).
  Every one of those is handled by explicit code — the popover's behaviour is `.applicationDefined` — so a path that stops working is a real regression, not a cosmetic one.
- [ ] Right-click opens a menu with exactly three items — **Refresh Now** (⌘R), **Settings…** (⌘,), **Quit** (⌘Q) — and no "Open" item.
- [ ] After dismissing that menu, the next left-click opens the popover again (the menu must not stick to the status item).
- [ ] **Refresh Now** advances the "Updated <time>" in the popover.

## Popover contents

- [ ] Fixed-width column on an opaque background. Switch the system to Dark Mode, reopen the popover: cards, text and chrome all render dark — no light cards inside dark chrome.
- [ ] Order top to bottom: window cards → footer line (source + "Updated <time>") → divider → "Projects · last 7 days" → divider → **Refresh** / **Settings…**.
- [ ] With `~/.claude/projects` in place, relaunch and open the popover before the first tick finishes → a small spinner, not empty cards. The spinner shows on every fresh launch, because the in-memory snapshot is never seeded from the stored `rate.json`.
- [ ] The first card is the Weekly (7 days) window and is the hero card; the Session (5 hours) window is last; any per-model windows sit between them.
- [ ] In the popover the hero card's token numeral is the *same* size as the other cards' — the popover renders every card compact. What marks the hero out is its headline-sized title, the plan pill, the limit caption and a larger cost figure.
- [ ] Hero card elements appear per the table below. A missing element is a failure only when its condition holds.

  | Element | Shown when |
  | --- | --- |
  | Title, subtitle | Always |
  | Plan pill | A plan tier is known (see [Official usage](#official-usage-opt-in)) |
  | Percentage chip | The window has a percentage |
  | Usage bar | The window has a percentage |
  | Limit caption | The window has a percentage |
  | Token numeral + "tok" | Local tokens are above zero |
  | Cost | Cost is above zero |
  | Reset line | The window has a reset time |

  In the default configuration — both limits 0, official usage off — the Weekly card has no percentage, so no chip, bar or caption. That is expected, and matches the local-only section below.
- [ ] A non-first card repeats the hero card's reset time only when its own reset differs.
- [ ] Limit caption wording matches the denominator: "Anthropic quota · <plan>" for official, "of <N> tok limit" for a limit you typed, "of your typical peak (<N> tok)" for the self-calibrated one.
- [ ] Reset line reads as a moment with no minutes (weekday, month, day, hour) followed by a "2d 4h left" chip.
- [ ] **Refresh** (⌘R) updates the "Updated" time and does **not** dismiss the popover. Test the shortcut on a *freshly opened* popover with no click inside it — the app takes focus as the popover opens, so ⌘R must work on that first keystroke.
- [ ] **Settings…** (⌘,) dismisses the popover and opens the Settings window — likewise on a freshly opened popover, with no click inside it first.

## Per-project list

- [ ] "Projects · last 7 days" lists projects sorted by tokens, largest first, at most 20 rows.
- [ ] Each row: name (middle-truncated), a bar scaled relative to the largest project, token count, USD cost.
- [ ] Hovering a name shows the project's full path as a tooltip.
- [ ] With more than about seven projects the list scrolls inside the popover instead of making the popover grow.
- [ ] With no readable project data, the whole projects section (and its divider) is absent — not an empty box.

## Local-only windows and percentages (official usage OFF)

- [ ] The window set is Weekly (7 days), Session (5 hours), plus one "Weekly · <Family>" card per model family present in the last 7 days, largest family first.
- [ ] **Regression (71401f5):** every "Weekly · <Family>" card shows a real non-zero token count — a family that appears in your logs must not render "0 tok".
  Cost is a weaker guarantee. Family assignment matches the family word anywhere in the model id, while pricing needs a known prefix, so a model logged under a bare `fable`/`mythos` shorthand yields real tokens and no cost figure.
- [ ] With the weekly limit at 0, the Weekly card shows tokens and cost and **no** percentage, chip or bar.
- [ ] With the 5-hour limit at 0, the Session card shows a percentage captioned "of your typical peak (<N> tok)" — but only once history holds at least three past non-empty 5-hour blocks. With less history than that there is no percentage at all.
- [ ] Set the 5-hour limit → the Session caption changes to "of <N> tok limit" and the refresh happens immediately, without reopening anything.
- [ ] Footer source line reads "local logs" (lowercase prose, not a badge).

## JSONL ingest

- [ ] Append a valid `"type":"assistant"` line (with `timestamp`, `cwd`, `message.model`, `message.usage`) under `~/.claude/projects/`, then **Refresh Now** → the Session token count increases.
- [ ] Append a user turn / tool result / malformed line → totals do not change.
- [ ] Append the same assistant line twice with the same `message.id` and `requestId` → it is counted once, not twice.
- [ ] Trigger two refreshes a minute apart with no new activity → the window totals stay stable and do not collapse toward zero.
- [ ] Truncate a JSONL file below the offset already recorded → the next refresh discards that file's retained events and re-reads it from byte 0, with no crash and no double-counting.
  The totals fall by exactly the events in the bytes you removed. That drop is correct.
- [ ] Delete a JSONL file → its contribution drops out on the next refresh; no crash.
- [ ] Write a partial (newline-less) trailing line → it is not counted; complete it and refresh → it is.
- [ ] Waiting idle, "Updated <time>" advances roughly every 5 minutes on its own.

## Global shortcut HUD

- [ ] ⌥⌘U from any other app summons the HUD — including while a full-screen app is frontmost.
- [ ] The panel appears on whichever screen has the pointer, slightly above centre.
- [ ] Summoning it triggers a refresh: the "Updated <time>" in its footer is current.
- [ ] Contents: one block per usage window separated by dividers, then a single footer with plan (when known), source label and "Updated <time>". No project list, no buttons.
- [ ] The first block's large numeral is the percentage when that window has a denominator (weekly limit set, or official usage on); tokens and cost sit small in the block's header row. Where a percentage exists, this is the inverse of the popover's cards.
- [ ] With **both limits 0 and official usage off** — the default — the first block is the Weekly window with no percentage, so the large slot holds the token count instead. That is correct behaviour, not a failure.
- [ ] The HUD auto-hides 5 seconds after appearing, fading out rather than vanishing.
- [ ] Keep the pointer inside the panel across that deadline → it stays up for another full 5 seconds.
  The pointer is sampled only when the timer fires, so after you move away the panel hides at the end of the current interval, not the moment the pointer leaves.
- [ ] ⌥⌘U again while it is visible hides it.
- [ ] Esc hides it while this app is the active one — for example with Settings open.
  ⌥⌘U deliberately does not activate the app, so a HUD summoned over another app leaves the keystrokes with that app. ⌥⌘U again and the auto-hide are the dismissals that always apply. Keeping the frontmost app's focus is the intended trade for a glance surface.
- [ ] Clicking outside the panel does **not** dismiss it, and clicking does not steal focus from the frontmost app.
- [ ] Dragging anywhere on the panel background moves it.
- [ ] Turning off "Global shortcut (⌥⌘U)" in Settings takes effect immediately — ⌥⌘U does nothing, with no relaunch. Turning it back on restores it immediately.
- [ ] On a fresh preferences domain the shortcut is ON by default.

## Settings window

- [ ] Reachable from the popover (⌘, or the **Settings…** button) and from the status item's right-click menu. The app comes to the front to show it without a Dock icon appearing.
- [ ] Window is titled "Settings", cannot be resized or minimised, and opens centred.
- [ ] Sections in order: **Usage** (explanatory text only), **Usage limits** (5-hour and Weekly numeric fields, both suffixed "M tok", footer "Set your plan's limits to see a percentage. 0 shows absolute usage only."), **Quick access** (⌥⌘U toggle), **Official usage** (toggle plus an orange warning that Anthropic's terms discourage third-party use of this login), **Data** (a "Re-prompt for ~/.claude access" button).
- [ ] There is no menu-bar toggle and no "quit and reopen" button.
- [ ] Merely **opening** Settings does not refresh — the "Updated" time is unchanged.
- [ ] **Changing** a limit field or the official-usage toggle refreshes immediately.
- [ ] "Re-prompt for ~/.claude access" opens the same open-panel as the popover's Grant Access button, and refreshes when it closes.
- [ ] Closing the Settings window does not quit the app — the status item is still there.
- [ ] Reopening Settings brings back the same window (state preserved, not a second window).

## Official usage (opt-in)

- [ ] On a fresh preferences domain, "Show official usage %" is OFF and the footer reads "local logs".
- [ ] Turning it on refreshes immediately. The first attempt may raise a macOS prompt to access the "Claude Code-credentials" keychain item; allowing it switches the footer to "official".
- [ ] With it on, the rendered window list is Anthropic's, not a fixed three, and the percentages match what `/status` reports in Claude Code.
- [ ] Display order is still forced: Weekly first, scoped per-model windows next, Session last — even though the wire order puts session first.
- [ ] **Scoped windows (71401f5):** a per-model window reported by Anthropic appears titled "Weekly · <Display name>" with subtitle "7 days", and shows a **non-zero** token count beside the percentage whenever that model family is present in your local logs.
  Cost beside it is not guaranteed: a bare `fable`/`mythos` shorthand hits the same pricing gap noted for the local per-family cards, and an unpriced card shows no cost figure.
- [ ] A scoped window that arrives without its own reset time still shows a reset (borrowed from the weekly window) rather than none.
- [ ] A window with no reset time at all shows its percentage alone, with no token line.
- [ ] Shortly after a weekly rollover, the token count beside an official percentage reflects Anthropic's new block (small), not the rolling 7-day total (large). The percentage and the tokens must describe the same period.
- [ ] **Regression (815f941): the keychain prompt must not recur.** With official usage on, leave the app resident for at least 45 minutes (three 15-minute throttle windows) → no prompt tied to the refresh interval. Quit and relaunch → the count starts over at one.
  The token is held in memory for the life of the process, so one prompt per launch is the normal case. A further keychain read happens only when that cached token comes within a minute of expiring, or when the server answers 401/403. A weekly rollover forces an off-schedule fetch, but it reuses the cached token and so must not prompt.
- [ ] Deny the keychain prompt: the app stays on its local windows with the footer reading "local logs", and does **not** prompt again on the next 5-minute tick.
- [ ] Disconnect the network (or otherwise make the request fail): the app silently keeps its local windows, shows no error dialog, and logs `[OfficialUsage] HTTP <code>` for a non-200 response.
- [ ] With an expired keychain token, the app falls back to local windows rather than attempting a token refresh.
- [ ] Turning official usage back off returns the window list to Weekly / Session / per-family on the next refresh, with the footer back to "local logs".
- [ ] Plan pill: once a keychain read has seen a recognised tier, the first card shows a pill such as "Max 20x".
  Two other sources can supply the tier without official usage ever being enabled: a `~/.claude/.credentials.json` written by an older Claude Code, and a cached tier carried over by the legacy settings migration below. With none of the three, there is no pill.

## Storage and migration

- [ ] After the first successful tick, `~/Library/Application Support/Claude Rate Widget/` contains `rate.json`, `projects.json`, `offsets.json`, `events.json` and `schema.json`.
- [ ] `schema.json` records version 4.
- [ ] Editing `schema.json` to a different version → the next tick discards stored events and offsets, re-reads from source, and arrives back at the same totals (may take one extra tick on a large history).
- [ ] With data still present in the legacy App Group container and none in Application Support, first launch copies `rate.json`, `projects.json`, `offsets.json`, `events.json` and `schema.json` across, leaving the originals in place.
- [ ] Legacy settings (official-usage toggle, hotkey toggle, both limits, cached plan tier) survive that migration when `UserDefaults.standard` has no value of its own.

## Accessibility

- [ ] The usage bar's VoiceOver value reads "<N> percent of limit" plus a word — "OK", "Near limit" or "Over limit" — so the level is never conveyed by colour alone.
- [ ] The percentage chip reads "<N> percent used" plus the same word.
- [ ] Over 100%, the bar renders full rather than overflowing its track.
