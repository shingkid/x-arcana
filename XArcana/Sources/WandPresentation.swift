import SceneKit
import UIKit

/// A camera-mounted prop whose luminous tip projects onto the rune's live endpoint.
@MainActor
final class WandPresentation {
    enum Mode { case wand, bow }
    private(set) var mode: Mode = .wand
    var aimingNode: SCNNode { mode == .wand ? tip : bowAim }

    private let camera: SCNNode
    private let wand = SCNNode()
    private let swing = SCNNode()
    private let bow = SCNNode()
    private let tip = SCNNode()
    private let bowAim = SCNNode()
    private let glow = SCNMaterial()
    private var viewport = CGSize(width: 16, height: 9)
    private var aim = CGPoint(x: 0.5, y: 0.5)
    private var drawing = false
    private let wandLength: Float = 0.72
    private let propCategory = 1 << 20

    init(camera: SCNNode) {
        self.camera = camera
        wand.name = "wandPresentation"
        bow.name = "bowPresentation"
        tip.name = "wandTip"
        bowAim.name = "bowAim"
        bow.addChildNode(bowAim)
        buildWand()
        buildBow()
        swing.name = "wandMeleeSweep"
        swing.addChildNode(wand)
        camera.addChildNode(swing)
        camera.addChildNode(bow)
        bow.isHidden = true
        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .omni
        light.light?.color = UIColor(red: 1, green: 0.82, blue: 0.58, alpha: 1)
        light.light?.intensity = 45
        light.light?.categoryBitMask = propCategory
        light.position = SCNVector3(-0.2, 0.2, -0.1)
        camera.addChildNode(light)
        update(aim: aim, isDrawing: false)
    }

    func updateViewport(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        viewport = size
        positionProps()
    }

    func setMode(_ mode: Mode) {
        resetMelee()
        self.mode = mode
        wand.isHidden = mode != .wand
        bow.isHidden = mode != .bow
        if mode == .bow { resetArrow() }
    }

    func update(aim: CGPoint, isDrawing: Bool) {
        guard aim.x.isFinite, aim.y.isFinite else { return }
        self.aim = aim
        if isDrawing && !drawing { resetArrow() }
        drawing = isDrawing
        glow.emission.contents =
            isDrawing
            ? UIColor(red: 1, green: 0.73, blue: 0.25, alpha: 1) : UIColor(red: 0.42, green: 0.73, blue: 1, alpha: 1)
        positionProps()
    }

    func cast() {
        tip.removeAction(forKey: "cast")
        tip.runAction(.sequence([.scale(to: 2.8, duration: 0.07), .scale(to: 1, duration: 0.3)]), forKey: "cast")
    }

    func melee() {
        guard mode == .wand else { return }
        resetMelee()
        swing.runAction(
            .sequence([
                .group([
                    .rotateBy(x: 0.14, y: -0.18, z: 0.55, duration: 0.10),
                    .moveBy(x: -0.07, y: 0.02, z: -0.04, duration: 0.10),
                ]),
                .group([
                    .rotateTo(x: 0, y: 0, z: 0, duration: 0.24),
                    .move(to: SCNVector3Zero, duration: 0.24),
                ]),
            ]), forKey: "melee")
    }

    func resetMelee() {
        swing.removeAction(forKey: "melee")
        swing.position = SCNVector3Zero
        swing.eulerAngles = SCNVector3Zero
    }

    func shoot() {
        bow.removeAction(forKey: "release")
        bow.eulerAngles = SCNVector3Zero
        bow.runAction(
            .sequence([
                .rotateBy(x: 0, y: -0.11, z: 0, duration: 0.09),
                .rotateBy(x: 0, y: 0.11, z: 0, duration: 0.22),
            ]), forKey: "release")
        if let arrow = bow.childNode(withName: "nockedArrow", recursively: false) {
            arrow.removeAllActions()
            arrow.position = SCNVector3Zero
            arrow.opacity = 1
            arrow.runAction(
                .sequence([
                    .wait(duration: 0.08),
                    .group([
                        .moveBy(x: 0, y: 0, z: -2, duration: 0.25), .fadeOut(duration: 0.25),
                    ]), .move(to: SCNVector3Zero, duration: 0), .fadeIn(duration: 0.18),
                ]))
        }
        positionProps()
    }

