import SceneKit
import UIKit
import simd

/// The registry owns companion health, movement, attacks, and expiry.
/// SceneKit actions only display effects. Simulation time decides every impact.
final class SummonCombat {
    struct Target {
        let node: SCNNode
        let center: SIMD3<Float>
    }

    struct Impact {
        let node: SCNNode
        let damage: Int
        let slowDuration: TimeInterval
    }

    final class Companion {
        let kind: SummonKind
        let node: SCNNode
        private(set) var health: Int
        var cooldown: TimeInterval = 0.7
        var slamCooldown: TimeInterval = 0.7
        var breathCooldown: TimeInterval = 0.7
        var attack: PendingAttack?
        var chargeDestination: SIMD3<Float>?
        var lifetime: TimeInterval = 0
        var touched: Set<ObjectIdentifier> = []
        var expired = false
        var healthText: SCNText?
        var healthFill: SCNNode?
        var animation = ""
        var center: SIMD3<Float> { node.simdWorldPosition + SIMD3(0, 1, 0) }
        init(kind: SummonKind, node: SCNNode) {
            self.kind = kind
            self.node = node
            health = kind.maxHealth
        }
        func damage(_ amount: Int) { health = max(0, health - amount) }
    }

    enum AttackStyle { case slap, slam, combo, breath }
    struct PendingAttack {
        let style: AttackStyle
        let target: SCNNode
        var elapsed: TimeInterval = 0
        var contacts: Int = 0
    }

    private let environment: EnvironmentDefinition
    private let scene: SCNScene
    private(set) var companions: [Companion] = []
    private var retiring: [SCNNode] = []
    var physicalTargets: [Target] {
        companions.filter { $0.kind != .patronus && $0.health > 0 && !$0.expired && $0.node.parent != nil }
            .map { Target(node: $0.node, center: $0.center) }
    }

    init(scene: SCNScene, environment: EnvironmentDefinition = .fantasy) {
        self.scene = scene
        self.environment = environment
    }

    func contains(_ kind: SummonKind) -> Bool {
        companions.contains {
            $0.kind == kind && !$0.expired && $0.node.parent != nil && ($0.health > 0 || kind == .patronus)
        }
    }

    /// Call only after asset availability and mana have been validated.
    func register(kind: SummonKind, node: SCNNode) {
        for old in companions where !kind.canCoexist(with: old.kind) { old.node.removeFromParentNode() }
        companions.removeAll { !kind.canCoexist(with: $0.kind) }
        if node.parent == nil { scene.rootNode.addChildNode(node) }
        let companion = Companion(kind: kind, node: node)
        companions.append(companion)
        node.simdWorldPosition = bounded(node.simdWorldPosition)
        if kind != .patronus { addHealthLabel(to: companion) }
        animate(companion, name: kind == .patronus ? "run" : "idle", loop: true)
    }

    func setPaused(_ paused: Bool) {
        for node in companions.map(\.node) + retiring {
            node.isPaused = paused
            CharacterAnimation.setPaused(paused, on: node)
        }
    }

    func cancelAttacks() {
        for ally in companions {
            ally.attack = nil
            animate(ally, name: ally.kind == .patronus ? "run" : "idle", loop: true)
        }
    }

    func reset() {
        for node in retiring { node.removeFromParentNode() }
        retiring.removeAll()
        for ally in companions { ally.node.removeFromParentNode() }
        companions.removeAll()
        for node in scene.rootNode.childNodes where node.name == "CompanionAttack" { node.removeFromParentNode() }
    }

    func isLiving(_ node: SCNNode) -> Bool {
        companions.contains { $0.node === node && $0.kind != .patronus && $0.health > 0 && node.parent != nil }
    }

    func damage(node: SCNNode, amount: Int) {
        guard let ally = companions.first(where: { $0.node === node && $0.kind != .patronus }), ally.health > 0 else {
            return
        }
        ally.damage(amount)
        ally.healthText?.string = "\(ally.health)/\(ally.kind.maxHealth)"
        ally.healthFill?.simdScale.x = Float(ally.health) / Float(ally.kind.maxHealth)
        if ally.health == 0 {
            ally.attack = nil
            CharacterAnimation.stop(on: node)
            node.removeFromParentNode()
        }
    }

