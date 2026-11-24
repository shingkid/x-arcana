import SceneKit
import XCTest
import simd

@testable import XArcana

final class SummonCombatTests: XCTestCase {
    func testRegistryAllowsOneAlanAndAlbertAndReplacesOnlyOnRegistration() {
        let scene = SCNScene()
        let combat = SummonCombat(scene: scene)
        let alan = companion(.alan, in: combat)
        let albert = companion(.albert, in: combat)
        XCTAssertEqual(combat.companions.count, 2)
        XCTAssertEqual(combat.physicalTargets.count, 2)
        let demon = companion(.demon, in: combat)
        XCTAssertNil(alan.parent)
        XCTAssertNil(albert.parent)
        XCTAssertEqual(combat.companions.count, 1)
        XCTAssertTrue(combat.physicalTargets.first?.node === demon)
        _ = companion(.patronus, in: combat)
        XCTAssertNil(demon.parent)
        XCTAssertTrue(combat.physicalTargets.isEmpty)
    }

    func testUnregisteredSceneNamesCannotFight() {
        let scene = SCNScene()
        let node = SCNNode()
        node.name = "SummonedDemon"
        scene.rootNode.addChildNode(node)
        let combat = SummonCombat(scene: scene)
        let enemy = target(at: SIMD3(0, 1, 1), in: scene)
        XCTAssertTrue(advance(combat, seconds: 5, targets: [enemy]).isEmpty)
    }

    func testAlanMovesAndWhacksOnlyAtContactRange() {
        let scene = SCNScene()
        let combat = SummonCombat(scene: scene)
        let alan = companion(.alan, in: combat)
        let enemy = target(at: SIMD3(0, 1, 4), in: scene)
        XCTAssertTrue(advance(combat, seconds: 1, targets: [enemy]).isEmpty)
        XCTAssertGreaterThan(alan.simdPosition.z, 0.8)
        XCTAssertLessThan(alan.simdPosition.z, 1)
        let hits = advance(combat, seconds: 4, targets: [enemy])
        XCTAssertFalse(hits.isEmpty)
        XCTAssertTrue(hits.allSatisfy { $0.node === enemy.node && $0.damage == 1 && $0.slowDuration == 0 })
    }

    func testAlanAttackChecksTargetPositionAtContact() {
        let scene = SCNScene()
        let combat = SummonCombat(scene: scene)
        _ = companion(.alan, in: combat)
        let enemy = target(at: SIMD3(0, 1, 1), in: scene)
        XCTAssertTrue(advance(combat, seconds: 0.75, targets: [enemy]).isEmpty)
        enemy.node.simdPosition = SIMD3(0, 1, 6)
        let moved = SummonCombat.Target(node: enemy.node, center: enemy.node.simdPosition)
        XCTAssertTrue(advance(combat, seconds: 0.5, targets: [moved]).isEmpty)
    }

    func testAlbertSlamsForOneDamageInsideRadiusWithCooldown() {
        let scene = SCNScene()
        let combat = SummonCombat(scene: scene)
        _ = companion(.albert, in: combat)
        let near = target(at: SIMD3(0, 1, 1), in: scene)
        let clustered = target(at: SIMD3(1.2, 1, 0), in: scene)
        let far = target(at: SIMD3(1.4, 1, 0), in: scene)
        let hits = advance(combat, seconds: 1.15, targets: [near, clustered, far])
        XCTAssertEqual(hits.count, 2)
        XCTAssertTrue(hits.allSatisfy { $0.damage == 1 })
        XCTAssertFalse(hits.contains { $0.node === far.node })
        XCTAssertTrue(advance(combat, seconds: 2.8, targets: [near, clustered, far]).isEmpty)
        XCTAssertEqual(advance(combat, seconds: 0.7, targets: [near, clustered, far]).count, 2)
    }

