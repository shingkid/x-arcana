import Darwin
import QuartzCore
import SceneKit
import UIKit
import XCTest

@testable import XArcana

/// Opt-in, visible-window rendering benchmark. This does not measure snapshot throughput.
/// Run alone with XARCANA_RENDER_BENCHMARK=1 and keep its window visible.
final class RenderPerformanceTests: XCTestCase {
    private var baselineAssets: [String: SCNNode] = [:]
    @MainActor
    func testVisibleCrowdAndDemonBreathFrameTimes() async throws {
        guard ProcessInfo.processInfo.environment["XARCANA_RENDER_BENCHMARK"] == "1" else {
            throw XCTSkip("Set XARCANA_RENDER_BENCHMARK=1 to run the visible-window render benchmark")
        }
        #if !targetEnvironment(macCatalyst)
            throw XCTSkip("This comparison requires a foreground Mac Catalyst test host")
        #else
            let windowScene = try XCTUnwrap(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                    .first { $0.activationState == .foregroundActive })
            let priorWindow = windowScene.windows.first { $0.isKeyWindow }
            let window = UIWindow(windowScene: windowScene)
            window.frame = CGRect(x: 0, y: 0, width: 1280, height: 720)
            let controller = UIViewController()
            controller.view.backgroundColor = .black
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                priorWindow?.makeKey()
            }

