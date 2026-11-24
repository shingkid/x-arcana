import SceneKit
import UIKit

enum RuneEffects {
    private static let ember = UIColor(red: 1, green: 0.26, blue: 0.035, alpha: 1)
    private static let flame = UIColor(red: 1, green: 0.84, blue: 0.25, alpha: 1)
    private static let violet = UIColor(red: 0.68, green: 0.23, blue: 1, alpha: 1)

    // Effects do not block the gaze ray used to place another spell.
    @discardableResult
    private static func part(
        _ geometry: SCNGeometry, color: UIColor, glow: Bool = false,
        at position: SIMD3<Float> = .zero, on parent: SCNNode
    ) -> SCNNode {
        let material = SCNMaterial()
        material.diffuse.contents = color
        if glow { material.lightingModel = .constant }
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.categoryBitMask = 2
        node.simdPosition = position
        parent.addChildNode(node)
        return node
    }

    private static func globe(
        _ radius: CGFloat, color: UIColor, at p: SIMD3<Float>, on parent: SCNNode,
        stretch: SIMD3<Float> = SIMD3(repeating: 1), glow: Bool = false
    ) -> SCNNode {
        let node = part(SCNSphere(radius: radius), color: color, glow: glow, at: p, on: parent)
        node.simdScale = stretch
        return node
    }

    static func sparkBurst(in scene: SCNScene, at target: SIMD3<Float>, facing camera: SCNNode) {
        let burst = SCNNode()
        burst.simdPosition = target
        burst.simdOrientation = camera.simdWorldOrientation
        // Keep even a cast against a nearby wall visible inside the glasses.
        burst.simdScale = SIMD3(repeating: min(1.6, simd_distance(camera.simdWorldPosition, target) * 0.65))
        scene.rootNode.addChildNode(burst)
        let flash = globe(0.035, color: .white, at: .zero, on: burst, glow: true)
        flash.runAction(.group([.scale(to: 1.7, duration: 0.14), .fadeOut(duration: 0.22)]))
        for index in 0..<13 {
            let angle = 2 * Float.pi * Float(index) / 13
            let reach: Float = index.isMultiple(of: 2) ? 0.27 : 0.18
            let direction = SIMD3<Float>(cos(angle), sin(angle), 0)
            let spark = globe(
                0.014, color: index.isMultiple(of: 3) ? .white : flame,
                at: direction * 0.025, on: burst,
                stretch: SIMD3(1.9, 0.65, 0.65), glow: true)
            spark.eulerAngles.z = angle
            let scatter = SCNAction.move(to: SCNVector3(direction * reach), duration: 0.55)
            scatter.timingMode = .easeOut
            spark.runAction(.group([scatter, .sequence([.wait(duration: 0.22), .fadeOut(duration: 0.37)])]))
        }
        burst.runAction(.sequence([.wait(duration: 0.62), .removeFromParentNode()]))
    }

    static func fireball(in scene: SCNScene, from camera: SCNNode, to target: SIMD3<Float>) {
        let root = scene.rootNode
        let origin = camera.simdConvertPosition(SIMD3(0.09, -0.08, -0.34), to: nil)
        let fire = SCNNode()
        fire.simdPosition = origin
        root.addChildNode(fire)
        _ = globe(0.060, color: ember, at: .zero, on: fire, glow: true)
        let sparks = SCNParticleSystem()
        sparks.emitterShape = SCNSphere(radius: 0.038)
        sparks.birthRate = 110
        sparks.particleLifeSpan = 0.20
        sparks.particleLifeSpanVariation = 0.10
        sparks.particleSize = 0.032
        sparks.particleSizeVariation = 0.014
        sparks.particleColor = flame
        sparks.particleVelocity = 0.13
        sparks.spreadingAngle = 180
        sparks.blendMode = .additive
        sparks.isLocal = false
        fire.addParticleSystem(sparks)
        let flight = SCNAction.move(to: SCNVector3(target), duration: 0.42)
        flight.timingMode = .easeIn
        let flash = SCNAction.group([.scale(to: 2.5, duration: 0.18), .fadeOut(duration: 0.22)])
        fire.runAction(.sequence([flight, flash, .removeFromParentNode()]))
    }

    @discardableResult
    static func summon(in scene: SCNScene, at target: SIMD3<Float>, facing viewer: SIMD3<Float>) -> SCNNode? {
        guard let demon = summonModel(named: "Demon") else { return nil }
        let count = scene.rootNode.childNodes.filter { $0.name == "SummonedDemon" }.count
        let portal = SCNNode()
        portal.name = "SummonedDemon"
        portal.categoryBitMask = 2
        portal.simdPosition = summonFloorPosition(in: scene, target: target, viewer: viewer, count: count)
        let towardViewer = viewer - portal.simdPosition
        portal.eulerAngles.y = atan2(towardViewer.x, towardViewer.z)
        scene.rootNode.addChildNode(portal)
        demon.name = "DemonSculpture"
        portal.addChildNode(demon)
        DemonFlight.install(on: demon)
        addSummonLight(to: portal, color: UIColor(red: 1, green: 0.48, blue: 0.27, alpha: 1))

        let ring = part(
            SCNTorus(ringRadius: 0.43, pipeRadius: 0.006), color: violet,
            glow: true, at: SIMD3(0, 0.012, 0), on: portal)
        ring.runAction(
            .sequence([
                .group([
                    .scale(to: 1.35, duration: 0.7),
                    .fadeOut(duration: 0.9),
                ]), .removeFromParentNode(),
            ]))
        _ = CharacterAnimation.sample("idle", at: 0, on: portal)
        DemonFlight.sample(on: portal, time: 0)
        return portal
    }

