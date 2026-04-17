import AppKit
import CoreGraphics
import Foundation

/// The dashboard popover contents. Its own view controller so `NSPopover` manages its
/// lifecycle and keyboard focus. Built programmatically (no nibs) so we have full control
/// over layout and theming.
///
/// Layout (top to bottom):
///   1. Header card — app name, version, live status dot
///   2. Telemetry row — position, velocity, FPS, behavior name
///   3. Behavior pills — mutually exclusive toggle group (idle/follow/wander/stop)
///   4. Action grid — one-shot tricks (hop, highlight, snapshot)
///   5. Engine row — pause, slow-mo
///   6. Scripts row — run demo, load script, quit
final class DashboardViewController: NSViewController {

    // MARK: - Callbacks

    var onOpenScript: (() -> Void)?
    var onRunDemo: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var onToggleSlowMo: (() -> Void)?
    var onQuit: (() -> Void)?

    // MARK: - Deps

    private let services: Services
    private let scheduler: CommandScheduler

    // MARK: - Views

    private let root = DashboardRootView()
    private let header = HeaderCardView()
    private let telemetry = TelemetryCardView()
    private let behaviorPills = PillGroupView(
        options: ["Idle", "Follow", "Wander", "Stop"]
    )
    private let actionGrid = ActionGridView()
    private let windowRow = WindowDiveRowView()
    private let engineRow = EngineRowView()
    private let logCard = LogCardView()
    private let scriptRow = ScriptRowView()

    private var ticker: Timer?
    private var currentBehaviorName: String = "idle"

    // MARK: - Init

    init(services: Services, scheduler: CommandScheduler) {
        self.services = services
        self.scheduler = scheduler
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = root
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 490)
        buildLayout()
        wireActions()
        refresh(animated: false)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        ticker?.invalidate()
        ticker = nil
    }

    /// Called by the controller after the popover shows — starts the live-stats ticker.
    func didAppear() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 1.0/15.0, repeats: true) { [weak self] _ in
            self?.refresh(animated: true)
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
        refresh(animated: false)
    }

    // MARK: - Layout

    private func buildLayout() {
        [header, telemetry, behaviorPills, actionGrid, windowRow, engineRow, logCard, scriptRow]
            .forEach { root.stack.addArrangedSubview($0) }
        // Make full-width children actually span the stack's width.
        for v in [telemetry, behaviorPills, actionGrid, windowRow, engineRow, logCard, scriptRow] {
            v.widthAnchor.constraint(equalTo: root.stack.widthAnchor,
                                     constant: -28).isActive = true
        }
        // Spacing varies per section for visual rhythm.
        root.stack.setCustomSpacing(12, after: header)
        root.stack.setCustomSpacing(16, after: telemetry)
        root.stack.setCustomSpacing(14, after: behaviorPills)
        root.stack.setCustomSpacing(12, after: actionGrid)
        root.stack.setCustomSpacing(14, after: windowRow)
        root.stack.setCustomSpacing(12, after: engineRow)
        root.stack.setCustomSpacing(14, after: logCard)
    }

    private func wireActions() {
        behaviorPills.selectedIndex = 0
        behaviorPills.onSelect = { [weak self] idx in
            guard let self = self else { return }
            let mode: SetBehaviorCommand.Mode = [.idle, .followCursor, .wander, .stop][idx]
            // "Stop" means stop everything — cancel any running script/commands too, not
            // just swap the primary behavior. Otherwise a running `flyTo` sequence would
            // reassert itself on the next tick.
            if mode == .stop {
                self.scheduler.cancelAll(services: self.services)
            }
            self.scheduler.runInBackground(SetBehaviorCommand(mode: mode), services: self.services)
            self.currentBehaviorName = mode.rawValue
        }

        actionGrid.onHop = { [weak self] in
            guard let self = self else { return }
            self.scheduler.runInBackground(HopCommand(), services: self.services)
        }
        actionGrid.onHighlight = { [weak self] in
            guard let self = self else { return }
            self.scheduler.runInBackground(HighlightFocusedWindowCommand(duration: 1.6),
                                           services: self.services)
        }
        actionGrid.onSnapshot = { [weak self] in
            guard let self = self else { return }
            self.scheduler.runInBackground(CaptureFocusedWindowCommand(), services: self.services)
        }

        windowRow.onDive = { [weak self] in
            guard let self = self else { return }
            self.scheduler.runInBackground(DiveIntoFocusedWindowCommand(),
                                           services: self.services)
        }
        windowRow.onEmerge = { [weak self] in
            guard let self = self else { return }
            self.scheduler.runInBackground(EmergeFromWindowCommand(),
                                           services: self.services)
        }

        engineRow.onPause = { [weak self] in
            self?.onTogglePause?()
        }
        engineRow.onSlowMo = { [weak self] in
            self?.onToggleSlowMo?()
        }

        scriptRow.onRunDemo = { [weak self] in self?.onRunDemo?() }
        scriptRow.onStopScript = { [weak self] in
            guard let self = self else { return }
            self.scheduler.cancelAll(services: self.services)
        }
        scriptRow.onLoadScript = { [weak self] in self?.onOpenScript?() }
        scriptRow.onQuit = { [weak self] in self?.onQuit?() }
    }

    // MARK: - Live refresh

    private func refresh(animated: Bool) {
        let pos = services.avatar.node.transform.position
        let v = services.avatar.physics.velocity
        header.setStatus(running: !scheduler.sequence.isEmpty,
                         paused: services.clock.isPaused,
                         slowMo: services.clock.timeScale < 1.0)
        telemetry.update(
            position: pos,
            speed: v.length,
            behavior: currentBehaviorName,
            pending: scheduler.sequence.count
        )
        engineRow.setState(paused: services.clock.isPaused,
                           slowMo: services.clock.timeScale < 1.0)
        windowRow.setAttachment(services.avatar.attachment.target)
        logCard.update(entries: services.log.tail(6))
    }
}