    func update(deltaTime: TimeInterval, targets: [Target]) -> [Impact] {
        guard deltaTime.isFinite, deltaTime > 0 else { return [] }
        let dt = min(0.05, deltaTime)
        retiring.removeAll { $0.parent == nil }
        companions.removeAll { $0.expired || $0.node.parent == nil || ($0.kind != .patronus && $0.health == 0) }
        var seen: Set<ObjectIdentifier> = []
        let enemies = targets.filter {
            $0.node.parent != nil && $0.center.x.isFinite && $0.center.y.isFinite && $0.center.z.isFinite
                && seen.insert(ObjectIdentifier($0.node)).inserted
        }
        var impacts: [Impact] = []
        for ally in companions {
            ally.lifetime += dt
            if ally.kind == .patronus {
                impacts += charge(ally, dt: dt, targets: enemies)
                continue
            }
            separate(ally, from: enemies, dt: dt)
            ally.cooldown = max(0, ally.cooldown - dt)
            ally.slamCooldown = max(0, ally.slamCooldown - dt)
            ally.breathCooldown = max(0, ally.breathCooldown - dt)
            if var attack = ally.attack {
                attack.elapsed += dt
                let contactTimes: [Double] =
                    attack.style == .combo ? [0.28, 0.56] : [attack.style == .breath ? 0.45 : 0.35]
                while attack.contacts < contactTimes.count, attack.elapsed + 0.000001 >= contactTimes[attack.contacts] {
                    impacts += contact(ally, attack: attack, targets: enemies)
                    attack.contacts += 1
                }
                ally.attack =
                    attack.elapsed >= (attack.style == .breath ? 1.18 : (attack.style == .combo ? 0.85 : 0.75))
                    ? nil : attack
                continue
            }
            guard let nearest = enemies.min(by: { distance(ally.center, $0.center) < distance(ally.center, $1.center) })
            else {
                animate(ally, name: "idle", loop: true)
                continue
            }
            let gap = distance(ally.center, nearest.center)
            face(ally.node, toward: nearest.center)
            animate(ally, name: gap > 1 ? "walk" : "idle", loop: true)
            if gap > 1 {
                move(
                    ally.node, toward: nearest.center, speed: ally.kind == .demon ? 1.05 : 0.9, stoppingAt: 0.95, dt: dt
                )
            }
            let style: AttackStyle
            let nearbyCount = enemies.filter { distance(ally.center, $0.center) <= 1.8 }.count
            if ally.kind == .demon, ally.slamCooldown <= 0, nearbyCount >= 2 {
                style = .slam
                ally.slamCooldown = 8
            } else if ally.kind == .demon, ally.breathCooldown <= 0, gap <= 3 {
                style = .breath
                ally.breathCooldown = 10
            } else {
                guard ally.cooldown <= 0, gap <= 1.2 else { continue }
                switch ally.kind {
                case .albert:
                    style = .slam
                    ally.cooldown = 3.5
                case .alan:
                    style = .slap
                    ally.cooldown = 1.2
                case .demon:
                    style = .combo
                    ally.cooldown = 1.8
                case .patronus: continue
                }
            }
            ally.attack = PendingAttack(style: style, target: nearest.node)
            animateAttack(ally, style: style)
        }
        return impacts
    }

    private func contact(_ ally: Companion, attack: PendingAttack, targets: [Target]) -> [Impact] {
        let victims: [Target]
        switch attack.style {
        case .slap, .combo:
            victims = targets.filter { $0.node === attack.target && distance(ally.center, $0.center) <= 1.35 }
        case .slam:
            let radius: Float = ally.kind == .albert ? 1.25 : 1.8
            victims = targets.filter { distance(ally.center, $0.center) <= radius }
            showSlam(at: ally.node.simdWorldPosition + SIMD3(0, 0.025, 0), radius: radius)
        case .breath:
            showBreath(from: ally)
            let forward = SIMD3<Float>(sin(ally.node.simdEulerAngles.y), 0, cos(ally.node.simdEulerAngles.y))
            victims = targets.filter {
                var offset = $0.center - ally.center
                offset.y = 0
                let length = simd_length(offset)
                return length <= 3 && (length < 0.001 || simd_dot(offset / length, forward) >= 0.7071)
            }
        }
        let amount = attack.style == .slam || attack.style == .breath ? 2 : 1
        return victims.map { Impact(node: $0.node, damage: amount, slowDuration: 0) }
    }

