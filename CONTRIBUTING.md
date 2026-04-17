# Contributing

Thanks for taking a look. colay is a small experiment, so the bar is informal but a few things keep it pleasant.

## Before you open a PR

1. `swift build` cleanly on macOS 13+.
2. New code follows the patterns already in the codebase: ECS components for state, Commands for actions, Behaviors for steering, Services for external dependencies. If you find yourself reaching for a singleton or a global, consider passing it through `Services` instead.
3. No new third-party dependencies without a discussion in an issue first — staying dep-free is a goal, not an accident.
4. New scriptable actions should be registered in `CommandRegistration.registerAll` with a `CommandSchema` so they show up in the manifest.

## Style

- Two-space-ish? No — Swift's standard 4-space indent. SwiftPM `swift-format` is fine but not required.
- Doc comments (`///`) on anything new that's likely to be called from outside the file.
- Prefer `final class` for reference types unless there's a real reason to subclass.
- Logging: use `services.log` rather than `print` so it shows up in the dashboard.

## Tests

There are no automated tests yet — see [TESTING.md](TESTING.md) for the plan. PRs that add the first XCTest target are very welcome.

## Reporting bugs

Please use the issue templates. A short script JSON or a screen recording goes a long way.

## Security

See [SECURITY.md](SECURITY.md). Please do not file security issues in the public tracker.