// MARK: - Root view
//
// NSStackView makes the layout declarative without pulling in AutoLayout constraints for
// every sub-view. Dark themed so it looks consistent across light/dark desktops.

private final class DashboardRootView: NSView {
    let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.11, alpha: 1).cgColor

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Header card

private final class HeaderCardView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Colay")
    private let subLabel = NSTextField(labelWithString: "Desktop agent · dev build")
    private let statusDot = StatusDotView()

    override init(frame frameRect: NSRect) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .heavy)
        titleLabel.textColor = NSColor.white
        subLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        subLabel.textColor = NSColor(white: 1, alpha: 0.5)
        subLabel.alphaValue = 0.85

        let text = NSStackView(views: [titleLabel, subLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        let logo = LogoView()
        logo.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 36),
            logo.heightAnchor.constraint(equalToConstant: 36)
        ])

        let row = NSStackView(views: [logo, text, NSView(), statusDot])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func setStatus(running: Bool, paused: Bool, slowMo: Bool) {
        if paused {
            statusDot.set(label: "PAUSED", color: .systemOrange)
        } else if slowMo {
            statusDot.set(label: "SLOW-MO", color: .systemPurple)
        } else if running {
            statusDot.set(label: "ACTIVE", color: .systemGreen)
        } else {
            statusDot.set(label: "IDLE", color: .systemTeal)
        }
    }
}

private final class StatusDotView: NSView {
    private let dot = NSView()
    private let label = NSTextField(labelWithString: "IDLE")

    override init(frame frameRect: NSRect) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false

        label.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        label.textColor = NSColor(white: 1, alpha: 0.75)

        addSubview(dot)
        addSubview(label)

        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(label text: String, color: NSColor) {
        label.stringValue = text
        dot.layer?.backgroundColor = color.cgColor
    }
}

// MARK: - Logo

private final class LogoView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds
        let cs = CGColorSpaceCreateDeviceRGB()
        let c1 = NSColor(calibratedRed: 0.42, green: 0.79, blue: 1.00, alpha: 1).cgColor
        let c2 = NSColor(calibratedRed: 0.20, green: 0.40, blue: 0.78, alpha: 1).cgColor
        let grad = CGGradient(colorsSpace: cs, colors: [c1, c2] as CFArray, locations: [0, 1])!
        let rect = b.insetBy(dx: 2, dy: 2)
        let path = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.32,
                          cornerHeight: rect.height * 0.32, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(grad,
                               start: CGPoint(x: rect.minX, y: rect.maxY),
                               end: CGPoint(x: rect.maxX, y: rect.minY),
                               options: [])
        ctx.restoreGState()
        // Eyes
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.85).cgColor)
        let eyeY = rect.midY + 1
        let dx: CGFloat = rect.width * 0.18
        let r: CGFloat = 2.2
        ctx.fillEllipse(in: CGRect(x: rect.midX - dx - r, y: eyeY - r, width: r*2, height: r*2))
        ctx.fillEllipse(in: CGRect(x: rect.midX + dx - r, y: eyeY - r, width: r*2, height: r*2))
    }
}

// MARK: - Telemetry card