    func testDemonComboHasTwoSeparateContactsAndDiesAtThirtyDamage() {
        let scene = SCNScene()
        let combat = SummonCombat(scene: scene)
        let demon = companion(.demon, in: combat)
        combat.companions[0].slamCooldown = 8
        combat.companions[0].breathCooldown = 10
        let enemy = target(at: SIMD3(0, 1, 1), in: scene)
        XCTAssertTrue(advance(combat, seconds: 0.9, targets: [enemy]).isEmpty)
        XCTAssertEqual(advance(combat, seconds: 0.15, targets: [enemy]).map(\.damage), [1])
        XCTAssertEqual(advance(combat, seconds: 0.3, targets: [enemy]).map(\.damage), [1])
        combat.damage(node: demon, amount: 29)
        XCTAssertTrue(combat.isLiving(demon))
        combat.damage(node: demon, amount: 1)
        XCTAssertFalse(combat.isLiving(demon))
        XCTAssertNil(demon.parent)
        XCTAssertTrue(advance(combat, seconds: 10, targets: [enemy]).isEmpty)
    }

    func testDemonExpiresAfterFiveSimulationSecondsAndCancelsPendingContacts() {
        let scene = SCNScene()
        let combat = SummonCombat(scene: scene)
        let demon = companion(.demon, in: combat)
        XCTAssertTrue(combat.hasActiveDemon)
        XCTAssertEqual(combat.demonRemaining, 5)
        _ = advance(combat, seconds: 4.7, targets: [])
        XCTAssertEqual(combat.demonRemaining, 0.3, accuracy: 0.000001)
        let enemy = target(at: SIMD3(0, 1, 1), in: scene)
        combat.companions[0].attack = SummonCombat.PendingAttack(style: .combo, target: enemy.node)
        combat.companions[0].attack?.elapsed = 0.25
        XCTAssertEqual(advance(combat, seconds: 0.25, targets: [enemy]).count, 1)
        XCTAssertTrue(combat.hasActiveDemon)
        XCTAssertTrue(advance(combat, seconds: 0.05, targets: [enemy]).isEmpty)
        XCTAssertFalse(combat.hasActiveDemon)
        XCTAssertEqual(combat.demonRemaining, 0)
        XCTAssertNil(demon.parent)
        XCTAssertTrue(combat.physicalTargets.isEmpty)
        XCTAssertTrue(advance(combat, seconds: 2, targets: [enemy]).isEmpty)
    }

    func testDemonPauseFreezesExpiryAndManaDismissalRemovesItImmediately() {
        let scene = SCNScene()
        let combat = SummonCombat(scene: scene)
        let demon = companion(.demon, in: combat)
        _ = advance(combat, seconds: 1, targets: [])
        combat.setPaused(true)
        _ = advance(combat, seconds: 10, targets: [])
        XCTAssertEqual(combat.demonRemaining, 4, accuracy: 0.000001)
        XCTAssertTrue(combat.hasActiveDemon)
        combat.setPaused(false)
        let enemy = target(at: SIMD3(0, 1, 1), in: scene)
        combat.companions[0].attack = SummonCombat.PendingAttack(style: .combo, target: enemy.node)
        combat.dismissDemon()
        combat.dismissDemon()
        XCTAssertFalse(combat.hasActiveDemon)
        XCTAssertEqual(combat.demonRemaining, 0)
        XCTAssertNil(demon.parent)
        XCTAssertTrue(combat.companions.isEmpty)
        XCTAssertTrue(advance(combat, seconds: 5, targets: [enemy]).isEmpty)
        _ = companion(.demon, in: combat)
        XCTAssertEqual(combat.demonRemaining, 5)
        combat.reset()
        XCTAssertFalse(combat.hasActiveDemon)
    }

    func testCompanionHealthPreservesFractionalStageDamage() {
        let scene = SCNScene()
        let combat = SummonCombat(scene: scene)
        let alan = companion(.alan, in: combat)
        combat.damage(node: alan, amount: 1.5)
        XCTAssertEqual(combat.companions[0].health, 13.5)
        XCTAssertEqual(combat.companions[0].healthText?.string as? String, "13.5/15")
        for amount in [Double.nan, .infinity, -1, 0] { combat.damage(node: alan, amount: amount) }
        XCTAssertEqual(combat.companions[0].health, 13.5)
        combat.damage(node: alan, amount: 13.5)
        XCTAssertFalse(combat.isLiving(alan))
        XCTAssertNil(alan.parent)
    }

