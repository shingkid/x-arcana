import SceneKit
import UIKit

/// Persistent companions built from the supplied portrait-character model.
/// Albert preserves the original body; Alan uses a simple male placeholder and racket.
enum PortraitSummons {
    private static let prototypes: [String: SCNNode] = {
        ["alan": "AlanCharacter", "albert": "PortraitCharacter"].compactMapValues { name in
            guard let url = resource(name, extension: "usdz"),
                let source = try? SCNScene(url: url, options: [.convertToYUp: true])
            else { return nil }
            let node = ScenePerformance.independentClone(of: source.rootNode)
            guard CharacterAnimation.install(on: node, asset: name, directory: "Fantasy") else { return nil }
            return node
        }
    }()

    private static var appearances: [String: SCNNode] = [:]

    static func prewarm() -> [SCNNode] {
        ["alan", "albert"].compactMap { prepared(key: $0) }
    }

    @discardableResult
    static func summon(
        name: String, in scene: SCNScene, at point: SIMD3<Float>,
        facing camera: SCNNode, environment: EnvironmentDefinition = .fantasy
    ) -> SCNNode? {
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { return nil }
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let template = prepared(key: key) else { return nil }
        let root = ScenePerformance.independentClone(of: template)
        root.name = "summon.\(key).\(UUID().uuidString)"
        root.simdPosition = placement(near: point, in: scene, camera: camera, environment: environment)
        let toward = camera.simdWorldPosition - root.simdPosition
        root.eulerAngles.y = atan2(toward.x, toward.z)
        scene.rootNode.addChildNode(root)
        root.opacity = 0
        root.runAction(.fadeIn(duration: 0.65))
        root.childNode(withName: "PortraitHalo", recursively: false)?.runAction(
            .repeatForever(
                .sequence([
                    .fadeOpacity(to: 0.45, duration: 1.8), .fadeOpacity(to: 1, duration: 1.8),
                ])))
        CharacterAnimation.play("idle", on: root, loop: true)
        return root
    }