            // Compare only known prior static-zombie assets, without changing the installed app.
            let baselinePath =
                ProcessInfo.processInfo.environment["XARCANA_BASELINE_BUNDLE"] ?? "/Applications/X Arcana.app"
            let baselineBundle = Bundle(path: baselinePath)
            let baselineVersion = baselineBundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            let baseline = ["2.0", "2.1"].contains(baselineVersion ?? "") ? baselineBundle : nil
            var reports: [[String: Any]] = []
            for useBaseline in baseline == nil ? [false] : [false, true] {
                let scenarios =
                    useBaseline
                    ? ["alan-albert", "demon-breath"]
                    : ["alan-albert", "demon-breath", "transfiguration"]
                let requestedScenario = ProcessInfo.processInfo.environment["XARCANA_BENCHMARK_SCENARIO"] ?? ""
                for scenario in scenarios where requestedScenario.isEmpty || requestedScenario == scenario {
                    let demon = scenario == "demon-breath"
                    let transfigured = scenario == "transfiguration"
                    let room = GameWorld()
                    XCTAssertNil(room.errorMessage)
                    let stage = GameStage(room: room)
                    stage.external = true
                    stage.setFrameRate(60)
                    stage.frame = controller.view.bounds
                    stage.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    controller.view.addSubview(stage)
                    controller.view.layoutIfNeeded()
                    let view = try XCTUnwrap(stage.subviews.compactMap { $0 as? SCNView }.first)
                    let registry = SummonCombat(scene: room.scene)
                    let performance = ScenePerformance(scene: room.scene, camera: room.camera)
                    let templates =
                        ZombieAppearance.prewarm(identities: Combat.identities)
                        + PortraitSummons.prewarm() + RuneEffects.prewarm() + SpellVFX.prewarm()
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        stage.prepare(nodes: templates) { continuation.resume() }
                    }
                    var zombies: [SCNNode] = []
                    var cats: [RainbowCat] = []
                    for index in 0..<8 {
                        let identity = Combat.identities[index]
                        let node = ZombieAppearance.make(identity: identity, index: index)
                        node.simdPosition = SIMD3(Float(index % 4) * 0.8 - 1.2, 0, Float(index / 4) * 1.1 - 0.1)
                        if useBaseline, let baseline {
                            try substituteZombie(node, identity: identity, bundle: baseline)
                        }
                        room.scene.rootNode.addChildNode(node)
                        if transfigured {
                            // Match production: retain cached enemy wrappers, hide their bodies and names,
                            // and attach one anchored cat per former enemy. These are not attack targets.
                            for child in node.childNodes { child.isHidden = true }
                            cats.append(
                                RainbowCat(
                                    parent: node, floorY: 0, anchored: true, phaseOffset: Float(index),
                                    camera: room.camera))
                        }
                        zombies.append(node)
                    }
                    if demon {
                        let node = try XCTUnwrap(
                            RuneEffects.summon(
                                in: room.scene, at: SIMD3(0, 0, -1.4),
                                facing: room.camera.simdWorldPosition))
                        if useBaseline, let baseline {
                            try substituteCharacter(
                                node, container: "DemonSculpture", asset: "Demon", directory: "Creatures",
                                height: nil, bundle: baseline)
                        }
                        registry.register(kind: .demon, node: node)
                    } else {
                        for (index, name) in ["alan", "albert"].enumerated() {
                            let node = try XCTUnwrap(
                                PortraitSummons.summon(
                                    name: name, in: room.scene,
                                    at: SIMD3(index == 0 ? -1.4 : 1.4, 0, -1.1), facing: room.camera))
                            if useBaseline, let baseline {
                                try substituteCharacter(
                                    node, container: "PortraitBody", asset: "PortraitCharacter",
                                    directory: "Fantasy", height: 1.72, bundle: baseline)
                            }
                            registry.register(kind: index == 0 ? .alan : .albert, node: node)
                        }
                    }
                    if transfigured {
                        XCTAssertEqual(cats.count, 8)
                        room.setTransfigurationPhase(0)
                    }
                    performance.prepare()
                    let originalDelegate = view.delegate
                    let samples = RenderSamples(previous: originalDelegate)
                    view.delegate = samples
                    let driver = BenchmarkDriver(
                        registry: registry, zombies: zombies, cats: cats, room: room,
                        performance: performance, demon: demon, animateZombies: !useBaseline)
                    driver.start()
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    samples.begin()
                    var peakMemory = footprint()
                    for _ in 0..<15 {
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                        peakMemory = max(peakMemory, footprint())
                    }
                    let result = samples.finish()
                    driver.stop()
                    view.delegate = originalDelegate
                    XCTAssertGreaterThan(result.frames, 30, "The visible SCNView must complete actual renders")
                    if demon {
                        XCTAssertGreaterThan(driver.breathStarts, 0, "The workload must include actual breath effects")
                    }
                    let label =
                        "\(useBaseline ? "installed-v\(baselineVersion ?? "unknown")-static-assets" : "current-assets")-\(scenario)"
                    let row: [String: Any] = [
                        "scenario": label, "frames": result.frames, "seconds": result.seconds,
                        "fps": result.fps, "p95FrameMilliseconds": result.p95 * 1000,
                        "peakProcessFootprintMiB": Double(peakMemory) / 1_048_576,
                        "stageRollingFPS": stage.frameTiming.fps,
                        "stageRollingP95Milliseconds": stage.frameTiming.p95 * 1000,
                        "requestedFPS": 60, "displayMaximumFPS": window.screen.maximumFramesPerSecond,
                        "drawableWidth": Double(view.bounds.width * view.contentScaleFactor),
                        "drawableHeight": Double(view.bounds.height * view.contentScaleFactor),
                        "gpu": view.device?.name ?? "unknown", "breathStarts": driver.breathStarts,
                        "playerImpactBursts": driver.impactBursts,
                        "activeZombies": transfigured ? 0 : zombies.count, "transfiguredCats": cats.count,
                        "rainbowHall": transfigured, "activeCompanions": registry.companions.count,
                        "sustainedBelow55FPS": result.fps < 55,
                        "performanceStatus": result.fps < 55 ? "below-target" : "pass",
                    ]
                    reports.append(row)
                    print("XARCANA_RENDER_BENCHMARK", row)
                    let capture = XCTAttachment(image: view.snapshot())
                    capture.name = label
                    capture.lifetime = .keepAlways
                    add(capture)
                    registry.reset()
                    for cat in cats { cat.remove() }
                    room.setTransfigurationPhase(nil)
                    stage.removeFromSuperview()
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            #if DEBUG
                let configuration = "debug"
            #else
                let configuration = "release"
            #endif
            XCTAssertFalse(reports.isEmpty, "The selected benchmark scenario must exist")
            let report: [String: Any] = [
                "configuration": configuration,
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "measurement":
                    "Visible SCNView didRender callback wall-clock intervals; 5-second warmup then 15-second sample. No snapshot loop.",
                "baseline": baseline == nil
                    ? "unavailable: installed bundle is missing or not a supported prior version" : baselinePath,
                "comparisonLimits":
                    "Prior-version mesh/texture substitution uses the current runtime, hall, camera, wrappers, accessories, animation controller and effects. Old bodies remain static. This is not the old app's end-to-end performance. The transfiguration scenario is current-only to keep comparison focused on the changed zombie rigs. Memory is process footprint and includes shared cached assets from earlier scenarios. Display refresh and the requested frame cap can limit FPS.",
                "workload":
                    "Two zombie scenarios retain eight fixed-health zombies with either the allowed Alan/Albert duo or the demon alone. No cats appear in these scenarios. The current-only transfiguration scenario replaces all eight visible zombies with cached roaming cats and the animated rainbow hall; the allowed duo remains present but cannot attack transformed enemies. Player fireball, lightning, and ice impacts overlap once per second in every scenario. Current zombies use simulation-sampled walk clips and the companion duo uses actual attack clips; demon breath occurs every two seconds. This stress workload exceeds sustained gameplay mana and breath frequency. Damage is ignored to retain comparable populations. Each scenario has five seconds of warmup and fifteen seconds of measurement at a requested 60 FPS; sustained measured FPS below 55 is flagged.",
                "results": reports,
            ]
            let attachment = XCTAttachment(
                data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
                uniformTypeIdentifier: "public.json")
            attachment.name = "X Arcana render benchmark"
            attachment.lifetime = .keepAlways
            add(attachment)
            // Write all diagnostics before flagging a sustained frame-rate failure.
            for row in reports where (row["sustainedBelow55FPS"] as? Bool) == true {
                XCTFail("Sustained render rate below 55 FPS: \(row["scenario"] ?? "unknown"), \(row["fps"] ?? 0) FPS")
            }
        #endif
    }

