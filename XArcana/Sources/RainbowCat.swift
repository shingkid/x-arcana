import SceneKit
import UIKit
import simd

/// Procedural pixel extrusion of the Nyan Cat character, created by Chris Torres.
/// Shared meshes and the combat clock keep a transformed horde bounded and pause-safe.
final class RainbowCat {
    let node = SCNNode()
    private var time: TimeInterval = 0
    private let floorY: Float
    private let anchored: Bool
    private let phaseOffset: Float
    private weak var camera: SCNNode?
    private struct Waypoint {
        let position: SIMD2<Float>
        let time: TimeInterval
    }
    private let route: [Waypoint]
    private var legs: [SCNNode] = []
    private let tail: SCNNode
    private var trail: [SCNNode] = []
    private static let pixel: Float = 0.035
    private static let footX: [Float] = [-0.30, -0.13, 0.23, 0.43]

    // This pixel map is the reproducible mesh definition. No downloaded image or texture is used.
    // K: outline, T: crust, P: frosting, S: sprinkles, G: fur, W: eye shine, C: cheeks.
    private static let body = pixelGeometry([
        ".......KKKKKKKKKKKKKKKK...........",
        ".....KKTTTTTTTTTTTTTTTTKK.........",
        "....KTTTPPPPPPPPPPPPPPTTTK........",
        "....KTPPPPSPPPPPPPSPPPPPTK........",
        "....KTPPPPPPPPPPPPPPPPPPTK........",
        "....KTPPPPPPPPSPPPPPPPPKKK....KK..",
        "....KTPSPPPPPPPPPPPPPPKGGK...KGGK.",
        "....KTPPPPPPPPPPPPPPPSKGGGK.KGGGK.",
        "....KTPPPPPPPPPPPPPPPPKGGGK.KGGGK.",
        "....KTPPPPPSPPPPPPPPPPKGGGGGGGGGK.",
        "....KTPPPPPPPPPPPSPPPKGGGGGGGGGGGK",
        "....KTPPPPPPPPPPPPPPPKGGWKGGGGWKGK",
        "....KTPPSPPPPPPPPPPPPKGGKKGGGGKKGK",
        "....KTPPPPPPPPSPPPPPSKGGGGGKKGGGGK",
        "....KTTTPPPPPPPPPPPPPKCCGKGGGGKCCK",
        ".....KKTTTTTTTTTTTTTTKGGGKGGGGKGGK",
        ".......KKKKKKKKKKKKKKKGGGGKKKKGGGK",
        "......................KGGGGGGGGGK.",
        ".......................KKKKKKKKK..",
        "..................................",
    ])
    private static let foot = pixelGeometry(["KKK..", "KGGK.", "KGGGK", ".KKK."])
    private static let tailMesh = pixelGeometry(["KK....", "KGGK..", ".KGGK.", "..KGGK", "...KK."])
    private static let palette: [Character: SIMD4<Float>] = [
        "K": SIMD4(0.015, 0.015, 0.02, 1), "T": SIMD4(1, 0.80, 0.60, 1),
        "P": SIMD4(1, 0.60, 0.80, 1), "S": SIMD4(1, 0.20, 0.60, 1),
        "G": SIMD4(0.60, 0.60, 0.60, 1), "W": SIMD4(1, 1, 1, 1),
        "C": SIMD4(1, 0.60, 0.60, 1),
    ]
    private static let pixelMaterial = material(.white)
    private static let rainbow: [SCNGeometry] = [
        UIColor(red: 1, green: 0, blue: 0, alpha: 1),
        UIColor(red: 1, green: 0.60, blue: 0, alpha: 1),
        UIColor(red: 1, green: 1, blue: 0, alpha: 1),
        UIColor(red: 0.20, green: 1, blue: 0, alpha: 1),
        UIColor(red: 0, green: 0.60, blue: 1, alpha: 1),
        UIColor(red: 0.40, green: 0.20, blue: 1, alpha: 1),
    ].map { color in
        let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
        box.materials = [material(color)]
        return box
    }

