import SceneKit
import UIKit
import simd

/// Maps the selected portrait texture onto a curved face surface without changing its pixels.
enum ZombieAppearance {
    struct FacePoint: Decodable {
        let x: Float
        let y: Float
        var vector: SIMD2<Float> { SIMD2(x, y) }
    }

    struct FaceRect: Decodable {
        let x: Float
        let y: Float
        let width: Float
        let height: Float
    }

    struct FaceRegion: Decodable {
        let id: String
        let faceRect: FaceRect
        let leftEye: FacePoint
        let rightEye: FacePoint
        let mouth: FacePoint
        let sourceWidth: Float?
        let sourceHeight: Float?
    }

    struct ModelFace: Decodable {
        let leftEye: FacePoint
        let rightEye: FacePoint
        let mouth: FacePoint
    }

    private static let faceRegions: [String: FaceRegion] = {
        guard let url = Bundle.main.url(forResource: "regions", withExtension: "json", subdirectory: "NPCFaces"),
            let data = try? Data(contentsOf: url),
            let regions = try? JSONDecoder().decode([FaceRegion].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: regions.map { ($0.id, $0) })
    }()

    private static let modelFace: ModelFace? = {
        let url =
            Bundle.main.url(forResource: "ZombieFace", withExtension: "json", subdirectory: "Creatures")
            ?? Bundle.main.url(forResource: "ZombieFace", withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ModelFace.self, from: data)
    }()

    enum BodyStyle: String, Decodable, Hashable { case male, female, neutral }

    struct BodyStyleMetadata: Decodable {
        let schemaVersion: Int
        let assignments: [String: BodyStyle]

        func validationIssues(identityIDs: [String]) -> [String] {
            var issues: [String] = []
            if schemaVersion != 1 { issues.append("Unsupported body-style schema: \(schemaVersion)") }
            let ids = Set(identityIDs)
            for id in ids.sorted() where assignments[id] == nil {
                issues.append("Missing body style for \(id); using neutral body")
            }
            for id in assignments.keys.sorted() where !ids.contains(id) {
                issues.append("Body style has an unknown identity: \(id)")
            }
            return issues
        }
    }

    private static let bodyMetadata: BodyStyleMetadata = {
        do {
            guard
                let url = Bundle.main.url(
                    forResource: "body-styles", withExtension: "json", subdirectory: "NPCPortraits")
            else {
                throw CocoaError(.fileNoSuchFile)
            }
            let decoded = try JSONDecoder().decode(BodyStyleMetadata.self, from: Data(contentsOf: url))
            guard decoded.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
            return decoded
        } catch {
            NSLog(
                "Zombie body-style metadata could not be loaded: %@. Using neutral bodies.", String(describing: error))
            return BodyStyleMetadata(schemaVersion: 1, assignments: [:])
        }
    }()

    private static var reportedMissingStyles: Set<String> = []

    static func bodyStyle(for identityID: String) -> BodyStyle {
        if let style = bodyMetadata.assignments[identityID] { return style }
        if reportedMissingStyles.insert(identityID).inserted {
            NSLog(
                "Missing zombie body style for %@; using neutral body. Update NPCPortraits/body-styles.json.",
                identityID)
        }
        return .neutral
    }

    static func metadataValidationIssues(identityIDs: [String]) -> [String] {
        bodyMetadata.validationIssues(identityIDs: identityIDs)
    }

    private static let prototypes: [BodyStyle: SCNNode] = {
        var result: [BodyStyle: SCNNode] = [:]
        for (style, name) in [(BodyStyle.neutral, "Zombie"), (.male, "ZombieMale"), (.female, "ZombieFemale")] {
            if let node = loadPrototype(named: name) { result[style] = node }
        }
        return result
    }()

    static func scale(for index: Int) -> SIMD3<Float> {
        // Small height differences preserve each authored body's human proportions.
        let heights: [Float] = [1, 0.98, 1.02, 1.01]
        return SIMD3(repeating: heights[((index % heights.count) + heights.count) % heights.count])
    }

    private struct AppearanceKey: Hashable {
        let id: String
        let name: String
        let image: String
        let variant: Int
        let bodyStyle: BodyStyle
    }

    private static var portraits: [AppearanceKey: SCNNode] = [:]
    private static var appearances: [AppearanceKey: SCNNode] = [:]

    /// Call on the scene's update queue before gameplay, then pass the nodes to SCNView.prepare.
    static func prewarm(identities: [Combat.Identity]) -> [SCNNode] {
        for issue in metadataValidationIssues(identityIDs: identities.map(\.id)) {
            NSLog("Zombie appearance metadata: %@", issue)
        }
        return identities.flatMap { identity in (0..<4).map { prepared(identity: identity, index: $0) } }
    }

