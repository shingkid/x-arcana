import SceneKit
import UIKit
import simd

/// A small, repeatable encounter. Positions and speeds are in metres.
final class Combat {
    static let zombieMaxHealth: Double = 2
    static let spawnInterval: TimeInterval = 8
    static func spawnInterval(for level: Int) -> TimeInterval {
        max(2, spawnInterval * pow(0.9, Double(max(0, level - 1))))
    }
    static func zombieDamage(for level: Int) -> Double { 1 + 0.5 * Double(max(0, level - 1)) }
    static let bowReloadDuration: TimeInterval = 0.4
    static let waveBreakDuration: TimeInterval = 20

    enum Event: Equatable {
        case waveCleared(Int)
        case waveStarted(Int)
    }

    struct Identity: Decodable {
        let id: String
        let name: String
        let image: String
    }

    enum Kind: String {
        case zombie

        var halfWidth: Float { 0.38 }
        var halfDepth: Float { 0.46 }
    }

    enum MeleeAttack: String { case swipe, bite }

    final class CombatantNode: SCNNode {
        var identityID = ""
        var identityName = ""
        var kind: Kind = .zombie
        var isDefeated = false
        var appearanceVariant = 0
        private(set) var lastMeleeAttack: MeleeAttack?
        private(set) var meleeAttackCount = 0
        func recordMelee(_ attack: MeleeAttack) {
            lastMeleeAttack = attack
            meleeAttackCount += 1
        }
        private(set) var health: Double = Combat.zombieMaxHealth
        private(set) var isTransfigured = false
        func setTransfigured(_ value: Bool) { isTransfigured = value }
        private(set) var slowRemaining: TimeInterval = 0
        func setSlowRemaining(_ value: TimeInterval) { slowRemaining = value }
        func setHealth(_ value: Double) { health = value }
    }

    static let identities: [Identity] = {
        guard let url = Bundle.main.url(forResource: "roster", withExtension: "json", subdirectory: "NPCPortraits"),
            let data = try? Data(contentsOf: url),
            let roster = try? JSONDecoder().decode([Identity].self, from: data)
        else { return [] }
        return roster
    }()

    private final class Enemy {
        let node: CombatantNode
        let animations: [SCNAnimationPlayer]
        let attackPose: SCNNode?
        let identity: Identity
        let kind: Kind
        let phase: Float
        let maxHealth = Combat.zombieMaxHealth
        var health: Double = Combat.zombieMaxHealth
        var attackTimer: TimeInterval
        var motionTime: TimeInterval = 0
        var meleeMotion: (time: TimeInterval, attack: MeleeAttack)?
        var velocity = SIMD3<Float>.zero
        var slowUntil: TimeInterval = 0
        var transfiguration: RainbowCat?
        var hiddenOriginals: [SCNNode] = []
        var pendingMelee: (remaining: TimeInterval, target: SCNNode?, attack: MeleeAttack)?
        var center: SIMD3<Float> { node.simdPosition + SIMD3(0, 1.05 * node.simdScale.y, 0) }

        init(node: CombatantNode, identity: Identity, kind: Kind, index: Int) {
            self.node = node
            self.identity = identity
            self.kind = kind
            phase = Float(index) * 1.7
            attackTimer = 1 + Double(index) * 0.15
            attackPose = node.childNode(withName: "Melee pose", recursively: true)
            var players: [SCNAnimationPlayer] = []
            node.enumerateChildNodes { child, _ in
                for key in child.animationKeys {
                    if let player = child.animationPlayer(forKey: key) {
                        player.animation.timeOffset = Double(index) * 0.13
                        player.animation.repeatCount = .infinity
                        player.speed = 0.65
                        players.append(player)
                    }
                }
            }
            animations = players
        }
    }

    private struct Projectile {
        let node: SCNNode
        let velocity: SIMD3<Float>
        let blastRadius: Float
        let isLightning: Bool
        var age: TimeInterval = 0
    }

    private let scene: SCNScene
    private let camera: SCNNode
    private let floorY: Float
    private let environment: EnvironmentDefinition
    private let root = SCNNode()
    private var enemies: [Enemy] = []
    private var projectiles: [Projectile] = []
    private var lastTime: TimeInterval?
    private var elapsed: TimeInterval = 0
    private var nextWave: TimeInterval?
    private var spawnedThisWave = 0
    private var nextSpawn: TimeInterval = 0
    private var shotCooldown: TimeInterval = 0
    private var meleeCooldown: TimeInterval = 0
    private var shieldNode: SCNNode?
    private var countdownNotifyDelay: TimeInterval = 0
    private lazy var allies = SummonCombat(scene: scene, environment: environment)
    private let run: SurvivalState
    private var isPaused = false
    private var nextNotification: TimeInterval = 0
    private(set) var lastRejection: CombatRejection?
    var runSnapshot: RunSnapshot { run.snapshot }
    var transfigurationPhase: TimeInterval? {
        run.snapshot.nyanRemaining > 0 ? SurvivalState.nyanDuration - run.snapshot.nyanRemaining : nil
    }
    var onChange: (() -> Void)?
    var onEvent: ((Event) -> Void)?
    var kills: Int { run.snapshot.kills }
    var wave: Int { run.snapshot.wave }
    private(set) var blockedAttacks = 0
    var remaining: Int { enemies.filter { $0.health > 0 }.count }
    var pendingSpawns: Int { run.snapshot.hasStarted && run.snapshot.countdownRemaining <= 0 ? 8 - spawnedThisWave : 0 }
    var onStatus: ((String) -> Void)?
    var summary: String { "Level \(wave) · \(remaining) zombies · \(kills) defeated" }

