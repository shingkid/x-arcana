import SceneKit
import XCTest

@testable import XArcana

final class CombatTests: XCTestCase {
    func testZombiesArriveGraduallyAndKeepAllSourceIdentities() throws {
        XCTAssertEqual(Combat.identities.count, 42)
        let (scene, combat) = makeEncounter(cameraHeight: 6)
        XCTAssertEqual(combat.remaining, 1)
        XCTAssertEqual(combat.pendingSpawns, 7)
        var time = advance(combat, from: 0, seconds: Combat.spawnInterval - 0.1)
        XCTAssertEqual(combat.remaining, 1)
        time = advance(combat, from: time, seconds: 0.2)
        XCTAssertEqual(combat.remaining, 2)
        time = advance(combat, from: time, seconds: Combat.spawnInterval * 6 + 0.5)
        let enemies = combatants(in: scene)
        XCTAssertEqual(enemies.count, 8)
        XCTAssertEqual(combat.pendingSpawns, 0)
        XCTAssertTrue(enemies.allSatisfy { $0.kind == .zombie && $0.health == 2 })
        XCTAssertGreaterThan(Set(enemies.map(\.appearanceVariant)).count, 1)
        for (index, node) in enemies.enumerated() {
            let identity = Combat.identities[index]
            XCTAssertEqual(node.identityID, identity.id)
            XCTAssertEqual(node.identityName, identity.name)
            XCTAssertNotNil(node.childNode(withName: "Face.\(identity.id)", recursively: true))
            XCTAssertNotNil(node.childNode(withName: "Name.\(identity.id)", recursively: true))
            XCTAssertNil(node.childNode(withName: "Identity.\(identity.id)", recursively: true))
        }
        let names = enemies.map(\.name)
        _ = advance(combat, from: time, seconds: 1)
        XCTAssertEqual(enemies.map(\.name), names)
    }

    func testZombieUsesDetailedMeshAndMappedPhoto() throws {
        let (scene, _) = makeEncounter()
        let zombie = try XCTUnwrap(combatants(in: scene).first)
        let body = try XCTUnwrap(zombie.childNode(withName: "Office zombie", recursively: true))
        var triangles = 0
        body.enumerateChildNodes { node, _ in
            triangles += node.geometry?.elements.reduce(0) { $0 + $1.primitiveCount } ?? 0
        }
        XCTAssertGreaterThan(triangles, 30_000)
        XCTAssertLessThan(triangles, 70_000)
        let face = try XCTUnwrap(zombie.childNode(withName: "Face.\(zombie.identityID)", recursively: true))
        XCTAssertNotNil(face.geometry?.firstMaterial?.diffuse.contents as? UIImage)
    }

    func testLightningDealsTwoDamageToOneZombie() throws {
        let (scene, combat) = makeEncounter()
        let time = advance(combat, from: 0, seconds: Combat.spawnInterval + 0.1)
        let enemies = combatants(in: scene)
        let target = enemies[0]
        target.simdPosition = SIMD3(0, 0, 1.5)
        enemies[1].simdPosition = SIMD3(0.9, 0, 1.5)
        XCTAssertTrue(combat.cast(toward: center(target)))
        _ = advance(combat, from: time, seconds: 0.7)
        XCTAssertEqual(target.health, 0)
        XCTAssertEqual(enemies[1].health, 2)
        XCTAssertEqual(combat.kills, 1)
        XCTAssertTrue(target.isDefeated)
        XCTAssertTrue(target.hasActions)
    }

    func testZombieHealthBarsAreIndependentFaceThePlayerAndPreserveFractionalDamage() throws {
        let (scene, combat) = makeEncounter(cameraHeight: 6)
        _ = advance(combat, from: 0, seconds: Combat.spawnInterval + 0.1)
        let enemies = combatants(in: scene)
        let first = try XCTUnwrap(enemies.first)
        let second = try XCTUnwrap(enemies.last)
        XCTAssertTrue(first.healthBar.parent === first)
        XCTAssertTrue(first.healthBar.constraints?.first is SCNBillboardConstraint)
        XCTAssertFalse(first.healthBar.isHidden)
        XCTAssertLessThan(first.healthBar.position.y, 1.88, "Keep health below the name")
        first.setHealth(1.1)
        let fills = first.healthBar.childNodes.filter { $0.name?.hasPrefix("Health segment") == true }
        XCTAssertEqual(fills.count, 2)
        XCTAssertEqual(fills[0].simdScale.x, 1)
        XCTAssertEqual(fills[1].simdScale.x, 0.1, accuracy: 0.00001)
        XCTAssertTrue(
            second.healthBar.childNodes.filter { $0.name?.hasPrefix("Health segment") == true }.allSatisfy {
                !$0.isHidden && $0.simdScale.x == 1
            })
        first.setTransfigured(true)
        XCTAssertTrue(first.healthBar.isHidden)
        first.setTransfigured(false)
        XCTAssertFalse(first.healthBar.isHidden)
        first.setHealth(0)
        XCTAssertTrue(first.healthBar.isHidden)
    }

    func testArrowsCanMissWhereElementalAimAssistStillFindsTheZombie() throws {
        let (scene, combat) = makeEncounter(cameraHeight: 6)
        let camera = try XCTUnwrap(scene.rootNode.childNode(withName: "Test camera", recursively: false))
        camera.simdPosition.y = 1.65
        let zombie = try XCTUnwrap(combatants(in: scene).first)
        zombie.simdPosition = SIMD3(0.58, 0, 1)
        let target = SIMD3<Float>(0, 0.1, -5)
        XCTAssertTrue(combat.shoot(toward: target))
        var time = advance(combat, from: 0, seconds: 0.6)
        XCTAssertEqual(zombie.health, 2, "Arrows must not snap from the wider spell-assist cone")
        zombie.simdPosition = SIMD3(0.58, 0, 1)
        XCTAssertTrue(combat.cast(toward: target))
        time = advance(combat, from: time, seconds: 0.6)
        XCTAssertTrue(zombie.isDefeated, "Elemental spell assistance remains forgiving")
    }

    func testTwoArrowsDealOneDamageEachAndDefeatAFullHealthZombie() throws {
        let (scene, combat) = makeEncounter()
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        enemy.simdPosition = SIMD3(0, 0, 1.5)
        let maximum = enemy.health
        var time = 0.0
        for hit in 1...2 {
            XCTAssertTrue(combat.shoot(toward: center(enemy)))
            XCTAssertFalse(combat.shoot(toward: center(enemy)))
            time = advance(combat, from: time, seconds: 0.6)
            if hit < 2 {
                XCTAssertEqual(enemy.health, maximum - Double(hit), accuracy: 1e-12)
                XCTAssertFalse(enemy.isDefeated)
                XCTAssertFalse(enemy.healthBar.isHidden)
                let fills = enemy.healthBar.childNodes.filter { $0.name?.hasPrefix("Health segment") == true }
                XCTAssertEqual(fills.filter { !$0.isHidden }.count, 2 - hit)
                XCTAssertEqual(combat.kills, 0)
            } else {
                XCTAssertEqual(enemy.health, 0)
                XCTAssertTrue(enemy.isDefeated)
                XCTAssertTrue(enemy.healthBar.isHidden)
                XCTAssertEqual(combat.kills, 1)
                XCTAssertEqual(combat.runSnapshot.score, 100)
            }
        }
        XCTAssertEqual(combat.runSnapshot.mana, 100)
    }

    func testFireballDamagesNearbyZombiesOnceAndLeavesDistantZombieUnhurt() throws {
        let (scene, combat) = makeEncounter()
        let time = advance(combat, from: 0, seconds: Combat.spawnInterval * 2 + 0.2)
        let enemies = combatants(in: scene)
        XCTAssertEqual(enemies.count, 3)
        enemies[0].simdPosition = SIMD3(0, 0, 1.5)
        enemies[1].simdPosition = SIMD3(2.15, 0, 0.3)
        enemies[2].simdPosition = SIMD3(-2, 0, -4)
        XCTAssertTrue(combat.fireball(toward: center(enemies[0])))
        _ = advance(combat, from: time, seconds: 0.8)
        XCTAssertEqual(enemies[0].health, 0)
        XCTAssertGreaterThan(enemies[1].health, 1)
        XCTAssertLessThan(enemies[1].health, 2)
        XCTAssertEqual(enemies[2].health, 2)
        XCTAssertEqual(combat.kills, 1)
        XCTAssertNotNil(scene.rootNode.childNode(withName: "Fireball blast", recursively: true))
    }

    func testFireballForgivingHitVolumeCatchesAVisibleEdgeGraze() throws {
        let (scene, combat) = makeEncounter()
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        enemy.simdPosition = SIMD3(0.62, 0, 3.5)
        XCTAssertTrue(combat.fireball(toward: SIMD3(0, 1.3, -5)))
        _ = advance(combat, from: 0, seconds: 0.2)
        XCTAssertEqual(enemy.health, 0)
        let blast = try XCTUnwrap(scene.rootNode.childNode(withName: "Fireball blast", recursively: true))
        XCTAssertGreaterThan(blast.simdPosition.z, 3)
    }

    func testRoomWallStopsAnArrowBeforeAnEnemy() throws {
        let (scene, combat) = makeEncounter()
        let wall = SCNNode(geometry: SCNBox(width: 12, height: 4, length: 0.3, chamferRadius: 0))
        wall.position = SCNVector3(0, 2, 3)
        scene.rootNode.addChildNode(wall)
        SCNTransaction.flush()
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        combat.shoot(toward: center(enemy))
        _ = advance(combat, from: 0, seconds: 1)
        XCTAssertEqual(enemy.health, 2)
        XCTAssertEqual(combat.kills, 0)
        XCTAssertNil(scene.rootNode.childNode(withName: "Flying arrow", recursively: true))
    }

    func testMagicMissDoesNotDamageEnemiesAndMeleeDamagesPlayer() {
        let (scene, combat) = makeEncounter()
        XCTAssertTrue(combat.cast(toward: SIMD3(0, 10, -2)))
        _ = advance(combat, from: 0, seconds: 20)
        XCTAssertEqual(combat.kills, 0)
        XCTAssertTrue(combatants(in: scene).allSatisfy { $0.health == 2 })
        XCTAssertLessThan(combat.runSnapshot.health, 100)
    }

    func testZombiesNeverShootOrDamageWhileOutsideMeleeRange() {
        let (scene, combat) = makeEncounter()
        for step in 1...1_200 {
            for (index, enemy) in combatants(in: scene).enumerated() {
                enemy.simdPosition = SIMD3(Float(index % 3) * 0.8 - 0.8, 0, 0)
            }
            combat.update(at: Double(step) / 60)
            XCTAssertNil(scene.rootNode.childNode(withName: "Undead curse", recursively: true))
        }
        XCTAssertEqual(combat.runSnapshot.health, 100)
        XCTAssertTrue(combatants(in: scene).allSatisfy { $0.health == 2 && $0.meleeAttackCount == 0 })
        XCTAssertNil(scene.rootNode.childNode(withName: "Melee ward", recursively: true))
    }

    func testSwipeAndBiteEachApplyOneDamageAtContact() throws {
        let (scene, combat) = makeEncounter()
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        enemy.simdPosition = SIMD3(0, 0, 3.85)
        var time = advance(combat, from: 0, seconds: 1.1)
        XCTAssertEqual(enemy.lastMeleeAttack, .swipe)
        XCTAssertEqual(combat.runSnapshot.health, 100)
        time = advance(combat, from: time, seconds: 0.3)
        XCTAssertEqual(combat.runSnapshot.health, 99)
        time = advance(combat, from: time, seconds: 2.3)
        XCTAssertEqual(enemy.lastMeleeAttack, .bite)
        XCTAssertEqual(combat.runSnapshot.health, 99)
        _ = advance(combat, from: time, seconds: 0.35)
        XCTAssertEqual(combat.runSnapshot.health, 98)
        XCTAssertEqual(enemy.meleeAttackCount, 2)
        XCTAssertNil(scene.rootNode.childNode(withName: "Melee ward", recursively: true))
    }

    func testLeavingRangeDuringWindupPreventsDamage() throws {
        let (scene, combat) = makeEncounter()
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        enemy.simdPosition = SIMD3(0, 0, 3.85)
        var time = advance(combat, from: 0, seconds: 1.1)
        XCTAssertEqual(enemy.meleeAttackCount, 1)
        enemy.simdPosition = SIMD3(0, 0, 0)
        time = advance(combat, from: time, seconds: 0.5)
        XCTAssertEqual(combat.runSnapshot.health, 100)
        XCTAssertEqual(enemy.meleeAttackCount, 1)
    }

    func testNearestPhysicalAllyReceivesZombieDamageInsteadOfPlayer() throws {
        let (scene, combat) = makeEncounter()
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        enemy.simdPosition = SIMD3(0, 0, 2)
        let friend = SCNNode()
        friend.simdPosition = SIMD3(0, 0, 2.95)
        XCTAssertEqual(combat.summon(kind: .alan) { friend }, .summoned)
        _ = advance(combat, from: 0, seconds: 2)
        XCTAssertGreaterThan(enemy.meleeAttackCount, 0)
        XCTAssertEqual(combat.runSnapshot.health, 100)
    }

