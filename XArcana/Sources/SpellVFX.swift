import SceneKit
import UIKit
import simd

/// Small CC0 flipbook accents. Combat owns placement, damage, and the parent effect budget.
enum SpellVFX {
    enum Effect: String, CaseIterable { case lightning, fire, ice, shield, summon }

    private struct Description: Decodable {
        let atlas: String
        let frameCount: Int
        let frameWidth: Int
        let frameHeight: Int
        let atlasWidth: Int
        let atlasHeight: Int
        let columns: Int
        let padding: Int
    }
    private struct Manifest: Decodable {
        let version: Int
        let effects: [String: Description]
    }
    private struct Atlas {
        let image: UIImage
        let transforms: [SCNMatrix4]
        let aspect: CGFloat
    }
    private static var atlases: [Effect: Atlas] = [:]
    private static let descriptions: [String: Description] = {
        guard let url = Bundle.main.url(forResource: "atlases", withExtension: "json", subdirectory: "Effects"),
            let data = try? Data(contentsOf: url), let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
            manifest.version == 1
        else { return [:] }
        return manifest.effects
    }()

    /// Prepares five shared atlas textures before the first cast.
    static func prewarm() -> [SCNNode] {
        Effect.allCases.compactMap { effect in
            guard let node = card(effect, size: 0.1) else { return nil }
            node.removeAllActions()
            return node
        }
    }

    /// Returns a camera-facing card that removes itself after one animation cycle.
    /// Size is the longest side in metres. The source aspect ratio remains unchanged.
    static func card(
        _ effect: Effect, size: CGFloat, duration: TimeInterval = 0.8,
        tint: UIColor = .white
    ) -> SCNNode? {
        guard size.isFinite, size > 0, duration.isFinite, duration > 0, duration <= 5,
            let atlas = atlas(effect)
        else { return nil }
        let width = atlas.aspect >= 1 ? size : size * atlas.aspect
        let height = atlas.aspect >= 1 ? size / atlas.aspect : size
        let geometry = SCNPlane(width: width, height: height)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = atlas.image
        material.diffuse.contentsTransform = atlas.transforms[0]
        material.diffuse.minificationFilter = .linear
        material.diffuse.magnificationFilter = .linear
        material.diffuse.mipFilter = .none
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        material.multiply.contents = tint
        material.blendMode = .add
        material.transparencyMode = .aOne
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = "SpellVFX.\(effect.rawValue)"
        node.categoryBitMask = 2
        node.castsShadow = false
        node.constraints = [SCNBillboardConstraint()]
        let transforms = atlas.transforms
        var previousFrame = -1
        let animate = SCNAction.customAction(duration: duration) { _, elapsed in
            let frame = min(transforms.count - 1, max(0, Int(Double(elapsed) / duration * Double(transforms.count))))
            guard frame != previousFrame else { return }
            previousFrame = frame
            // Reuse the image and matrix table. No images or mesh buffers are made during playback.
            material.diffuse.contentsTransform = transforms[frame]
        }
        node.runAction(.sequence([animate, .removeFromParentNode()]), forKey: "SpellVFX.playback")
        return node
    }

    private static func atlas(_ effect: Effect) -> Atlas? {
        if let cached = atlases[effect] { return cached }
        guard let description = descriptions[effect.rawValue], description.frameCount > 1,
            description.columns > 0, description.frameWidth > 0, description.frameHeight > 0,
            description.atlasWidth > 0, description.atlasHeight > 0,
            let url = Bundle.main.url(forResource: description.atlas, withExtension: nil, subdirectory: "Effects"),
            let source = UIImage(contentsOfFile: url.path), let cgImage = source.cgImage,
            cgImage.width == description.atlasWidth, cgImage.height == description.atlasHeight
        else {
            NSLog("Missing spell atlas: %@", effect.rawValue)
            return nil
        }
        // Force the shared image to decode during prewarm, then reuse it for every instance.
        let image = source.preparingForDisplay() ?? source
        let transforms = (0..<description.frameCount).map { frame -> SCNMatrix4 in
            let x =
                (frame % description.columns) * (description.frameWidth + 2 * description.padding) + description.padding
            let y =
                (frame / description.columns) * (description.frameHeight + 2 * description.padding)
                + description.padding
            var matrix = matrix_identity_float4x4
            matrix.columns.0.x = Float(description.frameWidth) / Float(description.atlasWidth)
            matrix.columns.1.y = Float(description.frameHeight) / Float(description.atlasHeight)
            matrix.columns.3.x = Float(x) / Float(description.atlasWidth)
            // SceneKit samples PNG rows from the top; the exporter packs with a bottom-up CGContext.
            matrix.columns.3.y = 1 - Float(y + description.frameHeight) / Float(description.atlasHeight)
            return SCNMatrix4(matrix)
        }
        let result = Atlas(
            image: image, transforms: transforms,
            aspect: CGFloat(description.frameWidth) / CGFloat(description.frameHeight))
        atlases[effect] = result
        return result
    }
}
