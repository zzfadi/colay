# colay

[![build](https://github.com/zzfadi/colay/actions/workflows/build.yml/badge.svg)](https://github.com/zzfadi/colay/actions/workflows/build.yml)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-lightgrey)](https://www.apple.com/macos/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**A little procedural companion that lives on your macOS desktop.**

colay wanders across your screen, watches your cursor, hops between your windows, and can dive into the one you're focused on. It's a real character — not a sprite loop — driven by steering behaviors and a tiny physics engine. And every cute motion you see is a script you can replay, extend, or wire up to something bigger.

<p align="center">
  <img src="docs/demo.gif" alt="colay wandering, hopping, and diving into the focused window" width="720" />
</p>

<p align="center">
  <em>Status: experimental. The shape is still moving. Please be kind.</em>
</p>

---

## The story

I wanted a real substrate to experiment with **on-screen agents** — something alive, observable, and scriptable that I could hand to an LLM and say *"go do that for me."*

Most desktop pets are one-off scripts. I wanted a proper little game engine: a scene graph, physics-based motion, a command scheduler, an event bus, a live log panel — all the pieces you'd need if you were going to hand the keyboard to an AI and watch it work.

This release (v0.1.0) is just the starting point. The character moves, the dashboard works, scripts load. The real project begins now.

## Where it's going

colay is designed from day one to be driven by AI agents. The direction:

- **Copilot / model SDK in the loop** — instead of JSON scripts, plug a model directly into the command bus so the companion can *reason* about what you're doing and act on the screen.
- **Skills / protocol surface** — expose the command registry as a standard tool surface (MCP, or similar) so any agent can drive colay without special-casing it.
- **Visible work, not hidden automation** — the whole point of an *on-screen* companion is that you *see* the agent doing the thing. If it clicked something, the character walked over and clicked it. No mystery macros.
- **Your machine, your rules** — local-first, no telemetry, permissions scoped tight. The goal is delight, not spyware with a face.

I'll be exploring and learning in public. Contributions, ideas, and forks very welcome.

## Install

### Download the DMG (signed & notarized)

Grab the latest `colay-<version>.dmg` from the [**Releases page**](https://github.com/zzfadi/colay/releases/latest), open it, drag `colay.app` into `/Applications`, and launch it from Spotlight.

Look for the companion icon in your menu bar — click it to open the dashboard.

### Homebrew (once the tap is live)

```bash
brew tap zzfadi/colay
brew install --cask colay
```

> Setting up the one-time `zzfadi/homebrew-colay` tap; template in [docs/homebrew-tap.md](docs/homebrew-tap.md).

### Build from source

```bash
git clone https://github.com/zzfadi/colay.git
cd colay
swift run
```

## First launch

macOS will ask for **Accessibility** permission the first time colay tries to click, type, or read the focused window. The character draws and follows your cursor without it — Accessibility is only needed for the scripted actions.

Grant it in **System Settings → Privacy & Security → Accessibility**.

## Quick tour

Click the status-bar icon to open the dashboard.

| Section | What it does |
|---|---|
| **Status** | Header card. Green dot = commands running. |
| **Telemetry** | Position, speed, current behavior, pending-command count. |
| **Behaviors** | Mutually exclusive pills: `Idle` / `Follow` / `Wander` / `Stop`. |
| **Actions** | One-shot tiles: `Hop`, `Highlight`, `Snapshot`. |
| **Window** | `Dive In` (attach to the focused window), `Emerge` (detach). |
| **Engine** | `Pause`, `Slow-Mo`. |
| **Log** | Live tail of engine events. |
| **Scripts** | `Run demo`, `Load script…`, `Quit`. |

Try: click **Follow** → drag your cursor around. Then open a window and hit **Dive In**.

## What's inside

Under the hood colay is a tiny game engine — entity-component scene graph, steering behaviors (Reynolds), physics integration, a command registry that already emits a JSON-Schema-ish manifest for tool callers. Less than 4 KLOC of Swift + AppKit, zero third-party dependencies.

The full architecture, command reference, per-frame tick order, source map, and security model live in [**docs/ARCHITECTURE.md**](docs/ARCHITECTURE.md).

## Requirements

- macOS 13 Ventura or newer
- Swift 5.9 (Xcode 15) or newer *(only if building from source)*

## Security & privacy

- No network I/O. No telemetry. No analytics. No credentials.
- `click` and `type` synthesize real `CGEvent`s — they can touch anything you can.
- Scripts are loaded only from local JSON files via an open-panel.

Longer version in [docs/ARCHITECTURE.md#security-model](docs/ARCHITECTURE.md#security-model).

## Contributing

Issues, PRs, and wild ideas all welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). For security issues, [SECURITY.md](SECURITY.md).

## License

MIT. See [LICENSE](LICENSE).