    func testZombieSeparationFromAllyStaysInsideEveryAisleBoundary() throws {
        let cases: [(enemy: SIMD3<Float>, ally: SIMD3<Float>, expected: SIMD3<Float>)] = [
            (SIMD3(2.1, 0, 0), SIMD3(1.8, 0, 0), SIMD3(2.2, 0, 0)),
            (SIMD3(-2.1, 0, 0), SIMD3(-1.8, 0, 0), SIMD3(-2.2, 0, 0)),
            (SIMD3(0, 0, 3.8), SIMD3(0, 0, 3.5), SIMD3(0, 0, 3.9)),
            (SIMD3(0, 0, -4.7), SIMD3(0, 0, -4.4), SIMD3(0, 0, -4.8)),
        ]
        for testCase in cases {
            let (scene, combat) = makeEncounter()
            let enemy = try XCTUnwrap(combatants(in: scene).first)
            enemy.simdPosition = testCase.enemy
            let alan = SCNNode()
            alan.simdPosition = testCase.ally
            XCTAssertEqual(combat.summon(kind: .alan) { alan }, .summoned)

            combat.update(at: 1.0 / 60)

            XCTAssertEqual(enemy.simdPosition.x, testCase.expected.x, accuracy: 0.001)
            XCTAssertEqual(enemy.simdPosition.z, testCase.expected.z, accuracy: 0.001)
            XCTAssertEqual(combat.runSnapshot.health, 100)
        }
    }

    func testRegisteredCompanionMovesAndDefeatsZombie() throws {
        let (scene, combat) = makeEncounter()
        let friend = SCNNode()
        friend.simdPosition = SIMD3(0, 0, 2)
        XCTAssertEqual(combat.summon(kind: .albert) { friend }, .summoned)
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        _ = advance(combat, from: 0, seconds: 12)
        XCTAssertEqual(enemy.health, 0)
        XCTAssertTrue(enemy.isDefeated)
        XCTAssertGreaterThanOrEqual(combat.kills, 1)
    }

    func testSummonValidationPreservesExistingAllyAndMana() {
        let state = unlockedDemonState()
        let (_, combat) = makeEncounter(state: state)
        let alan = SCNNode()
        XCTAssertEqual(combat.summon(kind: .alan) { alan }, .summoned)
        XCTAssertEqual(combat.runSnapshot.mana, 75)
        var created = false
        XCTAssertEqual(
            combat.summon(kind: .alan) {
                created = true
                return SCNNode()
            }, .alreadyActive)
        XCTAssertFalse(created)
        XCTAssertEqual(combat.summon(kind: .demon) { nil }, .unavailable)
        XCTAssertNotNil(alan.parent)
        XCTAssertEqual(combat.runSnapshot.mana, 75)
        let albert = SCNNode()
        XCTAssertEqual(combat.summon(kind: .albert) { albert }, .summoned)
        XCTAssertNotNil(alan.parent)
        XCTAssertNotNil(albert.parent)
        let demon = SCNNode()
        XCTAssertEqual(combat.summon(kind: .demon) { demon }, .summoned)
        XCTAssertNil(alan.parent)
        XCTAssertNil(albert.parent)
        XCTAssertEqual(combat.runSnapshot.mana, 45)
        XCTAssertTrue(state.spend(20))
        XCTAssertEqual(
            combat.summon(kind: .patronus) {
                created = true
                return SCNNode()
            }, .insufficientMana)
        XCTAssertFalse(created)
        XCTAssertNotNil(demon.parent)
    }

    func testPauseFreezesSimulationAndManaAndRestartClearsRun() throws {
        let (scene, combat) = makeEncounter()
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        XCTAssertTrue(combat.cast(toward: center(enemy)))
        let snapshot = combat.runSnapshot
        let position = enemy.simdPosition
        combat.setPaused(true)
        var time = advance(combat, from: 0, seconds: 30)
        XCTAssertEqual(combat.runSnapshot, snapshot)
        XCTAssertEqual(enemy.simdPosition, position)
        XCTAssertFalse(combat.shoot(toward: center(enemy)))
        XCTAssertEqual(combat.lastRejection, .paused)
        combat.setPaused(false)
        time = advance(combat, from: time, seconds: 2)
        XCTAssertEqual(combat.runSnapshot.mana, 95, accuracy: 0.000001)
        time = advance(combat, from: time, seconds: 1.3)
        XCTAssertEqual(combat.runSnapshot.mana, 100)
        combat.restart()
        XCTAssertEqual(combat.runSnapshot.health, 100)
        XCTAssertEqual(combat.runSnapshot.score, 0)
        XCTAssertFalse(combat.runSnapshot.hasStarted)
        XCTAssertEqual(combat.runSnapshot.countdownRemaining, 0)
        XCTAssertEqual(combat.remaining, 0)
        XCTAssertEqual(combat.pendingSpawns, 0)
        XCTAssertNil(enemy.parent)
        XCTAssertNil(scene.rootNode.childNode(withName: "Magic bolt", recursively: true))
    }

    func testGameOverStopsProjectilesSpawningManaAndNewInputs() throws {
        let (scene, combat) = makeEncounter()
        var time = 0.0
        for _ in 0..<12_000 {
            for enemy in combatants(in: scene) where !enemy.isDefeated {
                enemy.simdPosition = SIMD3(0, 0, 3.85)
            }
            time += 1.0 / 60
            combat.update(at: time)
            if combat.runSnapshot.isGameOver { break }
        }
        XCTAssertTrue(combat.runSnapshot.isGameOver)
        XCTAssertEqual(combat.runSnapshot.health, 0)
        let snapshot = combat.runSnapshot
        let positions = combatants(in: scene).map(\.simdPosition)
        _ = advance(combat, from: time, seconds: 10)
        XCTAssertEqual(combat.runSnapshot, snapshot)
        XCTAssertEqual(combatants(in: scene).map(\.simdPosition), positions)
        XCTAssertFalse(combat.cast(toward: SIMD3(0, 1, 0)))
        XCTAssertEqual(combat.lastRejection, .gameOver)
        XCTAssertFalse(combat.melee(toward: SIMD3(0, 1, 0)))
        XCTAssertEqual(combat.lastRejection, .gameOver)
        XCTAssertEqual(combat.summon(kind: .alan) { SCNNode() }, .gameOver)
        combat.restart()
        XCTAssertFalse(combat.runSnapshot.isGameOver)
        XCTAssertEqual(combat.runSnapshot.health, 100)
    }

    func testPatronusHalvesActualMovementWithoutDamagingZombie() throws {
        let (slowScene, slowed) = makeEncounter()
        let (normalScene, normal) = makeEncounter()
        let slowEnemy = try XCTUnwrap(combatants(in: slowScene).first)
        let normalEnemy = try XCTUnwrap(combatants(in: normalScene).first)
        slowEnemy.simdPosition = SIMD3(0, 0, -1)
        normalEnemy.simdPosition = SIMD3(0, 0, -1)
        let patronus = SCNNode()
        patronus.simdPosition = SIMD3(0, 0, -0.8)
        XCTAssertEqual(slowed.summon(kind: .patronus) { patronus }, .summoned)
        var time = advance(slowed, from: 0, seconds: 0.1)
        _ = advance(normal, from: 0, seconds: 0.1)
        XCTAssertGreaterThan(slowEnemy.slowRemaining, 14.8)
        slowEnemy.simdPosition = SIMD3(0, 0, -1)
        normalEnemy.simdPosition = SIMD3(0, 0, -1)
        _ = advance(normal, from: time, seconds: 0.5)
        time = advance(slowed, from: time, seconds: 0.5)
        let slowDistance = slowEnemy.simdPosition.z + 1
        let normalDistance = normalEnemy.simdPosition.z + 1
        XCTAssertEqual(slowDistance, normalDistance * 0.5, accuracy: 0.001)
        XCTAssertEqual(slowEnemy.health, 2)
        XCTAssertEqual(slowed.kills, 0)
    }

    func testPatronusHalvesActualMeleeCooldownAndWindupAndAnimationSpeed() throws {
        let (scene, combat) = makeEncounter()
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        enemy.simdPosition = SIMD3(0, 0, 3.85)
        let patronus = SCNNode()
        patronus.simdPosition = SIMD3(0, 0, 3.4)
        XCTAssertEqual(combat.summon(kind: .patronus) { patronus }, .summoned)
        var time = advance(combat, from: 0, seconds: 1.2)
        XCTAssertEqual(enemy.meleeAttackCount, 0)
        time = advance(combat, from: time, seconds: 1)
        XCTAssertEqual(enemy.meleeAttackCount, 1)
        XCTAssertEqual(combat.runSnapshot.health, 100)
        let pose = try XCTUnwrap(enemy.childNode(withName: "Melee pose", recursively: true))
        XCTAssertEqual(try XCTUnwrap(pose.action(forKey: "melee.swipe")).speed, 0.5)
        time = advance(combat, from: time, seconds: 0.6)
        XCTAssertEqual(combat.runSnapshot.health, 99)
        time = advance(combat, from: time, seconds: 4.1)
        XCTAssertEqual(enemy.meleeAttackCount, 1)
        _ = advance(combat, from: time, seconds: 0.5)
        XCTAssertEqual(enemy.meleeAttackCount, 2)
    }

    func testSlowRefreshPauseAndExpiryUseSimulationTimeWithoutStacking() throws {
        let (scene, combat) = makeEncounter()
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        enemy.simdPosition = .zero
        func castPatronus() {
            let patronus = SCNNode()
            patronus.simdPosition = SIMD3(0, 0, 0.2)
            XCTAssertEqual(combat.summon(kind: .patronus) { patronus }, .summoned)
        }
        func advanceSafely(from start: Double, seconds: Double) -> Double {
            var time = start
            for _ in 0..<Int(ceil(seconds * 60)) {
                for zombie in combatants(in: scene) {
                    zombie.simdPosition = zombie === enemy ? .zero : SIMD3(-2, 0, -4)
                }
                time += 1.0 / 60
                combat.update(at: time)
            }
            return time
        }
        castPatronus()
        var time = advanceSafely(from: 0, seconds: 10)
        XCTAssertEqual(enemy.slowRemaining, 5, accuracy: 0.03)
        let remaining = enemy.slowRemaining
        combat.setPaused(true)
        time = advanceSafely(from: time, seconds: 30)
        XCTAssertEqual(enemy.slowRemaining, remaining)
        combat.setPaused(false)
        castPatronus()
        time = advanceSafely(from: time, seconds: 0.1)
        XCTAssertGreaterThan(enemy.slowRemaining, 14.8)
        XCTAssertLessThanOrEqual(enemy.slowRemaining, 15)
        // A refreshed slow still moves at 50%, rather than multiplying to 25%.
        let startZ = enemy.simdPosition.z
        time = advance(combat, from: time, seconds: 0.5)
        XCTAssertEqual(enemy.simdPosition.z - startZ, 0.12, accuracy: 0.002)
        time = advanceSafely(from: time, seconds: 14.5)
        XCTAssertEqual(enemy.slowRemaining, 0)
        let expiryZ = enemy.simdPosition.z
        _ = advance(combat, from: time, seconds: 0.5)
        XCTAssertEqual(enemy.simdPosition.z - expiryZ, 0.24, accuracy: 0.002)
        XCTAssertEqual(enemy.health, 2)
        XCTAssertFalse(combat.runSnapshot.isGameOver)
    }

    func testIceConeDamagesEachForwardTargetOnceAndRejectsOutsideOrDistantTargets() throws {
        let (scene, combat) = makeEncounter(cameraHeight: 6)
        _ = advance(combat, from: 0, seconds: Combat.spawnInterval * 4 + 0.2)
        scene.rootNode.childNode(withName: "Test camera", recursively: false)?.position.y = 1.65
        let enemies = combatants(in: scene)
        XCTAssertEqual(enemies.count, 5)
        let positions: [SIMD3<Float>] = [
            SIMD3(0, 0, 1.5), SIMD3(0.8, 0, 1.3),
            SIMD3(2, 0, 3.8), SIMD3(0, 0, -1), SIMD3(0, 0, 6),
        ]
        for (enemy, position) in zip(enemies, positions) { enemy.simdPosition = position }
        XCTAssertTrue(combat.ice(toward: center(enemies[0])))
        XCTAssertEqual(enemies.map(\.health), [0, 0, 2, 2, 2])
        XCTAssertTrue(enemies[0].isDefeated)
        XCTAssertTrue(enemies[1].isDefeated)
        XCTAssertEqual(enemies[2].slowRemaining, 0)
        XCTAssertEqual(combat.runSnapshot.mana, 85)
        XCTAssertFalse(combat.ice(toward: center(enemies[0])))
        XCTAssertEqual(combat.lastRejection, .cooldown)
        XCTAssertEqual(combat.runSnapshot.mana, 85)
    }

    func testIceDefeatsTwoHealthZombieWithoutLeavingActiveSlow() throws {
        let (scene, combat) = makeEncounter()
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        enemy.simdPosition = SIMD3(0, 0, 1)
        XCTAssertTrue(combat.ice(toward: center(enemy)))
        XCTAssertEqual(enemy.health, 0)
        XCTAssertEqual(enemy.slowRemaining, 0)
        let position = enemy.simdPosition
        _ = advance(combat, from: 0, seconds: 0.5)
        XCTAssertEqual(enemy.simdPosition, position)
        XCTAssertEqual(combat.kills, 1)
    }

