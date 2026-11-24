import SceneKit
import UIKit
import simd

enum Palette {
    static let ink = UIColor(red: 0.065, green: 0.071, blue: 0.075, alpha: 1)
    static let paper = UIColor(red: 0.955, green: 0.918, blue: 0.845, alpha: 1)
    static let muted = UIColor(red: 0.74, green: 0.72, blue: 0.67, alpha: 1)
    static let gold = UIColor(red: 1.00, green: 0.80, blue: 0.43, alpha: 1)
}

final class GameStage: UIView {
    let room: GameWorld
    private let renderView = SCNView()
    private let timing = RenderTiming()
    var frameTiming: (fps: Double, p95: Double) { timing.snapshot() }
    private let caption = UILabel()
    private let captionPlate = UIView()
    private let runeTrail = RuneTrail()
    private let runHUD = RunHUD()
    private let spellGuide = RunSpellGuide()
    private var wandMode = true
    private var guideRunVisible = false
    private let runOver = RunOverView()
    private let runStart = RunStartView()
    private let announcement = RunAnnouncementView()
    private let castPreview = UILabel()
    private let setupPointer = UIView()
    private var setupVisible = false
    private(set) var hasSetupPointer = false
    var hoveredSetupChoice: Int? { runStart.hoveredChoice }
    var setupChoiceFrames: [CGRect] { runStart.choiceFrames.map { runStart.convert($0, to: self) } }
    var onRestart: (() -> Void)? {
        didSet { runOver.onRestart = onRestart }
    }
    var onSetupChoice: ((Int, Bool) -> Void)? {
        didSet { runStart.onChoice = onSetupChoice }
    }
    private lazy var wand = WandPresentation(camera: room.camera)
    private(set) var aim = CGPoint(x: 0.5, y: 0.5)
    var external = false {
        didSet {
            captionPlate.isHidden = !external
        }
    }