    func testDemonBreathHitsConeOncePerEnemyAndSlamHasIndependentCooldown() {
        let scene = SCNScene()
        let combat = SummonCombat(scene: scene)
        let demon = companion(.demon, in: combat)
        let ally = combat.companions[0]
        ally.breathCooldown = 0
        ally.slamCooldown = 0
        let front = target(at: SIMD3(0, 1, 2), in: scene)
        let side = target(at: SIMD3(2, 1, 1), in: scene)
        let rear = target(at: SIMD3(0, 1, -2), in: scene)
        let hits = advance(combat, seconds: 0.55, targets: [front, front, side, rear])
        XCTAssertEqual(hits.count, 1)
        XCTAssertTrue(hits.first?.node === front.node)
        XCTAssertEqual(hits.first?.damage, 2)
        XCTAssertGreaterThan(ally.breathCooldown, 9)
        XCTAssertEqual(ally.slamCooldown, 0)
        let near = target(at: SIMD3(0, 1, 1), in: scene)
        let clustered = target(at: SIMD3(1, 1, 0), in: scene)
        let slam = advance(combat, seconds: 1.1, targets: [near, clustered])
        XCTAssertEqual(slam.map(\.damage), [1, 1])
        XCTAssertGreaterThan(ally.slamCooldown, 7)
        XCTAssertNotNil(demon.parent)
    }

    func testPatronusChargesLargestClusterSlowsWithoutDamageAndVanishes() {
        let scene = SCNScene()
        let combat = SummonCombat(scene: scene)
        let patronus = companion(.patronus, in: combat)
        let isolated = target(at: SIMD3(-2, 1, 0), in: scene)
        let a = target(at: SIMD3(0, 1, 3), in: scene)
        let b = target(at: SIMD3(0.8, 1, 3), in: scene)
        XCTAssertTrue(combat.physicalTargets.isEmpty)
        combat.damage(node: patronus, amount: 100)
        XCTAssertNotNil(patronus.parent)
        XCTAssertTrue(advance(combat, seconds: 0.4, targets: [isolated, a, b]).isEmpty)
        XCTAssertGreaterThan(patronus.simdPosition.z, 1.2)
        let hits = advance(combat, seconds: 1.2, targets: [isolated, a, b])
        XCTAssertEqual(hits.count, 2)
        XCTAssertTrue(hits.allSatisfy { $0.damage == 0 && $0.slowDuration == 15 })
        XCTAssertFalse(combat.contains(.patronus))
        XCTAssertNil(patronus.parent)
        XCTAssertTrue(advance(combat, seconds: 20, targets: [isolated, a, b]).isEmpty)
    }

    func testPatronusTouchesPathTargetsOnceAndExpiresWithoutEnemies() {
        let scene = SCNScene()
        let combat = SummonCombat(scene: scene)
        _ = companion(.patronus, in: combat)
        let path = target(at: SIMD3(0, 1, 1.3), in: scene)
        let clusterA = target(at: SIMD3(0, 1, 3.2), in: scene)
        let clusterB = target(at: SIMD3(0.8, 1, 3.2), in: scene)
        let hits = advance(combat, seconds: 2, targets: [path, clusterA, clusterB])
        XCTAssertEqual(hits.count, 3)
        XCTAssertEqual(Set(hits.map { ObjectIdentifier($0.node) }).count, 3)
        XCTAssertTrue(hits.allSatisfy { $0.slowDuration == 15 && $0.damage == 0 })
        _ = companion(.patronus, in: combat)
        XCTAssertTrue(advance(combat, seconds: 3.1, targets: []).isEmpty)
        XCTAssertFalse(combat.contains(.patronus))
    }