    private func charge(_ ally: Companion, dt: TimeInterval, targets: [Target]) -> [Impact] {
        if ally.lifetime >= 3 {
            dissolve(ally)
            return []
        }
        if ally.chargeDestination == nil {
            // Stable ordering breaks ties and makes the chosen cluster repeatable.
            var largest: Target?
            var count = 0
            for candidate in targets {
                let nearby = targets.filter { distance(candidate.center, $0.center) <= 1.8 }.count
                if nearby > count {
                    count = nearby
                    largest = candidate
                }
            }
            guard let largest else { return [] }
            var direction = largest.center - ally.center
            direction.y = 0
            let length = simd_length(direction)
            direction = length > 0.001 ? direction / length : SIMD3(0, 0, -1)
            ally.chargeDestination = bounded(largest.center + direction * 1.8)
        }
        guard let destination = ally.chargeDestination else { return [] }
        let start = ally.center
        face(ally.node, toward: destination)
        move(ally.node, toward: destination, speed: 4, stoppingAt: 0, dt: dt)
        let end = ally.center
        let contacts = targets.filter {
            !ally.touched.contains(ObjectIdentifier($0.node)) && segmentDistance($0.center, from: start, to: end) <= 1
        }
        for target in contacts {
            ally.touched.insert(ObjectIdentifier(target.node))
            showPulse(at: target.center, radius: 0.7, color: .cyan)
        }
        if distance(ally.center, destination) <= 0.15 { dissolve(ally) }
        return contacts.map { Impact(node: $0.node, damage: 0, slowDuration: 15) }
    }

    private func dissolve(_ ally: Companion) {
        ally.expired = true
        retiring.append(ally.node)
        CharacterAnimation.stop(on: ally.node)
        ally.node.runAction(.sequence([.fadeOut(duration: 0.3), .removeFromParentNode()]), forKey: "dissolve")
    }

    private func segmentDistance(_ point: SIMD3<Float>, from start: SIMD3<Float>, to end: SIMD3<Float>) -> Float {
        let a = SIMD2(start.x, start.z)
        let b = SIMD2(end.x, end.z)
        let p = SIMD2(point.x, point.z)
        let delta = b - a
        let length = simd_length_squared(delta)
        let fraction = length > 0.000001 ? min(1, max(0, simd_dot(p - a, delta) / length)) : 0
        return simd_distance(p, a + delta * fraction)
    }

    private func bounded(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let position = environment.movementBounds.clamped(point)
        return SIMD3(position.x, environment.floorY, position.z)
    }

    private func separate(_ ally: Companion, from targets: [Target], dt: TimeInterval) {
        var point = ally.node.simdWorldPosition
        let index = companions.firstIndex(where: { $0 === ally }) ?? 0
        let neighbors =
            companions.filter { $0 !== ally && $0.kind != .patronus && $0.health > 0 }.map(\.center)
            + targets.map(\.center)
        for other in neighbors {
            var offset = point - other
            offset.y = 0
            let gap = simd_length(offset)
            guard gap < 0.6 else { continue }
            let direction = gap > 0.001 ? offset / gap : SIMD3<Float>(index.isMultiple(of: 2) ? -1 : 1, 0, 0)
            point += direction * min(0.6 - gap, Float(dt) * 2)
        }
        ally.node.simdWorldPosition = bounded(point)
    }