    private func resetArrow() {
        guard let arrow = bow.childNode(withName: "nockedArrow", recursively: false) else { return }
        arrow.removeAllActions()
        arrow.position = SCNVector3Zero
        arrow.opacity = 1
    }

    private func positionProps() {
        let endpoint = cameraPoint(aim, depth: 0.85)
        let grip = cameraPoint(CGPoint(x: 0.80, y: 1.10), depth: 0.38)
        let direction = endpoint - grip
        let fov = Float(camera.camera?.fieldOfView ?? 74) * .pi / 180
        let apparentScale = tan(fov / 2) / tan(Float(74) * .pi / 360)
        wand.simdPosition = grip
        wand.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(direction))
        wand.simdScale = SIMD3(0.7 * apparentScale, simd_length(direction) / wandLength, 0.7 * apparentScale)
        bow.simdPosition = endpoint
        bow.simdScale = SIMD3(repeating: apparentScale)
    }

    private func cameraPoint(_ point: CGPoint, depth: Float) -> SIMD3<Float> {
        let aspect = Float(viewport.width / viewport.height)
        let fov = Float(camera.camera?.fieldOfView ?? 74) * .pi / 180
        let extent = tan(fov / 2) * depth
        let horizontal = camera.camera?.projectionDirection != .vertical
        let halfWidth = horizontal ? extent : extent * aspect
        let halfHeight = horizontal ? extent / aspect : extent
        return SIMD3(
            (Float(point.x) * 2 - 1) * halfWidth,
            (1 - Float(point.y) * 2) * halfHeight, -depth)
    }

    private func buildWand() {
        let wood = material(UIColor(red: 0.25, green: 0.105, blue: 0.045, alpha: 1))
        wood.diffuse.contents = woodTexture()
        let darkWood = material(UIColor(red: 0.09, green: 0.035, blue: 0.02, alpha: 1))
        let brass = material(UIColor(red: 0.59, green: 0.39, blue: 0.16, alpha: 1))
        brass.metalness.contents = 0.65
        brass.roughness.contents = 0.35
        let handle = SCNCone(topRadius: 0.018, bottomRadius: 0.026, height: 0.18)
        add(handle, material: wood, at: SIMD3(0, 0.09, 0), to: wand)
        let shaft = SCNCone(topRadius: 0.003, bottomRadius: 0.015, height: 0.54)
        add(shaft, material: wood, at: SIMD3(0, 0.45, 0), to: wand)
        for y in [Float(0.012), 0.17, 0.19] {
            let ring = SCNTorus(ringRadius: y < 0.02 ? 0.025 : 0.017, pipeRadius: 0.0025)
            add(ring, material: brass, at: SIMD3(0, y, 0), to: wand)
        }
        // Raised roots wind around the grip and taper into the shaft.
        for strand in 0..<3 {
            var last: SIMD3<Float>?
            for step in 0...40 {
                let progress = Float(step) / 40
                let angle = progress * .pi * 4.3 + Float(strand) * .pi * 2 / 3
                let radius: Float = 0.027 - progress * 0.012
                let point = SIMD3(cos(angle) * radius, 0.02 + progress * 0.25, sin(angle) * radius)
                if let last { segment(from: last, to: point, radius: 0.0018, material: darkWood, parent: wand) }
                last = point
            }
        }
        glow.lightingModel = .constant
        glow.diffuse.contents = UIColor.white
        glow.emission.contents = UIColor(red: 0.42, green: 0.73, blue: 1, alpha: 1)
        glow.readsFromDepthBuffer = false
        let pearl = SCNSphere(radius: 0.005)
        pearl.segmentCount = 12
        pearl.materials = [glow]
        tip.geometry = pearl
        tip.position = SCNVector3(0, wandLength, 0)
        tip.renderingOrder = 102
        tip.categoryBitMask = propCategory
        wand.addChildNode(tip)
    }

    private func buildBow() {
        let wood = material(UIColor(red: 0.35, green: 0.16, blue: 0.065, alpha: 1))
        let gold = material(UIColor(red: 0.78, green: 0.53, blue: 0.21, alpha: 1))
        let string = material(UIColor(red: 0.93, green: 0.82, blue: 0.60, alpha: 1))
        var last: SIMD3<Float>?
        for index in 0...32 {
            let t = Float(index) / 32
            let point = SIMD3<Float>(-0.13 * sin(t * .pi), (t - 0.5) * 0.64, 0.06)
            if let last { segment(from: last, to: point, radius: 0.008, material: wood, parent: bow) }
            last = point
        }
        segment(
            from: SIMD3(0, -0.32, 0.06), to: SIMD3(0.04, 0, 0.3), radius: 0.001,
            material: string, parent: bow)
        segment(
            from: SIMD3(0.04, 0, 0.3), to: SIMD3(0, 0.32, 0.06), radius: 0.001,
            material: string, parent: bow)
        segment(
            from: SIMD3(-0.13, -0.05, 0.06), to: SIMD3(-0.13, 0.05, 0.06), radius: 0.013,
            material: gold, parent: bow)
        let arrow = SCNNode()
        arrow.name = "nockedArrow"
        bow.addChildNode(arrow)
        segment(
            from: SIMD3(0.04, 0, 0.30), to: SIMD3(0, 0, 0), radius: 0.003,
            material: string, parent: arrow)
        let head = SCNCone(topRadius: 0, bottomRadius: 0.011, height: 0.035)
        let arrowhead = add(head, material: gold, at: SIMD3(0, 0, -0.012), to: arrow)
        arrowhead.eulerAngles.x = -.pi / 2
        for side: Float in [-1, 1] {
            let feather = SCNBox(width: 0.018, height: 0.002, length: 0.045, chamferRadius: 0.002)
            add(feather, material: gold, at: SIMD3(0.04 + side * 0.009, 0, 0.27), to: arrow)
        }
    }

    private func material(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.emission.contents = color.withAlphaComponent(0.20)
        material.emission.intensity = 0.08
        material.roughness.contents = 0.66
        material.readsFromDepthBuffer = true
        material.writesToDepthBuffer = true
        return material
    }

    @discardableResult
    private func add(_ geometry: SCNGeometry, material: SCNMaterial, at point: SIMD3<Float>, to parent: SCNNode)
        -> SCNNode
    {
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.simdPosition = point
        node.categoryBitMask = propCategory
        node.renderingOrder = 100
        parent.addChildNode(node)
        return node
    }

    private func segment(
        from start: SIMD3<Float>, to end: SIMD3<Float>, radius: CGFloat,
        material: SCNMaterial, parent: SCNNode
    ) {
        let delta = end - start
        let cylinder = SCNCylinder(radius: radius, height: CGFloat(simd_length(delta)))
        cylinder.radialSegmentCount = 8
        let node = add(cylinder, material: material, at: (start + end) / 2, to: parent)
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(delta))
    }

    private func woodTexture() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 128, height: 512)).image { context in
            UIColor(red: 0.25, green: 0.105, blue: 0.045, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 128, height: 512))
            for line in 0..<48 {
                let path = UIBezierPath()
                let x = CGFloat(line) * 2.8
                path.move(to: CGPoint(x: x, y: 0))
                for step in 1...32 {
                    let y = CGFloat(step) * 16
                    let bend = sin(y * 0.027 + CGFloat(line) * 0.9) * 2.8
                    path.addLine(to: CGPoint(x: x + bend, y: y))
                }
                UIColor(red: 0.055, green: 0.022, blue: 0.009, alpha: line.isMultiple(of: 3) ? 0.65 : 0.30).setStroke()
                path.lineWidth = line.isMultiple(of: 3) ? 1.1 : 0.5
                path.stroke()
            }
        }
    }
}