    func testShieldAbsorbsDamagePersistsPastCooldownAndRejectsDuplicate() throws {
        let (scene, combat) = makeEncounter()
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        enemy.simdPosition = SIMD3(0, 0, 3.85)
        XCTAssertTrue(combat.shield())
        XCTAssertEqual(combat.runSnapshot.mana, 80)
        XCTAssertEqual(combat.runSnapshot.shieldHealth, 20)
        XCTAssertEqual(combat.runSnapshot.shieldRemaining, 0)
        XCTAssertEqual(combat.runSnapshot.shieldCooldownRemaining, 10)
        let dome = try XCTUnwrap(scene.rootNode.childNode(withName: "Player shield", recursively: true))
        let position = dome.simdWorldPosition
        var time = advance(combat, from: 0, seconds: 4.1)
        XCTAssertEqual(combat.runSnapshot.health, 100)
        XCTAssertEqual(combat.runSnapshot.shieldHealth, 18)
        XCTAssertEqual(combat.blockedAttacks, 2)
        XCTAssertEqual(dome.simdWorldPosition, position)
        time = advance(combat, from: time, seconds: 6.1)
        XCTAssertEqual(combat.runSnapshot.health, 100)
        XCTAssertGreaterThan(combat.runSnapshot.shieldHealth ?? 0, 0)
        XCTAssertEqual(combat.runSnapshot.shieldCooldownRemaining, 0)
        XCTAssertNotNil(dome.parent)
        let mana = combat.runSnapshot.mana
        XCTAssertFalse(combat.shield())
        XCTAssertEqual(combat.lastRejection, .cooldown)
        XCTAssertEqual(combat.runSnapshot.mana, mana)
        combat.restart()
        XCTAssertEqual(combat.runSnapshot.shieldHealth, 0)
        XCTAssertEqual(combat.runSnapshot.shieldCooldownRemaining, 0)
        XCTAssertNil(scene.rootNode.childNode(withName: "Player shield", recursively: true))
    }

    func testShieldDepletionRemovesDomeAndAllowsRecastAfterCooldown() throws {
        let (scene, combat) = makeEncounter()
        XCTAssertTrue(combat.shield())
        let dome = try XCTUnwrap(scene.rootNode.childNode(withName: "Player shield", recursively: true))
        var time = 0.0
        while combat.blockedAttacks < 20, time < 80 {
            for enemy in combatants(in: scene) { enemy.simdPosition = SIMD3(0, 0, 3.85) }
            time += 1.0 / 60
            combat.update(at: time)
        }
        XCTAssertEqual(combat.blockedAttacks, 20)
        XCTAssertEqual(combat.runSnapshot.shieldHealth, 0)
        XCTAssertNil(dome.parent)
        XCTAssertTrue(combat.shield())
        XCTAssertEqual(combat.runSnapshot.shieldHealth, 20)
        XCTAssertEqual(combat.runSnapshot.shieldCooldownRemaining, 10)
        XCTAssertEqual(combat.runSnapshot.mana, 80, accuracy: 0.001)
    }

    func testShieldDoesNotProtectPhysicalAllies() throws {
        let (scene, combat) = makeEncounter()
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        enemy.simdPosition = SIMD3(0, 0, 2)
        let alan = SCNNode()
        alan.simdPosition = SIMD3(0, 0, 2.95)
        XCTAssertEqual(combat.summon(kind: .alan) { alan }, .summoned)
        XCTAssertTrue(combat.shield())
        _ = advance(combat, from: 0, seconds: 1.5)
        let label = try XCTUnwrap(alan.childNode(withName: "CompanionHealth", recursively: false))
        let text = label.childNodes.compactMap { ($0.geometry as? SCNText)?.string as? String }
        XCTAssertTrue(text.contains("14/15"))
        XCTAssertEqual(combat.runSnapshot.health, 100)
        XCTAssertEqual(combat.blockedAttacks, 0)
    }

    func testShieldPauseAndFailedSpellCostsDoNotAdvanceOrSpend() {
        let state = SurvivalState(defaults: nil)
        let (_, combat) = makeEncounter(state: state)
        XCTAssertTrue(combat.shield())
        combat.setPaused(true)
        let paused = combat.runSnapshot
        var time = advance(combat, from: 0, seconds: 20)
        XCTAssertEqual(combat.runSnapshot, paused)
        XCTAssertFalse(combat.shield())
        XCTAssertEqual(combat.lastRejection, .paused)
        XCTAssertFalse(combat.ice(toward: SIMD3(0, 1, 0)))
        combat.setPaused(false)
        time = advance(combat, from: time, seconds: 1.1)
        XCTAssertEqual(combat.runSnapshot.shieldHealth, 20)
        XCTAssertEqual(combat.runSnapshot.shieldCooldownRemaining, 8.9166667, accuracy: 0.001)
        combat.restart()
        XCTAssertTrue(combat.startRun())
        time = advance(combat, from: time, seconds: 3.1)
        XCTAssertTrue(state.spend(95))
        XCTAssertEqual(combat.runSnapshot.mana, 5)
        XCTAssertFalse(combat.shield())
        XCTAssertEqual(combat.lastRejection, .insufficientMana)
        XCTAssertFalse(combat.ice(toward: SIMD3(0, 1, 0)))
        XCTAssertEqual(combat.lastRejection, .insufficientMana)
        XCTAssertEqual(combat.runSnapshot.mana, 5)
        XCTAssertEqual(combat.runSnapshot.shieldRemaining, 0)
        XCTAssertEqual(combat.runSnapshot.shieldCooldownRemaining, 0)
    }

    func testWaitingRunStartsOneCountdownAndSpawnsOnlyWhenItFinishes() {
        let (scene, combat) = makeEncounter(startsImmediately: false)
        var time = advance(combat, from: 0, seconds: 20)
        XCTAssertFalse(combat.runSnapshot.hasStarted)
        XCTAssertEqual(combat.remaining, 0)
        XCTAssertEqual(combat.pendingSpawns, 0)
        XCTAssertTrue(combatants(in: scene).isEmpty)
        XCTAssertFalse(combat.cast(toward: SIMD3(0, 1, 0)))
        XCTAssertFalse(combat.ice(toward: SIMD3(0, 1, 0)))
        XCTAssertFalse(combat.shield())
        XCTAssertFalse(combat.nyan())
        XCTAssertEqual(combat.lastRejection, .notReady)
        var madeAlly = false
        XCTAssertEqual(
            combat.summon(kind: .alan) {
                madeAlly = true
                return SCNNode()
            }, .unavailable)
        XCTAssertFalse(madeAlly)
        XCTAssertTrue(combat.startRun())
        XCTAssertFalse(combat.startRun())
        XCTAssertTrue(combat.runSnapshot.hasStarted)
        XCTAssertEqual(combat.runSnapshot.countdownRemaining, 3)
        time = advance(combat, from: time, seconds: 2.2)
        XCTAssertEqual(combat.remaining, 0)
        XCTAssertEqual(combat.runSnapshot.countdownRemaining, 0.8, accuracy: 0.001)
        XCTAssertFalse(combat.shoot(toward: SIMD3(0, 1, 0)))
        XCTAssertEqual(combat.runSnapshot.mana, 100)
        time = advance(combat, from: time, seconds: 0.9)
        XCTAssertEqual(combat.runSnapshot.countdownRemaining, 0)
        XCTAssertEqual(combat.remaining, 1)
        XCTAssertEqual(combat.pendingSpawns, 7)
        XCTAssertEqual(combat.runSnapshot.health, 100)
    }

    func testCountdownPauseAndProductionRestart() {
        let (_, combat) = makeEncounter(startsImmediately: false)
        XCTAssertTrue(combat.startRun())
        var time = advance(combat, from: 0, seconds: 1)
        let remaining = combat.runSnapshot.countdownRemaining
        combat.setPaused(true)
        time = advance(combat, from: time, seconds: 30)
        XCTAssertEqual(combat.runSnapshot.countdownRemaining, remaining)
        XCTAssertEqual(combat.remaining, 0)
        combat.setPaused(false)
        _ = advance(combat, from: time, seconds: 2.2)
        XCTAssertEqual(combat.remaining, 1)
        combat.restart()
        XCTAssertFalse(combat.runSnapshot.hasStarted)
        XCTAssertEqual(combat.runSnapshot.countdownRemaining, 0)
        XCTAssertEqual(combat.remaining, 0)
        XCTAssertEqual(combat.runSnapshot.mana, 100)
        XCTAssertTrue(combat.startRun())
        XCTAssertEqual(combat.runSnapshot.countdownRemaining, 3)
    }

    func testResetScoresClearsRunAndOnlyItsPersistedRecordsWhileRestartKeepsThem() throws {
        let suite = "XArcana.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("keep", forKey: "unrelated.preference")
        let state = chargedNyanState(defaults: defaults)
        let (scene, combat) = makeEncounter(defaults: defaults, cameraHeight: 6, state: state)
        XCTAssertTrue(combat.nyan())
        XCTAssertNotNil(combat.transfigurationPhase)
        combat.restart()
        XCTAssertEqual(combat.runSnapshot.score, 0)
        XCTAssertEqual(combat.runSnapshot.bestScore, 2_000)
        XCTAssertEqual(combat.runSnapshot.nyanKillsSinceCast, 0)
        XCTAssertTrue(combat.startRun())
        _ = advance(combat, from: 0, seconds: 3.1)
        let alan = SCNNode()
        XCTAssertEqual(combat.summon(kind: .alan) { alan }, .summoned)
        var published: RunSnapshot?
        combat.onChange = { [weak combat] in published = combat?.runSnapshot }
        combat.resetScores()
        var expected = RunSnapshot()
        expected.hasStarted = false
        XCTAssertEqual(combat.runSnapshot, expected)
        XCTAssertEqual(published, expected)
        XCTAssertNil(alan.parent)
        XCTAssertNil(combat.transfigurationPhase)
        XCTAssertTrue(combatants(in: scene).isEmpty)
        XCTAssertNil(defaults.object(forKey: "XArcana.bestScore"))
        XCTAssertNil(defaults.object(forKey: "XArcana.bestWave"))
        XCTAssertEqual(defaults.string(forKey: "unrelated.preference"), "keep")
        XCTAssertEqual(SurvivalState(defaults: defaults).snapshot, RunSnapshot())
    }

    func testNyanRequiresTwentyKillsThenTransformsOnlyLivingOnFieldZombies() throws {
        let state = SurvivalState(defaults: nil)
        let (scene, combat) = makeEncounter(cameraHeight: 6, state: state)
        let original = combat.runSnapshot
        XCTAssertFalse(combat.nyan())
        XCTAssertEqual(combat.runSnapshot, original)
        for _ in 0..<19 { state.recordKill() }
        XCTAssertFalse(combat.nyan())
        XCTAssertEqual(combat.runSnapshot.mana, 100)
        state.recordKill()
        XCTAssertTrue(combat.nyan())
        XCTAssertEqual(combat.runSnapshot.mana, 20)
        XCTAssertEqual(combat.runSnapshot.nyanKillsSinceCast, 0)
        XCTAssertEqual(combat.runSnapshot.nyanRemaining, SurvivalState.nyanDuration)
        XCTAssertEqual(combat.transfigurationPhase, 0)
        XCTAssertEqual(combat.remaining, 1)
        XCTAssertEqual(combat.pendingSpawns, 7)
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        XCTAssertTrue(enemy.isTransfigured)
        let cat = try XCTUnwrap(enemy.childNode(withName: "Transfigured Nyan cat", recursively: false))
        XCTAssertEqual(cat.categoryBitMask, 2)
        XCTAssertTrue(enemy.childNodes.filter { $0 !== cat }.allSatisfy(\.isHidden))
        XCTAssertEqual(cat.childNodes.filter { $0.name?.hasPrefix("Rainbow cat leg") == true }.count, 4)
        XCTAssertEqual(cat.childNodes.filter { $0.name == "Rainbow trail" }.count, 6)
        let active = combat.runSnapshot
        XCTAssertFalse(combat.nyan())
        XCTAssertEqual(combat.runSnapshot, active)
    }

    func testNyanCancelsPendingMeleePausesSpawnsAndResumesFutureZombiesNormally() throws {
        let (scene, combat) = makeEncounter(state: chargedNyanState())
        let first = try XCTUnwrap(combatants(in: scene).first)
        first.simdPosition = SIMD3(0, 0, 3.85)
        var time = advance(combat, from: 0, seconds: 1.1)
        XCTAssertEqual(first.meleeAttackCount, 1)
        XCTAssertTrue(combat.nyan())
        let position = first.simdPosition
        time = advance(combat, from: time, seconds: SurvivalState.nyanDuration - 0.1)
        XCTAssertEqual(first.simdPosition, position)
        XCTAssertEqual(combat.runSnapshot.health, 100)
        XCTAssertEqual(combat.kills, 20)
        XCTAssertEqual(combat.remaining, 1)
        XCTAssertEqual(combat.pendingSpawns, 7)
        XCTAssertEqual(first.meleeAttackCount, 1)
        time = advance(combat, from: time, seconds: 0.2)
        XCTAssertTrue(first.isDefeated)
        XCTAssertFalse(first.isTransfigured)
        XCTAssertNil(first.childNode(withName: "Transfigured Nyan cat", recursively: false))
        XCTAssertEqual(combat.runSnapshot.nyanRemaining, 0)
        XCTAssertEqual(combat.kills, 21)
        XCTAssertEqual(combat.runSnapshot.score, 2_100)
        XCTAssertEqual(combat.runSnapshot.bestWave, 0, "Queued zombies prevent a stage clear.")
        XCTAssertEqual(combat.wave, 1)
        XCTAssertEqual(combat.pendingSpawns, 7)
        time = advance(combat, from: time, seconds: Combat.spawnInterval + 0.2)
        let future = combatants(in: scene).filter { !$0.isDefeated }
        XCTAssertEqual(future.count, 1)
        XCTAssertFalse(try XCTUnwrap(future.first).isTransfigured)
        XCTAssertEqual(combat.pendingSpawns, 6)
        XCTAssertFalse(combat.nyan(), "One transformed kill does not recharge the next cast.")
    }

