import CoreGraphics
import Foundation

/// Root of the scene graph. Systems are discoverable and run in a fixed order per frame.
///
/// Fixed order matters: Behaviors compute forces first, then Physics integrates, then the
/// Renderer paints the result. Changing this order without thought will reintroduce the
/// "snaps to cursor" bug we just fixed.
final class Scene {
    let root: Node = Node(name: "root")

    let behaviorSystem = BehaviorSystem()
    let physicsSystem = PhysicsSystem()
    let gazeSystem = GazeSystem()
    let renderer = Renderer()

    func update(dt: TimeInterval, time: TimeInterval, services: Services) {
        behaviorSystem.update(root: root, dt: dt, time: time, services: services)
        physicsSystem.update(root: root, dt: dt)
        // Gaze runs AFTER physics so it sees the updated position/velocity and the look
        // vector tracks where the character actually is this frame.
        gazeSystem.update(root: root, dt: dt, services: services)
    }

    func render(in ctx: CGContext, size: CGSize, time: TimeInterval) {
        renderer.render(root: root, in: ctx, size: size, time: time)
    }

    func findNode(named name: String) -> Node? { root.find(name: name) }
}