    static func revelio(in scene: SCNScene, at target: SIMD3<Float>, from camera: SCNNode) {
        let reveal = anchoredEffect("Revelio", in: scene, at: target, from: camera)
        let distance = simd_distance(camera.simdWorldPosition, reveal.simdWorldPosition)
        reveal.simdScale = SIMD3(repeating: min(1.8, max(0.07, distance * 0.82)))
        let gold = UIColor(red: 1, green: 0.78, blue: 0.32, alpha: 1)

        // The wave crosses the slate before the concealed ink becomes readable.
        for index in 0..<3 {
            let ring = part(
                SCNTorus(ringRadius: 0.19, pipeRadius: 0.006), color: gold,
                glow: true, at: SIMD3(0, 0, 0.035), on: reveal)
            ring.eulerAngles.x = .pi / 2
            ring.opacity = 0
            let expand = SCNAction.scale(to: UIAccessibility.isReduceMotionEnabled ? 1.7 : 3.7, duration: 1.2)
            expand.timingMode = .easeOut
            ring.runAction(
                .sequence([
                    .wait(duration: Double(index) * 0.15), .fadeIn(duration: 0.08),
                    .group([expand, .fadeOut(duration: 1.2)]), .removeFromParentNode(),
                ]))
        }

        let slate = part(SCNPlane(width: 1, height: 0.60), color: .white, glow: true, on: reveal)
        slate.name = "HiddenInscription"
        slate.geometry?.firstMaterial?.diffuse.contents = inscription(at: target)
        slate.geometry?.firstMaterial?.writesToDepthBuffer = false
        slate.opacity = 0
        slate.runAction(
            .sequence([
                .wait(duration: 0.38), .fadeIn(duration: 0.65),
                .wait(duration: 10), .fadeOut(duration: 1.1),
            ]))
        reveal.runAction(.sequence([.wait(duration: 12.2), .removeFromParentNode()]))
    }

    static func lumos(in scene: SCNScene, from camera: SCNNode) {
        camera.childNode(withName: "Lumos", recursively: false)?.removeFromParentNode()
        let lantern = SCNNode()
        lantern.name = "Lumos"
        lantern.categoryBitMask = 2
        camera.addChildNode(lantern)

        // An omni light keeps the whole room lit as the wearer turns their head.
        // This light is stronger than the hall's ambient lanterns.
        let lamp = SCNNode()
        lamp.simdPosition = SIMD3(0, -0.06, -0.12)
        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(red: 0.86, green: 0.95, blue: 1, alpha: 1)
        light.intensity = 0
        light.attenuationStartDistance = 0.3
        light.attenuationEndDistance = 12
        light.attenuationFalloffExponent = 1.4
        lamp.light = light
        lantern.addChildNode(lamp)

        let tip = SCNNode()
        tip.simdPosition = SIMD3(0.14, -0.12, -0.42)
        lantern.addChildNode(tip)
        let handle = part(
            SCNCylinder(radius: 0.006, height: 0.11),
            color: UIColor(red: 0.32, green: 0.23, blue: 0.13, alpha: 1),
            at: SIMD3(0.014, -0.055, 0.02), on: tip)
        handle.eulerAngles = SCNVector3(-0.35, 0, 0.24)
        _ = globe(0.014, color: .white, at: .zero, on: tip, glow: true)
        let halo = globe(
            0.035, color: UIColor(red: 0.49, green: 0.79, blue: 1, alpha: 1),
            at: .zero, on: tip, glow: true)
        halo.opacity = 0.18
        halo.geometry?.firstMaterial?.blendMode = .add
        halo.geometry?.firstMaterial?.writesToDepthBuffer = false
        for angle in [Float(0), .pi / 2] {
            let ray = globe(
                0.024, color: .white, at: .zero, on: tip,
                stretch: SIMD3(1.5, 0.07, 0.07), glow: true)
            ray.eulerAngles.z = angle
            ray.opacity = 0.65
        }
        lantern.opacity = 0
        lantern.runAction(
            .sequence([
                .group([
                    .fadeIn(duration: 0.35),
                    .customAction(duration: 0.35) { _, elapsed in
                        light.intensity = 900 * min(1, elapsed / 0.35)
                    },
                ]),
                .wait(duration: 20),
                .group([
                    .fadeOut(duration: 2),
                    .customAction(duration: 2) { _, elapsed in
                        light.intensity = 900 * max(0, 1 - elapsed / 2)
                    },
                ]),
                .removeFromParentNode(),
            ]))
    }

    @discardableResult
    static func patronus(in scene: SCNScene, at target: SIMD3<Float>, from camera: SCNNode) -> SCNNode? {
        guard let stag = summonModel(named: "Stag") else { return nil }
        let guardian = SCNNode()
        guardian.name = "Patronus"
        guardian.categoryBitMask = 2
        var forward = camera.simdWorldFront
        forward.y = 0
        forward = simd_length_squared(forward) > 0.001 ? simd_normalize(forward) : SIMD3(0, 0, -1)
        let right = SIMD3<Float>(-forward.z, 0, forward.x)
        // Enter beside the player instead of materializing in the enemy cluster.
        var entry = camera.simdWorldPosition + right * 1.25 + forward * 1.65
        entry.y = 0
        guardian.simdWorldPosition = entry
        let direction = target - entry
        guardian.eulerAngles.y = atan2(direction.x, direction.z)
        scene.rootNode.addChildNode(guardian)
        stag.name = "SilverStag"
        guardian.addChildNode(stag)
        addSummonLight(to: guardian, color: UIColor(red: 0.51, green: 0.78, blue: 1, alpha: 1))

        addPatronusWisps(to: guardian)
        guardian.addChildNode(ScenePerformance.independentClone(of: mistTemplate))
        CharacterAnimation.play("run", on: guardian, speed: 1, loop: true)
        return guardian
    }