    init(
        parent: SCNNode, floorY: Float, anchored: Bool = false, phaseOffset: Float = 0,
        camera: SCNNode? = nil
    ) {
        self.floorY = floorY
        self.anchored = anchored
        self.phaseOffset = phaseOffset
        self.camera = camera
        route = Self.makeRoute(seed: phaseOffset.bitPattern)
        tail = SCNNode(geometry: Self.tailMesh)
        node.name = anchored ? "Transfigured Nyan cat" : "Rainbow cat"
        node.categoryBitMask = 2
        _ = piece(Self.body, name: "Pastry cat body")
        for index in 0..<4 {
            let leg = piece(Self.foot, name: "Rainbow cat leg \(index + 1)")
            legs.append(leg)
        }
        tail.name = "Rainbow cat tail"
        tail.categoryBitMask = 2
        tail.castsShadow = false
        tail.renderingOrder = 2
        node.addChildNode(tail)
        for band in 0..<6 {
            let stripe = piece(Self.rainbow[band], name: "Rainbow trail")
            stripe.simdScale = SIMD3(1.25, Self.pixel * 2.8, Self.pixel)
            stripe.opacity = 0.8
            stripe.renderingOrder = 1
            trail.append(stripe)
        }
        parent.addChildNode(node)
        update(deltaTime: 0)
    }

    func remove() { node.removeFromParentNode() }

    func update(deltaTime: TimeInterval) {
        guard deltaTime.isFinite, deltaTime >= 0 else { return }
        time += deltaTime
        let animationTime = Float(time) + phaseOffset
        if anchored, let camera {
            // Camera-relative routes remain visible after a head turn. The original enemy stays
            // still and untargetable; its scale and heading must not distort the pixel silhouette.
            let depth: Float = 4
            let fov = Float(camera.camera?.fieldOfView ?? 74) * .pi / 180
            let halfWidth = depth * tan(min(100 * .pi / 180, max(20 * .pi / 180, fov)) / 2)
            let sample = routeSample(at: time)
            let x = sample.position.x * halfWidth
            let y = sample.position.y * halfWidth
            let scale = halfWidth * 0.27 / (34 * Self.pixel)
            let heading: Float = sample.velocity.x >= 0 ? 1 : -1
            var placement = matrix_identity_float4x4
            placement.columns.0.x = scale * heading
            placement.columns.1.y = scale
            placement.columns.2.z = scale
            placement.columns.3 = SIMD4(x, y, -depth, 1)
            node.simdWorldTransform = camera.simdWorldTransform * placement
        } else if anchored {
            node.simdPosition = SIMD3(0, floorY + 1.05 + sin(animationTime * 2) * 0.12, 0)
            node.simdScale = SIMD3(repeating: 0.7)
        } else {
            let phase = animationTime * 0.6
            node.simdPosition = SIMD3(
                sin(phase) * 1.6, floorY + 2.25 + sin(animationTime * 2) * 0.12,
                -1.1 + cos(phase) * 1.2)
        }
        let reducedMotion = UIAccessibility.isReduceMotionEnabled
        for (index, leg) in legs.enumerated() {
            let run = sin(animationTime * 13 + Float(index % 2) * .pi)
            leg.simdPosition = SIMD3(
                Self.footX[index] + run * (reducedMotion ? 0.008 : Self.pixel),
                -0.31 + abs(run) * (reducedMotion ? 0.004 : Self.pixel * 0.7), 0)
        }
        tail.simdPosition = SIMD3(-0.54, -0.12 + sin(animationTime * 7) * (reducedMotion ? 0.004 : 0.025), -0.01)
        for (band, stripe) in trail.enumerated() {
            // Whole-pixel steps keep the six full-height bands faithful to the pixel character.
            let step: Float = reducedMotion ? 0 : (sin(animationTime * 7) >= 0 ? Self.pixel : -Self.pixel)
            stripe.simdPosition = SIMD3(-1.04, 0.23 - Float(band) * Self.pixel * 2.8 + step, -0.04)
        }
    }

    private static func makeRoute(seed: UInt32) -> [Waypoint] {
        var state = UInt64(seed) ^ 0x9E37_79B9
        func random() -> Float {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(state >> 40) / Float(1 << 24)
        }
        var points: [Waypoint] = []
        var previous = SIMD2<Float>(random() * 2 - 1, random() * 2 - 1)
        var time: TimeInterval = -2
        // Forty bounded waypoints cover much longer than the curse. Each cat has its own seed,
        // speeds and turns; the complete route is allocated once, before the render loop.
        for index in 0..<40 {
            var next = SIMD2<Float>(random() * 2 - 1, random() * 2 - 1)
            for _ in 0..<12 where simd_distance(next, previous) < 0.9 {
                next = SIMD2<Float>(random() * 2 - 1, random() * 2 - 1)
            }
            if index == 1 { time = 0 }
            points.append(Waypoint(position: next * SIMD2(0.68, 0.25), time: time))
            time += 1.25 + Double(random()) * 1.5
            previous = next
        }
        return points
    }

