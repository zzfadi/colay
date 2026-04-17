# Testing plan

There are no automated tests yet. This document captures what a useful test suite would look like and what has to be covered manually before each release.

## What's testable without a UI harness

These can be written as plain `XCTest` targets against a headless Engine fixture (inject a mock Clock, mock Overlay, no CVDisplayLink):

| Area | Unit-testable assertions |
|---|---|
| `Clock` | `dt` is 0 while paused; `time` advances only when unpaused; `timeScale` multiplies `dt`; `wallTime` advances always; `dt` clamps to 0.1s after a stall. |
| `EventBus` | Handlers fire for exact type; unrelated types don't; `Token` deinit unsubscribes; `subscriberCount` returns correct count. |
| `EngineLog` | Ring-buffer caps at 120; `tail(n)` returns newest-last; thread-safety under concurrent `append` (stress test). |
| `Math` | `smooth()`, `lerp`, `truncated(max:)`, `distance(to:)` invariants. |
| `CommandScheduler` | Programs run in order; `parallel` finishes when all children finish; `sequence` advances on child finish; `cancelAll` calls `cancel` on every in-flight cmd; loop replays. |
| `CommandRegistry` | Unknown type returns nil + logs; re-registration replaces; `manifest()` is stable. |
| Steering behaviors | Given a fixed state, each returns the expected force vector (edge cases: zero velocity, at-target, outside bounds). |
| `BehaviorComponent` | `preserveOnPrimarySwap` keeps named slots through `setPrimary`; `clearTransient` removes the rest. |
| `GazeSystem` | Resolves `.idle/.cursor/.point/.velocity` correctly; smoothing converges; override stack LIFO. |
| `WindowAttachmentComponent` | `attach`/`detach` roundtrip; `isAttached` reflects state. |
| `ScriptLoader` | Valid JSON parses; invalid root → throws; missing `type` entries are skipped. |
| `OverlayWindowController.screenRectToLocal` | Round-trip with `localToScreen` on a synthetic frame. |

## What requires an integration harness

These need a live `NSApplication` and can run under a UI test target using `XCUITest` or a scripted harness:

1. **Status-item + popover** — clicking the menu-bar item opens the popover; each pill swaps behavior; each action tile dispatches the right command. Validate by subscribing to `EngineLog` and asserting the log contains the expected `action` entry.
2. **Script loader** — `Run demo` loads the bundled demo and the scheduler reports non-empty sequence within one frame.
3. **Pause / Slow-Mo** — position does not change while paused; distance traveled per second is ~4× smaller in slow-mo.
4. **Overlay layering** — the overlay renders across multiple spaces / full-screen apps (manual).
5. **Multi-display** — overlay positioning and `screenRectToLocal` behave correctly on a setup with a non-primary monitor on the left and on the right. Current code assumes the first screen's height for the AX Y-flip; known limitation, should be documented + fixed or covered by the test.

## What requires Accessibility permission

These can only run on a machine where the tester has granted Accessibility to the colay binary and to the test runner:

1. **Sensor probe** — with a known window (e.g. TextEdit) focused, `captureFocusedWindow` delivers an `info.bounds` within 1 second and a non-nil `appName`.
2. **Highlight** — `highlightFocusedWindow` draws over the correct rect and fades out in `duration` seconds.
3. **Dive + Emerge** — after `diveIntoFocusedWindow`, `services.avatar.attachment.isAttached` is `true` and the attachment's `pid` matches the frontmost app. After `emergeFromWindow`, `isAttached` is `false`. Visual: the character visibly shrinks and stretches toward the window center, then reverses. No assertion for the visual; use a frame-hash or manual eye-test.
4. **Input synthesis** — `click` at a known point moves the cursor there and posts a mousedown/up (validate via a small test app that renders a hit-count). `type "hello"` produces "hello" in a focused text field.

## Manual smoke test (pre-release checklist)

Run on macOS 13+ with Accessibility granted:

1. `swift run` launches, status icon appears, popover opens.
2. Character is visible on every space, including full-screen apps.
3. Cursor movement → eyes track; character does not intercept clicks.
4. Each of `Idle`, `Follow`, `Wander`, `Stop` selects cleanly; `Stop` also cancels a running demo.
5. `Hop`, `Highlight`, `Snapshot` each log a line in the dashboard's log card.
6. `Dive In` attaches (status shows `● attached · <app>`); `Emerge` detaches. Pre-dive the character is anywhere on screen; dive visual is a smooth stretch-and-shrink toward the window center; emerge is the mirror image.
7. Load the bundled demo (`Run demo`) — all steps run to completion without a stall.
8. `Pause` freezes motion; `Slow-Mo` visibly slows it. Both toggle cleanly.
9. `Load script…` accepts an arbitrary JSON; a malformed file logs an error and doesn't crash.
10. Quit via the dashboard `Quit` button → process exits cleanly.

## Performance targets

- Idle CPU with no subscribers: < 1% on Apple Silicon.
- With `Follow` active: < 2% CPU, 60 fps on the overlay.
- Dashboard open (15 Hz refresh): < 0.5% additional CPU.
- Memory: steady-state under 40 MB.

## Known fragile areas worth covering first

1. `CommandRegistry.current` is a static used as a thread-local during composite construction. A test that constructs two nested parallel-of-sequence commands must verify the stack restores correctly.
2. `SensorService` sees the utility queue and main queue cross each other. A test that races `requestFocusedWindowSnapshot` against a real workspace-activation notification should show no `lastInfo` corruption.
3. `StayOnScreenBehavior` — on a resized overlay (e.g. user changes main display mid-run) bounds should track. Not currently verified.
4. `WindowTarget.axWindow` is always `nil` today — when real AX-element retention is added, ensure the ref survives focus changes and is released on `detach`.