    private static let mistTemplate: SCNNode = {
        let mist = SCNParticleSystem()
        mist.emitterShape = SCNBox(width: 0.5, height: 0.65, length: 1.1, chamferRadius: 0.2)
        mist.birthRate = 35
        mist.particleLifeSpan = 1.2
        mist.particleSize = 0.018
        mist.particleSizeVariation = 0.012
        mist.particleImage = spiritImage
        mist.particleColor = UIColor(red: 0.53, green: 0.79, blue: 1, alpha: 1)
        mist.particleVelocity = 0.06
        mist.spreadingAngle = 150
        mist.acceleration = SCNVector3(0, 0.035, 0)
        mist.blendMode = .additive
        mist.isLocal = false
        let trail = SCNNode()
        trail.categoryBitMask = 2
        trail.simdPosition = SIMD3(0, 0.85, 0)
        trail.addParticleSystem(mist)
        return trail
    }()

    private static let wispTemplate: SCNNode = {
        let node = SCNNode()
        buildPatronusWisps(to: node)
        return node
    }()

    private static let spiritImage = spiritParticleImage()

    static func prewarm() -> [SCNNode] {
        SpellVisuals.prepare()
        return [preparedModel(named: "Demon"), preparedModel(named: "Stag"), wispTemplate, mistTemplate].compactMap {
            $0
        }
    }

    private static func addPatronusWisps(to parent: SCNNode) {
        let wisps = ScenePerformance.independentClone(of: wispTemplate)
        for child in wisps.childNodes { parent.addChildNode(child) }
    }