    func testNyanEmitsStageClearAndStartEventsOnceWithPauseAndRestart() {
        let (_, combat) = makeEncounter(cameraHeight: 6, state: chargedNyanState())
        var time = advance(combat, from: 0, seconds: Combat.spawnInterval * 7 + 0.5)
        var events: [Combat.Event] = []
        var clearedScore: Int?
        combat.onEvent = { event in
            events.append(event)
            if case .waveCleared = event { clearedScore = combat.runSnapshot.score }
        }
        XCTAssertTrue(combat.nyan())
        time = advance(combat, from: time, seconds: 10)
        combat.setPaused(true)
        time = advance(combat, from: time, seconds: 30)
        XCTAssertTrue(events.isEmpty)
        combat.setPaused(false)
        time = advance(combat, from: time, seconds: SurvivalState.nyanDuration - 9.9)
        let clearedEvents: [Combat.Event] = [.waveCleared(1)]
        XCTAssertEqual(events, clearedEvents)
        XCTAssertEqual(clearedScore, 3_050)

        combat.setPaused(true)
        time = advance(combat, from: time, seconds: 30)
        XCTAssertEqual(events, clearedEvents)
        combat.setPaused(false)
        time = advance(combat, from: time, seconds: Combat.waveBreakDuration - 0.3)
        XCTAssertEqual(events, clearedEvents)
        time = advance(combat, from: time, seconds: 0.5)
        XCTAssertEqual(events, clearedEvents + [.waveStarted(2)])
        time = advance(combat, from: time, seconds: 0.5)
        XCTAssertEqual(events, clearedEvents + [.waveStarted(2)])

        combat.restart()
        XCTAssertEqual(events, clearedEvents + [.waveStarted(2)])
        time = advance(combat, from: time, seconds: 13)
        XCTAssertEqual(events, clearedEvents + [.waveStarted(2)])
        XCTAssertTrue(combat.startRun())
        _ = advance(combat, from: time, seconds: 3.1)
        XCTAssertEqual(events, clearedEvents + [.waveStarted(2), .waveStarted(1)])
        combat.onEvent = nil
    }

    func testProductionCountdownEmitsWaveStartOnlyAtCompletionAndRestartsCleanly() {
        let (_, combat) = makeEncounter(startsImmediately: false)
        var events: [Combat.Event] = []
        combat.onEvent = { events.append($0) }
        XCTAssertTrue(combat.startRun())
        XCTAssertFalse(combat.startRun())
        var time = advance(combat, from: 0, seconds: 2)
        XCTAssertTrue(events.isEmpty)
        combat.restart()
        time = advance(combat, from: time, seconds: 2)
        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(combat.runSnapshot.hasStarted)
        XCTAssertTrue(combat.startRun())
        time = advance(combat, from: time, seconds: 2)
        XCTAssertTrue(events.isEmpty)
        time = advance(combat, from: time, seconds: 1.2)
        XCTAssertEqual(events, [.waveStarted(1)])
        _ = advance(combat, from: time, seconds: 1)
        XCTAssertEqual(events, [.waveStarted(1)])
    }

    func testTransfigurationPauseFreezesCatsAndPhaseAndRestartRestoresOriginals() throws {
        let (scene, combat) = makeEncounter(state: chargedNyanState())
        XCTAssertTrue(combat.nyan())
        var time = advance(combat, from: 0, seconds: 1)
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        let cat = try XCTUnwrap(enemy.childNode(withName: "Transfigured Nyan cat", recursively: false))
        let original = try XCTUnwrap(enemy.childNodes.first { $0 !== cat })
        let catPosition = cat.simdPosition
        let catWorldTransform = cat.simdWorldTransform
        let phase = combat.transfigurationPhase
        let remaining = combat.runSnapshot.nyanRemaining
        XCTAssertTrue(original.isHidden)
        combat.setPaused(true)
        time = advance(combat, from: time, seconds: 30)
        XCTAssertEqual(cat.simdPosition, catPosition)
        XCTAssertEqual(cat.simdWorldTransform, catWorldTransform)
        XCTAssertEqual(combat.transfigurationPhase, phase)
        XCTAssertEqual(combat.runSnapshot.nyanRemaining, remaining)
        XCTAssertEqual(combat.kills, 20)
        combat.setPaused(false)
        _ = advance(combat, from: time, seconds: 1.1)
        XCTAssertLessThan(combat.runSnapshot.nyanRemaining, remaining)
        XCTAssertNotEqual(cat.simdPosition, catPosition)
        combat.restart()
        XCTAssertEqual(combat.runSnapshot.nyanRemaining, 0)
        XCTAssertNil(combat.transfigurationPhase)
        XCTAssertNil(cat.parent)
        XCTAssertFalse(original.isHidden)
        XCTAssertEqual(combat.kills, 0)
        XCTAssertEqual(combat.runSnapshot.nyanKillsSinceCast, 0)
        XCTAssertFalse(combat.runSnapshot.hasStarted)
        XCTAssertEqual(combat.remaining, 0)
    }

    func testTransfiguredCatsCannotBeDamagedByProjectilesOrIce() throws {
        let (scene, combat) = makeEncounter(state: chargedNyanState())
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        enemy.simdPosition = SIMD3(0, 0, 3.85)
        XCTAssertTrue(combat.shoot(toward: center(enemy)))
        XCTAssertTrue(combat.nyan())
        var time = advance(combat, from: 0, seconds: 0.7)
        XCTAssertTrue(combat.ice(toward: center(enemy)))
        time = advance(combat, from: time, seconds: 4.6)
        XCTAssertGreaterThanOrEqual(combat.runSnapshot.mana, SpellCatalog.fireball.manaCost)
        XCTAssertTrue(combat.fireball(toward: center(enemy)))
        _ = advance(combat, from: time, seconds: 1)
        XCTAssertEqual(combat.kills, 20)
        XCTAssertEqual(combat.runSnapshot.score, 2_000)
        XCTAssertTrue(combatants(in: scene).allSatisfy { $0.health == 2 && $0.isTransfigured })
    }

    func testPhysicalAllyRemainsButCannotTargetOrDamageTransfiguredCats() throws {
        let (scene, combat) = makeEncounter(state: chargedNyanState())
        let albert = SCNNode()
        albert.simdPosition = SIMD3(2.2, 0, 3.9)
        XCTAssertEqual(combat.summon(kind: .albert) { albert }, .summoned)
        let time = advance(combat, from: 0, seconds: 5)
        XCTAssertTrue(combat.nyan())
        let health = combatants(in: scene).map(\.health)
        let position = albert.simdPosition
        _ = advance(combat, from: time, seconds: 5)
        XCTAssertNotNil(albert.parent)
        XCTAssertEqual(albert.simdPosition, position)
        XCTAssertEqual(combatants(in: scene).map(\.health), health)
        XCTAssertEqual(combat.kills, 20)
    }

    func testNyanInsufficientManaDoesNotMaterializeOrTransformHorde() {
        let (scene, combat) = makeEncounter(state: chargedNyanState())
        XCTAssertEqual(combat.summon(kind: .alan) { SCNNode() }, .summoned)
        XCTAssertFalse(combat.nyan())
        XCTAssertEqual(combat.lastRejection, .insufficientMana)
        XCTAssertEqual(combat.runSnapshot.mana, 75)
        XCTAssertEqual(combat.runSnapshot.nyanRemaining, 0)
        XCTAssertEqual(combat.remaining, 1)
        XCTAssertEqual(combat.pendingSpawns, 7)
        XCTAssertTrue(combatants(in: scene).allSatisfy { !$0.isTransfigured })
    }

    func testLongPauseDoesNotTeleportPursuersOrSpawnTheWholeWave() throws {
        let (scene, combat) = makeEncounter()
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        let initial = enemy.simdPosition
        combat.update(at: 120)
        XCTAssertLessThan(simd_distance(enemy.simdPosition, initial), 0.03)
        XCTAssertEqual(combat.remaining, 1)
    }

    func testKillsAwardScoreExactlyOnceWithoutExperienceLevels() throws {
        let (scene, combat) = makeEncounter()
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        enemy.simdPosition = SIMD3(0, 0, 1.5)
        var time = 0.0
        for _ in 0..<2 {
            XCTAssertTrue(combat.shoot(toward: center(enemy)))
            time = advance(combat, from: time, seconds: 0.6)
        }
        XCTAssertEqual(combat.kills, 1)
        XCTAssertEqual(combat.runSnapshot.score, 100)
        XCTAssertEqual(combat.runSnapshot.xp, 0)
        XCTAssertEqual(combat.runSnapshot.level, 1)
        XCTAssertTrue(combat.fireball(toward: center(enemy)))
        _ = advance(combat, from: time, seconds: 1)
        XCTAssertEqual(combat.kills, 1)
        XCTAssertEqual(combat.runSnapshot.score, 100)
    }

    func testFireballSharesFiveDamageWithHighestWeightAtCenter() {
        let damage = CombatGeometry.fireballDamages(distances: [0, 1.5, 3, 3.01], radius: 3)
        XCTAssertEqual(damage.reduce(0, +), 5, accuracy: 0.000001)
        XCTAssertGreaterThan(damage[0], damage[1])
        XCTAssertGreaterThan(damage[1], damage[2])
        XCTAssertGreaterThan(damage[2], 0)
        XCTAssertEqual(damage[3], 0)
        XCTAssertEqual(CombatGeometry.fireballDamages(distances: [0], radius: 3), [5])
        XCTAssertEqual(CombatGeometry.fireballDamages(distances: [1, 1], radius: 3), [2.5, 2.5])
        XCTAssertEqual(CombatGeometry.fireballDamages(distances: [3.01, .nan, -1], radius: 3), [0, 0, 0])
        XCTAssertEqual(CombatGeometry.fireballDamages(distances: [0], radius: 0), [0])
        XCTAssertEqual(CombatGeometry.fireballDamages(distances: [], radius: 3), [])
    }

    func testFireballLeavesFractionalHealthWhenFiveDamageIsSharedByThreeZombies() {
        let (scene, combat) = makeEncounter(cameraHeight: 6)
        let time = advance(combat, from: 0, seconds: Combat.spawnInterval * 2 + 0.2)
        scene.rootNode.childNode(withName: "Test camera", recursively: false)?.position.y = 1.65
        let enemies = combatants(in: scene)
        for (index, enemy) in enemies.enumerated() {
            enemy.simdPosition = SIMD3(Float(index - 1) * 0.4, 0, 1.5)
        }
        XCTAssertTrue(combat.fireball(toward: center(enemies[1])))
        _ = advance(combat, from: time, seconds: 0.6)
        XCTAssertTrue(enemies.allSatisfy { $0.health > 0 && $0.health < 2 })
        XCTAssertEqual(enemies.map(\.health).reduce(0, +), 1, accuracy: 0.000001)
        XCTAssertEqual(combat.kills, 0)
        enemies[0].simdPosition = SIMD3(0, 0, 1.5)
        XCTAssertTrue(combat.ice(toward: center(enemies[0])))
        XCTAssertGreaterThan(combat.kills, 0)
    }

    func testWandMeleeDealsHalfDamageToNearestTargetAndFourSwingsDefeatIt() throws {
        let (scene, combat) = makeEncounter(cameraHeight: 6)
        var time = advance(combat, from: 0, seconds: Combat.spawnInterval + 0.1)
        scene.rootNode.childNode(withName: "Test camera", recursively: false)?.position.y = 1.65
        let enemies = combatants(in: scene)
        enemies[0].simdPosition = SIMD3(0, 0, 3.5)
        enemies[1].simdPosition = SIMD3(0.8, 0, 3.4)
        let mana = combat.runSnapshot.mana
        XCTAssertTrue(combat.melee(toward: center(enemies[0])))
        XCTAssertEqual(enemies.map(\.health), [1.5, 2])
        XCTAssertEqual(combat.runSnapshot.mana, mana)
        XCTAssertFalse(combat.melee(toward: center(enemies[0])))
        XCTAssertEqual(combat.lastRejection, .cooldown)
        for hit in 2...4 {
            time = advance(combat, from: time, seconds: 0.6)
            XCTAssertTrue(combat.melee(toward: center(enemies[0])))
            XCTAssertEqual(enemies.map(\.health), [2 - Double(hit) * 0.5, 2])
        }
        XCTAssertEqual(combat.kills, 1)
    }

    func testWandMeleeCanMissButCannotHitDistantRearOrTransfiguredTargets() throws {
        let (scene, combat) = makeEncounter(state: chargedNyanState())
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        enemy.simdPosition = SIMD3(0, 0, 1)
        XCTAssertTrue(combat.melee(toward: center(enemy)))
        XCTAssertEqual(enemy.health, 2)
        var time = advance(combat, from: 0, seconds: 0.6)
        enemy.simdPosition = SIMD3(0, 0, 3.85)
        XCTAssertTrue(combat.melee(toward: SIMD3(0, 1.65, 10)))
        XCTAssertEqual(enemy.health, 2)
        time = advance(combat, from: time, seconds: 0.6)
        XCTAssertTrue(combat.nyan())
        XCTAssertTrue(combat.melee(toward: center(enemy)))
        XCTAssertEqual(enemy.health, 2)
        XCTAssertEqual(combat.kills, 20)
    }