    static func make(identity: Combat.Identity, index: Int, style: BodyStyle? = nil) -> SCNNode {
        let node = ScenePerformance.independentClone(of: prepared(identity: identity, index: index, style: style))
        // SCNText can copy as an empty SCNGeometry before its first renderer preparation.
        // Build each label directly so the first spawn has a name before prewarming finishes.
        node.childNode(withName: "Name.\(identity.id)", recursively: true)?.removeFromParentNode()
        node.addChildNode(identityName(identity))
        return node
    }

    private static func prepared(identity: Combat.Identity, index: Int, style: BodyStyle? = nil) -> SCNNode {
        let variant = ((index % 4) + 4) % 4
        let style = style ?? bodyStyle(for: identity.id)
        let key = AppearanceKey(
            id: identity.id, name: identity.name, image: identity.image, variant: variant, bodyStyle: style)
        if let cached = appearances[key] { return cached }
        let portraitKey = AppearanceKey(
            id: identity.id, name: identity.name, image: identity.image, variant: 0, bodyStyle: style)

        let node = SCNNode()
        node.categoryBitMask = 2
        guard let prototype = prototypes[style] ?? prototypes[.neutral] else { return node }
        node.name = "ZombieBodyStyle.\(style.rawValue)"
        let portrait: SCNNode
        if let cached = portraits[portraitKey] {
            portrait = cached
        } else {
            portrait = ScenePerformance.independentClone(of: prototype)
            applyPortrait(identity, to: portrait)
            portraits[portraitKey] = portrait
        }
        let body = ScenePerformance.independentClone(of: portrait)
        body.name = "Office zombie"
        node.addChildNode(body)
        styleZombie(body, variant: variant)
        node.addChildNode(identityName(identity))
        appearances[key] = node
        return node
    }

    private static func loadPrototype(named name: String) -> SCNNode? {
        let url =
            Bundle.main.url(forResource: name, withExtension: "usdz", subdirectory: "Creatures")
            ?? Bundle.main.url(forResource: name, withExtension: "usdz")
        guard let url else {
            NSLog("Missing zombie model: Creatures/%@.usdz", name)
            return nil
        }
        guard
            let source = try? SCNScene(
                url: url,
                options: [
                    .convertToYUp: true,
                    .animationImportPolicy: SCNSceneSource.AnimationImportPolicy.playRepeatedly,
                ])
        else {
            NSLog("Could not load zombie model: %@", url.path)
            return nil
        }
        _ = CharacterAnimation.install(on: source.rootNode, asset: name, directory: "Creatures")
        source.rootNode.enumerateChildNodes { child, _ in
            child.categoryBitMask = 2
            child.castsShadow = true
            for material in child.geometry?.materials ?? [] { material.lightingModel = .physicallyBased }
        }
        source.rootNode.categoryBitMask = 2
        return source.rootNode
    }
    private static func identityName(_ identity: Combat.Identity) -> SCNNode {
        let text = SCNText(string: identity.name, extrusionDepth: 0.001)
        text.font = .systemFont(ofSize: 32, weight: .semibold)
        text.flatness = 0.05
        text.firstMaterial = material(UIColor(red: 0.94, green: 0.91, blue: 0.77, alpha: 1), glowing: true)
        let node = SCNNode()
        node.name = "Name.\(identity.id)"
        node.categoryBitMask = 2
        node.castsShadow = false
        let glyphs = SCNNode(geometry: text)
        glyphs.categoryBitMask = 2
        glyphs.castsShadow = false
        let bounds = text.boundingBox
        // Measure regular-sized glyphs before converting them to metres.
        // A centered child keeps the billboard anchor independent of glyph-space transforms.
        let height = Float(bounds.max.y - bounds.min.y)
        let scale: Float = height > 0 ? 0.15 / height : 1
        glyphs.simdScale = SIMD3(repeating: scale)
        glyphs.simdPosition = SIMD3(
            -Float(bounds.min.x + bounds.max.x) * scale / 2,
            -Float(bounds.min.y) * scale, 0)
        node.addChildNode(glyphs)
        node.position = SCNVector3(0, 1.88, 0)
        node.constraints = [SCNBillboardConstraint()]
        return node
    }