    private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        simd_length(SIMD2(a.x - b.x, a.z - b.z))
    }

    private func face(_ node: SCNNode, toward point: SIMD3<Float>) {
        let offset = point - node.simdWorldPosition
        node.simdEulerAngles.y = atan2(offset.x, offset.z)
    }

    private func move(_ node: SCNNode, toward point: SIMD3<Float>, speed: Float, stoppingAt stop: Float, dt: Double) {
        var offset = point - node.simdWorldPosition
        offset.y = 0
        let length = simd_length(offset)
        guard length > max(stop, 0.0001) else { return }
        let destination = node.simdWorldPosition + offset / length * min(speed * Float(dt), length - stop)
        node.simdWorldPosition = bounded(destination)
    }

    private func animateAttack(_ ally: Companion, style: AttackStyle) {
        let name: String
        switch style {
        case .slap: name = "slap"
        case .slam: name = "slam"
        case .combo: name = "clawCombo"
        case .breath: name = "breath"
        }
        animate(ally, name: name, loop: false)
    }

    private func animate(_ ally: Companion, name: String, loop: Bool) {
        guard ally.animation != name else { return }
        ally.animation = name
        CharacterAnimation.play(name, on: ally.node, speed: 1, loop: loop)
    }

    private func addHealthLabel(to ally: Companion) {
        ally.node.childNode(withName: "PortraitName", recursively: false)?.isHidden = true
        let label = SCNNode()
        label.name = "CompanionHealth"
        let labelHeight: Float = ally.kind == .demon ? 2.45 : (ally.kind == .albert ? 2.25 : 2.0)
        label.position = SCNVector3(0, labelHeight, 0)
        label.constraints = [SCNBillboardConstraint()]
        func text(_ string: String, height: Float, y: Float) -> SCNNode {
            let geometry = SCNText(string: string, extrusionDepth: 0)
            geometry.font = .systemFont(ofSize: 18, weight: .semibold)
            geometry.flatness = 0.3
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.white
            material.lightingModel = .constant
            material.isDoubleSided = true
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            let box = geometry.boundingBox
            let scale = height / max(1, box.max.y - box.min.y)
            node.simdScale = SIMD3(repeating: scale)
            node.position = SCNVector3(-(box.max.x + box.min.x) * scale / 2, y, 0)
            label.addChildNode(node)
            return node
        }
        _ = text(ally.kind.rawValue.capitalized, height: 0.12, y: 0.15)
        let hp = text("\(ally.health)/\(ally.kind.maxHealth)", height: 0.085, y: -0.025)
        ally.healthText = hp.geometry as? SCNText
        func bar(color: UIColor, depth: Float) -> SCNNode {
            let geometry = SCNPlane(width: 0.6, height: 0.045)
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.lightingModel = .constant
            material.isDoubleSided = true
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(0, 0.09, depth)
            label.addChildNode(node)
            return node
        }
        _ = bar(color: UIColor(white: 0.1, alpha: 0.9), depth: 0)
        ally.healthFill = bar(color: .systemGreen, depth: 0.002)
        label.categoryBitMask = 2
        label.enumerateChildNodes { node, _ in node.categoryBitMask = 2 }
        ally.node.addChildNode(label)
    }

    private func showSlam(at point: SIMD3<Float>, radius: Float) {
        showPulse(at: point, radius: radius, color: .orange)
        let root = SCNNode()
        root.name = "CompanionAttack"
        root.categoryBitMask = 2
        root.simdPosition = point
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.orange
        material.emission.contents = UIColor.red
        material.lightingModel = .constant
        material.blendMode = .add
        for index in 0..<8 {
            let angle = Float(index) * .pi / 4
            let geometry = SCNBox(width: 0.018, height: 0.008, length: CGFloat(radius * 0.7), chamferRadius: 0)
            geometry.materials = [material]
            let crack = SCNNode(geometry: geometry)
            crack.categoryBitMask = 2
            crack.simdPosition = SIMD3(sin(angle) * radius * 0.5, 0, cos(angle) * radius * 0.5)
            crack.simdEulerAngles.y = angle
            root.addChildNode(crack)
        }
        scene.rootNode.addChildNode(root)
        root.runAction(.sequence([.fadeOut(duration: 0.6), .removeFromParentNode()]))
    }

    private func showBreath(from ally: Companion) {
        let node = SCNNode()
        node.name = "CompanionAttack"
        node.categoryBitMask = 2
        let forward = SIMD3<Float>(sin(ally.node.simdEulerAngles.y), 0, cos(ally.node.simdEulerAngles.y))
        node.simdPosition =
            CharacterAnimation.attachment("mouth", on: ally.node)?.simdWorldPosition ?? (ally.center + forward * 0.35)
        node.simdEulerAngles.y = ally.node.simdEulerAngles.y
        let flame = SCNParticleSystem()
        flame.birthRate = 180
        flame.emissionDuration = 0.65
        flame.loops = false
        flame.particleLifeSpan = 0.65
        flame.particleLifeSpanVariation = 0.12
        flame.particleVelocity = 3.8
        flame.particleVelocityVariation = 0.6
        flame.emittingDirection = SCNVector3(0, 0, 1)
        flame.spreadingAngle = 20
        flame.particleSize = 0.13
        flame.particleSizeVariation = 0.08
        flame.particleColor = UIColor(red: 1, green: 0.3, blue: 0.025, alpha: 0.85)
        flame.blendMode = .additive
        flame.isLightingEnabled = false
        flame.isLocal = false
        node.addParticleSystem(flame)
        scene.rootNode.addChildNode(node)
        node.runAction(.sequence([.wait(duration: 1.5), .removeFromParentNode()]))
    }

    private func showPulse(at point: SIMD3<Float>, radius: Float, color: UIColor) {
        let ring = SCNTorus(ringRadius: CGFloat(radius), pipeRadius: 0.015)
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        material.blendMode = .add
        material.writesToDepthBuffer = false
        ring.materials = [material]
        let node = SCNNode(geometry: ring)
        node.name = "CompanionAttack"
        node.categoryBitMask = 2
        node.simdPosition = point
        scene.rootNode.addChildNode(node)
        node.runAction(.sequence([.fadeOut(duration: 0.5), .removeFromParentNode()]))
    }
}