    convenience init(
        scene: SCNScene, camera: SCNNode, floorY: Float,
        defaults: UserDefaults? = .standard, startsImmediately: Bool = true, state: SurvivalState? = nil
    ) {
        var environment = EnvironmentDefinition.fantasy
        environment.floorY = floorY
        environment.enemySpawns = environment.enemySpawns.map {
            EnvironmentDefinition.Point(x: $0.x, y: floorY, z: $0.z)
        }
        self.init(
            scene: scene, camera: camera, environment: environment,
            defaults: defaults, startsImmediately: startsImmediately, state: state)
    }

    init(
        scene: SCNScene, camera: SCNNode, environment: EnvironmentDefinition,
        defaults: UserDefaults? = .standard, startsImmediately: Bool = true, state: SurvivalState? = nil
    ) {
        run = state ?? SurvivalState(defaults: defaults, hasStarted: startsImmediately)
        self.scene = scene
        self.camera = camera
        self.floorY = environment.floorY
        self.environment = environment
        root.name = "Undead horde"
        root.categoryBitMask = 2
        scene.rootNode.addChildNode(root)
        if startsImmediately { spawnWave() }
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        lastTime = nil
        freezeVisuals(paused || run.snapshot.isGameOver)
    }

    func restart() {
        finishTransfiguration(defeat: false)
        allies.reset()
        for child in root.childNodes { child.removeFromParentNode() }
        enemies.removeAll()
        projectiles.removeAll()
        shieldNode = nil
        run.restart(hasStarted: false)
        spawnedThisWave = 0
        countdownNotifyDelay = 0
        elapsed = 0
        nextWave = nil
        nextNotification = 0
        shotCooldown = 0
        meleeCooldown = 0
        lastTime = nil
        blockedAttacks = 0
        lastRejection = nil
        root.isPaused = isPaused
        onChange?()
    }

    func resetScores() {
        run.clearRecords()
        restart()
    }

    @discardableResult
    func startRun() -> Bool {
        guard !isPaused, run.beginCountdown() else { return false }
        countdownNotifyDelay = 0.25
        onChange?()
        return true
    }

    @discardableResult
    func nyan() -> Bool {
        lastRejection = nil
        guard !run.snapshot.isGameOver else {
            lastRejection = .gameOver
            return false
        }
        guard !isPaused else {
            lastRejection = .paused
            return false
        }
        guard run.snapshot.hasStarted, run.snapshot.countdownRemaining <= 0 else {
            lastRejection = .notReady
            return false
        }
        guard run.snapshot.nyanRemaining <= 0 else {
            lastRejection = .cooldown
            return false
        }
        guard remaining > 0, run.snapshot.nyanKillsSinceCast >= 20 else {
            lastRejection = .cooldown
            return false
        }
        guard run.activateNyan(manaCost: SpellCatalog.nyan.manaCost) else {
            lastRejection = .insufficientMana
            return false
        }
        for enemy in enemies where enemy.health > 0 { transfigure(enemy) }
        allies.cancelAttacks()
        onChange?()
        return true
    }

    func summon(kind: SummonKind, makeNode: () -> SCNNode?) -> SummonResult {
        guard !run.snapshot.isGameOver else { return .gameOver }
        guard !isPaused, run.snapshot.hasStarted, run.snapshot.countdownRemaining <= 0 else { return .unavailable }
        guard !allies.contains(kind) else { return .alreadyActive }
        guard run.canSpend(kind == .demon ? SummonCombat.demonManaPerSecond : SpellCatalog.summon(kind).manaCost) else {
            return .insufficientMana
        }
        guard let node = makeNode() else { return .unavailable }
        // Creation succeeds before existing companions are removed or mana is spent.
        guard run.spend(SpellCatalog.summon(kind).manaCost) else {
            node.removeFromParentNode()
            return .insufficientMana
        }
        allies.register(kind: kind, node: node)
        SpellVisuals.entrance(on: node, kind: kind)
        onChange?()
        return .summoned
    }

