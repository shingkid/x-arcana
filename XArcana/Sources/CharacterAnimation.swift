import SceneKit
import simd

/// Plays display-only bone clips. Combat owns actor translation, targeting, and damage.
enum CharacterAnimation {
    private struct Bone: Decodable {
        let name: String
        let parent: Int
        let rest: [Float]
        let inverseBind: [Float]
    }
    private struct Part: Decodable {
        let material: String
        let indices: Data
    }
    private struct Mesh: Decodable {
        let name: String
        let positions: Data
        let normals: Data
        let uv: Data
        let weights: Data
        let boneIndices: Data
        let parts: [Part]
    }
    private struct Clip: Decodable {
        let duration: Double
        let frames: [[[Float]]]
        let nativeFrames: [[[Float]]]
    }
    private struct Asset: Decodable {
        let bones: [Bone]
        let meshes: [Mesh]
        let clips: [String: Clip]
        let attachments: [String: String]
    }
    private static var assets: [String: Asset] = [:]
    private static let actionKey = "CharacterAnimation.playback"
    private static let markerPrefix = "CharacterRig:"

    /// Cache clips once and retain native USD skinning when the importer supports it.
    @discardableResult
    static func install(
        on model: SCNNode, asset name: String, directory: String,
        resourceURL: URL? = nil
    ) -> Bool {
        if assets[name] == nil {
            guard
                let url = resourceURL
                    ?? Bundle.main.url(forResource: name + ".rig", withExtension: "json", subdirectory: directory),
                let data = try? Data(contentsOf: url),
                let asset = try? JSONDecoder().decode(Asset.self, from: data)
            else {
                NSLog("Missing character animation data: %@", name)
                return false
            }
            assets[name] = asset
        }
        guard let asset = assets[name] else { return false }
        var nativeBones: [SCNNode] = []
        model.enumerateChildNodes { node, _ in
            if let skinner = node.skinner, skinner.bones.count > nativeBones.count { nativeBones = skinner.bones }
            node.removeAllAnimations()
        }
        let native = asset.bones.allSatisfy { bone in nativeBones.contains { $0.name == usdName(bone.name) } }
        if !native { reconstruct(asset, on: model) }
        let marker = SCNNode()
        marker.name = markerPrefix + name + (native ? ":native" : ":baked")
        model.addChildNode(marker)
        return true
    }

    static func play(_ name: String, on node: SCNNode, speed: Float = 1, loop: Bool = false) {
        guard speed.isFinite, speed > 0, let context = context(on: node),
            let clip = context.asset.clips[name], clip.duration > 0
        else { return }
        let model = context.model
        // Repeated combat updates must not restart the same movement cycle.
        let key = actionKey + "." + name
        if model.action(forKey: key) != nil { return }
        stop(on: node)
        let frames = context.native ? clip.nativeFrames : clip.frames
        let bones = context.asset.bones.map {
            model.childNode(withName: context.native ? usdName($0.name) : $0.name, recursively: true)
        }
        let duration = clip.duration / Double(speed)
        let action = SCNAction.customAction(duration: duration) { _, elapsed in
            apply(frames: frames, bones: bones, progress: Float(elapsed) / Float(duration))
        }
        apply(frames: frames, bones: bones, progress: 0)
        model.runAction(loop ? .repeatForever(action) : action, forKey: key)
    }

    static func stop(on node: SCNNode) {
        guard let context = context(on: node) else { return }
        for key in context.model.actionKeys where key.hasPrefix(actionKey) {
            context.model.removeAction(forKey: key)
        }
    }

    static func setPaused(_ paused: Bool, on node: SCNNode) {
        guard let model = context(on: node)?.model else { return }
        for key in model.actionKeys where key.hasPrefix(actionKey) {
            model.action(forKey: key)?.speed = paused ? 0 : 1
        }
    }

    static func attachment(_ name: String, on node: SCNNode) -> SCNNode? {
        guard let context = context(on: node), let bone = context.asset.attachments[name] else { return nil }
        return context.model.childNode(withName: context.native ? usdName(bone) : bone, recursively: true)
    }

    /// Attach accessories without changing their resting position or size.
    static func attach(_ accessory: SCNNode, to name: String, on actor: SCNNode) {
        guard let joint = attachment(name, on: actor) else { return }
        let world = accessory.simdWorldTransform
        joint.addChildNode(accessory)
        accessory.simdWorldTransform = world
    }

    /// Deterministic sampling supports asset verification without a running renderer.
    @discardableResult
    static func sample(_ name: String, at time: TimeInterval, on node: SCNNode) -> Bool {
        guard let context = context(on: node), let clip = context.asset.clips[name] else { return false }
        let bones = context.asset.bones.map {
            context.model.childNode(withName: context.native ? usdName($0.name) : $0.name, recursively: true)
        }
        apply(
            frames: context.native ? clip.nativeFrames : clip.frames, bones: bones,
            progress: Float(time / max(clip.duration, 0.001)))
        return true
    }