    private static func buildPatronusWisps(to parent: SCNNode) {
        for strand in 0..<5 {
            var vertices: [SCNVector3] = []
            var coordinates: [CGPoint] = []
            var indices: [Int32] = []
            let phase = Float(strand) * 1.37
            for step in 0...48 {
                let t = Float(step) / 48
                let width = 0.020 * pow(sin(t * .pi), 0.7)
                let center = SIMD3<Float>(
                    sin(t * 6 + phase) * (0.08 + t * 0.24),
                    0.68 + Float(strand) * 0.11 + t * 0.38 + sin(t * 7 + phase) * 0.08,
                    -0.12 - t * 1.65)
                for side in [-Float(1), 1] {
                    vertices.append(SCNVector3(center + SIMD3(side * width, 0, 0)))
                    coordinates.append(CGPoint(x: side < 0 ? 0 : 1, y: CGFloat(t)))
                }
                if step > 0 {
                    let n = Int32(step * 2)
                    indices += [n - 2, n - 1, n, n - 1, n + 1, n]
                }
            }
            let geometry = SCNGeometry(
                sources: [
                    SCNGeometrySource(vertices: vertices),
                    SCNGeometrySource(textureCoordinates: coordinates),
                ],
                elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = UIColor(red: 0.41, green: 0.75, blue: 1, alpha: 0.6)
            material.blendMode = .add
            material.writesToDepthBuffer = false
            material.isDoubleSided = true
            material.shaderModifiers = [
                .geometry: """
                #pragma body
                _geometry.position.x += 0.035 * sin(scn_frame.time * 1.2 + _geometry.position.z * 4.0);
                _geometry.position.y += 0.025 * sin(scn_frame.time * 1.6 + _geometry.position.z * 3.0);
                """,
                .fragment: """
                #pragma transparent
                #pragma body
                float across = sin(_surface.diffuseTexcoord.x * 3.14159265);
                float along = sin(_surface.diffuseTexcoord.y * 3.14159265);
                _output.color.a *= pow(max(0.0, across), 1.5) * max(0.0, along) * 0.55;
                """,
            ]
            geometry.materials = [material]
            let wisp = SCNNode(geometry: geometry)
            wisp.name = "PatronusWisp"
            wisp.categoryBitMask = 2
            parent.addChildNode(wisp)
        }
    }

    private static func spiritParticleImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            let colors =
                [
                    UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.32).cgColor,
                    UIColor.clear.cgColor,
                ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                locations: [0, 0.25, 1])
            {
                context.cgContext.drawRadialGradient(
                    gradient, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                    endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
            }
        }
    }

    // Scene templates share mesh buffers. Each summon has independent transforms and materials.
    private static let demonTemplate = loadSummonScene(named: "Demon")
    private static let stagTemplate = loadSummonScene(named: "Stag")

    private static func loadSummonScene(named name: String) -> SCNScene? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz", subdirectory: "Creatures") else {
            NSLog("Missing creature asset: Creatures/%@.usdz", name)
            return nil
        }
        do {
            return try SCNScene(url: url, options: [.convertToYUp: true, .convertUnitsToMeters: 1])
        } catch {
            NSLog("Could not load creature %@: %@", name, error.localizedDescription)
            return nil
        }
    }

    private static var preparedModels: [String: SCNNode] = [:]

    private static func summonModel(named name: String) -> SCNNode? {
        guard let model = preparedModel(named: name) else { return nil }
        return ScenePerformance.independentClone(of: model)
    }

    private static func preparedModel(named name: String) -> SCNNode? {
        if let cached = preparedModels[name] { return cached }
        guard let template = name == "Demon" ? demonTemplate : stagTemplate else { return nil }
        let model = ScenePerformance.independentClone(of: template.rootNode)
        guard CharacterAnimation.install(on: model, asset: name, directory: "Creatures") else { return nil }
        model.categoryBitMask = 2
        model.enumerateChildNodes { node, _ in
            node.categoryBitMask = 2
            node.castsShadow = true
            // A local copy prevents a later summon from changing an existing creature's appearance.
            if let geometry = node.geometry {
                node.geometry = geometry.copy() as? SCNGeometry
                if name == "Demon" {
                    node.geometry?.materials = geometry.materials.map { original in
                        let material = original.copy() as! SCNMaterial
                        material.lightingModel = .physicallyBased
                        material.roughness.contents = 0.82
                        material.metalness.contents = 0
                        material.specular.contents = UIColor(white: 0.12, alpha: 1)
                        material.normal.intensity = 0.55
                        return material
                    }
                }
            }
        }
        if name == "Stag" { stylePatronus(model) }
        preparedModels[name] = model
        return model
    }

    private static func stylePatronus(_ model: SCNNode) {
        model.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }
            geometry.materials = geometry.materials.map { original in
                let material = original.copy() as! SCNMaterial
                material.lightingModel = .physicallyBased
                material.emission.contents = UIColor(red: 0.025, green: 0.065, blue: 0.11, alpha: 1)
                material.metalness.contents = 0.05
                material.roughness.contents = 0.36
                material.transparency = 0.82
                material.transparencyMode = .aOne
                material.blendMode = .alpha
                material.writesToDepthBuffer = false
                material.isDoubleSided = false
                material.shaderModifiers = [
                    .fragment: """
                    #pragma transparent
                    #pragma body
                    float facing = abs(dot(normalize(_surface.normal), normalize(_surface.view)));
                    float rim = pow(1.0 - clamp(facing, 0.0, 1.0), 1.55);
                    float breath = 0.96 + 0.04 * sin(scn_frame.time * 1.4 + _surface.position.y * 3.0);
                    _output.color.rgb = float3(0.28, 0.65, 1.0) * (0.22 + 2.3 * rim) * breath
                        + _output.color.rgb * 0.08;
                    _output.color.a *= 0.11 + rim * 0.75;
                    """
                ]
                return material
            }
        }

    }

    private static func summonFloorPosition(
        in scene: SCNScene, target: SIMD3<Float>,
        viewer: SIMD3<Float>, count: Int
    ) -> SIMD3<Float> {
        var heading = target - viewer
        heading.y = 0
        let reach = simd_length(heading)
        heading = reach > 0.001 ? heading / reach : SIMD3(0, 0, -1)
        var center = viewer + heading * min(3.6, max(2.7, reach - 0.65))
        center.y = 0
        let occupied = scene.rootNode.childNodes.filter {
            $0.name == "Patronus" || $0.name?.hasPrefix("Summoned") == true
                || $0.name?.lowercased().hasPrefix("summon") == true
        }.map { $0.simdPosition }
        var best = center
        var bestClearance: Float = -1
        for attempt in 0..<120 {
            let radius = attempt == 0 ? Float(0) : 0.53 * sqrt(Float(attempt))
            let angle = Float(attempt) * 2.399963
            var candidate = center + SIMD3(cos(angle) * radius, 0, sin(angle) * radius)
            candidate.x = min(2.4, max(-2.4, candidate.x))
            candidate.z = min(3.4, max(-4.7, candidate.z))
            let fromViewer = SIMD2(candidate.x - viewer.x, candidate.z - viewer.z)
            guard simd_length(fromViewer) >= 2.3 else { continue }
            let clearance =
                occupied.map {
                    simd_length(SIMD2(candidate.x - $0.x, candidate.z - $0.z))
                }.min() ?? Float.greatestFiniteMagnitude
            if clearance >= 1.05 { return candidate }
            if clearance > bestClearance {
                best = candidate
                bestClearance = clearance
            }
        }
        // In a crowded room, use the largest remaining gap without replacing an existing summon.
        return best
    }

    private static func addSummonLight(to root: SCNNode, color: UIColor) {
        let lamp = SCNNode()
        lamp.categoryBitMask = 2
        lamp.simdPosition = SIMD3(-0.5, 1.8, 0.8)
        let light = SCNLight()
        light.type = .omni
        light.categoryBitMask = 2
        light.color = color
        light.intensity = 18
        light.attenuationStartDistance = 0.5
        light.attenuationEndDistance = 2.4
        lamp.light = light
        root.addChildNode(lamp)
    }

    private static func anchoredEffect(
        _ name: String, in scene: SCNScene, at target: SIMD3<Float>,
        from camera: SCNNode, replace: Bool = true
    ) -> SCNNode {
        if replace { scene.rootNode.childNode(withName: name, recursively: false)?.removeFromParentNode() }
        let root = SCNNode()
        root.name = name
        root.categoryBitMask = 2
        let towardViewer = camera.simdWorldPosition - target
        let distance = simd_length(towardViewer)
        root.simdPosition = target + (distance > 0.001 ? towardViewer / distance * min(0.15, distance * 0.15) : .zero)
        // Preserve room-up even when the player looks down or tilts their head.
        root.eulerAngles.y = atan2(towardViewer.x, towardViewer.z)
        scene.rootNode.addChildNode(root)
        return root
    }

    @discardableResult
    private static func segment(
        from start: SIMD3<Float>, to end: SIMD3<Float>, radius: CGFloat,
        color: UIColor, glow: Bool = false, on parent: SCNNode
    ) -> SCNNode {
        let node = part(
            SCNCylinder(radius: radius, height: CGFloat(simd_distance(start, end))),
            color: color, glow: glow, at: (start + end) / 2, on: parent)
        node.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(end - start))
        return node
    }

    private static func inscription(at target: SIMD3<Float>) -> UIImage {
        let passages = [
            ["Where shadows keep silence,", "the stag remembers the way.", "Follow the silver light."],
            ["No lock can bind the heart.", "Beneath the oldest ember,", "a sleeping door awaits."],
            ["The stars forget no traveller.", "Speak softly to the darkness,", "and carry the dawn within."],
        ]
        // Nearby casts reveal the same inscription instead of random text.
        let region = Int(floor(target.x)) + Int(floor(target.z)) * 5 + Int(floor(target.y)) * 7
        let lines = passages[((region % passages.count) + passages.count) % passages.count]
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 720), format: format).image { context in
            // The hall remains visible through and around the hidden writing.
            let canvas = context.cgContext
            let shade =
                [
                    UIColor.black.withAlphaComponent(0.58).cgColor,
                    UIColor.black.withAlphaComponent(0.32).cgColor,
                    UIColor.clear.cgColor,
                ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: shade,
                locations: [0, 0.55, 1])
            {
                canvas.saveGState()
                canvas.translateBy(x: 600, y: 355)
                canvas.scaleBy(x: 1, y: 0.48)
                canvas.drawRadialGradient(
                    gradient, startCenter: .zero, startRadius: 0,
                    endCenter: .zero, endRadius: 590, options: [])
                canvas.restoreGState()
            }
            let gold = UIColor(red: 0.96, green: 0.76, blue: 0.39, alpha: 1)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let glow = NSShadow()
            glow.shadowColor = gold.withAlphaComponent(0.85)
            glow.shadowBlurRadius = 13
            glow.shadowOffset = .zero
            func line(_ text: String, y: CGFloat, size: CGFloat, color: UIColor) {
                text.draw(
                    in: CGRect(x: 64, y: y, width: 1072, height: size * 1.5),
                    withAttributes: [
                        .font: UIFont(name: "Baskerville", size: size)
                            ?? UIFont.systemFont(ofSize: size, weight: .medium),
                        .foregroundColor: color, .paragraphStyle: paragraph, .shadow: glow,
                    ])
            }
            for (index, text) in lines.enumerated() {
                line(
                    text, y: 215 + CGFloat(index) * 92, size: 64,
                    color: UIColor(red: 1, green: 0.94, blue: 0.76, alpha: 1))
            }
        }
    }
}