    func testDemonPrefersReadySlamForClusterBeforeBreath() {
        let scene = SCNScene()
        let combat = SummonCombat(scene: scene)
        _ = companion(.demon, in: combat)
        let ally = combat.companions[0]
        ally.slamCooldown = 0
        ally.breathCooldown = 0
        let a = target(at: SIMD3(0, 1, 1), in: scene)
        let b = target(at: SIMD3(1, 1, 0), in: scene)
        let hits = advance(combat, seconds: 0.45, targets: [a, b])
        XCTAssertEqual(hits.map(\.damage), [1, 1])
        XCTAssertEqual(ally.breathCooldown, 0)
        XCTAssertGreaterThan(ally.slamCooldown, 7)
    }

    func testAlliesStayInsideAisleAndHaveHealthLabels() {
        let scene = SCNScene()
        let combat = SummonCombat(scene: scene)
        let alan = companion(.alan, in: combat)
        let albert = companion(.albert, in: combat)
        let outside = target(at: SIMD3(20, 1, 20), in: scene)
        _ = advance(combat, seconds: 20, targets: [outside])
        for node in [alan, albert] {
            XCTAssertLessThanOrEqual(node.simdPosition.x, 2.2)
            XCTAssertLessThanOrEqual(node.simdPosition.z, 3.9)
            XCTAssertNotNil(node.childNode(withName: "CompanionHealth", recursively: false))
        }
        combat.damage(node: alan, amount: 3)
        XCTAssertEqual(combat.companions.first { $0.kind == .alan }?.healthText?.string as? String, "12/15")
    }

    func testHealthAndInvalidTimeAreDeterministic() {
        for kind in [SummonKind.alan, .albert, .demon] {
            let scene = SCNScene()
            let combat = SummonCombat(scene: scene)
            let node = companion(kind, in: combat)
            XCTAssertEqual(combat.companions[0].health, kind.maxHealth)
            let enemy = target(at: SIMD3(0, 1, 1), in: scene)
            for dt in [Double.nan, .infinity, -1, 0] {
                XCTAssertTrue(combat.update(deltaTime: dt, targets: [enemy]).isEmpty)
            }
            combat.damage(node: node, amount: kind.maxHealth)
            XCTAssertTrue(combat.physicalTargets.isEmpty)
        }
    }

    func testFlyingDemonKeepsGroundedTargetAndReturnsAirborneAfterSlam() {
        let scene = SCNScene()
        let combat = SummonCombat(scene: scene)
        let demon = companion(.demon, in: combat)
        let body = SCNNode()
        body.name = "DemonSculpture"
        demon.addChildNode(body)
        DemonFlight.install(on: body)
        let ally = combat.companions[0]
        ally.slamCooldown = 0
        ally.breathCooldown = 10
        let a = target(at: SIMD3(0, 1, 1), in: scene)
        let b = target(at: SIMD3(1, 1, 0), in: scene)
        _ = combat.update(deltaTime: 0.05, targets: [a, b])
        XCTAssertEqual(ally.animation, "slam")
        XCTAssertGreaterThan(body.simdPosition.y, 0.5)
        XCTAssertEqual(combat.physicalTargets.first?.center.y, 1)
        let hits = advance(combat, seconds: 0.35, targets: [a, b])
        XCTAssertEqual(hits.map(\.damage), [1, 1])
        XCTAssertLessThan(body.simdPosition.y, 0.1)
        _ = advance(combat, seconds: 0.45, targets: [a, b])
        XCTAssertGreaterThan(body.simdPosition.y, 0.5)
        XCTAssertEqual(demon.simdPosition.y, 0)
        XCTAssertTrue(combat.isLiving(demon))
        let remote = target(at: SIMD3(0, 1, 3.8), in: scene)
        ally.cooldown = 10
        _ = combat.update(deltaTime: 0.05, targets: [remote])
        XCTAssertNotEqual(ally.animation, "walk", "The airborne devil must not use walking legs")
        XCTAssertGreaterThan(body.simdPosition.y, 0.5, "A valid claw attack must preserve flight")
        XCTAssertEqual(demon.simdPosition.y, 0, "The combat root stays reachable by enemy melee")
    }