    private func asset(_ name: String, directory: String, bundle: Bundle) throws -> SCNNode {
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "usdz", subdirectory: directory))
        if let cached = baselineAssets[url.path] { return cached.clone() }
        let node = try SCNScene(url: url, options: [.convertToYUp: true]).rootNode
        baselineAssets[url.path] = node
        return node.clone()
    }

    private func substituteZombie(_ actor: SCNNode, identity: Combat.Identity, bundle: Bundle) throws {
        let body = try XCTUnwrap(actor.childNode(withName: "Office zombie", recursively: true))
        let portrait = try XCTUnwrap(actor.childNode(withName: "Face.\(identity.id)", recursively: true))
        portrait.removeFromParentNode()
        for child in body.childNodes { child.removeFromParentNode() }
        let old = try asset("Zombie", directory: "Creatures", bundle: bundle)
        old.childNode(withName: "Portrait_face_surface", recursively: true)?.removeFromParentNode()
        old.childNode(withName: "Eyes", recursively: true)?.isHidden = true
        old.addChildNode(portrait)
        body.addChildNode(old)
    }

    private func substituteCharacter(
        _ actor: SCNNode, container: String, asset name: String,
        directory: String, height: Float?, bundle: Bundle
    ) throws {
        let model = try XCTUnwrap(actor.childNode(withName: container, recursively: true))
        // Retain current accessory bones and effects for the same surrounding workload.
        model.enumerateChildNodes { node, _ in
            if node.skinner != nil {
                node.skinner = nil
                node.geometry = nil
            }
        }
        let old = try asset(name, directory: directory, bundle: bundle)
        if let height {
            let bounds = old.boundingBox
            let originalHeight = Float(bounds.max.y - bounds.min.y)
            let scale = height / max(0.001, originalHeight)
            old.simdScale = SIMD3(repeating: scale)
            old.simdPosition = SIMD3(
                -Float(bounds.min.x + bounds.max.x) * scale / 2,
                -Float(bounds.min.y) * scale, -Float(bounds.min.z + bounds.max.z) * scale / 2)
        }
        model.addChildNode(old)
    }

    private func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}

