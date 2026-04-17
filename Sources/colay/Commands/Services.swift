import Foundation

/// Everything a Command needs to do its work without reaching for globals.
///
/// Design pattern: **Service Locator (typed)**. The Engine builds one `Services` container
/// and passes it to commands and behaviors. It contains only the seams they legitimately
/// need; there is no NSApp lookup, no Singleton.shared.
struct Services {
    let clock: Clock
    let bus: EventBus
    let log: EngineLog
    let scene: Scene
    let avatar: AvatarRef
    let sensors: SensorService
    let input: InputSynth
    let overlay: OverlayRef
    let registry: CommandRegistry
    /// Optional so unit tests / preview can omit it. Mode commands use this to schedule
    /// their long-running side effects (e.g. the look-around windows watcher).
    weak var scheduler: CommandScheduler?
}

/// Indirection so commands can reach the avatar's components without holding a hard ref
/// to AppKit classes. Lets us swap avatars or run headless in tests.
final class AvatarRef {
    let node: Node
    let physics: PhysicsComponent
    let behaviors: BehaviorComponent
    let gaze: GazeComponent
    let attachment: WindowAttachmentComponent
    let character: CharacterDrawable

    init(node: Node, physics: PhysicsComponent, behaviors: BehaviorComponent,
         gaze: GazeComponent, attachment: WindowAttachmentComponent,
         character: CharacterDrawable) {
        self.node = node; self.physics = physics
        self.behaviors = behaviors; self.gaze = gaze
        self.attachment = attachment
        self.character = character
    }
}

/// Minimal interface into the overlay window — needed by commands that screen-convert
/// coordinates, e.g. Click / Highlight.
protocol OverlayRef: AnyObject {
    /// The window's frame in global screen coords (bottom-left origin).
    var frame: CGRect { get }
    /// The overlay's content size in points.
    var size: CGSize { get }
    /// Convert a local (scene) point to a global screen point.
    func localToScreen(_ p: CGPoint) -> CGPoint
    /// Convert a screen rect (top-left origin, as AX returns) into overlay-local (bottom-left).
    func screenRectToLocal(_ r: CGRect) -> CGRect
}