    func testWandMeleeRejectsInvalidTargetsAndCannotAttackWhileWaitingOrPaused() throws {
        let (scene, combat) = makeEncounter(startsImmediately: false)
        let target = SIMD3<Float>(0, 1, 3.85)
        XCTAssertFalse(combat.melee(toward: target))
        XCTAssertEqual(combat.lastRejection, .notReady)
        XCTAssertTrue(combat.startRun())
        XCTAssertFalse(combat.melee(toward: target))
        var time = advance(combat, from: 0, seconds: 3.1)
        XCTAssertFalse(combat.melee(toward: SIMD3(.nan, 0, 0)))
        XCTAssertEqual(combat.lastRejection, .invalidTarget)
        let camera = try XCTUnwrap(scene.rootNode.childNode(withName: "Test camera", recursively: false))
        XCTAssertFalse(combat.melee(toward: camera.simdPosition))
        XCTAssertTrue(combat.melee(toward: target), "Rejected targets must not start the swing cooldown.")
        combat.setPaused(true)
        time = advance(combat, from: time, seconds: 20)
        XCTAssertFalse(combat.melee(toward: target))
        XCTAssertEqual(combat.lastRejection, .paused)
        combat.setPaused(false)
        XCTAssertFalse(combat.melee(toward: target), "Pause must not consume the swing cooldown.")
        _ = advance(combat, from: time, seconds: 0.6)
        XCTAssertTrue(combat.melee(toward: target))
    }

    func testSweptCollisionFindsTargetBetweenFramesAndRejectsMiss() throws {
        let lower = SIMD3<Float>(-0.4, 0.1, -0.3)
        let upper = SIMD3<Float>(0.4, 1.8, 0.3)
        let hit = try XCTUnwrap(
            CombatGeometry.hitFraction(from: SIMD3(0, 1, 4), to: SIMD3(0, 1, -4), minimum: lower, maximum: upper))
        XCTAssertEqual(hit, 0.4625, accuracy: 0.0001)
        XCTAssertNil(
            CombatGeometry.hitFraction(from: SIMD3(1, 1, 4), to: SIMD3(1, 1, -4), minimum: lower, maximum: upper))
    }

    func testEveryManaActionPublishesItsExactCatalogCostOnce() {
        let actions: [(Double, (Combat) -> Bool)] =
            [
                (0, { $0.shoot(toward: SIMD3(0, 8, -5)) }),
                (SpellCatalog.lightning.manaCost, { $0.cast(toward: SIMD3(0, 8, -5)) }),
                (SpellCatalog.fireball.manaCost, { $0.fireball(toward: SIMD3(0, 8, -5)) }),
                (SpellCatalog.ice.manaCost, { $0.ice(toward: SIMD3(0, 8, -5)) }),
                (SpellCatalog.shield.manaCost, { $0.shield() }),
                (SpellCatalog.nyan.manaCost, { $0.nyan() }),
            ]
            + SummonKind.allCases.map { kind in
                (SpellCatalog.summon(kind).manaCost, { $0.summon(kind: kind) { SCNNode() } == .summoned })
            }
        for (cost, action) in actions {
            let state = unlockedDemonState()
            for _ in 0..<20 { state.recordKill() }
            let (_, combat) = makeEncounter(state: state)
            var published: [RunSnapshot] = []
            combat.onChange = { [weak combat] in
                if let snapshot = combat?.runSnapshot { published.append(snapshot) }
            }
            XCTAssertTrue(action(combat))
            XCTAssertEqual(combat.runSnapshot.mana, 100 - cost, accuracy: 0.000001)
            XCTAssertEqual(published.count, 1)
            XCTAssertEqual(published.last, combat.runSnapshot)
            XCTAssertFalse(action(combat), "A repeated action during cooldown or an active summon cannot spend again.")
            XCTAssertEqual(combat.runSnapshot.mana, 100 - cost, accuracy: 0.000001)
            XCTAssertEqual(published.count, 1)
        }
    }

    func testManaRegenerationIgnoresReplayedAndBackwardsFrameTimes() {
        let (_, combat) = makeEncounter()
        XCTAssertTrue(combat.shield())
        let time = advance(combat, from: 0, seconds: 2.5)
        XCTAssertEqual(combat.runSnapshot.mana, 82, accuracy: 0.000001)
        let snapshot = combat.runSnapshot
        combat.update(at: time)
        combat.update(at: time - 0.05)
        combat.update(at: .nan)
        combat.update(at: time)
        XCTAssertEqual(combat.runSnapshot, snapshot, "Previously counted frame time must not regenerate mana twice.")
        combat.update(at: time + 0.05)
        XCTAssertEqual(combat.runSnapshot.mana, snapshot.mana + 0.2, accuracy: 0.000001)
        combat.setPaused(true)
        let paused = combat.runSnapshot
        combat.update(at: time + 5)
        XCTAssertEqual(combat.runSnapshot, paused)
        combat.setPaused(false)
        combat.update(at: time + 10)
        XCTAssertEqual(combat.runSnapshot, paused, "The first resumed frame establishes a fresh clock.")
    }

    func testFireballSpendsImmediatelyAndRecoversAfterTwoSecondDelay() {
        let (_, combat) = makeEncounter(cameraHeight: 6)
        XCTAssertTrue(combat.fireball(toward: SIMD3(0, 8, -5)))
        XCTAssertEqual(combat.runSnapshot.mana, 85)
        var time = advance(combat, from: 0, seconds: 2)
        XCTAssertEqual(combat.runSnapshot.mana, 85, accuracy: 0.000001)
        time = advance(combat, from: time, seconds: 1)
        XCTAssertEqual(combat.runSnapshot.mana, 89, accuracy: 0.000001)
        time = advance(combat, from: time, seconds: 2)
        XCTAssertEqual(combat.runSnapshot.mana, 97, accuracy: 0.000001)
        _ = advance(combat, from: time, seconds: 0.75)
        XCTAssertEqual(combat.runSnapshot.mana, 100, accuracy: 0.000001)
        XCTAssertEqual(combat.runSnapshot.kills, 0, "This recovery trace must not include a stage refill.")
    }

    func testSpawnIntervalsAcceleratePerLevelAndStopAtTwoSeconds() {
        XCTAssertEqual(Combat.spawnInterval(for: 1), 8)
        XCTAssertEqual(Combat.spawnInterval(for: 2), 7.2, accuracy: 0.000001)
        XCTAssertEqual(Combat.spawnInterval(for: 3), 6.48, accuracy: 0.000001)
        XCTAssertEqual(Combat.spawnInterval(for: 100), 2)
    }

    func testLevelTwoSwipeAndBiteRetainHalfDamageAgainstPlayerAndShield() throws {
        let state = SurvivalState(defaults: nil)
        state.nextWave()
        let (scene, combat) = makeEncounter(state: state)
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        enemy.simdPosition = SIMD3(0, 0, 3.85)
        var time = advance(combat, from: 0, seconds: 1.4)
        XCTAssertEqual(enemy.lastMeleeAttack, .swipe)
        XCTAssertEqual(combat.runSnapshot.health, 108.5)
        XCTAssertTrue(combat.shield())
        time = advance(combat, from: time, seconds: 2.65)
        XCTAssertEqual(enemy.lastMeleeAttack, .bite)
        XCTAssertEqual(combat.runSnapshot.health, 108.5)
        XCTAssertEqual(combat.runSnapshot.shieldHealth, 18.5)
    }

    func testBowCannotFireBeforeItsHalfSecondReloadCompletes() {
        let (_, combat) = makeEncounter(cameraHeight: 6)
        let target = SIMD3<Float>(0, 8, -5)
        XCTAssertTrue(combat.shoot(toward: target))
        var time = advance(combat, from: 0, seconds: 0.3)
        XCTAssertFalse(combat.shoot(toward: target))
        XCTAssertEqual(combat.lastRejection, .cooldown)
        time = advance(combat, from: time, seconds: 0.183)
        XCTAssertFalse(combat.shoot(toward: target))
        _ = advance(combat, from: time, seconds: 0.034)
        XCTAssertTrue(combat.shoot(toward: target))
        XCTAssertEqual(combat.runSnapshot.mana, 100)
    }

    func testDemonDrainsTwentyManaPerSecondWithoutRegenerationThenExpires() {
        let (_, combat) = makeEncounter(cameraHeight: 6, state: unlockedDemonState())
        let demon = SCNNode()
        demon.simdPosition = SIMD3(0, 10, 4.8)
        XCTAssertEqual(combat.summon(kind: .demon) { demon }, .summoned)
        XCTAssertEqual(combat.runSnapshot.mana, 100)
        var time = advance(combat, from: 0, seconds: 3)
        XCTAssertEqual(combat.runSnapshot.mana, 40, accuracy: 0.000001)
        XCTAssertNotNil(demon.parent)
        combat.setPaused(true)
        time = advance(combat, from: time, seconds: 8)
        XCTAssertEqual(combat.runSnapshot.mana, 40, accuracy: 0.000001)
        combat.setPaused(false)
        time = advance(combat, from: time, seconds: 2.05)
        XCTAssertNil(demon.parent)
        XCTAssertEqual(combat.runSnapshot.mana, 0, accuracy: 0.000001)
        _ = advance(combat, from: time, seconds: 3)
        XCTAssertGreaterThan(combat.runSnapshot.mana, 0)
    }

    func testDemonDismissesWhenManaRunsOutAndRestartStopsItsDrain() {
        let state = unlockedDemonState()
        XCTAssertTrue(state.spend(80))
        let (_, combat) = makeEncounter(cameraHeight: 6, state: state)
        let demon = SCNNode()
        XCTAssertEqual(combat.summon(kind: .demon) { demon }, .summoned)
        XCTAssertEqual(combat.runSnapshot.mana, 20)
        var time = advance(combat, from: 0, seconds: 1.05)
        XCTAssertNil(demon.parent)
        XCTAssertEqual(combat.runSnapshot.mana, 0, accuracy: 0.000001)
        time = advance(combat, from: time, seconds: 8)
        XCTAssertGreaterThanOrEqual(combat.runSnapshot.mana, 20)
        let second = SCNNode()
        XCTAssertEqual(combat.summon(kind: .demon) { second }, .summoned)
        combat.restart()
        XCTAssertNil(second.parent)
        _ = advance(combat, from: time, seconds: 2)
        XCTAssertEqual(combat.runSnapshot.mana, 100)
        XCTAssertFalse(combat.runSnapshot.hasStarted)
    }

    func testDemonRequiresTwentyManaWithoutRemovingExistingAllyOnFailure() {
        let state = unlockedDemonState()
        let (_, combat) = makeEncounter(cameraHeight: 6, state: state)
        let alan = SCNNode()
        XCTAssertEqual(combat.summon(kind: .alan) { alan }, .summoned)
        XCTAssertTrue(state.spend(56))
        var created = false
        XCTAssertEqual(
            combat.summon(kind: .demon) {
                created = true
                return SCNNode()
            }, .insufficientMana)
        XCTAssertFalse(created)
        XCTAssertNotNil(alan.parent)
        XCTAssertEqual(combat.runSnapshot.mana, 19)
    }

    func testLockedDemonRejectsBeforeModelCreationManaAndAllyReplacement() {
        let state = SurvivalState(defaults: nil)
        let (_, combat) = makeEncounter(state: state)
        let alan = SCNNode()
        XCTAssertEqual(combat.summon(kind: .alan) { alan }, .summoned)
        XCTAssertTrue(state.spend(75))
        let before = combat.runSnapshot
        var created = false
        XCTAssertEqual(
            combat.summon(kind: .demon) {
                created = true
                return SCNNode()
            }, .locked)
        XCTAssertFalse(created)
        XCTAssertEqual(combat.runSnapshot, before)
        XCTAssertNotNil(alan.parent)
    }

    func testLevelTenSpawnsOneThirtyHealthDemonWithoutZombiesOrNyan() throws {
        let state = finalBossState()
        for _ in 0..<20 { state.recordKill() }
        let (scene, combat) = makeEncounter(cameraHeight: 6, state: state)
        let boss = try XCTUnwrap(combatants(in: scene).first)
        XCTAssertTrue(combat.isBossFight)
        XCTAssertEqual(combat.wave, 10)
        XCTAssertEqual(combat.runSnapshot.maxHealth, 200)
        XCTAssertEqual(combat.runSnapshot.health, 200)
        XCTAssertEqual(combat.runSnapshot.maxMana, 200)
        XCTAssertEqual(combat.remaining, 1)
        XCTAssertEqual(combat.pendingSpawns, 0)
        XCTAssertEqual(boss.kind, .demonBoss)
        XCTAssertEqual(boss.identityName, "Demon King")
        XCTAssertEqual(boss.health, 30)
        XCTAssertEqual(boss.maxHealth, 30)
        XCTAssertNotNil(boss.childNode(withName: "DemonSculpture", recursively: true))
        XCTAssertFalse(boss.healthBar.isHidden)
        XCTAssertTrue(boss.healthBar.constraints?.first is SCNBillboardConstraint)
        let before = combat.runSnapshot
        XCTAssertFalse(combat.nyan())
        XCTAssertEqual(combat.runSnapshot, before)
        XCTAssertFalse(boss.isTransfigured)
        _ = advance(combat, from: 0, seconds: 60)
        XCTAssertEqual(combatants(in: scene).count, 1)
        XCTAssertTrue(combatants(in: scene).allSatisfy { $0.kind == .demonBoss })
        XCTAssertEqual(combat.pendingSpawns, 0)
    }