    func update(at time: TimeInterval) {
        guard time.isFinite else { return }
        guard let previous = lastTime else {
            lastTime = time
            return
        }
        guard time > previous else { return }
        let dt = min(0.05, time - previous)
        lastTime = time
        guard !isPaused, !run.snapshot.isGameOver, dt > 0 else { return }
        guard run.snapshot.hasStarted else { return }
        if run.snapshot.countdownRemaining > 0 {
            run.advanceCountdown(deltaTime: dt)
            countdownNotifyDelay -= dt
            if run.snapshot.countdownRemaining <= 0 {
                spawnWave()
                onStatus?("Go! \(summary)")
            }
            if countdownNotifyDelay <= 0 || run.snapshot.countdownRemaining <= 0 {
                countdownNotifyDelay = 0.25
                onChange?()
            }
            return
        }
        elapsed += dt
        let wasNyanActive = run.snapshot.nyanRemaining > 0
        let demonTime = min(dt, allies.demonRemaining)
        if demonTime > 0 {
            let cost = min(run.snapshot.mana, demonTime * SummonCombat.demonManaPerSecond)
            _ = run.spend(cost)
            if run.snapshot.mana <= 0.000001 { allies.dismissDemon() }
        }
        run.update(deltaTime: dt, suppressRegeneration: demonTime > 0)
        if wasNyanActive, run.snapshot.nyanRemaining <= 0 {
            finishTransfiguration(defeat: true)
        }
        if (run.snapshot.shieldHealth ?? 0) <= 0 {
            shieldNode?.removeFromParentNode()
            shieldNode = nil
        } else {
            shieldNode?.simdPosition = camera.simdWorldPosition + SIMD3(0, -0.55, 0)
        }
        shotCooldown = max(0, shotCooldown - dt)
        meleeCooldown = max(0, meleeCooldown - dt)
        if let nextWave, elapsed >= nextWave {
            self.nextWave = nil
            run.nextWave()
            spawnWave()
            onStatus?("A new level has started. \(summary)")
            onChange?()
        }
        if run.snapshot.nyanRemaining <= 0, pendingSpawns > 0, elapsed >= nextSpawn {
            spawnNextZombie()
            onStatus?(summary)
            onChange?()
        }
        let player = camera.simdWorldPosition
        for enemy in enemies where enemy.health > 0 {
            guard !run.snapshot.isGameOver else { break }
            if let cat = enemy.transfiguration {
                cat.update(deltaTime: dt)
                enemy.node.setSlowRemaining(max(0, enemy.slowUntil - elapsed))
                continue
            }
            let physicalAllies = allies.physicalTargets
            let nearestAlly = physicalAllies.min {
                horizontalDistance(enemy.center, $0.center) < horizontalDistance(enemy.center, $1.center)
            }
            let victim = nearestAlly.flatMap {
                horizontalDistance(enemy.center, $0.center) < horizontalDistance(enemy.center, player) ? $0 : nil
            }
            let target = victim?.center ?? player
            var toward = target - enemy.node.simdPosition
            toward.y = 0
            let distance = simd_length(toward)
            let speed: Float = enemy.slowUntil > elapsed ? 0.5 : 1
            enemy.node.setSlowRemaining(max(0, enemy.slowUntil - elapsed))
            for attack in [MeleeAttack.swipe, .bite] {
                enemy.attackPose?.action(forKey: "melee.\(attack.rawValue)")?.speed = CGFloat(speed)
            }
            enemy.velocity = .zero
            if enemy.pendingMelee == nil, distance > 0.95 {
                enemy.velocity = toward / distance * min(0.48 * speed, (distance - 0.95) / Float(dt))
            }
            for other in enemies where other !== enemy && other.health > 0 {
                var apart = enemy.node.simdPosition - other.node.simdPosition
                apart.y = 0
                let gap = simd_length(apart)
                if gap > 0.001, gap < 0.72 { enemy.velocity += apart / gap * (0.72 - gap) * speed }
            }
            for ally in physicalAllies {
                var apart = enemy.node.simdPosition - ally.center
                apart.y = 0
                let gap = simd_length(apart)
                if gap > 0.001, gap < 0.65 { enemy.velocity += apart / gap * (0.65 - gap) * speed }
            }
            var position = enemy.node.simdPosition + enemy.velocity * Float(dt)
            position = environment.movementBounds.clamped(position)
            let fromTarget = SIMD3(position.x - target.x, 0, position.z - target.z)
            let clearance = simd_length(fromTarget)
            if clearance > 0.001, clearance < 0.9 { position += fromTarget / clearance * (0.9 - clearance) }
            position = environment.movementBounds.clamped(position)
            enemy.node.simdPosition = position
            enemy.node.simdEulerAngles.y = atan2(toward.x, toward.z)
            enemy.motionTime += dt * Double(speed)
            if var melee = enemy.meleeMotion {
                melee.time += dt * Double(speed)
                enemy.meleeMotion = melee.time < 0.625 ? melee : nil
                ZombieAppearance.sampleMotion(melee.attack.rawValue, at: melee.time, on: enemy.node)
            } else {
                let walking = simd_length(enemy.velocity) > 0.03
                let time = enemy.motionTime + Double(enemy.phase)
                ZombieAppearance.sampleMotion(walking ? "walk" : "idle", at: time, on: enemy.node)
            }
            enemy.attackTimer -= dt * Double(speed)
            if var pending = enemy.pendingMelee {
                pending.remaining -= dt * Double(speed)
                enemy.pendingMelee = pending
                if pending.remaining <= 0 {
                    enemy.pendingMelee = nil
                    let stillLiving = pending.target.map { allies.isLiving($0) } ?? !run.snapshot.isGameOver
                    let contact =
                        pending.target.map { $0.simdWorldPosition + SIMD3(0, 1, 0) } ?? camera.simdWorldPosition
                    if stillLiving, horizontalDistance(enemy.center, contact) <= 1.35,
                        abs(contact.y - enemy.center.y) < 1.5
                    {
                        let amount = Self.zombieDamage(for: wave)
                        if let ally = pending.target {
                            allies.damage(node: ally, amount: amount)
                        } else {
                            let shielded = (run.snapshot.shieldHealth ?? 0) > 0
                            run.damage(amount)
                            if shielded {
                                blockedAttacks += 1
                                if let shieldNode { SpellVisuals.shieldContact(on: shieldNode, at: enemy.center) }
                                onStatus?(
                                    "Shield blocked a \(pending.attack.rawValue). \(run.snapshot.shieldHealth ?? 0) shield HP left."
                                )
                                if run.snapshot.shieldHealth == 0 {
                                    shieldNode?.removeFromParentNode()
                                    shieldNode = nil
                                }
                            } else {
                                onStatus?(
                                    run.snapshot.isGameOver
                                        ? "Game over. Score \(run.snapshot.score)."
                                        : "Zombie \(pending.attack.rawValue): -\(amount) health.")
                            }
                            onChange?()
                            if run.snapshot.isGameOver {
                                finishTransfiguration(defeat: false)
                                freezeVisuals(true)
                            }
                        }
                    }
                }
            } else if enemy.attackTimer <= 0, horizontalDistance(enemy.center, target) <= 1.25,
                abs(target.y - enemy.center.y) < 1.5
            {
                enemy.attackTimer = 2.6 + Double(enemy.node.appearanceVariant) * 0.25
                performMelee(enemy, target: victim?.node)
            }
        }
        guard !run.snapshot.isGameOver else { return }
        updateProjectiles(dt: dt)
        let targets = enemies.filter { $0.health > 0 && $0.transfiguration == nil }.map {
            SummonCombat.Target(node: $0.node, center: $0.center)
        }
        for impact in allies.update(deltaTime: dt, targets: targets) {
            guard let enemy = enemies.first(where: { $0.node === impact.node }), enemy.health > 0 else { continue }
            if impact.damage > 0 { damage(enemy, amount: Double(impact.damage)) }
            if impact.slowDuration > 0 {
                applySlow(to: enemy, duration: impact.slowDuration)
            }
        }
        if elapsed >= nextNotification {
            nextNotification = elapsed + 0.25
            onChange?()
        }
    }