    private func routeSample(at time: TimeInterval) -> (position: SIMD2<Float>, velocity: SIMD2<Float>) {
        var index = 1
        while index < route.count - 3, time >= route[index + 1].time { index += 1 }
        let previous = route[index - 1]
        let start = route[index]
        let end = route[index + 1]
        let next = route[index + 2]
        let duration = Float(end.time - start.time)
        let t = Float(min(1, max(0, (time - start.time) / Double(duration))))
        let t2 = t * t
        let t3 = t2 * t
        let v0 = (end.position - previous.position) / Float(end.time - previous.time) * duration * 0.7
        let v1 = (next.position - start.position) / Float(next.time - start.time) * duration * 0.7
        let position =
            (2 * t3 - 3 * t2 + 1) * start.position + (t3 - 2 * t2 + t) * v0
            + (-2 * t3 + 3 * t2) * end.position + (t3 - t2) * v1
        let velocity =
            (6 * t2 - 6 * t) * start.position + (3 * t2 - 4 * t + 1) * v0
            + (-6 * t2 + 6 * t) * end.position + (3 * t2 - 2 * t) * v1
        return (simd_clamp(position, SIMD2(-0.73, -0.29), SIMD2(0.73, 0.29)), velocity)
    }

    @discardableResult
    private func piece(_ geometry: SCNGeometry, name: String) -> SCNNode {
        let child = SCNNode(geometry: geometry)
        child.name = name
        child.categoryBitMask = 2
        child.castsShadow = false
        child.renderingOrder = 2
        node.addChildNode(child)
        return child
    }

    private static func pixelGeometry(_ rows: [String]) -> SCNGeometry {
        let width = rows[0].count
        precondition(rows.allSatisfy { $0.count == width })
        var vertices: [SCNVector3] = []
        var colors: [SIMD4<Float>] = []
        var indices: [UInt32] = []
        // Merge each horizontal color run into a square-edged extrusion. One vertex-color
        // material renders the entire character; no texture, chamfer, particles, or lights.
        for (y, row) in rows.enumerated() {
            let pixels = Array(row)
            var x = 0
            while x < width {
                guard let srgb = palette[pixels[x]] else {
                    x += 1
                    continue
                }
                // SceneKit vertex colors are linear, while the authored pixel palette is sRGB.
                func linear(_ value: Float) -> Float {
                    value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
                }
                let color = SIMD4(linear(srgb.x), linear(srgb.y), linear(srgb.z), srgb.w)
                let start = x
                while x < width, pixels[x] == pixels[start] { x += 1 }
                let left = (Float(start) - Float(width) / 2) * pixel
                let right = (Float(x) - Float(width) / 2) * pixel
                let top = (Float(rows.count) / 2 - Float(y)) * pixel
                let bottom = top - pixel
                let front = pixel / 2
                let back = -front
                let corners: [SCNVector3] = [
                    SCNVector3(left, bottom, front), SCNVector3(right, bottom, front),
                    SCNVector3(right, top, front), SCNVector3(left, top, front),
                    SCNVector3(left, bottom, back), SCNVector3(right, bottom, back),
                    SCNVector3(right, top, back), SCNVector3(left, top, back),
                ]
                let base = UInt32(vertices.count)
                vertices.append(contentsOf: corners)
                colors.append(contentsOf: repeatElement(color, count: 8))
                for index: UInt32 in [
                    0, 1, 2, 0, 2, 3, 5, 4, 7, 5, 7, 6,
                    4, 0, 3, 4, 3, 7, 1, 5, 6, 1, 6, 2,
                    3, 2, 6, 3, 6, 7, 4, 5, 1, 4, 1, 0,
                ] { indices.append(base + index) }
            }
        }
        let colorSource = colors.withUnsafeBytes { bytes in
            SCNGeometrySource(
                data: Data(bytes), semantic: .color, vectorCount: colors.count,
                usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride)
        }
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), colorSource],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [pixelMaterial]
        return geometry
    }

    private static func material(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.readsFromDepthBuffer = false
        material.writesToDepthBuffer = false
        return material
    }
}