private final class RenderSamples: NSObject, SCNSceneRendererDelegate {
    struct Result {
        let frames: Int
        let seconds: Double
        let fps: Double
        let p95: Double
    }
    private let previousDelegate: SCNSceneRendererDelegate?
    private let lock = NSLock()
    private var started: Double?
    private var previous: Double?
    private var intervals: [Double] = []
    private var frames = 0
    init(previous: SCNSceneRendererDelegate?) { previousDelegate = previous }
    func begin() {
        lock.lock()
        defer { lock.unlock() }
        started = CACurrentMediaTime()
        previous = nil
        intervals.removeAll()
        frames = 0
    }
    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        previousDelegate?.renderer?(renderer, didRenderScene: scene, atTime: time)
        let now = CACurrentMediaTime()
        lock.lock()
        defer { lock.unlock() }
        guard started != nil else { return }
        if let previous, now > previous { intervals.append(now - previous) }
        previous = now
        frames += 1
    }
    func finish() -> Result {
        lock.lock()
        defer { lock.unlock() }
        let elapsed = CACurrentMediaTime() - (started ?? CACurrentMediaTime())
        started = nil
        let sorted = intervals.sorted()
        let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        return Result(frames: frames, seconds: elapsed, fps: Double(frames) / max(0.001, elapsed), p95: p95)
    }
}

@MainActor private final class BenchmarkDriver: NSObject {
    private let registry: SummonCombat
    private let zombies: [SCNNode]
    private let performance: ScenePerformance
    private let demon: Bool
    private let animateZombies: Bool
    private var displayLink: CADisplayLink?
    private var previous: Double?
    private var nextBreath: Double = 0
    private var nextImpact: Double = 0
    private let cats: [RainbowCat]
    private let room: GameWorld
    private var simulationTime: TimeInterval = 0
    private(set) var breathStarts = 0
    private(set) var impactBursts = 0
    init(
        registry: SummonCombat, zombies: [SCNNode], cats: [RainbowCat], room: GameWorld,
        performance: ScenePerformance, demon: Bool, animateZombies: Bool
    ) {
        self.registry = registry
        self.zombies = zombies
        self.cats = cats
        self.room = room
        self.performance = performance
        self.demon = demon
        self.animateZombies = animateZombies
    }
    func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }
    @objc private func tick(_ link: CADisplayLink) {
        let dt = previous.map { max(0, min(0.05, link.timestamp - $0)) } ?? 1 / 60
        previous = link.timestamp
        simulationTime += dt
        if animateZombies && cats.isEmpty {
            for (index, zombie) in zombies.enumerated() {
                ZombieAppearance.sampleMotion("walk", at: simulationTime + Double(index) * 0.19, on: zombie)
            }
        }
        for cat in cats { cat.update(deltaTime: dt) }
        if !cats.isEmpty {
            // Keep the last active phase for the final screenshot if scheduling adds a few milliseconds.
            room.setTransfigurationPhase(min(SurvivalState.nyanDuration - 0.001, simulationTime))
        }
        if link.timestamp >= nextImpact, let root = zombies.first?.parent {
            nextImpact = link.timestamp + 1
            SpellVisuals.fireball(at: SIMD3(0, 1.1, -0.3), radius: 3, floorY: 0, on: root)
            SpellVisuals.lightning(at: SIMD3(-1.2, 1.1, 0), on: root)
            SpellVisuals.ice(from: SIMD3(0.1, 1.4, 3), direction: SIMD3(0, 0, -1), on: root)
            impactBursts += 1
        }
        if demon, link.timestamp >= nextBreath, let ally = registry.companions.first, ally.attack == nil {
            ally.breathCooldown = 0
            ally.slamCooldown = 100
            nextBreath = link.timestamp + 2
        }
        let wasBreathing = registry.companions.first?.attack?.style == .breath
        let targets: [SummonCombat.Target] =
            cats.isEmpty
            ? zombies.map {
                SummonCombat.Target(node: $0, center: $0.simdWorldPosition + SIMD3(0, 1.05, 0))
            } : []
        _ = registry.update(deltaTime: dt, targets: targets)
        if !wasBreathing, registry.companions.first?.attack?.style == .breath { breathStarts += 1 }
        performance.update(at: link.timestamp)
    }
}