private final class TelemetryCardView: NSView {
    private let pos = TelemetryCell(title: "POS")
    private let speed = TelemetryCell(title: "SPD")
    private let behavior = TelemetryCell(title: "MODE")
    private let pending = TelemetryCell(title: "QUEUE")

    override init(frame frameRect: NSRect) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.04).cgColor

        let row1 = NSStackView(views: [pos, speed])
        let row2 = NSStackView(views: [behavior, pending])
        [row1, row2].forEach {
            $0.orientation = .horizontal
            $0.distribution = .fillEqually
            $0.spacing = 8
        }
        let stack = NSStackView(views: [row1, row2])
        stack.orientation = .vertical
        stack.distribution = .fillEqually
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            heightAnchor.constraint(equalToConstant: 78)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(position: CGPoint, speed: CGFloat, behavior name: String, pending count: Int) {
        self.pos.setValue(String(format: "%.0f, %.0f", position.x, position.y))
        self.speed.setValue(String(format: "%.0f pt/s", speed))
        self.behavior.setValue(name)
        self.pending.setValue("\(count)")
    }
}

private final class TelemetryCell: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "—")

    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = title
        titleLabel.font = NSFont.monospacedSystemFont(ofSize: 8, weight: .bold)
        titleLabel.textColor = NSColor(white: 1, alpha: 0.4)
        valueLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        valueLabel.textColor = NSColor(white: 1, alpha: 0.9)

        let s = NSStackView(views: [titleLabel, valueLabel])
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 1
        s.translatesAutoresizingMaskIntoConstraints = false
        addSubview(s)
        NSLayoutConstraint.activate([
            s.leadingAnchor.constraint(equalTo: leadingAnchor),
            s.trailingAnchor.constraint(equalTo: trailingAnchor),
            s.topAnchor.constraint(equalTo: topAnchor),
            s.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func setValue(_ v: String) { valueLabel.stringValue = v }
}

// MARK: - Pill group

private final class PillGroupView: NSView {
    private let options: [String]
    private var pills: [PillButton] = []

    var selectedIndex: Int = 0 {
        didSet {
            for (i, p) in pills.enumerated() { p.isOn = i == selectedIndex }
        }
    }
    var onSelect: ((Int) -> Void)?

    init(options: [String]) {
        self.options = options
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 30)
        ])
        for (i, title) in options.enumerated() {
            let pill = PillButton(title: title)
            pill.onClick = { [weak self] in
                self?.selectedIndex = i
                self?.onSelect?(i)
            }
            if i == 0 { pill.isOn = true }
            pills.append(pill)
            stack.addArrangedSubview(pill)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class PillButton: NSView {
    private let label = NSTextField(labelWithString: "")
    var onClick: (() -> Void)?
    var isOn: Bool = false {
        didSet { apply() }
    }

    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7

        label.stringValue = title
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)
        ])
        apply()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                       owner: self, userInfo: nil))
    }

    private var hovered: Bool = false { didSet { apply() } }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    private func apply() {
        if isOn {
            layer?.backgroundColor = NSColor(calibratedRed: 0.32, green: 0.62, blue: 1.0, alpha: 1).cgColor
            label.textColor = NSColor.white
        } else if hovered {
            layer?.backgroundColor = NSColor(white: 1, alpha: 0.12).cgColor
            label.textColor = NSColor(white: 1, alpha: 0.95)
        } else {
            layer?.backgroundColor = NSColor(white: 1, alpha: 0.06).cgColor
            label.textColor = NSColor(white: 1, alpha: 0.75)
        }
    }
}

// MARK: - Action grid