    func testBossRequiresThirtyOneDamageArrowsThenLevelElevenStartsAfterTheNormalBreak() throws {
        let (scene, combat) = makeEncounter(cameraHeight: 6, state: finalBossState())
        let boss = try XCTUnwrap(combatants(in: scene).first)
        var events: [Combat.Event] = []
        combat.onEvent = { events.append($0) }
        var time = 0.0
        for hit in 1...30 {
            boss.simdPosition = SIMD3(0, 1.5, 1.5)
            XCTAssertTrue(combat.shoot(toward: center(boss)), "Arrow \(hit)")
            time = advance(combat, from: time, seconds: 0.6)
            XCTAssertEqual(boss.health, max(0, 30 - Double(hit)), accuracy: 1e-10)
            XCTAssertEqual(boss.isDefeated, hit == 30)
            XCTAssertFalse(combat.runSnapshot.hasWon)
            XCTAssertFalse(combat.runSnapshot.isGameOver)
            XCTAssertEqual(combat.kills, 0)
            if hit < 30 {
                XCTAssertFalse(combat.runSnapshot.demonUnlocked)
                XCTAssertFalse(boss.healthBar.isHidden)
            }
        }
        let cleared = combat.runSnapshot
        XCTAssertTrue(cleared.demonUnlocked)
        XCTAssertEqual(cleared.score, 1_250)
        XCTAssertEqual(cleared.bestWave, 10)
        XCTAssertEqual(cleared.nyanKillsSinceCast, 0)
        XCTAssertTrue(boss.healthBar.isHidden)
        XCTAssertEqual(events.filter { $0 == .demonUnlocked }.count, 1)
        XCTAssertEqual(events.filter { $0 == .waveCleared(10) }.count, 1)
        time = advance(combat, from: time, seconds: Combat.waveBreakDuration - 1)
        XCTAssertEqual(combat.wave, 10)
        XCTAssertEqual(combat.remaining, 0)
        XCTAssertEqual(combat.runSnapshot.score, cleared.score, "A dead boss cannot award points twice")
        time = advance(combat, from: time, seconds: 1.1)
        XCTAssertEqual(combat.wave, 11)
        XCTAssertEqual(combat.runSnapshot.maxHealth, 210)
        XCTAssertEqual(combat.runSnapshot.health, 210)
        XCTAssertEqual(combat.runSnapshot.maxMana, 210)
        XCTAssertEqual(combat.runSnapshot.mana, 210)
        XCTAssertEqual(combat.remainingDemonKings, 1)
        XCTAssertEqual(combat.remainingZombies + combat.pendingZombieSpawns, 2)
        XCTAssertEqual(events.filter { $0 == .waveStarted(11) }.count, 1)
        XCTAssertEqual(events.filter { $0 == .demonUnlocked }.count, 1)
    }

    func testEndlessStageCompositionAddsZombiesAndOneKingEveryFiveLevels() {
        let stages: [(level: Int, zombies: Int, kings: Int)] = [
            (1, 8, 0), (9, 8, 0), (10, 0, 1), (11, 2, 1), (12, 4, 1),
            (13, 6, 1), (14, 8, 1), (15, 8, 2), (19, 8, 2), (20, 8, 3),
            (25, 8, 4), (30, 8, 5), (100, 8, 19),
        ]
        for stage in stages {
            let composition = Combat.stageComposition(for: stage.level)
            XCTAssertEqual(composition.zombies, stage.zombies, "Level \(stage.level)")
            XCTAssertEqual(composition.demonKings, stage.kings, "Level \(stage.level)")
        }
    }

    func testKingsArriveFourSecondsApartAndExtraKingsWaitForAnActiveSlot() throws {
        let (scene, combat) = makeEncounter(cameraHeight: 6, state: stageState(level: 25))
        XCTAssertEqual(Combat.maxActiveDemonKings, 3)
        XCTAssertEqual(Combat.maxActiveZombies, 8)
        XCTAssertEqual(Combat.demonKingSpawnInterval, 4)
        XCTAssertEqual(combat.remainingDemonKings, 1)
        XCTAssertEqual(combat.pendingDemonKingSpawns, 3)
        var time = advance(combat, from: 0, seconds: 3.9)
        XCTAssertEqual(combat.remainingDemonKings, 1)
        time = advance(combat, from: time, seconds: 0.2)
        XCTAssertEqual(combat.remainingDemonKings, 2)
        time = advance(combat, from: time, seconds: 3.8)
        XCTAssertEqual(combat.remainingDemonKings, 2)
        time = advance(combat, from: time, seconds: 0.2)
        XCTAssertEqual(combat.remainingDemonKings, 3)
        time = advance(combat, from: time, seconds: 20)
        XCTAssertEqual(combat.remainingDemonKings, 3)
        XCTAssertEqual(combat.pendingDemonKingSpawns, 1)
        XCTAssertEqual(combat.remainingZombies, 8)
        XCTAssertEqual(combat.pendingZombieSpawns, 0)
        let kings = combatants(in: scene).filter { $0.kind == .demonBoss }
        XCTAssertEqual(Set(kings.map(\.identityID)).count, 3)
        XCTAssertEqual(Set(kings.map(\.name)).count, 3)
        XCTAssertTrue(kings.allSatisfy { $0.health == 30 && !$0.isDefeated })
        let defeated = try XCTUnwrap(kings.first)
        time = defeatBoss(defeated, in: scene, combat: combat, from: time)
        time = advance(combat, from: time, seconds: 4.1)
        XCTAssertEqual(combat.remainingDemonKings, 3)
        XCTAssertEqual(combat.pendingDemonKingSpawns, 0)
        XCTAssertEqual(combat.runSnapshot.score, 1_000)
        XCTAssertEqual(combat.runSnapshot.kills, 0)
        XCTAssertFalse(combat.runSnapshot.isGameOver)
    }

    func testMixedStageDoesNotClearUntilBothTheBossAndQueuedZombiesAreDefeated() throws {
        let state = stageState(level: 11)
        for _ in 0..<20 { state.recordKill() }
        let (scene, combat) = makeEncounter(cameraHeight: 6, state: state)
        var events: [Combat.Event] = []
        combat.onEvent = { events.append($0) }
        XCTAssertTrue(combat.nyan())
        let boss = try XCTUnwrap(combatants(in: scene).first { $0.kind == .demonBoss })
        var time = defeatBoss(boss, in: scene, combat: combat, from: 0)
        XCTAssertEqual(combat.runSnapshot.score, 3_000)
        XCTAssertEqual(combat.runSnapshot.kills, 20)
        XCTAssertEqual(combat.runSnapshot.nyanKillsSinceCast, 0)
        XCTAssertTrue(combat.runSnapshot.demonUnlocked)
        XCTAssertFalse(events.contains(.waveCleared(11)))
        XCTAssertFalse(combat.runSnapshot.isGameOver)
        time = advance(combat, from: time, seconds: SurvivalState.nyanDuration - time + 0.1)
        XCTAssertEqual(combat.remaining, 0)
        XCTAssertEqual(combat.pendingZombieSpawns, 1)
        XCTAssertEqual(combat.runSnapshot.score, 3_100)
        XCTAssertFalse(events.contains(.waveCleared(11)), "The queued zombie must prevent an early clear")
        time = advance(combat, from: time, seconds: Combat.spawnInterval(for: 11) + 0.1)
        let zombie = try XCTUnwrap(combatants(in: scene).first { $0.kind == .zombie && !$0.isDefeated })
        for _ in 0..<2 {
            positionForArrow(zombie, in: scene)
            XCTAssertTrue(combat.shoot(toward: center(zombie)))
            time = advance(combat, from: time, seconds: 0.6)
        }
        XCTAssertEqual(combat.remaining, 0)
        XCTAssertEqual(combat.pendingSpawns, 0)
        XCTAssertEqual(combat.runSnapshot.score, 3_450)
        XCTAssertEqual(combat.kills, 22)
        XCTAssertEqual(combat.runSnapshot.nyanKillsSinceCast, 2)
        XCTAssertEqual(events.filter { $0 == .waveCleared(11) }.count, 1)
        XCTAssertEqual(events.filter { $0 == .demonUnlocked }.count, 1)
        _ = advance(combat, from: time, seconds: 1)
        XCTAssertEqual(combat.runSnapshot.score, 3_450)
        XCTAssertEqual(combat.wave, 11)
    }

    func testNyanTransformsOnlyZombiesWhileKingsKeepAttackingAndArriving() throws {
        let state = stageState(level: 20)
        for _ in 0..<20 { state.recordKill() }
        let (scene, combat) = makeEncounter(state: state)
        var time = advance(combat, from: 0, seconds: 4.1)
        let kings = combatants(in: scene).filter { $0.kind == .demonBoss }
        let zombies = combatants(in: scene).filter { $0.kind == .zombie }
        XCTAssertEqual(kings.count, 2)
        XCTAssertFalse(zombies.isEmpty)
        XCTAssertEqual(combat.pendingDemonKingSpawns, 1)
        let queuedZombies = combat.pendingZombieSpawns
        let attacks = kings.map(\.bossAttackCount).reduce(0, +)
        XCTAssertTrue(combat.nyan())
        XCTAssertTrue(zombies.allSatisfy(\.isTransfigured))
        XCTAssertTrue(kings.allSatisfy { !$0.isTransfigured && $0.health == 30 })
        time = advance(combat, from: time, seconds: 10)
        XCTAssertEqual(combat.pendingDemonKingSpawns, 0)
        XCTAssertEqual(combat.pendingZombieSpawns, queuedZombies)
        XCTAssertEqual(combat.remainingDemonKings, 3)
        XCTAssertTrue(combatants(in: scene).filter { $0.kind == .demonBoss }.allSatisfy { !$0.isTransfigured })
        XCTAssertGreaterThan(kings.map(\.bossAttackCount).reduce(0, +), attacks)
        XCTAssertLessThan(combat.runSnapshot.health, Double(combat.runSnapshot.maxHealth))
        XCTAssertTrue(kings.allSatisfy { !$0.isTransfigured && !$0.isDefeated })
        XCTAssertFalse(combat.runSnapshot.isGameOver)
        _ = advance(combat, from: time, seconds: SurvivalState.nyanDuration - 10 + 0.1)
        XCTAssertTrue(zombies.allSatisfy(\.isDefeated))
        XCTAssertTrue(kings.allSatisfy { !$0.isTransfigured && !$0.isDefeated })
        XCTAssertEqual(combat.pendingDemonKingSpawns, 0)
        XCTAssertEqual(combat.pendingZombieSpawns, queuedZombies)
        XCTAssertEqual(combat.wave, 20)
        XCTAssertFalse(combat.runSnapshot.hasWon)
    }

    func testOneKingDeathPreservesOtherKingSlowAllyProjectilesAndActiveCombat() throws {
        let (scene, combat) = makeEncounter(cameraHeight: 6, state: stageState(level: 15))
        let first = try XCTUnwrap(combatants(in: scene).first { $0.kind == .demonBoss })
        var time = 0.0
        for _ in 0..<26 {
            positionForArrow(first, in: scene)
            XCTAssertTrue(combat.shoot(toward: center(first)))
            time = advance(combat, from: time, seconds: 0.6)
        }
        let second = try XCTUnwrap(combatants(in: scene).first { $0.kind == .demonBoss && $0 !== first })
        positionForArrow(first, in: scene)
        first.simdPosition = SIMD3(-0.5, 1.5, 2.5)
        second.simdPosition = SIMD3(0.5, 1.5, 2.5)
        XCTAssertTrue(combat.ice(toward: center(first)))
        XCTAssertEqual(first.health, 2)
        XCTAssertEqual(second.health, 28)
        XCTAssertGreaterThan(second.slowRemaining, 0)
        let ally = SCNNode()
        ally.simdPosition = SIMD3(2, 10, 4.8)
        XCTAssertEqual(combat.summon(kind: .alan) { ally }, .summoned)
        time = advance(combat, from: time, seconds: 0.3)
        XCTAssertTrue(combat.shoot(toward: SIMD3(0, 6, -5)))
        time = advance(combat, from: time, seconds: 0.52)
        let projectile = try XCTUnwrap(scene.rootNode.childNode(withName: "Flying arrow", recursively: true))
        second.simdPosition = SIMD3(-2, 1.5, -4)
        first.simdPosition = SIMD3(-0.5, 1.5, 2.5)
        XCTAssertTrue(combat.ice(toward: center(first)))
        XCTAssertTrue(first.isDefeated)
        XCTAssertFalse(second.isDefeated)
        XCTAssertEqual(second.health, 28)
        XCTAssertGreaterThan(second.slowRemaining, 0)
        XCTAssertNotNil(ally.parent)
        XCTAssertNotNil(projectile.parent)
        XCTAssertEqual(combat.remainingDemonKings, 1)
        XCTAssertEqual(combat.runSnapshot.score, 1_000)
        XCTAssertFalse(combat.runSnapshot.isGameOver)
        XCTAssertFalse(try XCTUnwrap(scene.rootNode.childNode(withName: "Undead horde", recursively: false)).isPaused)
        XCTAssertFalse(combat.cast(toward: center(second)), "The ice cooldown still applies after a king dies")
        _ = advance(combat, from: time, seconds: 0.3)
        XCTAssertTrue(combat.shoot(toward: center(second)))
    }