    private func transfigure(_ enemy: Enemy) {
        guard enemy.health > 0, enemy.transfiguration == nil else { return }
        enemy.pendingMelee = nil
        enemy.velocity = .zero
        enemy.node.removeAllActions()
        enemy.node.opacity = 1
        enemy.attackPose?.removeAllActions()
        for animation in enemy.animations { animation.paused = true }
        enemy.hiddenOriginals = enemy.node.childNodes.filter { !$0.isHidden }
        for original in enemy.hiddenOriginals { original.isHidden = true }
        enemy.node.setTransfigured(true)
        enemy.transfiguration = RainbowCat(
            parent: enemy.node, floorY: 0, anchored: true, phaseOffset: enemy.phase, camera: camera)
    }

    private func finishTransfiguration(defeat: Bool) {
        if defeat { nextSpawn = elapsed + Self.spawnInterval(for: wave) }
        for enemy in enemies where enemy.transfiguration != nil {
            enemy.transfiguration?.remove()
            enemy.transfiguration = nil
            enemy.node.setTransfigured(false)
            if defeat {
                // Original bodies stay hidden. The cats disappear at the song boundary.
                damage(enemy, amount: enemy.health)
            } else {
                for original in enemy.hiddenOriginals { original.isHidden = false }
                for animation in enemy.animations { animation.paused = false }
            }
            enemy.hiddenOriginals.removeAll()
        }
    }