private final class ActionGridView: NSView {
    var onHop: (() -> Void)?
    var onHighlight: (() -> Void)?
    var onSnapshot: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: "ACTIONS")
        header.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        header.textColor = NSColor(white: 1, alpha: 0.4)

        let hop = TileButton(title: "Hop", subtitle: "play a bounce",
                             icon: "arrow.up.circle.fill", accent: .systemPink)
        hop.onClick = { [weak self] in self?.onHop?() }
        let hi = TileButton(title: "Highlight", subtitle: "focused window",
                            icon: "rectangle.dashed", accent: .systemYellow)
        hi.onClick = { [weak self] in self?.onHighlight?() }
        let sn = TileButton(title: "Snapshot", subtitle: "capture AX info",
                            icon: "camera.viewfinder", accent: .systemTeal)
        sn.onClick = { [weak self] in self?.onSnapshot?() }

        let row = NSStackView(views: [hop, hi, sn])
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 8

        let stack = NSStackView(views: [header, row])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class TileButton: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let accent: NSColor
    private var enabled: Bool = true

    var onClick: (() -> Void)?

    func setEnabled(_ on: Bool) {
        enabled = on
        alphaValue = on ? 1.0 : 0.35
    }

    init(title: String, subtitle: String, icon: String, accent: NSColor) {
        self.accent = accent
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.05).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1, alpha: 0.05).cgColor

        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = NSColor.white
        subLabel.stringValue = subtitle
        subLabel.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        subLabel.textColor = NSColor(white: 1, alpha: 0.5)
        subLabel.lineBreakMode = .byTruncatingTail

        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: title) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .bold)
            iconView.image = img.withSymbolConfiguration(cfg)
        }
        iconView.contentTintColor = accent

        let text = NSStackView(views: [titleLabel, subLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 0

        let stack = NSStackView(views: [iconView, text])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            heightAnchor.constraint(equalToConstant: 70)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        guard enabled else { return }
        flash()
        onClick?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.1).cgColor
        layer?.borderColor = accent.withAlphaComponent(0.6).cgColor
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.05).cgColor
        layer?.borderColor = NSColor(white: 1, alpha: 0.05).cgColor
    }

    private func flash() {
        layer?.backgroundColor = accent.withAlphaComponent(0.25).cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.layer?.backgroundColor = NSColor(white: 1, alpha: 0.05).cgColor
        }
    }
}

// MARK: - Window dive row
//
// Split visually from the plain ACTIONS grid because "dive" changes the avatar's state
// (attached vs free-roaming), not just fires a one-shot effect. The status line makes
// that state visible: "free-roaming" vs "attached · <app>".

private final class WindowDiveRowView: NSView {
    var onDive: (() -> Void)?
    var onEmerge: (() -> Void)?

    private let headerLabel = NSTextField(labelWithString: "WINDOW")
    private let statusLabel = NSTextField(labelWithString: "free-roaming")
    private let diveBtn = TileButton(title: "Dive In", subtitle: "enter focused window",
                                     icon: "arrow.down.circle.fill",
                                     accent: NSColor(calibratedRed: 0.38, green: 0.86, blue: 1.0, alpha: 1))
    private let emergeBtn = TileButton(title: "Emerge", subtitle: "leave window",
                                       icon: "arrow.up.forward.circle.fill",
                                       accent: NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.45, alpha: 1))

    override init(frame frameRect: NSRect) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        headerLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        headerLabel.textColor = NSColor(white: 1, alpha: 0.4)
        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        statusLabel.textColor = NSColor(white: 1, alpha: 0.6)
        statusLabel.lineBreakMode = .byTruncatingMiddle

        let headerRow = NSStackView(views: [headerLabel, statusLabel])
        headerRow.orientation = .horizontal
        headerRow.spacing = 8
        headerRow.distribution = .fill

        diveBtn.onClick = { [weak self] in self?.onDive?() }
        emergeBtn.onClick = { [weak self] in self?.onEmerge?() }

        let buttons = NSStackView(views: [diveBtn, emergeBtn])
        buttons.orientation = .horizontal
        buttons.distribution = .fillEqually
        buttons.spacing = 8

        let stack = NSStackView(views: [headerRow, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            buttons.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            headerRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])
        setAttachment(nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setAttachment(_ t: WindowTarget?) {
        if let t = t {
            let label = t.appName ?? "window"
            statusLabel.stringValue = "● attached · \(label)"
            statusLabel.textColor = NSColor(calibratedRed: 0.38, green: 0.86, blue: 1.0, alpha: 1)
            diveBtn.setEnabled(false)
            emergeBtn.setEnabled(true)
        } else {
            statusLabel.stringValue = "○ free-roaming"
            statusLabel.textColor = NSColor(white: 1, alpha: 0.5)
            diveBtn.setEnabled(true)
            emergeBtn.setEnabled(false)
        }
    }
}

// MARK: - Engine row

private final class EngineRowView: NSView {
    var onPause: (() -> Void)?
    var onSlowMo: (() -> Void)?
    private let pauseBtn = ToggleChip(title: "Pause")
    private let slowMoBtn = ToggleChip(title: "Slow-Mo")

    override init(frame frameRect: NSRect) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView(views: [pauseBtn, slowMoBtn])
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 28)
        ])
        pauseBtn.onClick = { [weak self] in self?.onPause?() }
        slowMoBtn.onClick = { [weak self] in self?.onSlowMo?() }
    }
    required init?(coder: NSCoder) { fatalError() }

    func setState(paused: Bool, slowMo: Bool) {
        pauseBtn.isOn = paused
        slowMoBtn.isOn = slowMo
    }
}

