# colay — architecture & reference

Deep dive for contributors. For what colay *is* and how to install it, see the [README](../README.md).

## Design goals

- A **proper scene graph** — adding visuals shouldn't require touching anything else
- **Physics-based motion** so movement reads as alive rather than tween'd
- A **command surface** cleanly introspectable — the same JSON schema a human types is what an LLM tool-caller will eventually target
- **Observability baked in** — a live log panel so you can see what the agent just did

## Architecture

```
 main ──► AppDelegate ──► OverlayWindowController (transparent, click-through NSWindow)
                        │        └─ SceneView ──► Scene ──► Node tree + Systems
                        │
                        └─► Engine (owns CVDisplayLink)
                             ├─ Clock           time / pause / slow-mo
                             ├─ EventBus        typed pub/sub
                             ├─ EngineLog       ring-buffer log for UI
                             ├─ SensorService   debounced AX focused-window probe
                             ├─ InputSynth      CGEvent click / type
                             ├─ CommandRegistry schema + factory per command type
                             └─ CommandScheduler  sequence + background queues

 StatusItemController ──► DashboardViewController (popover UI, polls engine state)
 ScriptLoader ──► CommandScheduler.load(program:) ──► CommandRegistry.make(...)
```

### Per-frame order

`Engine.tick` runs, in order, on the main thread:

```
Clock.advance → Sensors.frameTick (cheap if no subscribers)
             → Scheduler.tick       (one sequence + N background cmds)
             → BehaviorSystem       (sum forces from behavior slots)
             → PhysicsSystem        (symplectic Euler, Reynolds-style force cap)
             → GazeSystem           (resolve declared gaze target → look vector)
             → SceneView.needsDisplay → Renderer.render
```

### Patterns used

- **Entity-Component** — every scene object is a `Node` with attached `Component`s (`Transform`, `Physics`, `Behavior`, `Gaze`, `Render`, `WindowAttachment`).
- **System pass** — per-concern traversals instead of virtual methods on `Node`.
- **Command pattern** (+ Prototype) — every scriptable action is a Command with `start / update / cancel`.
- **Strategy + Composite** — behaviors return forces; a BehaviorComponent holds a weighted stack.
- **Registry + Factory** — `CommandRegistry` is the single seam for scripts and future tool-callers.
- **Service Locator** (typed) — `Services` is passed to every command; no singletons.
- **Observer / PubSub** — `EventBus` for sensor events; `EngineLog` polled by the dashboard.

### Source map

```
Sources/colay/
  main.swift                       entry point
  AppDelegate.swift                wires Overlay + Engine + StatusItem
  Package.swift                    SwiftPM manifest (root)

  Core/                            Clock, EventBus, EngineLog, Math helpers
  Engine/                          Engine (frame loop, services builder)
  Overlay/                         transparent window + SceneView
  Scene/
    Node.swift, Scene.swift        scene graph + ordered systems
    Renderer.swift                 depth-first painter
    Systems.swift                  BehaviorSystem + PhysicsSystem
    Tween.swift                    Easing + Tween
    Components/                    Transform, Physics, Render, Behavior,
                                   Gaze, WindowAttachment
    Drawables/                     CharacterDrawable, RippleDrawable,
                                   HighlightRectDrawable
  Behaviors/                       Steering.swift — Arrive/Seek/Wander/Follow/Bumper/Idle
  Commands/
    Command.swift                  protocol + BaseCommand
    CommandParams.swift, Registry, Scheduler, Registration
    Services.swift                 typed service locator
    Primitives/                    Motion, System, WindowDive
  Scripts/ScriptLoader.swift       JSON parser (Commands built by registry)
  Sensors/SensorService.swift      AX focused-window probe, debounced, bg queue
  Input/
    InputSynth.swift               CGEvent click + type
    AccessibilityPermission.swift  one-time prompt helper
  Status/                          StatusItemController + DashboardViewController
  Resources/demo.json              sample script
```

## Scripts

A script is a JSON file of actions. See [`Sources/colay/Resources/demo.json`](../Sources/colay/Resources/demo.json):

```json
{
  "name": "demo",
  "loop": false,
  "actions": [
    { "type": "setBehavior", "mode": "idle" },
    { "type": "flyTo", "to": { "x": 260, "y": 220 } },
    { "type": "hop" },
    { "type": "parallel", "actions": [
        { "type": "highlightFocusedWindow", "duration": 1.6 },
        { "type": "captureFocusedWindow" }
    ]},
    { "type": "followCursor", "duration": 4.0, "orbitRadius": 120 }
  ]
}
```

### Command reference

| Type | Summary |
|---|---|
| `flyTo` | Fly to `{ x, y }` via physics arrive. |
| `followCursor` | Orbit the cursor for `duration` seconds. |
| `wait` | Pause the sequence. |
| `scaleTo`, `fadeTo` | Tween character scale / alpha. |
| `hop` | Playful bounce. |
| `click` | Synthesize a mouse click at a point (or at the avatar). |
| `type` | Type a string at `cps` characters/sec. |
| `highlightFocusedWindow` | Fading outline around the frontmost window. |
| `captureFocusedWindow` | Snapshot AX info about the focused window into the log. |
| `diveIntoFocusedWindow` | Dive + attach. |
| `emergeFromWindow` | Emerge + detach. |
| `setBehavior` | Mode: `idle` / `followCursor` / `wander` / `stop`. |
| `log` | Append a line to the dashboard log. |
| `parallel` | Run child actions concurrently. |
| `sequence` | Run child actions in order (useful inside `parallel`). |

The registry emits a JSON-Schema-ish manifest (`CommandRegistry.manifest()`) so an LLM tool-caller can consume the same surface directly.

## Security model

**This project synthesizes user input.** The following are worth understanding before running scripts you didn't write:

- `click` and `type` post real `CGEvent`s — they can interact with any app the user can.
- `captureFocusedWindow` / `highlightFocusedWindow` / `diveIntoFocusedWindow` read AX (app, window title, bounds); they do not read window *contents*.
- The app requests Accessibility permission on first use of those APIs; everything else (the character drawing, cursor position, overlay) works without it.
- Scripts are loaded from local JSON files via an open-panel only — no network loading.
- No network I/O anywhere in the project.
- No telemetry, no analytics, no credentials.

If you fork this and add network I/O, treat the existing command surface as untrusted — it can read your active window and drive your mouse + keyboard.

## Testing

There are no automated tests yet. A minimal E2E test plan is tracked in [TESTING.md](../TESTING.md).