    private func horizontalDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        simd_length(SIMD2(a.x - b.x, a.z - b.z))
    }

    private func freezeVisuals(_ paused: Bool) {
        root.isPaused = paused
        for child in scene.rootNode.childNodes where child.name == "CompanionAttack" { child.isPaused = paused }
        allies.setPaused(paused)
    }

    @discardableResult
    func shoot(toward target: SIMD3<Float>) -> Bool {
        fire(toward: target, attack: .arrow)
    }

    @discardableResult
    func cast(toward target: SIMD3<Float>) -> Bool {
        fire(toward: target, attack: .zap)
    }

    @discardableResult
    func fireball(toward target: SIMD3<Float>) -> Bool {
        fire(toward: target, attack: .fireball)
    }

    @discardableResult
    func ice(toward target: SIMD3<Float>) -> Bool {
        guard validateAction(cost: SpellCatalog.ice.manaCost, usesShotCooldown: true) else { return false }
        let eye = camera.simdWorldPosition
        let ray = target - eye
        guard target.x.isFinite, target.y.isFinite, target.z.isFinite, simd_length_squared(ray) > 0.0001 else {
            lastRejection = .invalidTarget
            return false
        }
        let direction = simd_normalize(ray)
        _ = run.spend(SpellCatalog.ice.manaCost)
        shotCooldown = 0.24
        showIce(from: eye, direction: direction)
        for enemy in enemies where enemy.health > 0 && enemy.transfiguration == nil {
            let offset = enemy.center - eye
            let length = simd_length(offset)
            guard length <= 5, length > 0.001, simd_dot(offset / length, direction) >= cos(Float.pi / 6) else {
                continue
            }
            damage(enemy, amount: 2)
            if enemy.health > 0 { applySlow(to: enemy, duration: 6) }
        }
        onChange?()
        return true
    }

    @discardableResult
    func melee(toward target: SIMD3<Float>) -> Bool {
        guard validateAction(cost: 0, usesShotCooldown: false) else { return false }
        guard meleeCooldown <= 0 else {
            lastRejection = .cooldown
            return false
        }
        let eye = camera.simdWorldPosition
        let ray = target - eye
        guard target.x.isFinite, target.y.isFinite, target.z.isFinite, simd_length_squared(ray) > 0.0001 else {
            lastRejection = .invalidTarget
            return false
        }
        let direction = simd_normalize(ray)
        let victim = enemies.filter { enemy in
            guard enemy.health > 0, enemy.transfiguration == nil else { return false }
            let offset = enemy.center - eye
            let distance = simd_length(offset)
            return distance <= 2 && distance > 0.001 && simd_dot(offset / distance, direction) >= 0.5
        }.min { simd_distance($0.center, eye) < simd_distance($1.center, eye) }
        meleeCooldown = 0.5
        if let victim {
            damage(victim)
            burst(at: victim.center, color: .cyan)
        }
        return true
    }

    @discardableResult
    func shield() -> Bool {
        lastRejection = nil
        guard !run.snapshot.isGameOver else {
            lastRejection = .gameOver
            return false
        }
        guard !isPaused else {
            lastRejection = .paused
            return false
        }
        guard run.snapshot.hasStarted, run.snapshot.countdownRemaining <= 0 else {
            lastRejection = .notReady
            return false
        }
        guard (run.snapshot.shieldHealth ?? 0) == 0, run.snapshot.shieldCooldownRemaining <= 0 else {
            lastRejection = .cooldown
            return false
        }
        guard run.activateShield(manaCost: SpellCatalog.shield.manaCost) else {
            lastRejection = .insufficientMana
            return false
        }
        showShield()
        onChange?()
        return true
    }

    private func validateAction(cost: Double, usesShotCooldown: Bool) -> Bool {
        lastRejection = nil
        guard !run.snapshot.isGameOver else {
            lastRejection = .gameOver
            return false
        }
        guard !isPaused else {
            lastRejection = .paused
            return false
        }
        guard run.snapshot.hasStarted, run.snapshot.countdownRemaining <= 0 else {
            lastRejection = .notReady
            return false
        }
        guard !usesShotCooldown || shotCooldown <= 0 else {
            lastRejection = .cooldown
            return false
        }
        guard run.canSpend(cost) else {
            lastRejection = .insufficientMana
            return false
        }
        return true
    }

    private func applySlow(to enemy: Enemy, duration: TimeInterval) {
        enemy.slowUntil = max(enemy.slowUntil, elapsed + duration)
        enemy.node.setSlowRemaining(max(0, enemy.slowUntil - elapsed))
        for attack in [MeleeAttack.swipe, .bite] {
            enemy.attackPose?.action(forKey: "melee.\(attack.rawValue)")?.speed = 0.5
        }
    }

    private func showShield() {
        shieldNode?.removeFromParentNode()
        let dome = SCNSphere(radius: 1.3)
        dome.segmentCount = 18
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.25, green: 0.7, blue: 1, alpha: 0.15)
        material.emission.contents = UIColor(red: 0.1, green: 0.35, blue: 0.55, alpha: 1)
        material.lightingModel = .constant
        material.fillMode = .lines
        material.transparency = 0.24
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.blendMode = .add
        dome.materials = [material]
        let node = SCNNode(geometry: dome)
        node.name = "Player shield"
        node.categoryBitMask = 2
        node.simdPosition = camera.simdWorldPosition + SIMD3(0, -0.55, 0)
        root.addChildNode(node)
        shieldNode = node
        SpellVisuals.shieldActivation(on: node)
    }

    private func showIce(from origin: SIMD3<Float>, direction: SIMD3<Float>) {
        SpellVisuals.ice(from: origin, direction: direction, on: root)
    }

    private enum Attack { case arrow, zap, fireball }

    private func fire(toward target: SIMD3<Float>, attack: Attack) -> Bool {
        lastRejection = nil
        guard !run.snapshot.isGameOver else {
            lastRejection = .gameOver
            return false
        }
        guard !isPaused else {
            lastRejection = .paused
            return false
        }
        guard run.snapshot.hasStarted, run.snapshot.countdownRemaining <= 0 else {
            lastRejection = .notReady
            return false
        }
        guard shotCooldown <= 0 else {
            lastRejection = .cooldown
            return false
        }
        guard target.x.isFinite, target.y.isFinite, target.z.isFinite else {
            lastRejection = .invalidTarget
            return false
        }
        let cost: Double =
            attack == .arrow ? 0 : (attack == .zap ? SpellCatalog.lightning.manaCost : SpellCatalog.fireball.manaCost)
        guard run.canSpend(cost) else {
            lastRejection = .insufficientMana
            return false
        }
        let eye = camera.simdWorldPosition
        let ray = target - eye
        guard simd_length_squared(ray) > 0.0001 else {
            lastRejection = .invalidTarget
            return false
        }
        let direction = simd_normalize(ray)
        let speed: Float = attack == .arrow ? 12 : 10
        // The projectile starts below the sight line, at the visible wand or bow.
        let origin = eye + camera.simdWorldOrientation.act(SIMD3(0.10, -0.13, -0.33))
        var destination = eye + direction * 15
        var bestScore: Float = .greatestFiniteMagnitude
        for enemy in enemies where enemy.health > 0 && enemy.transfiguration == nil {
            let offset = enemy.center - eye
            let along = simd_dot(offset, direction)
            guard along > 0.3, along < 14 else { continue }
            let miss = simd_length(offset - direction * along)
            // A visible nine-degree cone helps with hand and head tracking noise.
            guard miss < max(0.5, along * 0.16) else { continue }
            let score = miss / along + along * 0.001
            if score < bestScore {
                bestScore = score
                destination = enemy.center + enemy.velocity * (simd_distance(origin, enemy.center) / speed)
            }
        }
        let travel = simd_normalize(destination - origin)
        let node: SCNNode
        switch attack {
        case .arrow:
            node = makeArrow()
            node.name = "Flying arrow"
        case .zap:
            node = orb(color: UIColor(red: 0.32, green: 0.78, blue: 1, alpha: 1), radius: 0.065)
            node.name = "Magic bolt"
            let core = orb(color: UIColor(red: 0.7, green: 0.95, blue: 1, alpha: 1), radius: 0.035)
            core.simdScale = SIMD3(0.75, 4, 0.75)
            node.addChildNode(core)
        case .fireball:
            node = orb(color: UIColor(red: 1, green: 0.31, blue: 0.035, alpha: 1), radius: 0.13)
            node.name = "Combat fireball"
            let sparks = SCNParticleSystem()
            sparks.birthRate = UIAccessibility.isReduceMotionEnabled ? 35 : 95
            sparks.particleLifeSpan = 0.35
            sparks.particleSize = 0.035
            sparks.particleColor = .orange
            sparks.particleVelocity = 0.15
            sparks.spreadingAngle = 180
            sparks.blendMode = .additive
            sparks.isLocal = false
            node.addParticleSystem(sparks)
        }
        node.simdPosition = origin
        node.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: travel)
        root.addChildNode(node)
        projectiles.append(
            Projectile(
                node: node, velocity: travel * speed,
                blastRadius: attack == .fireball ? 3 : 0, isLightning: attack == .zap))
        shotCooldown = attack == .arrow ? Self.bowReloadDuration : 0.24
        _ = run.spend(cost)
        onChange?()
        return true
    }

    private func performMelee(_ enemy: Enemy, target: SCNNode?) {
        let attack: MeleeAttack =
            (enemy.node.appearanceVariant + enemy.node.meleeAttackCount).isMultiple(of: 2)
            ? .swipe : .bite
        enemy.node.recordMelee(attack)
        enemy.pendingMelee = (0.34, target, attack)
        enemy.meleeMotion = (0, attack)
        if let pose = enemy.attackPose {
            pose.removeAllActions()
            pose.simdPosition = .zero
            pose.simdEulerAngles = .zero
            // The joints use simulation time above; this marker retains attack presentation timing.
            let strike = SCNAction.wait(duration: 0.64)
            strike.speed = enemy.slowUntil > elapsed ? 0.5 : 1
            pose.runAction(strike, forKey: "melee.\(attack.rawValue)")
        }

    }

    private func updateProjectiles(dt: TimeInterval) {
        for index in projectiles.indices.reversed() {
            projectiles[index].age += dt
            let projectile = projectiles[index]
            let start = projectile.node.simdPosition
            let end = start + projectile.velocity * Float(dt)
            var impact: Float?
            var victim: Enemy?
            for enemy in enemies where enemy.health > 0 && enemy.transfiguration == nil {
                let foot = enemy.node.simdPosition
                let padding: Float = projectile.blastRadius > 0 ? 0.2 : 0.12
                if let fraction = CombatGeometry.hitFraction(
                    from: start, to: end,
                    minimum: foot + SIMD3(-enemy.kind.halfWidth, 0.12, -enemy.kind.halfDepth) * enemy.node.simdScale
                        - SIMD3(repeating: padding),
                    maximum: foot + SIMD3(enemy.kind.halfWidth, 1.82, enemy.kind.halfDepth) * enemy.node.simdScale
                        + SIMD3(repeating: padding)),
                    fraction < (impact ?? 2)
                {
                    impact = fraction
                    victim = enemy
                }
            }
            let options: [String: Any] = [
                SCNHitTestOption.categoryBitMask.rawValue: 1,
                SCNHitTestOption.backFaceCulling.rawValue: false,
                SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue,
            ]
            let wall = scene.rootNode.hitTestWithSegment(from: SCNVector3(start), to: SCNVector3(end), options: options)
                .map {
                    simd_distance(start, SIMD3<Float>($0.worldCoordinates)) / max(0.0001, simd_distance(start, end))
                }.min()
            if let wall, wall < (impact ?? 2) {
                impact = wall
                victim = nil
            }
            if let impact {
                let point = start + (end - start) * impact
                if projectile.blastRadius > 0 {
                    explode(at: point, radius: projectile.blastRadius)
                } else {
                    if projectile.isLightning {
                        SpellVisuals.lightning(at: point, on: root)
                    } else {
                        burst(at: point, color: victim == nil ? .cyan : .orange)
                    }
                    if let victim { damage(victim, amount: projectile.isLightning ? 2 : victim.maxHealth / 3) }
                }
            }
            if impact != nil || projectile.age > 4 || end.y < floorY || !environment.projectileBounds.contains(end) {
                if impact == nil, projectile.blastRadius > 0 { explode(at: end, radius: projectile.blastRadius) }
                projectile.node.removeFromParentNode()
                projectiles.remove(at: index)
            } else {
                projectile.node.simdPosition = end
            }
        }
    }

    private func damage(_ enemy: Enemy, amount: Double = 1) {
        guard !run.snapshot.isGameOver, enemy.health > 0, enemy.transfiguration == nil else { return }
        let residualHealth = max(0, enemy.health - amount)
        // Three equal fractional arrow hits must not leave a floating-point sliver alive.
        enemy.health = residualHealth <= enemy.maxHealth * 1e-12 ? 0 : residualHealth
        enemy.node.setHealth(enemy.health)
        enemy.node.removeAction(forKey: "hit")
        guard enemy.health <= 0 else {
            enemy.node.runAction(
                .sequence([.fadeOpacity(to: 0.45, duration: 0.06), .fadeIn(duration: 0.16)]), forKey: "hit")
            return
        }
        enemy.node.opacity = 1
        run.recordKill()
        enemy.pendingMelee = nil
        onChange?()
        enemy.node.isDefeated = true
        for animation in enemy.animations { animation.paused = true }
        enemy.attackPose?.removeAllActions()
        enemy.node.runAction(
            .sequence([
                .group([
                    .rotateBy(x: -.pi / 2, y: 0, z: 0.12, duration: 0.4),
                    .moveBy(x: 0, y: -0.1, z: 0, duration: 0.4),
                ]),
                .wait(duration: 0.35), .fadeOut(duration: 0.7), .removeFromParentNode(),
            ]))
        if remaining == 0, pendingSpawns == 0, nextWave == nil {
            run.clearWave()
            onEvent?(.waveCleared(wave))
            onChange?()
            nextWave = elapsed + Self.waveBreakDuration
            onStatus?("Level cleared. The next level starts in twenty seconds.")
        } else {
            onStatus?("\(enemy.identity.name)'s \(enemy.kind.rawValue) defeated. \(summary)")
        }
    }

    private func spawnWave() {
        for enemy in enemies { enemy.node.removeFromParentNode() }
        enemies.removeAll()
        spawnedThisWave = 0
        spawnNextZombie()
        onEvent?(.waveStarted(wave))
    }

    private func spawnNextZombie() {
        guard pendingSpawns > 0 else { return }
        let positions = environment.enemySpawns
        let roster = Self.identities.isEmpty ? [Identity(id: "unknown", name: "Lost soul", image: "")] : Self.identities
        let index = spawnedThisWave
        let point = positions[index % positions.count]
        let kind: Kind = .zombie
        let identity = roster[((wave - 1) * positions.count + index) % roster.count]
        let body = ZombieAppearance.make(identity: identity, index: index)
        if let model = body.childNode(withName: "Office zombie", recursively: true) {
            let pose = SCNNode()
            pose.name = "Melee pose"
            pose.categoryBitMask = 2
            model.parent?.addChildNode(pose)
            pose.addChildNode(model)
        }
        let node = CombatantNode()
        node.categoryBitMask = 2
        node.addChildNode(body)
        node.name = "Enemy.\(identity.id).\(kind.rawValue)"
        node.identityID = identity.id
        node.identityName = identity.name
        node.kind = kind
        node.appearanceVariant = index % 4
        node.simdScale = ZombieAppearance.scale(for: index)
        node.simdPosition = point.vector
        root.addChildNode(node)
        let enemy = Enemy(node: node, identity: identity, kind: kind, index: index)
        enemies.append(enemy)
        if run.snapshot.nyanRemaining > 0 { transfigure(enemy) }
        spawnedThisWave += 1
        nextSpawn = elapsed + Self.spawnInterval(for: wave)
    }

    private func explode(at point: SIMD3<Float>, radius: Float) {
        SpellVisuals.fireball(at: point, radius: radius, floorY: floorY, on: root)
        let targets = enemies.filter { $0.health > 0 && $0.transfiguration == nil }
        let damages = CombatGeometry.fireballDamages(
            distances: targets.map { simd_distance($0.center, point) }, radius: radius)
        for (enemy, amount) in zip(targets, damages) where amount > 0 {
            damage(enemy, amount: amount)
        }
    }

    private func makeArrow() -> SCNNode {
        let node = SCNNode()
        node.categoryBitMask = 2
        let shaft = SCNCylinder(radius: 0.012, height: 0.48)
        shaft.firstMaterial = material(.init(red: 0.65, green: 0.36, blue: 0.13, alpha: 1), glowing: true)
        let shaftNode = SCNNode(geometry: shaft)
        shaftNode.categoryBitMask = 2
        node.addChildNode(shaftNode)
        let tip = SCNCone(topRadius: 0, bottomRadius: 0.045, height: 0.12)
        tip.firstMaterial = material(.init(red: 1, green: 0.88, blue: 0.52, alpha: 1), glowing: true)
        let tipNode = SCNNode(geometry: tip)
        tipNode.categoryBitMask = 2
        tipNode.position.y = 0.29
        node.addChildNode(tipNode)
        return node
    }

    private func orb(color: UIColor, radius: CGFloat) -> SCNNode {
        let shape = SCNSphere(radius: radius)
        shape.segmentCount = 12
        shape.firstMaterial = material(color, glowing: true)
        let node = SCNNode(geometry: shape)
        node.categoryBitMask = 2
        return node
    }

    private func material(_ color: UIColor, glowing: Bool = false) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.roughness.contents = 0.8
        if glowing {
            material.lightingModel = .constant
            material.emission.contents = color
        }
        return material
    }

    private func burst(at point: SIMD3<Float>, color: UIColor) {
        let node = orb(color: color, radius: 0.10)
        node.simdPosition = point
        root.addChildNode(node)
        node.runAction(
            .sequence([.group([.scale(to: 3.5, duration: 0.2), .fadeOut(duration: 0.24)]), .removeFromParentNode()]))
    }

}

