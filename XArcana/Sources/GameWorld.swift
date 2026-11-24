import SceneKit
import UIKit

/// Coordinates use metres, room Y for height, and UIKit's upper-left screen origin.
final class GameWorld {
    let scene: SCNScene
    let environment: EnvironmentDefinition
    let camera = SCNNode()
    private var environmentNodes: [SCNNode] = []
    private struct RainbowSurface {
        let geometry: SCNGeometry
        let originals: [SCNMaterial]
        let rainbow: [SCNMaterial]
    }
    private var rainbowSurfaces: [RainbowSurface] = []
    private var rainbowMaterials: [SCNMaterial] = []
    private(set) var transfigurationPhase: TimeInterval?
    private(set) var isSeeThrough = false
    private var homeView = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
    private var homeHeading = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
    private var homePitch: Float = 0
    private var referenceHead: simd_quatf?
    private var latestHead: simd_quatf?
    private var headFilter = HeadPoseFilter()
    private var latestHeadTime: TimeInterval?
    private var usesGravityReference = false
    private(set) var viewRevision = 0
    var trackingMessage = "Head tracking offline"
    var needsLocalNetworkPermission = false
    var isHeadTracked: Bool { latestHead != nil }
    private(set) var errorMessage: String?

    convenience init(environmentNamed name: String? = nil, bundle: Bundle = .main) {
        do {
            let selectedName = try name ?? EnvironmentDefinition.configuredName(bundle: bundle)
            try self.init(environment: EnvironmentDefinition.load(named: selectedName, bundle: bundle), bundle: bundle)
        } catch {
            self.init(
                validatedEnvironment: .fantasy, scene: SCNScene(),
                errorMessage: "The environment could not open. \(error.localizedDescription)")
        }
    }

    convenience init(environment: EnvironmentDefinition, bundle: Bundle = .main) throws {
        let definition = try environment.validated()
        let url = try definition.sceneURL(bundle: bundle)
        let scene: SCNScene
        do {
            scene = try SCNScene(url: url, options: [.convertToYUp: true, .convertUnitsToMeters: 1])
        } catch {
            throw EnvironmentError.invalidAsset(url.lastPathComponent, error.localizedDescription)
        }
        self.init(validatedEnvironment: definition, scene: scene, errorMessage: nil)
    }

    /// Allows an already loaded or generated environment to use the same world behavior.
    convenience init(environment: EnvironmentDefinition, scene: SCNScene) throws {
        self.init(validatedEnvironment: try environment.validated(), scene: scene, errorMessage: nil)
    }

    private init(validatedEnvironment: EnvironmentDefinition, scene: SCNScene, errorMessage: String?) {
        self.environment = validatedEnvironment
        self.scene = scene
        self.errorMessage = errorMessage
        environmentNodes = scene.rootNode.childNodes
        let optics = SCNCamera()
        optics.projectionDirection = .horizontal
        optics.fieldOfView = CGFloat(environment.camera.horizontalFieldOfView)
        optics.zNear = 0.03
        optics.zFar = 30
        optics.wantsHDR = true
        optics.wantsExposureAdaptation = false
        optics.exposureOffset = -0.65
        optics.bloomIntensity = 0.3
        optics.bloomThreshold = 1.1
        optics.bloomBlurRadius = 8
        optics.screenSpaceAmbientOcclusionIntensity = 0.65
        optics.screenSpaceAmbientOcclusionRadius = 0.35
        camera.camera = optics
        camera.simdPosition = environment.camera.position.vector
        scene.rootNode.addChildNode(camera)
        camera.simdLook(at: environment.camera.lookAt.vector)
        homeView = camera.simdOrientation
        let forward = homeView.act(SIMD3(0, 0, -1))
        homeHeading = simd_quatf(angle: atan2(-forward.x, -forward.z), axis: SIMD3(0, 1, 0))
        homePitch = asin(forward.y)
        scene.background.contents = environment.background.uiColor
        for light in environment.lights { addLight(light) }
    }

    func setSeeThrough(_ enabled: Bool) {
        guard isSeeThrough != enabled else { return }
        isSeeThrough = enabled
        for root in environmentNodes {
            root.isHidden = enabled
            root.categoryBitMask = enabled ? 0 : 1
            root.enumerateChildNodes { node, _ in node.categoryBitMask = enabled ? 0 : 1 }
        }
        // Transparent pixels let the host composite optical AR without an opaque hall.
        scene.background.contents = enabled ? UIColor.clear : environment.background.uiColor
        // Approximate horizontal field of view of the Air 2's 16:9 image.
        camera.camera?.fieldOfView = enabled ? 40 : CGFloat(environment.camera.horizontalFieldOfView)
        viewRevision += 1
    }

