---
name: regression-check
description: Run the nepogano smoke/regression checklist (docs/regression-checklist.md) before cutting a release build, or after a batch of fixes, to catch anything broken in primary or secondary app/landing functionality. Builds and installs a fresh APK, verifies what's automatable via adb, and walks the rest with the user.
---
# Nepogano regression check

This project accumulates real, previously-fixed bugs faster than any test
suite would get written for them. `docs/regression-checklist.md` is the
living list of what to re-check — most items exist because something
concrete broke there once (cross-referenced to a commit or ARCHITECTURE.md
where relevant). This skill runs that list, not a generic "test the app"
pass.

## When to use

- Before bumping the version in `pubspec.yaml` and cutting an
  `appbundle`/`ipa` for release.
- After a pack of unrelated fixes accumulated in one session, when the user
  asks "did I break anything" or "run the tests" before deciding to ship.
- NOT for verifying a single fix you just made in the same turn — that's
  ordinary build+install+check, already part of normal workflow. This skill
  is for the wider sweep across everything, right before it goes out.

## What this skill can and cannot automate

Be upfront about this with the user before starting, and again in the final
report — don't imply full automated coverage that didn't happen.

- **Fully automatable:** `flutter analyze` (whole project, not just changed
  files), `flutter build apk --release` succeeding, install via `adb`.
- **Semi-automatable via adb** (no accessibility-tree tool exists for this
  physical Android device, only raw shell):
  - `adb shell input tap X Y` / `input text "..."` / `input swipe` to drive
    the UI.
  - `adb exec-out uiautomator dump /dev/tty` (or dump to a file and `adb
    pull` it) gives an XML view hierarchy with `text`/`resource-id`/`bounds`
    for the current screen — use this to find what to tap instead of
    guessing coordinates from a screenshot alone.
  - `adb exec-out screencap -p > shot.png` for a visual check (Read the PNG
    with the Read tool for anything colors/layout/spacing related that the
    XML dump can't tell you).
  - This is slow and single-account: it's your own device, your own
    logged-in session. Anything needing a SECOND account (friend requests,
    shared subject diaries, receiving a nudge/comment/time-capsule-from-a-friend)
    cannot be driven this way — flag those as "needs the user" rather than
    skipping silently.
  - **Onboarding dialogs/first-run popups won't show on a normal pass** —
    `_subjectIntroSeenKey`, `_yesterdayIntroSeenKey`, `_constellationIntroSeenKey`
    (and similar `SharedPreferences`-backed "seen" flags, see ARCHITECTURE.md)
    are already flipped true on a device that's been used all session. To
    actually exercise these, clear the app's local storage first:
    `adb shell pm clear com.nepogano.app` — this also wipes the Supabase
    session (signs out) and any cached local state, so it's a deliberate,
    disruptive step: ask before doing it on the user's own logged-in device
    rather than doing it by default on every run, and expect to log back in
    (or ask the user to) afterward to continue the rest of the checklist.
    Do this as its OWN pass focused on first-run screens, not mixed into the
    main walkthrough where a fresh empty account would fail most other
    checklist items (no friends, no subjects, no history).
- **Landing pages** (`landing/*.html`): drive via the Browser pane
  (`preview_start` with the `landing` launch config — create
  `.claude/launch.json` per its tool docs if missing, `python3 -m
  http.server` over `landing/`) plus `resize_window` to emulate
  mobile/desktop and `navigate`/`javascript_exec` to simulate device
  detection (see this session's history for the pattern: overriding
  `navigator.userAgent` isn't reliable after `location.reload()`, so
  re-run the detection snippet inline instead of reloading).
- **Needs the user, always:** anything about how something *feels* rather
  than whether it *runs* (is the cooldown timer readable, does a color read
  as accent vs muted, is a wrap "3 lines and cramped" vs "2 lines and
  fine") — these were all caught by the user's own eyes earlier this
  session, not by automation. Say so plainly rather than rubber-stamping
  visual items you only inferred from a dump.

## Workflow

1. **Confirm scope.** Ask (if not already clear from context) whether this
   is a pre-release full sweep or a narrower check after specific recent
   changes — narrows which checklist sections matter most, though a
   pre-release run should still touch every section at least at the
   "does it crash" level.
2. **Static baseline.**
   - `flutter analyze` on the whole project (not just files touched this
     session) — report any NEW issues; pre-existing info-level lints
     unrelated to recent work aren't blockers, say so rather than treating
     every analyzer line as a finding.
   - `flutter build apk --release` — must succeed before anything else is
     worth checking.
3. **Install.** `adb devices -l` to confirm a device is attached; if none,
   stop here and tell the user plainly — don't fabricate results for
   sections that need the phone. Install with `adb install -r`.
4. **Walk `docs/regression-checklist.md` section by section.** For each
   **[П]** (primary) item first, then **[Д]** (secondary):
   - If it's automatable per the section above, drive it and report
     pass/fail with what you actually observed (a dump snippet, a
     screenshot detail) — not just "looks fine."
   - If it needs a second account or subjective judgment, list it under a
     clearly separate "needs your check" section in the final report rather
     than silently skipping or guessing an outcome.
   - If something looks broken, stop and investigate like any other bug
     report — read the relevant source, don't just note it and move on.
5. **Landing pages**, if the release also bundles landing changes (check
   `git log` since the last tagged/noted release for `landing/` diffs): run
   the relevant `/join`, `/confirmed`, `/` scenarios via the Browser pane.
6. **Report.** A compact pass/fail table or grouped list — what passed
   automatically, what you found broken (with the fix already started, per
   normal practice in this project — don't just report bugs without acting
   on them when the fix is clear and small), and what still needs the
   user's own pass on the device (named explicitly, not implied).
7. **Update the checklist.** If this run's investigation surfaced a new
   real bug (whether you fixed it in the process or the user asks you to
   fix it separately), add a scenario for it to
   `docs/regression-checklist.md` per that file's own "Як оновлювати"
   section — this is what keeps the list worth re-running next time,
   instead of decaying into a stale list of yesterday's bugs.

## Notes specific to this project

- `adb`/device connectivity has been flaky throughout past sessions (USB
  reconnects, `adb devices -l` sometimes returns empty right after a daemon
  restart) — re-run `adb devices -l` once before concluding "no device," not
  as a retry loop, just a single sanity re-check.
- Bash's cwd resets to `$HOME` between calls in this environment — always
  `cd /path/to/nepogano &&` explicitly, per this project's own established
  pattern, rather than relying on a prior `cd`.
- Anything requiring a friend/second-account flow: say so and ask the user
  whether they have a second test account handy, rather than marking it
  "skipped" without explanation.