/// Short, scene-local spectacle. These nodes never decide damage or move the viewer.
/// Meshes and materials are shared; opacity, scale, and motion belong to each node.
enum SpellVisuals {
    enum Tone { case electric, frost, ember, gold, violet, spirit }
    private final class TransientRoot: SCNNode {}
    private static let ringMesh: SCNTorus = {
        let ring = SCNTorus(ringRadius: 1, pipeRadius: 0.012)
        ring.ringSegmentCount = 56
        ring.pipeSegmentCount = 4
        return ring
    }()
    private static let beamMesh: SCNCylinder = {
        let beam = SCNCylinder(radius: 1, height: 1)
        beam.radialSegmentCount = 5
        return beam
    }()
    private static let coreMesh: SCNSphere = {
        let sphere = SCNSphere(radius: 1)
        sphere.segmentCount = 12
        return sphere
    }()
    private static let shardMesh: SCNGeometry = {
        let vertices = [
            SCNVector3(0, 1, 0), SCNVector3(-0.3, 0, 0), SCNVector3(0, 0, 0.3),
            SCNVector3(0.3, 0, 0), SCNVector3(0, 0, -0.3), SCNVector3(0, -0.6, 0),
        ]
        let indices: [Int32] = [
            0, 1, 2, 0, 2, 3, 0, 3, 4, 0, 4, 1,
            5, 2, 1, 5, 3, 2, 5, 4, 3, 5, 1, 4,
        ]
        return SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }()
    private static let colors: [Tone: UIColor] = [
        .electric: UIColor(red: 0.32, green: 0.72, blue: 1, alpha: 1),
        .frost: UIColor(red: 0.62, green: 0.92, blue: 1, alpha: 1),
        .ember: UIColor(red: 1, green: 0.23, blue: 0.035, alpha: 1),
        .gold: UIColor(red: 1, green: 0.74, blue: 0.22, alpha: 1),
        .violet: UIColor(red: 0.64, green: 0.35, blue: 1, alpha: 1),
        .spirit: UIColor(red: 0.28, green: 0.9, blue: 0.86, alpha: 1),
    ]
    private static let materials: [Tone: SCNMaterial] = colors.mapValues { color in
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color
        material.lightingModel = .constant
        material.blendMode = .add
        material.writesToDepthBuffer = false
        material.isDoubleSided = true
        return material
    }
    private static let particleImage: UIImage = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
        return renderer.image { context in
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray,
                locations: [0, 1])!
            context.cgContext.drawRadialGradient(
                gradient, startCenter: CGPoint(x: 16, y: 16), startRadius: 0,
                endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
        }
    }()

    static func prepare() {
        _ = ringMesh
        _ = beamMesh
        _ = coreMesh
        _ = shardMesh
        _ = materials
        _ = particleImage
    }

    @discardableResult
    private static func effect(
        _ name: String, at point: SIMD3<Float>, on parent: SCNNode,
        lifetime: TimeInterval
    ) -> SCNNode {
        // This cap can remove only optional visual roots, never actors or projectiles.
        let previous = parent.childNodes.filter { $0 is TransientRoot }
        for old in previous.prefix(max(0, previous.count - 11)) { old.removeFromParentNode() }
        let root = TransientRoot()
        root.name = name
        root.categoryBitMask = 2
        root.simdPosition = point
        parent.addChildNode(root)
        root.runAction(.sequence([.wait(duration: lifetime), .removeFromParentNode()]), forKey: "visual.cleanup")
        return root
    }

    private static func node(_ mesh: SCNGeometry, tone: Tone, on parent: SCNNode) -> SCNNode {
        let geometry = mesh.copy() as! SCNGeometry
        geometry.materials = [materials[tone]!]
        let node = SCNNode(geometry: geometry)
        node.categoryBitMask = 2
        node.castsShadow = false
        parent.addChildNode(node)
        return node
    }

    private static func beam(
        from start: SIMD3<Float>, to end: SIMD3<Float>, width: Float,
        tone: Tone, on parent: SCNNode
    ) {
        let delta = end - start
        let length = simd_length(delta)
        guard length > 0.0001 else { return }
        let line = node(beamMesh, tone: tone, on: parent)
        line.simdPosition = (start + end) / 2
        line.simdScale = SIMD3(width, length, width)
        line.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: delta / length)
    }

    private static func ring(
        radius: Float, tone: Tone, at point: SIMD3<Float> = .zero,
        on parent: SCNNode, duration: TimeInterval = 0.6
    ) -> SCNNode {
        let ring = node(ringMesh, tone: tone, on: parent)
        ring.simdPosition = point
        ring.simdScale = SIMD3(repeating: UIAccessibility.isReduceMotionEnabled ? radius : radius * 0.18)
        ring.opacity = 0.7
        let spread = SCNAction.scale(to: CGFloat(radius), duration: duration)
        spread.timingMode = .easeOut
        ring.runAction(.group([spread, .fadeOut(duration: duration)]))
        return ring
    }

    private static func particles(
        tone: Tone, count: CGFloat, life: CGFloat, speed: CGFloat,
        spread: CGFloat = 180, on root: SCNNode
    ) {
        let system = SCNParticleSystem()
        system.birthRate = UIAccessibility.isReduceMotionEnabled ? count * 0.3 : count
        system.emissionDuration = 0.18
        system.loops = false
        system.particleLifeSpan = life
        system.particleLifeSpanVariation = life * 0.15
        system.particleSize = 0.035
        system.particleSizeVariation = 0.018
        system.particleImage = particleImage
        system.particleColor = colors[tone]!
        system.particleVelocity = speed
        system.particleVelocityVariation = speed * 0.25
        system.spreadingAngle = spread
        system.emittingDirection = SCNVector3(0, 0, 1)
        system.acceleration = SCNVector3(0, -0.8, 0)
        system.blendMode = .additive
        system.isLocal = false
        system.isLightingEnabled = false
        root.addParticleSystem(system)
    }

    static func lightning(at point: SIMD3<Float>, on parent: SCNNode) {
        let root = effect("Lightning impact", at: point, on: parent, lifetime: 0.65)
        if let accent = SpellVFX.card(.lightning, size: 1.8, duration: 0.5) {
            accent.position.y = 0.25
            accent.opacity = 0.85
            root.addChildNode(accent)
        }
        let core = node(coreMesh, tone: .frost, on: root)
        core.simdScale = SIMD3(repeating: 0.11)
        core.opacity = 0.65
        core.runAction(.group([.scale(to: 0.28, duration: 0.16), .fadeOut(duration: 0.22)]))
        let arcs = SCNNode()
        arcs.categoryBitMask = 2
        root.addChildNode(arcs)
        for branch in 0..<5 {
            let angle = Float(branch) * 2 * .pi / 5 + 0.2
            var start = SIMD3<Float>.zero
            for step in 1...4 {
                let reach = Float(step) * (branch.isMultiple(of: 2) ? 0.22 : 0.16)
                let bend = step.isMultiple(of: 2) ? Float(0.09) : -0.09
                let end = SIMD3(
                    cos(angle) * reach + sin(angle) * bend,
                    sin(angle) * reach - cos(angle) * bend, Float(branch % 3 - 1) * reach * 0.3)
                beam(from: start, to: end, width: 0.012, tone: step == 1 ? .frost : .electric, on: arcs)
                start = end
            }
        }
        arcs.runAction(.sequence([.wait(duration: 0.07), .fadeOut(duration: 0.28)]))
        let corona = ring(radius: 0.6, tone: .electric, on: root, duration: 0.35)
        corona.eulerAngles.x = .pi / 2
        particles(tone: .frost, count: 100, life: 0.35, speed: 1.6, on: root)
    }

    static func fireball(at point: SIMD3<Float>, radius: Float, floorY: Float, on parent: SCNNode) {
        let root = effect("Fireball blast", at: point, on: parent, lifetime: 1.2)
        if let accent = SpellVFX.card(.fire, size: CGFloat(radius * 1.3), duration: 0.75) {
            accent.opacity = 0.7
            root.addChildNode(accent)
        }
        let core = node(coreMesh, tone: .ember, on: root)
        core.simdScale = SIMD3(repeating: UIAccessibility.isReduceMotionEnabled ? radius * 0.55 : 0.15)
        core.opacity = 0.42
        let expansion = SCNAction.scale(to: CGFloat(radius * 0.55), duration: 0.28)
        expansion.timingMode = .easeOut
        core.runAction(.group([expansion, .fadeOut(duration: 0.35)]))
        _ = ring(radius: radius, tone: .gold, at: SIMD3(0, floorY + 0.035 - point.y, 0), on: root, duration: 0.75)
        let halo = ring(radius: radius * 0.85, tone: .ember, on: root, duration: 0.55)
        halo.eulerAngles.x = .pi / 2
        let diagonal = ring(radius: radius * 0.62, tone: .gold, on: root, duration: 0.42)
        diagonal.eulerAngles = SCNVector3(0.7, 0, 0.55)
        particles(tone: .gold, count: 300, life: 0.75, speed: 2.8, on: root)
        for index in 0..<8 {
            let angle = Float(index) * .pi / 4
            let spark = node(shardMesh, tone: index.isMultiple(of: 2) ? .ember : .gold, on: root)
            spark.simdScale = SIMD3(0.06, 0.16, 0.06)
            spark.simdEulerAngles = SIMD3(0.4, angle, 0.7)
            let end = SIMD3(
                cos(angle) * radius * 0.75, Float(index % 3) * 0.2 - 0.2,
                sin(angle) * radius * 0.75)
            if UIAccessibility.isReduceMotionEnabled { spark.simdPosition = end }
            let scatter = SCNAction.move(to: SCNVector3(end), duration: 0.6)
            scatter.timingMode = .easeOut
            spark.runAction(.group([scatter, .fadeOut(duration: 0.7)]))
        }
    }

    static func ice(from origin: SIMD3<Float>, direction: SIMD3<Float>, on parent: SCNNode) {
        let root = effect("Ice cone", at: origin + direction * 0.3, on: parent, lifetime: 0.95)
        root.simdOrientation = simd_quatf(from: SIMD3(0, 0, 1), to: direction)
        if let accent = SpellVFX.card(.ice, size: 1.4, duration: 0.6) {
            accent.position.z = 1.5
            accent.opacity = 0.4
            root.addChildNode(accent)
        }
        particles(tone: .frost, count: 180, life: 0.5, speed: 8, spread: 30, on: root)
        for index in 0..<12 {
            let angle = Float(index) * 2.39996
            let distance = 2.0 + Float(index % 4) * 0.7
            let spread: Float = 0.2 + Float(index % 3) * 0.1
            let end = SIMD3(cos(angle) * distance * spread, sin(angle) * distance * spread, distance)
            let shard = node(shardMesh, tone: index.isMultiple(of: 3) ? .electric : .frost, on: root)
            shard.simdPosition = UIAccessibility.isReduceMotionEnabled ? end : SIMD3(end.x * 0.05, end.y * 0.05, 0.3)
            shard.simdScale = SIMD3(0.11, 0.3, 0.11)
            shard.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(end))
            shard.opacity = 0.7
            let flight = SCNAction.move(to: SCNVector3(end), duration: 0.45)
            flight.timingMode = .easeOut
            shard.runAction(.group([flight, .sequence([.wait(duration: 0.16), .fadeOut(duration: 0.4)])]))
        }
        let front = ring(radius: 0.5, tone: .frost, at: SIMD3(0, 0, 0.6), on: root, duration: 0.28)
        front.eulerAngles.x = .pi / 2
    }

    static func shieldActivation(on shield: SCNNode) {
        let root = effect("Shield awakening", at: .zero, on: shield, lifetime: 0.9)
        _ = ring(radius: 1.3, tone: .electric, at: SIMD3(0, -0.85, 0), on: root, duration: 0.7)
        for index in 0..<2 {
            let arch = ring(radius: 1.3, tone: .frost, on: root, duration: 0.7)
            arch.eulerAngles = SCNVector3(.pi / 2, Float(index) * .pi / 2, 0)
            arch.opacity = 0.32
        }
        // Persistent details sit on the edge of the dome, not over the crosshair.
        for index in 0..<8 {
            let angle = Float(index) * .pi / 4
            let seal = node(shardMesh, tone: .electric, on: shield)
            seal.name = "Shield seal"
            seal.simdPosition = SIMD3(cos(angle) * 1.25, -0.55, sin(angle) * 1.25)
            seal.simdScale = SIMD3(0.06, 0.13, 0.06)
            seal.opacity = 0.25
        }
    }

    static func shieldContact(on shield: SCNNode, at worldPoint: SIMD3<Float>) {
        let offset = shield.simdConvertPosition(worldPoint, from: nil)
        guard simd_length_squared(offset) > 0.001 else { return }
        let normal = simd_normalize(offset)
        let root = effect("Shield contact", at: normal * 1.28, on: shield, lifetime: 0.5)
        if let accent = SpellVFX.card(.shield, size: 0.75, duration: 0.4) {
            accent.opacity = 0.5
            root.addChildNode(accent)
        }
        let ripple = ring(radius: 0.42, tone: .frost, on: root, duration: 0.4)
        ripple.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: normal)
    }

    static func entrance(on actor: SCNNode, kind: SummonKind) {
        guard let parent = actor.parent else { return }
        let tone: Tone
        switch kind {
        case .demon: tone = .ember
        case .patronus: tone = .frost
        case .albert: tone = .violet
        case .alan: tone = .spirit
        }
        let root = effect("CompanionAttack", at: actor.simdPosition + SIMD3(0, 0.025, 0), on: parent, lifetime: 1.25)
        if kind == .patronus {
            particles(tone: .frost, count: 70, life: 0.45, speed: 0.35, spread: 90, on: root)
            return
        }
        if let accent = SpellVFX.card(kind == .patronus ? .shield : .summon, size: 1.9, duration: 1) {
            accent.constraints = []
            accent.eulerAngles.x = -.pi / 2
            accent.position.y = 0.025
            accent.opacity = 0.6
            root.addChildNode(accent)
        }
        _ = ring(radius: kind == .demon ? 1.25 : 0.9, tone: tone, on: root, duration: 0.85)
        _ = ring(
            radius: kind == .demon ? 0.85 : 0.62, tone: kind == .demon ? .gold : .frost,
            at: SIMD3(0, 0.015, 0), on: root, duration: 0.7)
        let glyphs = SCNNode()
        glyphs.categoryBitMask = 2
        root.addChildNode(glyphs)
        for index in 0..<8 {
            let angle = Float(index) * .pi / 4
            let center = SIMD3<Float>(cos(angle) * 0.7, 0.02, sin(angle) * 0.7)
            let tangent = SIMD3<Float>(-sin(angle), 0, cos(angle)) * 0.09
            beam(from: center - tangent, to: center + tangent, width: 0.012, tone: tone, on: glyphs)
        }
        glyphs.runAction(.sequence([.wait(duration: 0.35), .fadeOut(duration: 0.55)]))
        let column = SCNNode()
        column.categoryBitMask = 2
        column.simdPosition = SIMD3(0, 0.2, 0)
        column.eulerAngles.x = -.pi / 2
        root.addChildNode(column)
        particles(tone: tone, count: 180, life: 0.7, speed: 1.5, spread: 65, on: column)
    }
}