private final class ToggleChip: NSView {
    private let label: NSTextField
    var onClick: (() -> Void)?
    var isOn: Bool = false { didSet { apply() } }

    init(title: String) {
        self.label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7

        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        apply()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onClick?() }

    private func apply() {
        if isOn {
            layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.85).cgColor
            label.textColor = NSColor.white
        } else {
            layer?.backgroundColor = NSColor(white: 1, alpha: 0.06).cgColor
            label.textColor = NSColor(white: 1, alpha: 0.75)
        }
    }
}

// MARK: - Script row

private final class ScriptRowView: NSView {
    var onRunDemo: (() -> Void)?
    var onStopScript: (() -> Void)?
    var onLoadScript: (() -> Void)?
    var onQuit: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: "SCRIPTS")
        header.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        header.textColor = NSColor(white: 1, alpha: 0.4)

        let run = LinkButton(title: "Run demo.json", icon: "play.fill")
        run.onClick = { [weak self] in self?.onRunDemo?() }
        let stop = LinkButton(title: "Stop current script", icon: "stop.fill")
        stop.onClick = { [weak self] in self?.onStopScript?() }
        let load = LinkButton(title: "Load script…", icon: "doc.badge.plus")
        load.onClick = { [weak self] in self?.onLoadScript?() }
        let quit = LinkButton(title: "Quit", icon: "power", destructive: true)
        quit.onClick = { [weak self] in self?.onQuit?() }

        let list = NSStackView(views: [run, stop, load, quit])
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 2

        let stack = NSStackView(views: [header, list])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class LinkButton: NSView {
    private let label = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let destructive: Bool
    var onClick: (() -> Void)?

    init(title: String, icon: String, destructive: Bool = false) {
        self.destructive = destructive
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6

        label.stringValue = title
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = destructive ? NSColor.systemRed : NSColor(white: 1, alpha: 0.85)

        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: title) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            iconView.image = img.withSymbolConfiguration(cfg)
        }
        iconView.contentTintColor = destructive ? NSColor.systemRed : NSColor(white: 1, alpha: 0.55)

        let row = NSStackView(views: [iconView, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

// MARK: - Log card
//
// Compact live log. The dashboard polls `services.log.tail(N)` on its refresh ticker
// (15Hz) and hands the entries here. We only repaint when the text actually changes to
// keep the popover cheap while it's open.

private final class LogCardView: NSView {
    private let titleLabel = NSTextField(labelWithString: "LIVE LOG")
    private let textView = NSTextView()
    private let scroll = NSScrollView()
    private var lastSignature: String = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.35).cgColor
        layer?.borderColor = NSColor(white: 1, alpha: 0.05).cgColor
        layer?.borderWidth = 1

        titleLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        titleLabel.textColor = NSColor(white: 1, alpha: 0.4)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 2, height: 2)
        textView.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        textView.textColor = NSColor(white: 1, alpha: 0.9)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.documentView = textView
        scroll.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(scroll)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),

            scroll.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            heightAnchor.constraint(equalToConstant: 108)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Signature-checked update. Rebuilds the attributed string only when the log
    /// content has changed since the last refresh.
    func update(entries: [EngineLog.Entry]) {
        let sig = entries.map { "\(Int($0.time.timeIntervalSince1970))|\($0.message)" }
            .joined(separator: ";")
        guard sig != lastSignature else { return }
        lastSignature = sig

        let result = NSMutableAttributedString()
        let df = LogCardView.timeFormatter
        for e in entries {
            let ts = df.string(from: e.time)
            let color: NSColor = {
                switch e.kind {
                case .info:   return NSColor(white: 1, alpha: 0.75)
                case .action: return NSColor.systemCyan
                case .warn:   return NSColor.systemYellow
                case .error:  return NSColor.systemRed
                }
            }()
            result.append(NSAttributedString(
                string: "\(ts)  ",
                attributes: [
                    .foregroundColor: NSColor(white: 1, alpha: 0.35),
                    .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
                ]
            ))
            result.append(NSAttributedString(
                string: "\(e.message)\n",
                attributes: [
                    .foregroundColor: color,
                    .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
                ]
            ))
        }
        if entries.isEmpty {
            result.append(NSAttributedString(
                string: "—\n",
                attributes: [.foregroundColor: NSColor(white: 1, alpha: 0.3)]
            ))
        }
        textView.textStorage?.setAttributedString(result)
        textView.scrollToEndOfDocument(nil)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