/// Swept collision prevents fast arrows from passing through enemies between frames.
enum CombatGeometry {
    static func fireballDamages(distances: [Float], radius: Float) -> [Double] {
        guard radius.isFinite, radius > 0 else { return distances.map { _ in 0 } }
        let weights = distances.map { distance -> Double in
            guard distance.isFinite, distance >= 0, distance <= radius else { return 0 }
            return max(0.1, 1 - Double(distance / radius))
        }
        let total = weights.reduce(0, +)
        guard total > 0 else { return weights }
        return weights.map { 5 * $0 / total }
    }

    static func hitFraction(
        from start: SIMD3<Float>, to end: SIMD3<Float>,
        minimum: SIMD3<Float>, maximum: SIMD3<Float>
    ) -> Float? {
        let delta = end - start
        var entry: Float = 0
        var exit: Float = 1
        for axis in 0..<3 {
            if abs(delta[axis]) < 0.000001 {
                if start[axis] < minimum[axis] || start[axis] > maximum[axis] { return nil }
            } else {
                let a = (minimum[axis] - start[axis]) / delta[axis]
                let b = (maximum[axis] - start[axis]) / delta[axis]
                entry = max(entry, min(a, b))
                exit = min(exit, max(a, b))
                if entry > exit { return nil }
            }
        }
        return entry
    }
}