    private static func prepared(key: String) -> SCNNode? {
        let identity = key == "albert" ? "albert" : "alan"
        if let cached = appearances[identity] { return cached }
        guard let prototype = prototypes[identity] else { return nil }
        let model = ScenePerformance.independentClone(of: prototype)
        let displayName = identity == "albert" ? "Albert" : "Alan"
        let color =
            identity == "albert"
            ? UIColor(red: 0.64, green: 0.48, blue: 1, alpha: 1)
            : UIColor(red: 0.22, green: 0.88, blue: 0.80, alpha: 1)
        let root = SCNNode()
        model.name = "PortraitBody"
        if identity == "albert" { model.simdScale = SIMD3(repeating: 1.2) }
        if identity == "alan" {
            model.enumerateChildNodes { node, _ in
                for material in node.geometry?.materials ?? [] {
                    material.roughness.contents = 0.95
                    material.metalness.contents = 0
                    material.specular.contents = UIColor(white: 0.06, alpha: 1)
                    material.normal.intensity = 0
                }
            }
        }
        root.addChildNode(model)

        if identity == "alan", let hand = CharacterAnimation.attachment("rightHand", on: root) {
            let racket = badmintonRacket()
            racket.name = "AlanBadmintonRacket"
            // The rig's local Y axis follows the hand toward the fingers.
            racket.position.y = 0.018
            hand.addChildNode(racket)
            let transform = hand.simdWorldTransform
            racket.simdScale = SIMD3(
                1 / simd_length(SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)),
                1 / simd_length(SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)),
                1 / simd_length(SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)))
        }

        let label = SCNText(string: displayName.uppercased(), extrusionDepth: 0.001)
        label.font = .systemFont(ofSize: 32, weight: .semibold)
        label.flatness = 0.1
        label.firstMaterial = material(color, emission: 0.5)
        let labelNode = SCNNode()
        labelNode.name = "PortraitName"
        let glyphs = SCNNode(geometry: label)
        let bounds = label.boundingBox
        let height = bounds.max.y - bounds.min.y
        let scale: Float = height > 0 ? 0.12 / height : 1
        glyphs.simdScale = SIMD3(repeating: scale)
        glyphs.simdPosition = SIMD3(-(bounds.min.x + bounds.max.x) * scale / 2, -bounds.min.y * scale, 0)
        labelNode.addChildNode(glyphs)
        labelNode.position = SCNVector3(0, identity == "albert" ? 2.27 : 1.94, 0)
        root.addChildNode(labelNode)

        let halo = SCNTorus(ringRadius: identity == "albert" ? 0.60 : 0.50, pipeRadius: 0.014)
        halo.firstMaterial = material(color, emission: 0.85)
        let haloNode = SCNNode(geometry: halo)
        haloNode.name = "PortraitHalo"
        haloNode.position.y = 0.025
        root.addChildNode(haloNode)
        let glow = SCNLight()
        glow.type = .omni
        glow.color = color
        glow.intensity = identity == "alan" ? 4 : 18
        glow.attenuationStartDistance = 0.1
        glow.attenuationEndDistance = 2.2
        let light = SCNNode()
        light.light = glow
        light.position = SCNVector3(0, 0.8, 0.7)
        root.addChildNode(light)
        root.enumerateChildNodes { node, _ in node.categoryBitMask = 2 }
        root.categoryBitMask = 2
        appearances[identity] = root
        return root
    }

    /// A light racket with a separate grip, shaft, oval rim, and woven strings.
    private static func badmintonRacket() -> SCNNode {
        let racket = SCNNode()
        let graphite = material(UIColor(red: 0.025, green: 0.055, blue: 0.07, alpha: 1))
        graphite.metalness.contents = 0.65
        graphite.roughness.contents = 0.28
        let teal = material(UIColor(red: 0.05, green: 0.85, blue: 0.74, alpha: 1))
        let string = material(UIColor(white: 0.94, alpha: 0.85))
        var vertices = [SCNVector3]()
        var normals = [SCNVector3]()
        var triangles = [[Int32]](repeating: [], count: 3)
        func rod(_ a: SIMD3<Float>, _ b: SIMD3<Float>, radius: CGFloat, material: SCNMaterial) {
            let direction = simd_normalize(b - a)
            let reference: SIMD3<Float> = abs(direction.z) < 0.9 ? SIMD3(0, 0, 1) : SIMD3(1, 0, 0)
            let u = simd_normalize(simd_cross(direction, reference))
            let v = simd_cross(direction, u)
            let offset = Int32(vertices.count)
            let part = material === graphite ? 0 : (material === teal ? 1 : 2)
            for end in [a, b] {
                for side in 0..<6 {
                    let angle = Float(side) / 6 * Float.pi * 2
                    let normal = u * cos(angle) + v * sin(angle)
                    vertices.append(SCNVector3(end + normal * Float(radius)))
                    normals.append(SCNVector3(normal))
                }
            }
            for side in 0..<6 {
                let i = offset + Int32(side)
                let j = offset + Int32((side + 1) % 6)
                triangles[part] += [i, j, i + 6, j, j + 6, i + 6]
            }
        }
        rod(SIMD3(0, -0.045, 0), SIMD3(0, 0.075, 0), radius: 0.014, material: graphite)
        for index in 0..<9 {
            let y = -Float(0.04) + Float(index) * 0.013
            for side in 0..<12 {
                let a = Float(side) / 12 * 2 * Float.pi
                let b = Float(side + 1) / 12 * 2 * Float.pi
                rod(
                    SIMD3(cos(a) * 0.014, y, sin(a) * 0.014),
                    SIMD3(cos(b) * 0.014, y, sin(b) * 0.014), radius: 0.0015, material: teal)
            }
        }
        rod(SIMD3(0, 0.075, 0), SIMD3(0, 0.38, 0), radius: 0.006, material: graphite)
        let center: Float = 0.47
        let rx: Float = 0.12
        let ry: Float = 0.155
        for index in 0..<48 {
            let a = Float(index) / 48 * 2 * Float.pi
            let b = Float(index + 1) / 48 * 2 * Float.pi
            rod(
                SIMD3(cos(a) * rx, center + sin(a) * ry, 0),
                SIMD3(cos(b) * rx, center + sin(b) * ry, 0), radius: 0.006,
                material: index.isMultiple(of: 3) ? teal : graphite)
        }
        for index in -6...6 {
            let x = Float(index) * 0.016
            let y = ry * sqrt(max(0, 1 - x * x / (rx * rx)))
            rod(SIMD3(x, center - y, 0), SIMD3(x, center + y, 0), radius: 0.0009, material: string)
        }
        for index in -8...8 {
            let y = Float(index) * 0.016
            let x = rx * sqrt(max(0, 1 - y * y / (ry * ry)))
            rod(SIMD3(-x, center + y, 0.001), SIMD3(x, center + y, 0.001), radius: 0.0009, material: string)
        }
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
            elements: triangles.map { SCNGeometryElement(indices: $0, primitiveType: .triangles) })
        geometry.materials = [graphite, teal, string]
        racket.geometry = geometry
        return racket
    }

    private static func placement(
        near point: SIMD3<Float>, in scene: SCNScene,
        camera: SCNNode, environment: EnvironmentDefinition
    ) -> SIMD3<Float> {
        var desired = SIMD3(point.x, environment.floorY, point.z)
        let cameraPoint = SIMD3(camera.simdWorldPosition.x, environment.floorY, camera.simdWorldPosition.z)
        if simd_distance(desired, cameraPoint) < 1.5 {
            var forward = camera.simdWorldOrientation.act(SIMD3<Float>(0, 0, -1))
            forward.y = 0
            if simd_length(forward) < 0.01 { forward = SIMD3(0, 0, -1) }
            desired = cameraPoint + simd_normalize(forward) * 2
        }
        let others = scene.rootNode.childNodes.filter {
            $0.name?.hasPrefix("summon.") == true || $0.name == "SummonedDemon" || $0.name == "Patronus"
        }
        for index in 0..<96 {
            let radius = index == 0 ? Float(0) : 0.7 * sqrt(Float(index))
            let angle = Float(index) * 2.399963
            let candidate = environment.movementBounds.clamped(
                SIMD3(
                    desired.x + cos(angle) * radius,
                    environment.floorY, desired.z + sin(angle) * radius))
            if others.allSatisfy({ simd_distance($0.simdPosition, candidate) >= 0.85 }) {
                return candidate
            }
        }
        return environment.movementBounds.clamped(desired)
    }

    private static func material(_ color: UIColor, emission: CGFloat = 0) -> SCNMaterial {
        let result = SCNMaterial()
        result.diffuse.contents = color
        result.emission.contents = color.withAlphaComponent(1)
        result.emission.intensity = emission
        result.roughness.contents = 0.4
        return result
    }

    private static func resource(_ name: String, extension ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Fantasy")
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }
}