    private static func context(on node: SCNNode) -> (model: SCNNode, asset: Asset, native: Bool)? {
        var marker: SCNNode?
        node.enumerateChildNodes { child, stop in
            if child.name?.hasPrefix(markerPrefix) == true {
                marker = child
                stop.pointee = true
            }
        }
        guard let marker, let model = marker.parent, let parts = marker.name?.split(separator: ":"),
            parts.count == 3, let asset = assets[String(parts[1])]
        else { return nil }
        return (model, asset, parts[2] == "native")
    }

    private static func usdName(_ name: String) -> String {
        name.replacingOccurrences(of: ".", with: "_").replacingOccurrences(of: "-", with: "_")
    }

    private static func apply(frames: [[[Float]]], bones: [SCNNode?], progress: Float) {
        guard !frames.isEmpty else { return }
        let frame = min(1, max(0, progress)) * Float(frames.count - 1)
        let first = Int(frame)
        let next = min(first + 1, frames.count - 1)
        let t = frame - Float(first)
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        for (index, bone) in bones.enumerated() {
            guard let bone, index < frames[first].count, index < frames[next].count else { continue }
            let a = frames[first][index]
            let b = frames[next][index]
            guard a.count == 10, b.count == 10 else { continue }
            bone.simdPosition = SIMD3(a[0], a[1], a[2]) * (1 - t) + SIMD3(b[0], b[1], b[2]) * t
            bone.simdOrientation = simd_slerp(
                simd_quatf(ix: a[3], iy: a[4], iz: a[5], r: a[6]),
                simd_quatf(ix: b[3], iy: b[4], iz: b[5], r: b[6]), t)
            bone.simdScale = SIMD3(a[7], a[8], a[9]) * (1 - t) + SIMD3(b[7], b[8], b[9]) * t
        }
        SCNTransaction.commit()
    }

    private static func matrix(_ values: [Float]) -> SCNMatrix4 {
        guard values.count == 16 else { return SCNMatrix4Identity }
        return SCNMatrix4(
            simd_float4x4(
                columns: (
                    SIMD4(values[0], values[1], values[2], values[3]),
                    SIMD4(values[4], values[5], values[6], values[7]),
                    SIMD4(values[8], values[9], values[10], values[11]),
                    SIMD4(values[12], values[13], values[14], values[15])
                )))
    }

    private static func reconstruct(_ asset: Asset, on model: SCNNode) {
        var materials: [String: SCNMaterial] = [:]
        model.enumerateChildNodes { node, _ in
            for material in node.geometry?.materials ?? [] {
                if let name = material.name { materials[name] = material }
            }
        }
        for child in model.childNodes { child.removeFromParentNode() }
        let skeleton = SCNNode()
        skeleton.name = "BakedSkeleton"
        model.addChildNode(skeleton)
        let bones = asset.bones.map { bone -> SCNNode in
            let node = SCNNode()
            node.name = bone.name
            node.transform = matrix(bone.rest)
            return node
        }
        for (index, bone) in asset.bones.enumerated() {
            (bone.parent >= 0 ? bones[bone.parent] : skeleton).addChildNode(bones[index])
        }
        for mesh in asset.meshes {
            let count = mesh.positions.count / 12
            func source(_ data: Data, _ semantic: SCNGeometrySource.Semantic, _ components: Int, _ bytes: Int = 4)
                -> SCNGeometrySource
            {
                SCNGeometrySource(
                    data: data, semantic: semantic, vectorCount: count, usesFloatComponents: semantic != .boneIndices,
                    componentsPerVector: components, bytesPerComponent: bytes, dataOffset: 0,
                    dataStride: components * bytes)
            }
            let geometry = SCNGeometry(
                sources: [
                    source(mesh.positions, .vertex, 3), source(mesh.normals, .normal, 3), source(mesh.uv, .texcoord, 2),
                ],
                elements: mesh.parts.map {
                    SCNGeometryElement(
                        data: $0.indices, primitiveType: .triangles, primitiveCount: $0.indices.count / 12,
                        bytesPerIndex: 4)
                })
            geometry.materials = mesh.parts.map {
                materials[$0.material] ?? materials[usdName($0.material)] ?? SCNMaterial()
            }
            let node = SCNNode(geometry: geometry)
            node.name = mesh.name
            let skinner = SCNSkinner(
                baseGeometry: geometry, bones: bones,
                boneInverseBindTransforms: asset.bones.map { NSValue(scnMatrix4: matrix($0.inverseBind)) },
                boneWeights: source(mesh.weights, .boneWeights, 4),
                boneIndices: source(mesh.boneIndices, .boneIndices, 4, 2))
            skinner.skeleton = skeleton
            node.skinner = skinner
            model.addChildNode(node)
        }
    }
}