    /// Recolors only the authored hall. Simulation time freezes the effect during a pause.
    /// Hidden hall surfaces remain hidden in optical see-through mode.
    func setTransfigurationPhase(_ phase: TimeInterval?) {
        let next = phase.flatMap { $0.isFinite && (0..<SurvivalState.nyanDuration).contains($0) ? $0 : nil }
        guard next != transfigurationPhase else { return }
        let wasActive = transfigurationPhase != nil
        transfigurationPhase = next
        if let next {
            if rainbowSurfaces.isEmpty { prepareRainbowSurfaces() }
            if !wasActive {
                for surface in rainbowSurfaces { surface.geometry.materials = surface.rainbow }
            }
            let uniform = NSNumber(value: Float(next))
            for material in rainbowMaterials { material.setValue(uniform, forKey: "rainbowPhase") }
        } else if wasActive {
            for surface in rainbowSurfaces { surface.geometry.materials = surface.originals }
        }
    }

    private func prepareRainbowSurfaces() {
        var copies: [ObjectIdentifier: SCNMaterial] = [:]
        var geometries = Set<ObjectIdentifier>()
        func prepare(_ node: SCNNode) {
            guard let geometry = node.geometry, geometries.insert(ObjectIdentifier(geometry)).inserted else { return }
            let originals = geometry.materials
            let rainbow = originals.map { original -> SCNMaterial in
                let key = ObjectIdentifier(original)
                if let cached = copies[key] { return cached }
                let material = original.copy() as! SCNMaterial
                material.name = "Rainbow hall: \(original.name ?? "surface")"
                var modifiers = original.shaderModifiers ?? [:]
                // World coordinates keep the bands continuous across tiles, columns, and walls.
                // This adds no geometry, texture uploads, transparent passes, or scene lights.
                let existing = modifiers[.surface] ?? "#pragma body\n"
                modifiers[.surface] =
                    "#pragma arguments\nfloat rainbowPhase;\n" + existing + "\n" + """
                        float3 rainbowWorld = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
                        float rainbowHue = rainbowWorld.x * 0.095 + rainbowWorld.z * 0.055
                            + rainbowWorld.y * 0.075 + rainbowPhase * 0.035;
                        float3 rainbowColor = clamp(abs(fract(rainbowHue + float3(0.0, 0.666667, 0.333333))
                            * 6.0 - 3.0) - 1.0, 0.0, 1.0);
                        rainbowColor = mix(float3(0.12), float3(1.0), rainbowColor);
                        float rainbowDetail = dot(_surface.diffuse.rgb, float3(0.2126, 0.7152, 0.0722));
                        _surface.diffuse.rgb = rainbowColor * (0.42 + 0.58 * rainbowDetail);
                        _surface.emission.rgb = mix(_surface.emission.rgb, rainbowColor * 0.28, 0.85);
                        """
                material.shaderModifiers = modifiers
                material.setValue(NSNumber(value: 0), forKey: "rainbowPhase")
                copies[key] = material
                return material
            }
            rainbowSurfaces.append(RainbowSurface(geometry: geometry, originals: originals, rainbow: rainbow))
        }
        for root in environmentNodes {
            prepare(root)
            root.enumerateChildNodes { node, _ in prepare(node) }
        }
        rainbowMaterials = Array(copies.values)
    }

    func setHeadPose(
        _ pose: simd_quatf?, gravityReferenced: Bool = false,
        at time: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        guard let pose else {
            if isHeadTracked {
                latestHead = nil
                referenceHead = nil
                latestHeadTime = nil
                centerView()
            }
            return
        }
        if usesGravityReference != gravityReferenced {
            referenceHead = nil
            usesGravityReference = gravityReferenced
        }
        let anchor = referenceHead ?? reference(for: pose)
        if referenceHead == nil { headFilter.reset(at: time) }
        referenceHead = anchor
        latestHead = pose
        latestHeadTime = time
        let delta = headFilter.update(anchor.inverse * pose, at: time)
        var next = simd_normalize(homeHeading * delta * simd_quatf(angle: homePitch, axis: SIMD3(1, 0, 0)))
        #if targetEnvironment(macCatalyst)
            next = HeadHorizon.upright(next, previous: camera.simdOrientation)
        #endif
        if simd_length_squared(next.vector - camera.simdOrientation.vector) > 0.00000001
            && simd_length_squared(next.vector + camera.simdOrientation.vector) > 0.00000001
        {
            camera.simdOrientation = next
            viewRevision += 1
        }
    }

    func centerView() {
        referenceHead = latestHead.map { reference(for: $0) }
        headFilter.reset(at: latestHeadTime)
        camera.simdOrientation = homeView
        viewRevision += 1
    }