    func testFlyingBossTelegraphsItsAttacksAndDealsTheDeclaredDamage() throws {
        let (scene, combat) = makeEncounter(state: finalBossState())
        let boss = try XCTUnwrap(combatants(in: scene).first)
        boss.simdPosition = SIMD3(0, 1.5, 3.4)
        let start = boss.simdPosition
        var previous = combat.runSnapshot.health
        var damage: [Double] = []
        var telegraphs: [Combat.BossAttackStyle] = []
        combat.onEvent = { if case .bossPreparing(let style) = $0 { telegraphs.append(style) } }
        combat.onChange = {
            let next = combat.runSnapshot.health
            if next < previous { damage.append(previous - next) }
            previous = next
        }
        let time = advance(combat, from: 0, seconds: 1)
        XCTAssertNotEqual(boss.simdPosition, start)
        XCTAssertLessThan(simd_distance(boss.simdPosition, start), 1)
        XCTAssertEqual(combat.runSnapshot.health, 200, "The initial flight must give time to aim")
        _ = advance(combat, from: time, seconds: 25)
        XCTAssertTrue(telegraphs.contains(.clawCombo))
        XCTAssertTrue(telegraphs.contains(.slam))
        XCTAssertTrue(telegraphs.contains(.breath))
        XCTAssertTrue(damage.contains(4), "Claw contacts deal four damage")
        XCTAssertTrue(damage.contains(8), "Slam contact deals eight damage")
        XCTAssertTrue(damage.contains(6), "Breath contact deals six damage")
        XCTAssertTrue(damage.allSatisfy { [4.0, 6.0, 8.0].contains($0) })
    }

    func testBossTakesNormalElementalDamageAndPauseFreezesItsAttacks() throws {
        let (scene, combat) = makeEncounter(state: finalBossState())
        let boss = try XCTUnwrap(combatants(in: scene).first)
        boss.simdPosition = SIMD3(0, 1.5, 2)
        XCTAssertTrue(combat.cast(toward: center(boss)))
        var time = advance(combat, from: 0, seconds: 0.5)
        XCTAssertEqual(boss.health, 28)
        boss.simdPosition = SIMD3(0, 1.5, 2)
        XCTAssertTrue(combat.ice(toward: center(boss)))
        XCTAssertEqual(boss.health, 26)
        time = advance(combat, from: time, seconds: 0.3)
        XCTAssertTrue(combat.fireball(toward: center(boss)))
        time = advance(combat, from: time, seconds: 0.7)
        XCTAssertEqual(boss.health, 21)
        combat.setPaused(true)
        let position = boss.simdPosition
        let paused = combat.runSnapshot
        time = advance(combat, from: time, seconds: 30)
        XCTAssertEqual(combat.runSnapshot, paused)
        XCTAssertEqual(boss.simdPosition, position)
        XCTAssertFalse(combat.shoot(toward: center(boss)))
        XCTAssertEqual(combat.lastRejection, .paused)
        combat.setPaused(false)
        for _ in 0..<600 {
            boss.simdPosition = SIMD3(0, 1.5, 3.85)
            time = advance(combat, from: time, seconds: 1.0 / 60)
        }
        XCTAssertLessThan(combat.runSnapshot.health, paused.health)
        XCTAssertFalse(combat.runSnapshot.hasWon)
        XCTAssertFalse(combat.runSnapshot.demonUnlocked)
    }

    private func stageState(level: Int) -> SurvivalState {
        let state = SurvivalState(defaults: nil)
        for _ in 1..<level { state.nextWave() }
        return state
    }

    private func finalBossState() -> SurvivalState { stageState(level: 10) }

    private func positionForArrow(_ target: Combat.CombatantNode, in scene: SCNScene) {
        for enemy in combatants(in: scene) where enemy !== target && !enemy.isDefeated {
            enemy.simdPosition = SIMD3(-2, enemy.kind == .demonBoss ? 1.5 : 0, -4)
        }
        target.simdPosition = SIMD3(0, target.kind == .demonBoss ? 1.5 : 0, 1.5)
    }

    @discardableResult
    private func defeatBoss(
        _ boss: Combat.CombatantNode, in scene: SCNScene, combat: Combat, from start: Double
    ) -> Double {
        var time = start
        for _ in 0..<30 {
            positionForArrow(boss, in: scene)
            XCTAssertTrue(combat.shoot(toward: center(boss)))
            time = advance(combat, from: time, seconds: 0.6)
        }
        XCTAssertTrue(boss.isDefeated)
        return time
    }

    private func unlockedDemonState() -> SurvivalState {
        let state = finalBossState()
        state.recordBossDefeat()
        state.restart()
        return state
    }

    private func center(_ node: SCNNode) -> SIMD3<Float> {
        node.simdPosition + SIMD3(0, 1.05 * node.simdScale.y, 0)
    }

    private func combatants(in scene: SCNScene) -> [Combat.CombatantNode] {
        scene.rootNode.childNode(withName: "Undead horde", recursively: false)?.childNodes.compactMap {
            $0 as? Combat.CombatantNode
        } ?? []
    }

    private func makeEncounter(
        startsImmediately: Bool = true, defaults: UserDefaults? = nil, cameraHeight: Float = 1.65,
        state: SurvivalState? = nil
    ) -> (SCNScene, Combat) {
        let scene = SCNScene()
        let camera = SCNNode()
        camera.name = "Test camera"
        camera.simdPosition = SIMD3(0, cameraHeight, 4.8)
        scene.rootNode.addChildNode(camera)
        let combat = Combat(
            scene: scene, camera: camera, floorY: 0, defaults: defaults, startsImmediately: startsImmediately,
            state: state)
        combat.update(at: 0)
        return (scene, combat)
    }

    private func chargedNyanState(defaults: UserDefaults? = nil) -> SurvivalState {
        let state = SurvivalState(defaults: defaults)
        for _ in 0..<20 { state.recordKill() }
        return state
    }

    @discardableResult
    private func advance(_ combat: Combat, from start: Double, seconds: Double) -> Double {
        var time = start
        for _ in 0..<Int(ceil(seconds * 60)) {
            time += 1.0 / 60
            combat.update(at: time)
        }
        return time
    }
}

final class SurvivalStateTests: XCTestCase {
    func testBossDefeatsAwardOneThousandEachWithoutZombieChargeOrEndingTheRun() throws {
        let state = SurvivalState(defaults: nil)
        for _ in 1..<10 { state.nextWave() }
        for _ in 0..<20 { state.recordKill() }
        XCTAssertTrue(state.activateNyan(manaCost: 0))
        state.recordBossDefeat()
        XCTAssertTrue(state.snapshot.demonUnlocked)
        XCTAssertFalse(state.snapshot.hasWon)
        XCTAssertFalse(state.snapshot.isGameOver)
        XCTAssertEqual(state.snapshot.score, 3_000)
        XCTAssertEqual(state.snapshot.kills, 20)
        XCTAssertEqual(state.snapshot.nyanKillsSinceCast, 0)
        XCTAssertEqual(state.snapshot.nyanRemaining, SurvivalState.nyanDuration)
        state.recordBossDefeat()
        XCTAssertEqual(state.snapshot.score, 4_000)
        XCTAssertEqual(state.snapshot.kills, 20)
        XCTAssertEqual(state.snapshot.nyanKillsSinceCast, 0)
        state.clearWave()
        XCTAssertEqual(state.snapshot.score, 4_250)
        XCTAssertEqual(state.snapshot.bestScore, 4_250)
        XCTAssertEqual(state.snapshot.bestWave, 10)
        state.nextWave()
        XCTAssertEqual(state.snapshot.wave, 11)
        XCTAssertEqual(state.snapshot.maxHealth, 210)
        XCTAssertEqual(state.snapshot.health, 210)
        XCTAssertEqual(state.snapshot.maxMana, 210)
        XCTAssertEqual(state.snapshot.mana, 210)
        XCTAssertFalse(state.snapshot.hasWon)
        XCTAssertFalse(state.snapshot.isGameOver)
        XCTAssertEqual(
            try JSONDecoder().decode(RunSnapshot.self, from: JSONEncoder().encode(state.snapshot)), state.snapshot)
    }

    func testDemonUnlockPersistsAcrossRestartScoreResetAndNewState() throws {
        let suite = "XArcana.BossTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = SurvivalState(defaults: defaults)
        XCTAssertFalse(state.snapshot.demonUnlocked)
        XCTAssertFalse(state.snapshot.hasWon)
        for _ in 1..<10 { state.nextWave() }
        state.recordBossDefeat()
        XCTAssertTrue(defaults.bool(forKey: "XArcana.demonUnlocked"))
        state.restart(hasStarted: false)
        XCTAssertTrue(state.snapshot.demonUnlocked)
        XCTAssertFalse(state.snapshot.hasWon)
        XCTAssertFalse(state.snapshot.isGameOver)
        XCTAssertFalse(state.snapshot.hasStarted)
        XCTAssertEqual(state.snapshot.wave, 1)
        XCTAssertEqual(state.snapshot.health, 100)
        XCTAssertEqual(state.snapshot.mana, 100)
        XCTAssertEqual(state.snapshot.score, 0)
        state.clearRecords()
        XCTAssertEqual(state.snapshot.bestScore, 0)
        XCTAssertEqual(state.snapshot.bestWave, 0)
        XCTAssertTrue(state.snapshot.demonUnlocked)
        XCTAssertTrue(defaults.bool(forKey: "XArcana.demonUnlocked"))
        let restored = SurvivalState(defaults: defaults)
        XCTAssertTrue(restored.snapshot.demonUnlocked)
        XCTAssertFalse(restored.snapshot.hasWon)
        XCTAssertEqual(restored.snapshot.bestScore, 0)
        XCTAssertEqual(restored.snapshot.bestWave, 0)
    }

    func testOrdinaryKillsStageClearsAndLossDoNotUnlockDemon() {
        let state = SurvivalState(defaults: nil)
        for _ in 1..<10 {
            for _ in 0..<8 { state.recordKill() }
            state.clearWave()
            state.nextWave()
        }
        XCTAssertEqual(state.snapshot.wave, 10)
        XCTAssertFalse(state.snapshot.demonUnlocked)
        state.damage(Double(state.snapshot.maxHealth))
        XCTAssertTrue(state.snapshot.isGameOver)
        XCTAssertFalse(state.snapshot.hasWon)
        XCTAssertFalse(state.snapshot.demonUnlocked)
        state.recordBossDefeat()
        XCTAssertFalse(state.snapshot.demonUnlocked)
        state.restart()
        XCTAssertFalse(state.snapshot.demonUnlocked)
    }

    func testNyanCounterCapsAtTwentyAndEveryCastRequiresTwentyNewKills() {
        let state = SurvivalState(defaults: nil)
        for _ in 0..<19 { state.recordKill() }
        XCTAssertFalse(state.activateNyan(manaCost: 0))
        XCTAssertEqual(state.snapshot.nyanKillsSinceCast, 19)
        for _ in 0..<10 { state.recordKill() }
        XCTAssertEqual(state.snapshot.nyanKillsSinceCast, 20)
        XCTAssertTrue(state.activateNyan(manaCost: 0))
        XCTAssertEqual(state.snapshot.nyanKillsSinceCast, 0)
        state.update(deltaTime: SurvivalState.nyanDuration)
        for _ in 0..<19 { state.recordKill() }
        XCTAssertFalse(state.activateNyan(manaCost: 0))
        state.recordKill()
        XCTAssertTrue(state.activateNyan(manaCost: 0))
        state.restart()
        XCTAssertEqual(state.snapshot.nyanKillsSinceCast, 0)
        XCTAssertFalse(state.activateNyan(manaCost: 0))
    }

    func testFractionalShieldOverflowAndPlayerHealthRoundTripWithoutRounding() throws {
        let state = SurvivalState(defaults: nil)
        XCTAssertTrue(state.activateShield())
        state.damage(19.5)
        XCTAssertEqual(state.snapshot.shieldHealth, 0.5)
        state.damage(1.5)
        XCTAssertEqual(state.snapshot.shieldHealth, 0)
        XCTAssertEqual(state.snapshot.health, 99)
        state.damage(1.5)
        XCTAssertEqual(state.snapshot.health, 97.5)
        let decoded = try JSONDecoder().decode(RunSnapshot.self, from: JSONEncoder().encode(state.snapshot))
        XCTAssertEqual(decoded, state.snapshot)
    }

    func testManaDelayRegenerationAndFreeActions() {
        let state = SurvivalState(defaults: nil)
        XCTAssertTrue(state.spend(15))
        XCTAssertEqual(state.snapshot.mana, 85)
        state.update(deltaTime: 1.9)
        XCTAssertEqual(state.snapshot.mana, 85)
        XCTAssertTrue(state.spend(0))
        state.update(deltaTime: 0.2)
        XCTAssertEqual(state.snapshot.mana, 85.4, accuracy: 0.0001)
        XCTAssertFalse(state.spend(100))
        state.update(deltaTime: 1)
        XCTAssertEqual(state.snapshot.mana, 89.4, accuracy: 0.0001)
        state.update(deltaTime: 10)
        XCTAssertEqual(state.snapshot.mana, 100)
    }

    func testEachPaidCastRestartsRegenerationDelay() {
        let state = SurvivalState(defaults: nil)
        XCTAssertTrue(state.spend(15))
        state.update(deltaTime: 1.5)
        XCTAssertTrue(state.spend(5))
        XCTAssertEqual(state.snapshot.mana, 80)
        state.update(deltaTime: 2)
        XCTAssertEqual(state.snapshot.mana, 80)
        state.update(deltaTime: 0.5)
        XCTAssertEqual(state.snapshot.mana, 82)
    }

