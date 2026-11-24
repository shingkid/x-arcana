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

    func testThreeArrowsDefeatAFullHealthZombieWithoutFractionalRemainder() throws {
        let (scene, combat) = makeEncounter()
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        enemy.simdPosition = SIMD3(0, 0, 1.5)
        let maximum = enemy.health
        var time = 0.0
        for hit in 1...3 {
            XCTAssertTrue(combat.shoot(toward: center(enemy)))
            XCTAssertFalse(combat.shoot(toward: center(enemy)))
            time = advance(combat, from: time, seconds: 0.6)
            if hit < 3 {
                XCTAssertEqual(enemy.health, maximum * Double(3 - hit) / 3, accuracy: 1e-12)
                XCTAssertFalse(enemy.isDefeated)
                XCTAssertEqual(combat.kills, 0)
            } else {
                XCTAssertEqual(enemy.health, 0)
                XCTAssertTrue(enemy.isDefeated)
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
        let state = SurvivalState(defaults: nil)
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
        for _ in 0..<3 {
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

    func testWandMeleeDealsOneDamageToNearestTargetAndTwoSwingsDefeatIt() throws {
        let (scene, combat) = makeEncounter(cameraHeight: 6)
        var time = advance(combat, from: 0, seconds: Combat.spawnInterval + 0.1)
        scene.rootNode.childNode(withName: "Test camera", recursively: false)?.position.y = 1.65
        let enemies = combatants(in: scene)
        enemies[0].simdPosition = SIMD3(0, 0, 3.5)
        enemies[1].simdPosition = SIMD3(0.8, 0, 3.4)
        let mana = combat.runSnapshot.mana
        XCTAssertTrue(combat.melee(toward: center(enemies[0])))
        XCTAssertEqual(enemies.map(\.health), [1, 2])
        XCTAssertEqual(combat.runSnapshot.mana, mana)
        XCTAssertFalse(combat.melee(toward: center(enemies[0])))
        XCTAssertEqual(combat.lastRejection, .cooldown)
        time = advance(combat, from: time, seconds: 0.6)
        XCTAssertTrue(combat.melee(toward: center(enemies[0])))
        XCTAssertEqual(enemies.map(\.health), [0, 2])
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
            let (_, combat) = makeEncounter(state: chargedNyanState())
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

    func testBowCannotFireBeforeItsFourTenthsReloadCompletes() {
        let (_, combat) = makeEncounter(cameraHeight: 6)
        let target = SIMD3<Float>(0, 8, -5)
        XCTAssertTrue(combat.shoot(toward: target))
        var time = advance(combat, from: 0, seconds: 0.3)
        XCTAssertFalse(combat.shoot(toward: target))
        XCTAssertEqual(combat.lastRejection, .cooldown)
        time = advance(combat, from: time, seconds: 0.083)
        XCTAssertFalse(combat.shoot(toward: target))
        _ = advance(combat, from: time, seconds: 0.034)
        XCTAssertTrue(combat.shoot(toward: target))
        XCTAssertEqual(combat.runSnapshot.mana, 100)
    }

    func testDemonDrainsTwentyManaPerSecondWithoutRegenerationThenExpires() {
        let (_, combat) = makeEncounter(cameraHeight: 6)
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
        let state = SurvivalState(defaults: nil)
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
        let state = SurvivalState(defaults: nil)
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