/// Small runtime accessories preserve the licensed body mesh and its weighted skeleton.
enum DemonFlight {
    static func install(on body: SCNNode) {
        guard body.childNode(withName: "DevilWing.L", recursively: true) == nil else { return }
        let membrane = SCNMaterial()
        membrane.name = "Devil wing membrane"
        membrane.diffuse.contents = UIColor(red: 0.32, green: 0.045, blue: 0.03, alpha: 1)
        membrane.emission.contents = UIColor(red: 0.18, green: 0.026, blue: 0.019, alpha: 1)
        membrane.lightingModel = .physicallyBased
        membrane.roughness.contents = 0.9
        membrane.isDoubleSided = false
        let bone = SCNMaterial()
        bone.diffuse.contents = UIColor(red: 0.11, green: 0.07, blue: 0.055, alpha: 1)
        bone.roughness.contents = 0.75
        for (name, side) in [("L", Float(1)), ("R", Float(-1))] {
            let mount = SCNNode()
            mount.name = "DevilWingMount." + name
            mount.categoryBitMask = 2
            mount.simdPosition = SIMD3(side * 0.2, 1.5, -0.22)
            body.addChildNode(mount)
            let wing = SCNNode()
            wing.name = "DevilWing." + name
            wing.categoryBitMask = 2
            mount.addChildNode(wing)
            let anchors: [SIMD3<Float>] = [
                SIMD3(0, 0, 0), SIMD3(0.43, 0.47, -0.05), SIMD3(1.05, 0.64, -0.1),
                SIMD3(1.4, 0.12, -0.13), SIMD3(1.02, -0.04, -0.07), SIMD3(0.95, -0.43, 0),
                SIMD3(0.62, -0.23, 0.03), SIMD3(0.4, -0.53, 0.04), SIMD3(0.2, -0.25, 0.02),
            ].map { SIMD3($0.x * side, $0.y, $0.z) }
            var outline = [anchors[0]]
            func curve(_ start: Int, _ control: SIMD3<Float>, _ end: Int, steps: Int) {
                for step in 1...steps {
                    let t = Float(step) / Float(steps)
                    let point = anchors[start] * (1 - t) * (1 - t) + control * 2 * (1 - t) * t + anchors[end] * t * t
                    outline.append(point)
                }
            }
            curve(0, anchors[1], 2, steps: 4)
            curve(2, (anchors[2] + anchors[3]) * 0.5, 3, steps: 3)
            curve(3, anchors[4], 5, steps: 5)
            curve(5, anchors[6], 7, steps: 5)
            curve(7, anchors[8], 0, steps: 4)
            outline.removeLast()
            let vertices = (outline + outline).map { SCNVector3($0) }
            let count = Int32(outline.count)
            var indices: [Int32] = []
            for index in 1..<(outline.count - 1) {
                let next = Int32(index + 1)
                indices += [0, Int32(index), next, count, count + next, count + Int32(index)]
            }
            // Separate faces provide correct lighting from either side of the moving membrane.
            let normals =
                Array(repeating: SCNVector3(0, 0, -side), count: outline.count)
                + Array(repeating: SCNVector3(0, 0, side), count: outline.count)
            let geometry = SCNGeometry(
                sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
                elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
            geometry.materials = [membrane]
            let skin = SCNNode(geometry: geometry)
            skin.name = "DevilWingMembrane"
            skin.categoryBitMask = 2
            skin.castsShadow = true
            wing.addChildNode(skin)
            for index in [2, 3, 5, 7] {
                let end = anchors[index]
                let strut = SCNCylinder(radius: index == 2 ? 0.021 : 0.012, height: CGFloat(simd_length(end)))
                strut.radialSegmentCount = 5
                strut.heightSegmentCount = 1
                strut.materials = [bone]
                let finger = SCNNode(geometry: strut)
                finger.name = "DevilWingFinger"
                finger.categoryBitMask = 2
                finger.simdPosition = end * 0.5
                finger.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(end))
                wing.addChildNode(finger)
            }
            CharacterAnimation.attach(mount, to: "chest", on: body)
        }
    }