    init(room: GameWorld) {
        self.room = room
        super.init(frame: .zero)
        accessibilityIdentifier = "roomPreview"
        isAccessibilityElement = false
        // Transparent SceneKit pixels reveal the host's black optical-AR canvas.
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true
        renderView.delegate = timing
        renderView.scene = room.scene
        renderView.backgroundColor = .clear
        renderView.isOpaque = false
        renderView.pointOfView = room.camera
        renderView.antialiasingMode = .multisampling2X
        renderView.preferredFramesPerSecond = 60
        renderView.rendersContinuously = true
        renderView.isPlaying = true
        renderView.isUserInteractionEnabled = false
        renderView.isAccessibilityElement = true
        renderView.accessibilityLabel = "Fantasy room"
        renderView.accessibilityTraits = .image
        addSubview(renderView)
        runeTrail.isUserInteractionEnabled = false
        addSubview(runeTrail)
        captionPlate.backgroundColor = Palette.ink.withAlphaComponent(0.88)
        addSubview(captionPlate)
        captionPlate.addSubview(caption)
        caption.textColor = Palette.paper
        caption.textAlignment = .center
        caption.numberOfLines = 3
        captionPlate.isHidden = true
        addSubview(runHUD)
        spellGuide.isHidden = true
        addSubview(spellGuide)
        addSubview(runOver)
        addSubview(runStart)
        addSubview(announcement)
        castPreview.font = .systemFont(ofSize: 16, weight: .semibold)
        castPreview.textColor = Palette.paper
        castPreview.backgroundColor = Palette.ink.withAlphaComponent(0.9)
        castPreview.textAlignment = .center
        castPreview.layer.cornerRadius = 6
        castPreview.clipsToBounds = true
        castPreview.isUserInteractionEnabled = false
        castPreview.isHidden = true
        castPreview.accessibilityIdentifier = "wandSpellPreview"
        addSubview(castPreview)
        setupPointer.isUserInteractionEnabled = false
        setupPointer.isAccessibilityElement = false
        setupPointer.accessibilityIdentifier = "setupPointer"
        setupPointer.backgroundColor = Palette.ink
        setupPointer.layer.borderColor = UIColor.white.cgColor
        setupPointer.layer.borderWidth = 3
        setupPointer.layer.cornerRadius = 9
        setupPointer.bounds.size = CGSize(width: 18, height: 18)
        setupPointer.isHidden = true
        addSubview(setupPointer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        renderView.frame = bounds
        // Bound the drawable to 1080p, including Retina Mac windows.
        let scale = min(window?.screen.scale ?? 1, 1920 / max(1, bounds.width), 1080 / max(1, bounds.height))
        renderView.contentScaleFactor = max(0.5, scale)
        wand.updateViewport(size: bounds.size)
        let side = min(bounds.width, bounds.height) * 0.82
        runeTrail.bounds.size = CGSize(width: side, height: side)
        guard external else { return }
        let margin = max(12, bounds.width * 0.03)
        let noticeWidth = min(560, bounds.width - 48)
        announcement.frame = CGRect(
            x: (bounds.width - noticeWidth) / 2, y: 80,
            width: noticeWidth, height: 98)
        let hudWidth = min(800, bounds.width - margin * 2)
        let guideHeight: CGFloat = spellGuide.isHidden ? 0 : 66
        let guideGap: CGFloat = spellGuide.isHidden ? 0 : 10
        spellGuide.frame = CGRect(
            x: margin, y: bounds.height - margin - guideHeight,
            width: bounds.width - margin * 2, height: guideHeight)
        runHUD.frame = CGRect(
            x: (bounds.width - hudWidth) / 2,
            y: spellGuide.frame.minY - guideGap - 78, width: hudWidth, height: 78)
        let panelWidth = min(440, bounds.width - 32)
        let panelHeight = min(380, bounds.height - 32)
        runOver.frame = CGRect(
            x: (bounds.width - panelWidth) / 2, y: (bounds.height - panelHeight) / 2,
            width: panelWidth, height: panelHeight)
        let startWidth = min(460, bounds.width - 32)
        let startHeight: CGFloat = runStart.isCountingDown ? min(270, bounds.height - 32) : min(560, bounds.height - 32)
        runStart.frame = CGRect(
            x: runStart.isCountingDown ? (bounds.width - startWidth) / 2 : 24,
            y: (bounds.height - startHeight) / 2, width: startWidth, height: startHeight)
        let width = bounds.width * 0.83
        caption.font = .systemFont(ofSize: max(16, bounds.height * 0.033), weight: .medium)
        let content = caption.sizeThatFits(CGSize(width: width - 28, height: .greatestFiniteMagnitude))
        let plate = CGSize(width: min(width, content.width + 28), height: content.height + 14)
        captionPlate.frame = CGRect(
            x: (bounds.width - plate.width) / 2,
            y: runHUD.frame.minY - 10 - plate.height, width: plate.width, height: plate.height)
        captionPlate.layer.cornerRadius = 8
        caption.frame = captionPlate.bounds.insetBy(dx: 14, dy: 7)
    }

    func prepare(nodes: [SCNNode], completion: @escaping () -> Void) {
        renderView.prepare([room.scene] + nodes) { _ in
            DispatchQueue.main.async { completion() }
        }
    }

    func setFrameRate(_ rate: Int) {
        renderView.preferredFramesPerSecond = rate == 120 ? 120 : 60
    }

    func showRun(_ run: RunSnapshot) {
        setupVisible = !run.hasStarted && !run.isGameOver
        guideRunVisible = run.hasStarted && !run.isGameOver && run.countdownRemaining <= 0
        spellGuide.isHidden = !wandMode || !guideRunVisible
        runStart.show(run)
        if !setupVisible { clearSetupPointer() }
        runHUD.show(run)
        runOver.show(run)
        setNeedsLayout()
    }

    func showSetup(step: String, seeThrough: Bool, bow: Bool) {
        runStart.showChoices(step: step, seeThrough: seeThrough, bow: bow)
    }

    func announce(title: String, detail: String) { announcement.announce(title: title, detail: detail) }
    func advanceAnnouncements(deltaTime: Double) { announcement.advance(deltaTime: deltaTime) }
    func clearAnnouncements() { announcement.clear() }

    func showCastPreview(_ text: String?) {
        castPreview.isHidden = text == nil || text?.isEmpty == true
        guard let text, !text.isEmpty else { return }
        castPreview.text = text
        let size = castPreview.sizeThatFits(CGSize(width: 300, height: 36))
        let width = min(bounds.width - 24, size.width + 20)
        castPreview.frame = CGRect(
            x: min(bounds.width - width - 12, max(12, aim.x * bounds.width - width / 2)),
            y: max(12, min(bounds.height - 120, aim.y * bounds.height - 48)), width: width, height: 32)
    }

    func setCaption(_ text: String) {
        guard caption.text != text else { return }
        caption.text = text
        if external { setNeedsLayout() }
    }

    func clearSetupPointer() {
        hasSetupPointer = false
        setupPointer.isHidden = true
        runStart.hover(nil)
    }

    func aimWand(angles: SIMD2<Float>?) {
        if setupVisible {
            guard let angles, angles.x.isFinite, angles.y.isFinite else {
                clearSetupPointer()
                return
            }
            layoutIfNeeded()
            runStart.layoutIfNeeded()
            let targets = setupChoiceFrames
            guard targets.count == 2, targets.allSatisfy({ $0.width > 0 && $0.height > 0 }) else { return }
            let area = targets[0].union(targets[1])
            let gain = max(400, area.width * 1.4)
            let point = CGPoint(
                x: min(bounds.width - 12, max(12, area.midX + CGFloat(angles.x) * gain)),
                y: min(bounds.height - 12, max(12, area.midY - CGFloat(angles.y) * gain)))
            aim = CGPoint(x: point.x / max(1, bounds.width), y: point.y / max(1, bounds.height))
            hasSetupPointer = true
            setupPointer.center = point
            setupPointer.isHidden = false
            runStart.hover(runStart.choice(at: convert(point, to: runStart)))
        } else if let angles {
            aim = CGPoint(
                x: min(0.90, max(0.1, 0.5 + CGFloat(angles.x) / 1.1)),
                y: min(0.85, max(0.15, 0.5 - CGFloat(angles.y) / 1.1)))
        }
        wand.update(aim: aim, isDrawing: false)
    }

    func aimedWorldPoint() -> SIMD3<Float> {
        let far = renderView.unprojectPoint(
            SCNVector3(
                Float(aim.x * bounds.width),
                Float(aim.y * bounds.height), 0.99))
        let direction = SIMD3<Float>(far) - room.camera.simdWorldPosition
        guard simd_length(direction) > 0.001 else { return room.castingPoint() }
        return room.camera.simdWorldPosition + simd_normalize(direction) * 14
    }

    func animateCast() { wand.cast() }
    func animateShot() { wand.shoot() }
    func setMode(_ mode: WandPresentation.Mode) {
        wand.setMode(mode)
        wandMode = mode == .wand
        spellGuide.isHidden = !wandMode || !guideRunVisible
        setNeedsLayout()
    }

    func showRune(points: [CGPoint], at anchor: SIMD3<Float>?) {
        guard let anchor, !points.isEmpty else {
            if !runeTrail.isHidden { runeTrail.show(points: [], active: false) }
            return
        }
        let projected = renderView.projectPoint(SCNVector3(anchor))
        guard projected.z > 0, projected.z < 1 else {
            runeTrail.show(points: [], active: false)
            return
        }
        runeTrail.center = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
        runeTrail.show(points: points, active: true)
        if let last = points.last {
            let side = runeTrail.bounds.width
            aim = CGPoint(
                x: (runeTrail.center.x + (last.x - 0.5) * side) / max(1, bounds.width),
                y: (runeTrail.center.y + (last.y - 0.5) * side) / max(1, bounds.height))
            wand.update(aim: aim, isDrawing: true)
        }
    }
}

/// Render callbacks run off the main thread. Keep their work bounded and avoid UI access.
private final class RenderTiming: NSObject, SCNSceneRendererDelegate {
    private let lock = NSLock()
    private var previous: TimeInterval?
    private var intervals: [TimeInterval] = []

    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        if let previous, time > previous {
            intervals.append(time - previous)
            if intervals.count > 120 { intervals.removeFirst(intervals.count - 120) }
        }
        previous = time
    }

    func snapshot() -> (fps: Double, p95: Double) {
        lock.lock()
        let values = intervals
        lock.unlock()
        guard !values.isEmpty else { return (0, 0) }
        let sorted = values.sorted()
        return (
            Double(values.count) / max(0.0001, values.reduce(0, +)),
            sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        )
    }
}
