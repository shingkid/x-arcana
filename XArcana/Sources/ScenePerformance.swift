import SceneKit
import simd

/// Budgets optional summon effects without removing companions or changing their combat.
/// Call from the same serial queue that owns scene updates and summon creation.
final class ScenePerformance {
    private final class Light {
        weak var node: SCNNode?
        let value: SCNLight

        init(node: SCNNode, value: SCNLight) {
            self.node = node
            self.value = value
        }

        func restore() { node?.light = value }
    }

    private final class Companion {
        weak var node: SCNNode?
        var lights: [Light] = []
        var particles: [(system: SCNParticleSystem, birthRate: CGFloat)] = []

        init(node: SCNNode) {
            self.node = node
            func collect(_ child: SCNNode) {
                if let light = child.light { lights.append(Light(node: child, value: light)) }
                for system in child.particleSystems ?? [] { particles.append((system, system.birthRate)) }
            }
            collect(node)
            node.enumerateChildNodes { child, _ in collect(child) }
        }

        func restore() {
            for light in lights { light.restore() }
            for particle in particles { particle.system.birthRate = particle.birthRate }
        }
    }

    private let scene: SCNScene
    private let camera: SCNNode
    private var companions: [ObjectIdentifier: Companion] = [:]
    private var lastUpdate: TimeInterval?
    private let lightLimit = 4

    init(scene: SCNScene, camera: SCNNode) {
        self.scene = scene
        self.camera = camera
    }

    deinit { for companion in companions.values { companion.restore() } }

    func prepare() { refresh() }

    func update(at time: TimeInterval) {
        guard time.isFinite else { return }
        if let lastUpdate, time >= lastUpdate, time - lastUpdate < 0.25 { return }
        lastUpdate = time
        refresh()
    }

    private func refresh() {
        let nodes = scene.rootNode.childNodes.filter {
            $0.name == "SummonedDemon" || $0.name == "Patronus" || $0.name?.hasPrefix("summon.alan.") == true
                || $0.name?.hasPrefix("summon.albert.") == true
        }
        let present = Set(nodes.map(ObjectIdentifier.init))
        for id in Array(companions.keys) where !present.contains(id) {
            companions.removeValue(forKey: id)?.restore()
        }
        for node in nodes {
            let id = ObjectIdentifier(node)
            if companions[id] == nil { companions[id] = Companion(node: node) }
        }
        let viewer = camera.simdWorldPosition
        var lights: [(light: Light, distance: Float)] = []
        for companion in companions.values {
            guard let node = companion.node else { continue }
            let distance = simd_distance(viewer, node.simdWorldPosition)
            // Keep the shader, ribbon wisps, names and full meshes visible at every distance.
            let rate: CGFloat = distance < 5 ? 1 : (distance < 9 ? 0.35 : 0)
            for particle in companion.particles {
                let birthRate = particle.birthRate * rate
                if particle.system.birthRate != birthRate { particle.system.birthRate = birthRate }
            }
            for light in companion.lights {
                guard let lamp = light.node else { continue }
                lights.append((light, simd_distance_squared(viewer, lamp.simdWorldPosition)))
            }
        }
        lights.sort { $0.distance < $1.distance }
        for (index, entry) in lights.enumerated() {
            guard let node = entry.light.node else { continue }
            if index < lightLimit && entry.distance < 100 {
                if node.light !== entry.light.value { node.light = entry.light.value }
            } else if node.light != nil {
                // Removing the light component avoids shading work; its node remains intact.
                node.light = nil
            }
        }
    }

    /// Shares immutable mesh buffers and textures, but isolates mutable materials and lights.
    static func independentClone(of template: SCNNode) -> SCNNode {
        let clone = template.clone()
        var counterparts: [ObjectIdentifier: SCNNode] = [:]
        var pairs: [(SCNNode, SCNNode)] = []
        func pair(_ source: SCNNode, _ copy: SCNNode) {
            counterparts[ObjectIdentifier(source)] = copy
            pairs.append((source, copy))
            for (original, child) in zip(source.childNodes, copy.childNodes) { pair(original, child) }
        }
        pair(template, clone)
        func isolate(_ node: SCNNode) {
            if let source = node.geometry, let geometry = source.copy() as? SCNGeometry {
                geometry.materials = source.materials.map { $0.copy() as! SCNMaterial }
                node.geometry = geometry
            }
            if let light = node.light { node.light = light.copy() as? SCNLight }
            let particles = node.particleSystems ?? []
            if !particles.isEmpty {
                node.removeAllParticleSystems()
                for system in particles { node.addParticleSystem(system.copy() as! SCNParticleSystem) }
            }
        }
        isolate(clone)
        clone.enumerateChildNodes { node, _ in isolate(node) }
        // Skin weights and mesh buffers can be shared. Bone transforms and playback cannot.
        for (source, copy) in pairs {
            if let skin = source.skinner {
                let bones = skin.bones.compactMap { counterparts[ObjectIdentifier($0)] }
                precondition(bones.count == skin.bones.count, "Clone the complete character rig hierarchy")
                let geometry = (skin.baseGeometry?.copy() as? SCNGeometry)
                geometry?.materials = skin.baseGeometry?.materials.map { $0.copy() as! SCNMaterial } ?? []
                let independent = SCNSkinner(
                    baseGeometry: geometry, bones: bones,
                    boneInverseBindTransforms: skin.boneInverseBindTransforms,
                    boneWeights: skin.boneWeights, boneIndices: skin.boneIndices)
                independent.baseGeometryBindTransform = skin.baseGeometryBindTransform
                if let skeleton = skin.skeleton { independent.skeleton = counterparts[ObjectIdentifier(skeleton)] }
                copy.skinner = independent
                if let geometry { copy.geometry = geometry }
            }
            for key in source.animationKeys {
                guard let player = source.animationPlayer(forKey: key),
                    let animation = player.animation.copy() as? SCNAnimation
                else { continue }
                let independent = SCNAnimationPlayer(animation: animation)
                independent.speed = player.speed
                independent.paused = player.paused
                copy.addAnimationPlayer(independent, forKey: key)
            }
        }
        return clone
    }
}