    static func sample(on actor: SCNNode, time: TimeInterval, slamTime: TimeInterval? = nil) {
        guard let body = actor.childNode(withName: "DemonSculpture", recursively: true) else { return }
        let phase = Float(time) * 5.8
        let hover: Float = UIAccessibility.isReduceMotionEnabled ? 0.6 : 0.6 + sin(phase) * 0.065
        var height = hover
        if let slamTime {
            // The body meets the floor at the authoritative slam contact, then climbs back up.
            let t = Float(slamTime)
            let lift = t < 0.35 ? max(0, 1 - t / 0.35) : min(1, (t - 0.35) / 0.4)
            height = 0.025 + (hover - 0.025) * lift
        }
        body.simdPosition.y = height
        body.simdEulerAngles.x = -0.12 * min(1, height / 0.6)
        let tuck = min(1, height / 0.5)
        for side in ["L", "R"] {
            // CharacterAnimation samples a fresh pose before these additive flight adjustments.
            for (joint, bend) in [("thigh", Float(-0.38)), ("shin.Top", Float(0.75)), ("foot", Float(-0.25))] {
                let bone =
                    body.childNode(withName: joint + "." + side, recursively: true)
                    ?? body.childNode(
                        withName: joint.replacingOccurrences(of: ".", with: "_") + "_" + side, recursively: true)
                bone?.simdOrientation =
                    (bone?.simdOrientation ?? simd_quatf(angle: 0, axis: SIMD3(1, 0, 0)))
                    * simd_quatf(angle: bend * tuck, axis: SIMD3(1, 0, 0))
            }
            let wing = body.childNode(withName: "DevilWing." + side, recursively: true)
            let direction: Float = side == "L" ? 1 : -1
            let flap: Float = UIAccessibility.isReduceMotionEnabled ? 0.12 : 0.12 + sin(phase) * 0.38
            wing?.simdEulerAngles.z = direction * flap
            wing?.simdEulerAngles.y = direction * -0.2
        }
    }
}