    func testInvalidTimeCannotAdvanceManaOrItsRegenerationDelay() {
        let state = SurvivalState(defaults: nil)
        XCTAssertTrue(state.spend(20))
        let spent = state.snapshot
        for deltaTime: TimeInterval in [0, -1, .nan, .infinity, -.infinity] {
            state.update(deltaTime: deltaTime)
            XCTAssertEqual(state.snapshot, spent)
        }
        state.update(deltaTime: 2)
        XCTAssertEqual(state.snapshot.mana, 80)
        state.update(deltaTime: 0.5)
        XCTAssertEqual(state.snapshot.mana, 82)
    }

    func testKillsAndStageClearDoNotAdvanceLevelOrRefillResourcesBeforeNextStage() {
        let state = SurvivalState(defaults: nil)
        state.damage(60)
        XCTAssertTrue(state.spend(90))
        for _ in 0..<8 { state.recordKill() }
        XCTAssertEqual(state.snapshot.kills, 8)
        XCTAssertEqual(state.snapshot.score, 800)
        XCTAssertEqual(state.snapshot.level, 1)
        XCTAssertEqual(state.snapshot.wave, 1)
        XCTAssertEqual(state.snapshot.xp, 0)
        XCTAssertEqual(state.snapshot.xpToNextLevel, 0)
        XCTAssertEqual(state.snapshot.health, 40)
        XCTAssertEqual(state.snapshot.mana, 10)
        state.clearWave()
        XCTAssertEqual(state.snapshot.score, 1_050)
        XCTAssertEqual(state.snapshot.bestWave, 1)
        XCTAssertEqual(state.snapshot.level, 1)
        XCTAssertEqual(state.snapshot.health, 40)
        XCTAssertEqual(state.snapshot.mana, 10)
        state.nextWave()
        XCTAssertEqual(state.snapshot.level, 2)
        XCTAssertEqual(state.snapshot.wave, 2)
        XCTAssertEqual(state.snapshot.maxHealth, 110)
        XCTAssertEqual(state.snapshot.health, 110)
        XCTAssertEqual(state.snapshot.maxMana, 110)
        XCTAssertEqual(state.snapshot.mana, 110)
        XCTAssertEqual(state.snapshot.score, 1_050)
        state.damage(70)
        XCTAssertTrue(state.spend(100))
        for _ in 0..<8 { state.recordKill() }
        state.clearWave()
        XCTAssertEqual(state.snapshot.bestWave, 2)
        XCTAssertEqual(state.snapshot.level, 2)
        XCTAssertEqual(state.snapshot.health, 40)
        XCTAssertEqual(state.snapshot.mana, 10)
        state.nextWave()
        XCTAssertEqual(state.snapshot.level, 3)
        XCTAssertEqual(state.snapshot.wave, 3)
        XCTAssertEqual(state.snapshot.health, 120)
        XCTAssertEqual(state.snapshot.mana, 120)
        XCTAssertEqual(state.snapshot.xp, 0)
        XCTAssertEqual(state.snapshot.xpToNextLevel, 0)
        XCTAssertEqual(state.snapshot.score, 2_100)
    }

    func testNextStageRestoresResourcesWithoutChangingRemainingShieldHealthOrCooldown() {
        let state = SurvivalState(defaults: nil)
        state.damage(60)
        XCTAssertTrue(state.activateShield())
        state.damage(7)
        XCTAssertEqual(state.snapshot.health, 40)
        XCTAssertEqual(state.snapshot.shieldHealth, 13)
        let cooldown = state.snapshot.shieldCooldownRemaining
        state.nextWave()
        XCTAssertEqual(state.snapshot.level, 2)
        XCTAssertEqual(state.snapshot.wave, 2)
        XCTAssertEqual(state.snapshot.health, 110)
        XCTAssertEqual(state.snapshot.mana, 110)
        XCTAssertEqual(state.snapshot.shieldHealth, 13)
        XCTAssertEqual(state.snapshot.shieldCooldownRemaining, cooldown)
    }

    func testStagesCannotAdvanceDuringSetupCountdownOrGameOver() {
        let state = SurvivalState(defaults: nil, hasStarted: false)
        let waiting = state.snapshot
        state.nextWave()
        XCTAssertEqual(state.snapshot, waiting)
        XCTAssertTrue(state.beginCountdown())
        let countdown = state.snapshot
        state.nextWave()
        XCTAssertEqual(state.snapshot, countdown)
        state.advanceCountdown(deltaTime: 3)
        state.damage(100)
        let ended = state.snapshot
        state.nextWave()
        XCTAssertEqual(state.snapshot, ended)
    }

    func testOlderSnapshotDecodesWithoutShieldFields() throws {
        let snapshot = try JSONDecoder().decode(RunSnapshot.self, from: Data(#"{"health":75,"mana":80}"#.utf8))
        XCTAssertEqual(snapshot.health, 75)
        XCTAssertEqual(snapshot.mana, 80)
        XCTAssertNil(snapshot.shieldHealth)
        XCTAssertEqual(snapshot.shieldRemaining, 0)
        XCTAssertEqual(snapshot.shieldCooldownRemaining, 0)
        XCTAssertTrue(snapshot.hasStarted)
        XCTAssertEqual(snapshot.countdownRemaining, 0)
        XCTAssertEqual(snapshot.nyanRemaining, 0)
        XCTAssertEqual(snapshot.nyanKillsSinceCast, 0)
        XCTAssertFalse(snapshot.demonUnlocked)
        XCTAssertFalse(snapshot.hasWon)
        XCTAssertEqual(try JSONDecoder().decode(RunSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }

    func testShieldAbsorbsTwentyDamageAndCarriesOverflowToHealth() {
        let state = SurvivalState(defaults: nil)
        XCTAssertTrue(state.activateShield())
        state.damage(1)
        XCTAssertEqual(state.snapshot.shieldHealth, 19)
        XCTAssertEqual(state.snapshot.health, 100)
        state.damage(22)
        XCTAssertEqual(state.snapshot.shieldHealth, 0)
        XCTAssertEqual(state.snapshot.health, 97)
        state.damage(1)
        XCTAssertEqual(state.snapshot.health, 96)
    }

    func testShieldHasNoExpiryRejectsActiveDuplicateAndRecastsAfterDepletion() {
        let state = SurvivalState(defaults: nil)
        XCTAssertTrue(state.activateShield())
        state.update(deltaTime: 100)
        XCTAssertEqual(state.snapshot.shieldHealth, 20)
        XCTAssertEqual(state.snapshot.shieldCooldownRemaining, 0)
        let active = state.snapshot
        XCTAssertFalse(state.activateShield())
        XCTAssertEqual(state.snapshot, active)
        state.damage(20)
        XCTAssertEqual(state.snapshot.health, 100)
        XCTAssertEqual(state.snapshot.shieldHealth, 0)
        XCTAssertTrue(state.activateShield())
        XCTAssertEqual(state.snapshot.mana, 80)
        XCTAssertEqual(state.snapshot.shieldHealth, 20)
        state.damage(20)
        let depleted = state.snapshot
        XCTAssertFalse(state.activateShield())
        XCTAssertEqual(state.snapshot, depleted)
        state.update(deltaTime: 10)
        XCTAssertTrue(state.activateShield())
    }

    func testShieldHealthRoundTripsAndLegacyTimerRemainsReadable() throws {
        var snapshot = RunSnapshot()
        snapshot.shieldHealth = 17
        XCTAssertEqual(try JSONDecoder().decode(RunSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        let legacy = try JSONDecoder().decode(RunSnapshot.self, from: Data(#"{"shieldRemaining":4}"#.utf8))
        XCTAssertNil(legacy.shieldHealth)
        XCTAssertEqual(legacy.shieldRemaining, 4)
        XCTAssertEqual(try JSONDecoder().decode(RunSnapshot.self, from: JSONEncoder().encode(legacy)), legacy)
    }

    func testShieldCooldownStopsAtGameOverAndRestartClearsIt() {
        let state = SurvivalState(defaults: nil)
        XCTAssertTrue(state.activateShield())
        state.damage(120)
        let ended = state.snapshot
        state.update(deltaTime: 20)
        XCTAssertEqual(state.snapshot, ended)
        XCTAssertFalse(state.activateShield())
        state.restart()
        XCTAssertEqual(state.snapshot.shieldHealth, 0)
        XCTAssertEqual(state.snapshot.shieldRemaining, 0)
        XCTAssertEqual(state.snapshot.shieldCooldownRemaining, 0)
    }

    func testNyanEndsOnDeathAndRestartAndCannotStartBeforeCountdown() {
        let waiting = SurvivalState(defaults: nil, hasStarted: false)
        XCTAssertFalse(waiting.activateNyan())
        XCTAssertTrue(waiting.beginCountdown())
        XCTAssertFalse(waiting.activateNyan())
        waiting.advanceCountdown(deltaTime: 3)
        for _ in 0..<20 { waiting.recordKill() }
        XCTAssertTrue(waiting.activateNyan())
        XCTAssertEqual(waiting.snapshot.mana, 20)
        waiting.damage(100)
        XCTAssertEqual(waiting.snapshot.nyanRemaining, 0)
        XCTAssertFalse(waiting.activateNyan())
        waiting.restart(hasStarted: false)
        XCTAssertFalse(waiting.snapshot.hasStarted)
        XCTAssertEqual(waiting.snapshot.nyanRemaining, 0)
    }

    func testRecordsPersistAndRestartKeepsOnlyRecords() throws {
        let suite = "XArcana.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = SurvivalState(defaults: defaults)
        state.recordKill()
        state.clearWave()
        state.nextWave()
        XCTAssertEqual(state.snapshot.score, 350)
        XCTAssertEqual(state.snapshot.bestWave, 1)
        state.damage(Double(state.snapshot.maxHealth))
        let ended = state.snapshot
        state.update(deltaTime: 100)
        state.recordKill()
        state.clearWave()
        XCTAssertFalse(state.spend(0))
        XCTAssertEqual(state.snapshot, ended)
        state.restart()
        XCTAssertEqual(state.snapshot.health, 100)
        XCTAssertEqual(state.snapshot.mana, 100)
        XCTAssertEqual(state.snapshot.level, 1)
        XCTAssertEqual(state.snapshot.wave, 1)
        XCTAssertEqual(state.snapshot.score, 0)
        XCTAssertEqual(state.snapshot.bestScore, 350)
        XCTAssertEqual(state.snapshot.bestWave, 1)
        let restored = SurvivalState(defaults: defaults)
        XCTAssertEqual(restored.snapshot.bestScore, 350)
        XCTAssertEqual(restored.snapshot.bestWave, 1)
    }
}

@MainActor
final class StageHUDTests: XCTestCase {
    func testHUDShowsCurrentStageAndKillsWithoutExperienceProgress() throws {
        var run = RunSnapshot()
        run.wave = 7
        run.level = 9
        run.xp = 30
        run.xpToNextLevel = 200
        run.kills = 12
        run.score = 1_450
        run.bestWave = 6
        let hud = RunHUD()
        hud.show(run)
        let labels = hud.subviews.compactMap { $0 as? UILabel }
        let level = try XCTUnwrap(labels.first { $0.accessibilityIdentifier == "playerLevel" })
        let score = try XCTUnwrap(labels.first { $0.accessibilityIdentifier == "playerScore" })
        XCTAssertEqual(level.text, "Level 7  ·  Best cleared 6")
        XCTAssertEqual(level.accessibilityLabel, "Level 7, best cleared level 6")
        XCTAssertEqual(score.text, "1450 pts · 12 defeated · Nyan 0/20")
        XCTAssertFalse(labels.contains { $0.text?.contains("XP") == true })
        XCTAssertEqual(hud.subviews.compactMap { $0 as? UIProgressView }.count, 2)
    }

    func testBossVictoryShowsVictoryAndPermanentStarUnlock() throws {
        var run = RunSnapshot()
        run.isGameOver = true
        run.hasWon = true
        run.demonUnlocked = true
        run.wave = 10
        run.bestWave = 10
        let view = RunOverView(frame: CGRect(x: 0, y: 0, width: 600, height: 500))
        view.show(run)
        let stack = try XCTUnwrap(view.subviews.first as? UIStackView)
        let labels = stack.arrangedSubviews.compactMap { $0 as? UILabel }
        XCTAssertFalse(view.isHidden)
        XCTAssertTrue(labels.contains { $0.attributedText?.string == "VICTORY" })
        let results = try XCTUnwrap(labels.first { $0.accessibilityIdentifier == "runResults" })
        XCTAssertTrue(results.text?.contains("Demon defeated") == true)
        XCTAssertTrue(results.text?.contains("Star summon unlocked") == true)
        XCTAssertTrue(results.text?.contains("Best cleared level 10") == true)
        run.hasWon = false
        view.show(run)
        XCTAssertTrue(labels.contains { $0.attributedText?.string == "YOU DIED" })
        XCTAssertFalse(results.text?.contains("Star summon unlocked") == true)
    }

    func testGameOverShowsStageAndBestClearedLevel() throws {
        var run = RunSnapshot()
        run.isGameOver = true
        run.wave = 3
        run.level = 8
        run.bestWave = 2
        let view = RunOverView(frame: CGRect(x: 0, y: 0, width: 600, height: 500))
        view.show(run)
        let stack = try XCTUnwrap(view.subviews.first as? UIStackView)
        let results = try XCTUnwrap(
            stack.arrangedSubviews.compactMap { $0 as? UILabel }.first { $0.accessibilityIdentifier == "runResults" })
        XCTAssertTrue(results.text?.contains("Level 3") == true)
        XCTAssertTrue(results.text?.contains("Best cleared level 2") == true)
        XCTAssertFalse(results.text?.contains("Wave") == true)
    }
}
