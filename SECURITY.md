# Security policy

## Reporting a vulnerability

If you believe you've found a security issue in colay, **please do not open a public GitHub issue.** Use one of these channels instead:

- GitHub's private vulnerability reporting on this repository (Security tab → "Report a vulnerability")
- Direct email to the maintainer listed on the GitHub profile

Please include:

- Affected version / commit
- A minimal reproduction (a small Swift snippet or a script JSON file)
- Your assessment of impact
- Whether you'd like to be credited in the fix

You can expect an acknowledgement within a few days. Fix turnaround depends on severity.

## Threat model

colay is a local desktop utility. It has no network surface and does not phone home. The interesting attack surface is:

1. **Synthesized input.** `click` and `type` post real `CGEvent`s and require macOS Accessibility permission. A malicious script can interact with anything the user can.
2. **Script loader.** Scripts are JSON files chosen by the user via `NSOpenPanel`. There is no sandbox around the command set — treat untrusted JSON the way you'd treat an executable.
3. **AX read access.** With Accessibility granted, the sensor reads window title, app name, and bounds of the focused window. It does not read window contents, clipboard, or text fields.

If you are forking colay and adding network input or any kind of remote command channel, the existing command surface should be considered untrusted by default — gate it behind an explicit allow-list.

## Out of scope

- Issues that require physical or admin access to the machine
- Bugs in macOS APIs themselves (CGEvent, AX) — please report those to Apple
- Denial-of-service via a script that intentionally floods the scheduler — the scheduler is single-threaded and `Stop` will halt it
