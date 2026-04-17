import CoreGraphics
import Foundation

/// One place that registers every primitive. Adding a new primitive = adding one entry
/// here plus its class. This is the file an AI tool-caller bridge will later auto-export.
enum CommandRegistration {
    static func registerAll(into r: CommandRegistry) {

        r.register(CommandSchema(
            type: "flyTo", summary: "Fly to a point using physics-based arrive steering",
            params: [
                .init(name: "to", type: "point", required: true, description: "Target point in overlay coords"),
                .init(name: "arriveRadius", type: "number", required: false, description: "Stop threshold, default 6pt"),
                .init(name: "maxDuration", type: "number", required: false, description: "Safety timeout, default 6s")
            ]
        )) { p in
            let t = p.point("to") ?? .zero
            let r = CGFloat(p.double("arriveRadius") ?? 6)
            let d = p.double("maxDuration") ?? 6
            return FlyToCommand(target: t, arriveRadius: r, maxDuration: d)
        }

        r.register(CommandSchema(
            type: "followCursor", summary: "Follow the cursor at an orbit radius",
            params: [
                .init(name: "duration", type: "number", required: true, description: "Seconds"),
                .init(name: "orbitRadius", type: "number", required: false, description: "Preferred distance from cursor")
            ]
        )) { p in
            FollowCursorCommand(
                duration: p.double("duration") ?? 3,
                orbitRadius: CGFloat(p.double("orbitRadius") ?? 110)
            )
        }

        r.register(CommandSchema(
            type: "wait", summary: "Pause for N seconds",
            params: [.init(name: "duration", type: "number", required: true, description: "Seconds")]
        )) { p in WaitCommand(duration: p.double("duration") ?? 0.5) }

        r.register(CommandSchema(
            type: "scaleTo", summary: "Tween character scale",
            params: [
                .init(name: "scale", type: "number", required: true, description: "Target scale"),
                .init(name: "duration", type: "number", required: false, description: "Seconds"),
                .init(name: "easing", type: "easing", required: false, description: "Ease function")
            ]
        )) { p in
            ScaleToCommand(
                target: CGFloat(p.double("scale") ?? 1),
                duration: p.double("duration") ?? 0.3,
                easing: p.easing("easing")
            )
        }

        r.register(CommandSchema(
            type: "fadeTo", summary: "Tween character alpha",
            params: [
                .init(name: "alpha", type: "number", required: true, description: "Target alpha 0..1"),
                .init(name: "duration", type: "number", required: false, description: "Seconds"),
                .init(name: "easing", type: "easing", required: false, description: "Ease function")
            ]
        )) { p in
            FadeToCommand(
                target: CGFloat(p.double("alpha") ?? 1),
                duration: p.double("duration") ?? 0.3,
                easing: p.easing("easing")
            )
        }

        r.register(CommandSchema(
            type: "hop", summary: "Little playful hop",
            params: [.init(name: "duration", type: "number", required: false, description: "Seconds, default 0.5")]
        )) { p in HopCommand(duration: p.double("duration") ?? 0.5) }

        r.register(CommandSchema(
            type: "click", summary: "Synthesize a mouse click",
            params: [
                .init(name: "at", type: "point", required: false, description: "Overlay-local point; default = avatar position"),
                .init(name: "button", type: "string", required: false, description: "left|right|middle")
            ]
        )) { p in ClickCommand(at: p.point("at"), button: p.string("button") ?? "left") }

        r.register(CommandSchema(
            type: "type", summary: "Type a string of text",
            params: [
                .init(name: "text", type: "string", required: true, description: "Text to type"),
                .init(name: "cps", type: "number", required: false, description: "Chars per second, default 20")
            ]
        )) { p in TypeCommand(text: p.string("text") ?? "", cps: p.double("cps") ?? 20) }

        r.register(CommandSchema(
            type: "highlightFocusedWindow", summary: "Draw a fading outline around the focused window",
            params: [.init(name: "duration", type: "number", required: false, description: "Seconds, default 1.2")]
        )) { p in HighlightFocusedWindowCommand(duration: p.double("duration") ?? 1.2) }

        r.register(CommandSchema(
            type: "captureFocusedWindow", summary: "One-shot snapshot of the focused app/window",
            params: []
        )) { _ in CaptureFocusedWindowCommand() }

        r.register(CommandSchema(
            type: "diveIntoFocusedWindow",
            summary: "Fly to the focused window, play dive effect, attach avatar to it",
            params: []
        )) { _ in DiveIntoFocusedWindowCommand() }

        r.register(CommandSchema(
            type: "emergeFromWindow",
            summary: "Play emerge effect and detach avatar from the currently attached window",
            params: []
        )) { _ in EmergeFromWindowCommand() }

        r.register(CommandSchema(
            type: "setBehavior", summary: "Set the avatar's continuous behavior",
            params: [.init(name: "mode", type: "string", required: true, description: "idle|followCursor|wander|stop")]
        )) { p in
            let m = SetBehaviorCommand.Mode(rawValue: p.string("mode") ?? "idle") ?? .idle
            return SetBehaviorCommand(mode: m)
        }

        r.register(CommandSchema(
            type: "log", summary: "Log a message",
            params: [.init(name: "message", type: "string", required: true, description: "Text")]
        )) { p in LogCommand(message: p.string("message") ?? "") }

        r.register(CommandSchema(
            type: "parallel", summary: "Run child actions concurrently",
            params: [.init(name: "actions", type: "actions", required: true, description: "Array of command objects")]
        )) { p in
            let children: [Command] = p.children().compactMap { type, params in
                // Re-dispatch through the registry lookup we'll set up as the caller.
                // We capture the registry via a thread-local; see CommandRegistry.resolveChildren.
                CommandRegistry.current?.make(type: type, params: params)
            }
            return ParallelCommand(children)
        }

        r.register(CommandSchema(
            type: "sequence", summary: "Run child actions in order",
            params: [.init(name: "actions", type: "actions", required: true, description: "Array of command objects")]
        )) { p in
            let children: [Command] = p.children().compactMap { type, params in
                CommandRegistry.current?.make(type: type, params: params)
            }
            return SequenceCommand(children)
        }
    }
}