    private static func styleZombie(_ body: SCNNode, variant: Int) {
        // Restrained changes in the same office palette; no color-coded skin or factions.
        let shirts: [UIColor] = [
            .init(white: 0.94, alpha: 1),
            .init(red: 0.66, green: 0.77, blue: 0.87, alpha: 1),
            .init(red: 0.86, green: 0.78, blue: 0.64, alpha: 1),
            .init(red: 0.69, green: 0.74, blue: 0.68, alpha: 1),
        ]
        body.enumerateChildNodes { node, _ in
            guard let source = node.geometry else { return }
            let geometry = source.copy() as! SCNGeometry
            geometry.materials = source.materials.map { original in
                let copy = original.copy() as! SCNMaterial
                let name = (copy.name ?? "").lowercased()
                copy.metalness.contents = 0
                copy.roughness.contents = 0.94
                if name.contains("shirt") { copy.multiply.contents = shirts[variant] }
                if name.contains("trousers") { copy.multiply.contents = UIColor(white: 0.94, alpha: 1) }
                return copy
            }
            node.geometry = geometry
            node.skinner?.baseGeometry?.materials = geometry.materials
        }
    }

    private static func applyPortrait(_ identity: Combat.Identity, to body: SCNNode) {
        guard
            let face =
                (body.childNode(withName: "Portrait_face_surface", recursively: true)
                    ?? body.childNode(withName: "PortraitFace", recursively: true)),
            let geometry = face.geometry,
            let coordinates = geometry.sources(for: .texcoord).first
        else { return }
        guard let region = Self.faceRegions[identity.id], let model = Self.modelFace,
            let url = Bundle.main.url(forResource: identity.image, withExtension: nil, subdirectory: "NPCPortraits"),
            let portrait = UIImage(contentsOfFile: url.path)
        else {
            // A new identity keeps the neutral model's own face until a portrait is supplied.
            face.isHidden = true
            return
        }
        var vertexColors: [Float] = []
        let mapped: [CGPoint] = coordinates.data.withUnsafeBytes { data in
            (0..<coordinates.vectorCount).map { index in
                let offset = coordinates.dataOffset + index * coordinates.dataStride
                func component(_ component: Int) -> Float {
                    let position = offset + component * coordinates.bytesPerComponent
                    if coordinates.bytesPerComponent == 8 {
                        return Float(data.loadUnaligned(fromByteOffset: position, as: Double.self))
                    }
                    return data.loadUnaligned(fromByteOffset: position, as: Float.self)
                }
                let local = SIMD2(component(0), 1 - component(1))
                let radius = simd_length((local - SIMD2(repeating: 0.5)) * 2)
                let edge = min(1, max(0, (radius - 0.68) / 0.32))
                let alpha = 1 - edge * edge * (3 - 2 * edge)
                vertexColors += [1, 1, 1, alpha]
                let uv = portraitUV(local, region: region, model: model)
                return CGPoint(x: CGFloat(uv.x), y: CGFloat(1 - uv.y))
            }
        }
        let skinTone = portraitSkinTone(portrait, region: region)
        body.enumerateChildNodes { node, _ in
            for material in node.geometry?.materials ?? [] {
                let name = (material.name ?? "").lowercased()
                if name.contains("skin") && !name.contains("sunken") || name.contains("nails") {
                    material.diffuse.contents = skinTone
                }
            }
        }
        let surface = SCNMaterial()
        surface.name = "NPC face.\(identity.id)"
        surface.lightingModel = .physicallyBased
        surface.diffuse.contents = portrait
        surface.diffuse.wrapS = .clamp
        surface.diffuse.wrapT = .clamp
        surface.roughness.contents = 0.95
        surface.transparencyMode = .aOne
        surface.blendMode = .alpha
        surface.writesToDepthBuffer = false
        surface.shaderModifiers = [
            .geometry: """
            #pragma varyings
            float portraitAlpha;
            #pragma body
            out.portraitAlpha = _geometry.color.a;
            """,
            .surface: """
            #pragma transparent
            #pragma body
            _surface.diffuse.a *= in.portraitAlpha;
            // Preserve the photograph's colour and contrast for identity recognition.
            _surface.diffuse.rgb *= 0.98;
            _surface.emission.rgb = float3(0.0);
            """,
        ]
        let colorData = vertexColors.withUnsafeBytes { Data($0) }
        let colors = SCNGeometrySource(
            data: colorData, semantic: .color, vectorCount: coordinates.vectorCount,
            usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        // USD meshes can use separate position, normal and UV index channels.
        // Preserve those channels when replacing UVs and adding local opacity.
        let channels =
            geometry.geometrySourceChannels ?? Array(repeating: NSNumber(value: 0), count: geometry.sources.count)
        let retained = geometry.sources.enumerated().filter {
            $0.element.semantic != .texcoord && $0.element.semantic != .color
        }
        let textureIndex = geometry.sources.firstIndex { $0 === coordinates } ?? 0
        let textureChannel = channels[textureIndex]
        let sources = retained.map(\.element) + [SCNGeometrySource(textureCoordinates: mapped), colors]
        let sourceChannels = retained.map { channels[$0.offset] } + [textureChannel, textureChannel]
        face.geometry = SCNGeometry(sources: sources, elements: geometry.elements, sourceChannels: sourceChannels)
        face.geometry?.materials = [surface]
        if let skin = face.skinner, let geometry = face.geometry {
            let mappedSkin = SCNSkinner(
                baseGeometry: geometry, bones: skin.bones,
                boneInverseBindTransforms: skin.boneInverseBindTransforms,
                boneWeights: skin.boneWeights, boneIndices: skin.boneIndices)
            mappedSkin.skeleton = skin.skeleton
            mappedSkin.baseGeometryBindTransform = skin.baseGeometryBindTransform
            face.skinner = mappedSkin
        }
        face.name = "Face.\(identity.id)"
        face.categoryBitMask = 2
        face.castsShadow = false
        face.renderingOrder = 5
        body.childNode(withName: "Eyes", recursively: true)?.isHidden = true
    }

    /// Sample the cheeks for the surrounding model, leaving the portrait texture unchanged.
    private static func portraitSkinTone(_ portrait: UIImage, region: FaceRegion) -> UIColor {
        guard let image = portrait.cgImage else { return UIColor(white: 0.65, alpha: 1) }
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard
            let context = CGContext(
                data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return UIColor(white: 0.65, alpha: 1) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let eyeCenter = (region.leftEye.vector + region.rightEye.vector) * 0.5
        let cheekY = (eyeCenter.y + region.mouth.y) * 0.5
        var samples = SIMD3<Float>.zero
        var count: Float = 0
        for eye in [region.leftEye, region.rightEye] {
            let x = min(side - 2, max(1, Int(eye.x * Float(side))))
            let y = min(side - 2, max(1, Int((1 - cheekY) * Float(side))))
            for row in (y - 1)...(y + 1) {
                for column in (x - 1)...(x + 1) {
                    let index = (row * side + column) * 4
                    samples += SIMD3(Float(pixels[index]), Float(pixels[index + 1]), Float(pixels[index + 2])) / 255
                    count += 1
                }
            }
        }
        let colour = samples / max(1, count)
        let pale = colour * 0.72 + SIMD3<Float>(0.76, 0.73, 0.70) * 0.28
        return UIColor(red: CGFloat(pale.x), green: CGFloat(pale.y), blue: CGFloat(pale.z), alpha: 1)
    }

    /// Match the eye line with a similarity transform in image pixels.
    /// A three-point affine warp can stretch a wide photo into the shared model's narrow mouth.
    static func portraitUV(_ local: SIMD2<Float>, region: FaceRegion, model: ModelFace) -> SIMD2<Float> {
        let size = SIMD2(max(1, region.sourceWidth ?? 1), max(1, region.sourceHeight ?? 1))
        let modelAcross = model.rightEye.vector - model.leftEye.vector
        let photoAcross = (region.rightEye.vector - region.leftEye.vector) * size
        let denominator = simd_length_squared(modelAcross)
        guard denominator > 0.00001 else { return region.leftEye.vector }
        let real = simd_dot(modelAcross, photoAcross) / denominator
        let imaginary = (modelAcross.x * photoAcross.y - modelAcross.y * photoAcross.x) / denominator
        let delta = local - model.leftEye.vector
        let transformed = SIMD2(real * delta.x - imaginary * delta.y, imaginary * delta.x + real * delta.y)
        return region.leftEye.vector + transformed / size
    }

    /// Combat supplies simulation time so slow effects and pauses also govern the joints.
    @discardableResult
    static func sampleMotion(_ clip: String, at time: TimeInterval, on node: SCNNode) -> Bool {
        guard time.isFinite else { return false }
        let duration: TimeInterval
        switch clip {
        case "walk": duration = 1.1666666667
        case "idle": duration = 2.4166666667
        default: return CharacterAnimation.sample(clip, at: max(0, time), on: node)
        }
        let loopTime = max(0, time).truncatingRemainder(dividingBy: duration)
        return CharacterAnimation.sample(clip, at: loopTime, on: node)
    }

    private static func material(_ color: UIColor, glowing: Bool = false) -> SCNMaterial {
        let result = SCNMaterial()
        result.diffuse.contents = color
        if glowing {
            result.lightingModel = .constant
            result.emission.contents = color
        }
        return result
    }
}