    private func reference(for pose: simd_quatf) -> simd_quatf {
        guard usesGravityReference else { return pose }
        let forward = pose.act(SIMD3<Float>(0, 0, -1))
        return simd_quatf(angle: atan2(-forward.x, -forward.z), axis: SIMD3(0, 1, 0))
    }

    func castingPoint() -> SIMD3<Float> {
        let origin = camera.simdWorldPosition
        let forward = camera.simdWorldOrientation.act(SIMD3<Float>(0, 0, -1))
        let options: [String: Any] = [
            SCNHitTestOption.categoryBitMask.rawValue: 1,
            SCNHitTestOption.backFaceCulling.rawValue: false,
            SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue,
        ]
        // Commit the latest camera and room transforms before casting the central ray.
        SCNTransaction.flush()
        let hits = scene.rootNode.hitTestWithSegment(
            from: SCNVector3(origin),
            to: SCNVector3(origin + forward * 6), options: options)
        let nearest = hits.map { simd_distance(origin, SIMD3<Float>($0.worldCoordinates)) }.min()
        // Pull the effect toward the viewer so its geometry stays in front of the surface.
        let distance = nearest.map { max(0.08, $0 - min(0.24, $0 * 0.25)) } ?? 2
        return origin + forward * distance
    }

    private func addLight(_ definition: EnvironmentDefinition.Light) {
        let node = SCNNode()
        let light = SCNLight()
        light.type = definition.kind == .ambient ? .ambient : .omni
        light.color = definition.color.uiColor
        light.intensity = CGFloat(definition.intensity)
        if definition.kind == .omni {
            light.attenuationStartDistance = CGFloat(definition.attenuationStart)
            light.attenuationEndDistance = CGFloat(definition.attenuationEnd)
            light.attenuationFalloffExponent = CGFloat(definition.falloffExponent)
        }
        node.light = light
        node.simdPosition = definition.position.vector
        scene.rootNode.addChildNode(node)
    }

    func performRune(_ kind: RuneKind?, at worldPoint: SIMD3<Float>) {
        guard worldPoint.x.isFinite, worldPoint.y.isFinite, worldPoint.z.isFinite else { return }
        switch kind {
        case .fireball:
            RuneEffects.fireball(in: scene, from: camera, to: worldPoint)
        case .summon:
            RuneEffects.summon(in: scene, at: worldPoint, facing: camera.simdWorldPosition)
        case .zap:
            strike(at: worldPoint)
        case .revelio:
            RuneEffects.revelio(in: scene, at: worldPoint, from: camera)
        case .lumos:
            RuneEffects.lumos(in: scene, from: camera)
        case .patronus:
            RuneEffects.patronus(in: scene, at: worldPoint, from: camera)
        case .ice, .shield, .nyan:
            break  // Combat owns these effects and their resource checks.
        case nil:
            RuneEffects.sparkBurst(in: scene, at: worldPoint, facing: camera)
        }
    }

    private func strike(at point: SIMD3<Float>) {
        let impact = SCNNode()
        impact.simdPosition = point
        scene.rootNode.addChildNode(impact)
        let bolt = SCNMaterial()
        bolt.lightingModel = .constant
        bolt.diffuse.contents = UIColor(red: 0.82, green: 0.90, blue: 1, alpha: 1)
        bolt.emission.contents = UIColor(red: 0.16, green: 0.35, blue: 0.95, alpha: 1)
        let corners: [SIMD3<Float>] = [
            SIMD3(-0.13, 0.68, 0), SIMD3(0.04, 0.41, 0.02),
            SIMD3(-0.08, 0.39, 0.02), SIMD3(0.04, 0.17, 0), .zero,
        ]
        for (a, b) in zip(corners, corners.dropFirst()) {
            let segment = SCNCylinder(radius: 0.008, height: CGFloat(simd_distance(a, b)))
            segment.firstMaterial = bolt
            let node = SCNNode(geometry: segment)
            node.categoryBitMask = 2
            node.simdPosition = (a + b) / 2
            node.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(b - a))
            impact.addChildNode(node)
        }
        let glow = SCNLight()
        glow.type = .omni
        glow.color = UIColor(red: 0.40, green: 0.67, blue: 1, alpha: 1)
        glow.intensity = 240
        glow.attenuationEndDistance = 1.2
        impact.light = glow
        impact.runAction(.sequence([.wait(duration: 0.16), .fadeOut(duration: 0.30), .removeFromParentNode()]))
    }

}

extension EnvironmentDefinition.Color {
    fileprivate var uiColor: UIColor {
        UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: 1)
    }
}