    func testPauseFreezesFlightChargeAndSimulationFadeAndResetRemovesAll() {
        let scene = SCNScene()
        let combat = SummonCombat(scene: scene)
        let demon = companion(.demon, in: combat)
        let body = SCNNode()
        body.name = "DemonSculpture"
        demon.addChildNode(body)
        _ = combat.update(deltaTime: 0.05, targets: [])
        let altitude = body.simdPosition.y
        let lifetime = combat.companions[0].lifetime
        combat.setPaused(true)
        _ = advance(combat, seconds: 1, targets: [])
        XCTAssertEqual(body.simdPosition.y, altitude)
        XCTAssertEqual(combat.companions[0].lifetime, lifetime)
        combat.setPaused(false)
        let patronus = companion(.patronus, in: combat)
        _ = advance(combat, seconds: 3.05, targets: [])
        XCTAssertFalse(combat.contains(.patronus))
        XCTAssertNotNil(patronus.parent)
        combat.setPaused(true)
        let opacity = patronus.opacity
        _ = advance(combat, seconds: 1, targets: [])
        XCTAssertEqual(patronus.opacity, opacity)
        XCTAssertNotNil(patronus.parent)
        combat.setPaused(false)
        _ = advance(combat, seconds: 0.35, targets: [])
        XCTAssertNil(patronus.parent)
        let fresh = companion(.patronus, in: combat)
        _ = advance(combat, seconds: 3.05, targets: [])
        combat.reset()
        XCTAssertNil(fresh.parent)
        XCTAssertTrue(combat.companions.isEmpty)
        XCTAssertTrue(scene.rootNode.childNodes.isEmpty)
    }

    func testPatronusEntryStaysAtFloorAndFollowsCurvedPath() {
        let scene = SCNScene()
        let combat = SummonCombat(scene: scene)
        let node = SCNNode()
        node.simdPosition = SIMD3(3, 7, 4.5)
        combat.register(kind: .patronus, node: node)
        XCTAssertEqual(node.simdPosition, SIMD3(3, 0, 4.5))
        let a = target(at: SIMD3(0, 1, 0), in: scene)
        let b = target(at: SIMD3(0.7, 1, 0), in: scene)
        _ = advance(combat, seconds: 0.6, targets: [a, b])
        let ally = combat.companions[0]
        XCTAssertNotNil(ally.chargeControl)
        XCTAssertEqual(node.simdPosition.y, 0)
        XCTAssertLessThan(node.simdPosition.z, 4.5)
        let start = ally.chargeStart!
        let destination = ally.chargeDestination!
        let midpoint = (start + destination) * 0.5
        XCTAssertGreaterThan(simd_distance(ally.chargeControl!, midpoint), 0.5)
        let before = node.simdPosition
        combat.setPaused(true)
        _ = advance(combat, seconds: 1, targets: [a, b])
        XCTAssertEqual(node.simdPosition, before)
        combat.setPaused(false)
        let hits = advance(combat, seconds: 2, targets: [a, b])
        XCTAssertEqual(Set(hits.map { ObjectIdentifier($0.node) }).count, 2)
        XCTAssertTrue(hits.allSatisfy { $0.damage == 0 && $0.slowDuration == 15 })
        XCTAssertNil(node.parent)
    }

    @discardableResult
    private func companion(_ kind: SummonKind, in combat: SummonCombat) -> SCNNode {
        let node = SCNNode()
        combat.register(kind: kind, node: node)
        return node
    }

    private func target(at point: SIMD3<Float>, in scene: SCNScene) -> SummonCombat.Target {
        let node = SCNNode()
        node.simdPosition = point
        scene.rootNode.addChildNode(node)
        return SummonCombat.Target(node: node, center: point)
    }

    private func advance(
        _ combat: SummonCombat, seconds: TimeInterval,
        targets: [SummonCombat.Target]
    ) -> [SummonCombat.Impact] {
        let steps = Int((seconds / 0.05).rounded())
        return (0..<steps).flatMap { _ in combat.update(deltaTime: 0.05, targets: targets) }
    }
}
