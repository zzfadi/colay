import AppKit
import CoreVideo
import Foundation

/// Top-level assembly. Builds all services, wires them together, owns the display link,
/// and pumps the frame loop. Think of this as the "game" object.
final class Engine {
    let clock = Clock()
    let bus = EventBus()
    let log = EngineLog()
    let sensors: SensorService
    let input = InputSynth()
    let registry = CommandRegistry()
    let scheduler = CommandScheduler()

    let overlay: OverlayWindowController
    let scene: Scene
    let avatar: AvatarRef

    private var displayLink: CVDisplayLink?

    init(overlay: OverlayWindowController) {
        self.overlay = overlay
        self.scene = overlay.sceneView.scene
        self.sensors = SensorService(bus: bus)

        // ---- Build avatar ----
        let node = Node(name: "avatar")
        let character = CharacterDrawable()
        node.transform.size = CGSize(width: 52, height: 52)
        node.transform.position = CGPoint(
            x: overlay.frame.midX, y: overlay.frame.midY
        )
        node.addComponent(RenderComponent(character, layer: 10))

        let phys = PhysicsComponent()
        phys.maxSpeed = 700
        phys.maxForce = 1800
        phys.damping = 2.2
        node.addComponent(phys)

        let behaviors = BehaviorComponent()
        // Default behavior: gentle idle bob + "stay on screen" bumper. Script/menu can
        // override by setting a new primary behavior.
        behaviors.add(IdleBobBehavior(), weight: 1.0, name: "idle")
        behaviors.add(StayOnScreenBehavior(boundsProvider: { [weak overlay] in
            overlay?.frame ?? .zero
        }), weight: 1.0, name: "stayOnScreen")
        node.addComponent(behaviors)

        let gaze = GazeComponent()
        gaze.base = .cursor // always curious about the user by default
        node.addComponent(gaze)

        let attachment = WindowAttachmentComponent()
        node.addComponent(attachment)

        scene.root.addChild(node)
        self.avatar = AvatarRef(node: node, physics: phys, behaviors: behaviors,
                                gaze: gaze, attachment: attachment,
                                character: character)

        CommandRegistration.registerAll(into: registry)
    }

    /// Services container — built per-call because it captures the current `self`. This
    /// is the only thing Commands and Behaviors see.
    func makeServices() -> Services {
        Services(
            clock: clock, bus: bus, log: log, scene: scene,
            avatar: avatar, sensors: sensors, input: input,
            overlay: overlay, registry: registry, scheduler: scheduler
        )
    }

    // MARK: - Frame loop

    func start() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let link = displayLink else { return }
        let ref = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { (_, inNow, _, _, _, userData) -> CVReturn in
            let engine = Unmanaged<Engine>.fromOpaque(userData!).takeUnretainedValue()
            let now = CFTimeInterval(inNow.pointee.videoTime) / CFTimeInterval(inNow.pointee.videoTimeScale)
            // All engine work happens on main to keep AppKit + the scene lock-free.
            DispatchQueue.main.async { engine.tick(now: now) }
            return kCVReturnSuccess
        }, ref)
        CVDisplayLinkStart(link)
    }

    func stop() {
        if let link = displayLink { CVDisplayLinkStop(link) }
    }

    private func tick(now: CFTimeInterval) {
        clock.advance(now: now)
        let services = makeServices()

        // Sensors poll themselves only if subscribed; cheap otherwise.
        sensors.frameTick(now: clock.wallTime)

        scheduler.tick(dt: clock.dt, services: services)
        scene.update(dt: clock.dt, time: clock.time, services: services)

        overlay.sceneView.currentTime = clock.time
        overlay.sceneView.needsDisplay = true
    }

    // MARK: - Script loading

    func loadScript(at url: URL) {
        do {
            let parsed = try ScriptLoader.load(from: url)
            scheduler.load(program: parsed.actions, loop: parsed.loop,
                           registry: registry, services: makeServices())
            log.info("loaded script '\(parsed.name)' (\(parsed.actions.count) actions, loop=\(parsed.loop))")
        } catch {
            log.error("failed to load script \(url.lastPathComponent): \(error)")
        }
    }

    func togglePause() {
        clock.isPaused.toggle()
        log.info(clock.isPaused ? "paused" : "resumed")
    }
    func toggleSlowMo() {
        clock.timeScale = (clock.timeScale < 1.0) ? 1.0 : 0.25
        log.info("timeScale = \(clock.timeScale)")
    }
}
