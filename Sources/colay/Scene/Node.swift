import CoreGraphics
import Foundation

/// Lightweight ECS: a Node is an **entity** that carries **components** keyed by type.
///
/// Design pattern: **Entity-Component**. Instead of one fat `Node` class with position,
/// rotation, drawable, physics, behaviors, lifetime, etc. stuffed together, the Node is a
/// thin identity + container and each concern lives in its own Component. Systems
/// (Renderer, PhysicsSystem, BehaviorSystem, CommandScheduler) walk the tree and operate
/// on the components they care about.
///
/// Why: this is exactly how real game engines scale. It lets us add new capabilities
/// (trail, shadow, collision, AI sensors) without editing Node itself, and it keeps
/// per-frame work data-oriented rather than virtual-dispatch-heavy.
final class Node {
    let id: UUID = UUID()
    let name: String
    weak var parent: Node?
    private(set) var children: [Node] = []

    private var components: [ObjectIdentifier: Component] = [:]

    init(name: String) {
        self.name = name
        addComponent(TransformComponent())
    }

    // MARK: - Tree

    func addChild(_ node: Node) {
        node.parent = self
        children.append(node)
    }

    func removeChild(_ node: Node) {
        children.removeAll { $0 === node }
        node.parent = nil
    }

    func removeFromParent() { parent?.removeChild(self) }

    func find(name: String) -> Node? {
        if self.name == name { return self }
        for c in children { if let n = c.find(name: name) { return n } }
        return nil
    }

    // MARK: - Components

    @discardableResult
    func addComponent<C: Component>(_ c: C) -> C {
        let key = ObjectIdentifier(C.self)
        c.node = self
        components[key] = c
        c.didAttach()
        return c
    }

    func removeComponent<C: Component>(_ type: C.Type) {
        let key = ObjectIdentifier(type)
        if let c = components[key] { c.willDetach(); c.node = nil }
        components.removeValue(forKey: key)
    }

    func component<C: Component>(_ type: C.Type) -> C? {
        components[ObjectIdentifier(type)] as? C
    }

    /// Convenience for the always-present transform.
    var transform: TransformComponent { component(TransformComponent.self)! }

    // MARK: - System visits

    /// Iterate all components on this node (order not guaranteed).
    func forEachComponent(_ body: (Component) -> Void) {
        for c in components.values { body(c) }
    }
}

/// Base protocol for all components.
///
/// Components are **plain objects** (not protocols-with-assoctypes) so the scene can
/// store them heterogeneously. Per-frame work is done by systems iterating the tree, not
/// by components calling each other.
class Component {
    weak var node: Node?
    var enabled: Bool = true

    /// Called when attached to a node.
    func didAttach() {}
    /// Called right before detach.
    func willDetach() {}
}
