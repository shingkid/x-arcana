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
        XCTAssertTrue(enemies.allSatisfy { $0.kind == .zombie && $0.health == 3 })
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

    func testZapIsSingleTargetAndThreeHitsDefeatOneZombie() throws {
        let (scene, combat) = makeEncounter()
        var time = advance(combat, from: 0, seconds: Combat.spawnInterval + 0.1)
        let enemies = combatants(in: scene)
        let target = enemies[0]
        target.simdPosition = SIMD3(0, 0, 1.5)
        enemies[1].simdPosition = SIMD3(0.9, 0, 1.5)
        for health in [2, 1, 0] {
            XCTAssertTrue(combat.cast(toward: center(target)))
            time = advance(combat, from: time, seconds: 0.7)
            XCTAssertEqual(target.health, health)
            XCTAssertEqual(enemies[1].health, 3)
        }
        XCTAssertEqual(combat.kills, 1)
        XCTAssertTrue(target.isDefeated)
        XCTAssertTrue(target.hasActions)
    }

    func testArrowTravelsThenDealsOneDamage() throws {
        let (scene, combat) = makeEncounter()
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        XCTAssertTrue(combat.shoot(toward: center(enemy)))
        XCTAssertEqual(enemy.health, 3)
        XCTAssertFalse(combat.shoot(toward: center(enemy)))
        _ = advance(combat, from: 0, seconds: 1)
        XCTAssertEqual(enemy.health, 2)
        XCTAssertEqual(combat.kills, 0)
        XCTAssertFalse(enemy.isDefeated)
    }

    func testFireballDamagesNearbyZombiesOnceAndLeavesDistantZombieUnhurt() throws {
        let (scene, combat) = makeEncounter()
        let time = advance(combat, from: 0, seconds: Combat.spawnInterval * 2 + 0.2)
        let enemies = combatants(in: scene)
        XCTAssertEqual(enemies.count, 3)
        enemies[0].simdPosition = SIMD3(0, 0, 1.5)
        enemies[1].simdPosition = SIMD3(0.8, 0, 1.3)
        enemies[2].simdPosition = SIMD3(-2, 0, -4)
        XCTAssertTrue(combat.fireball(toward: center(enemies[0])))
        _ = advance(combat, from: time, seconds: 0.8)
        XCTAssertEqual(enemies[0].health, 2)
        XCTAssertEqual(enemies[1].health, 2)
        XCTAssertEqual(enemies[2].health, 3)
        XCTAssertEqual(combat.kills, 0)
        XCTAssertNotNil(scene.rootNode.childNode(withName: "Fireball blast", recursively: true))
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
        XCTAssertEqual(enemy.health, 3)
        XCTAssertEqual(combat.kills, 0)
        XCTAssertNil(scene.rootNode.childNode(withName: "Flying arrow", recursively: true))
    }

    func testMagicMissDoesNotDamageEnemiesAndMeleeDamagesPlayer() {
        let (scene, combat) = makeEncounter()
        XCTAssertTrue(combat.cast(toward: SIMD3(0, 10, -2)))
        _ = advance(combat, from: 0, seconds: 20)
        XCTAssertEqual(combat.kills, 0)
        XCTAssertTrue(combatants(in: scene).allSatisfy { $0.health == 3 })
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
        XCTAssertTrue(combatants(in: scene).allSatisfy { $0.health == 3 && $0.meleeAttackCount == 0 })
        XCTAssertNil(scene.rootNode.childNode(withName: "Melee ward", recursively: true))
    }

    func testSwipeAndBiteApplyOneAndThreeDamageAtContact() throws {
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
        XCTAssertEqual(combat.runSnapshot.health, 96)
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
        let (_, combat) = makeEncounter()
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
        XCTAssertEqual(combat.runSnapshot.mana, 5)
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
        XCTAssertEqual(slowEnemy.health, 3)
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
        XCTAssertEqual(enemy.health, 3)
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
        XCTAssertEqual(enemies.map(\.health), [2, 2, 3, 3, 3])
        XCTAssertEqual(enemies[0].slowRemaining, 6)
        XCTAssertEqual(enemies[1].slowRemaining, 6)
        XCTAssertEqual(enemies[2].slowRemaining, 0)
        XCTAssertEqual(combat.runSnapshot.mana, 85)
        XCTAssertFalse(combat.ice(toward: center(enemies[0])))
        XCTAssertEqual(combat.lastRejection, .cooldown)
        XCTAssertEqual(combat.runSnapshot.mana, 85)
    }

    func testIceSlowExpiresAfterSixSecondsAndDoesNotShortenPatronus() throws {
        let (scene, combat) = makeEncounter()
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        enemy.simdPosition = SIMD3(0, 0, 1)
        XCTAssertTrue(combat.ice(toward: center(enemy)))
        var time = advance(combat, from: 0, seconds: 0.5)
        XCTAssertEqual(enemy.simdPosition.z, 1.12, accuracy: 0.002)
        XCTAssertEqual(enemy.slowRemaining, 5.5, accuracy: 0.001)
        time = advance(combat, from: time, seconds: 5.6)
        XCTAssertEqual(enemy.slowRemaining, 0)
        let patronus = SCNNode()
        patronus.simdPosition = enemy.simdPosition + SIMD3(0, 0, 0.2)
        XCTAssertEqual(combat.summon(kind: .patronus) { patronus }, .summoned)
        time = advance(combat, from: time, seconds: 0.1)
        let remaining = enemy.slowRemaining
        XCTAssertGreaterThan(remaining, 14.8)
        XCTAssertTrue(combat.ice(toward: center(enemy)))
        XCTAssertEqual(enemy.health, 1)
        XCTAssertEqual(enemy.slowRemaining, remaining, accuracy: 0.001)
    }

    func testShieldBlocksPlayerForFiveSecondsAndHasTenSecondCooldown() throws {
        let (scene, combat) = makeEncounter()
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        enemy.simdPosition = SIMD3(0, 0, 3.85)
        XCTAssertTrue(combat.shield())
        XCTAssertEqual(combat.runSnapshot.mana, 80)
        XCTAssertEqual(combat.runSnapshot.shieldRemaining, 5)
        XCTAssertEqual(combat.runSnapshot.shieldCooldownRemaining, 10)
        let dome = try XCTUnwrap(scene.rootNode.childNode(withName: "Player shield", recursively: true))
        let position = dome.simdWorldPosition
        var time = advance(combat, from: 0, seconds: 4.1)
        XCTAssertEqual(combat.runSnapshot.health, 100)
        XCTAssertEqual(combat.blockedAttacks, 2)
        XCTAssertEqual(dome.simdWorldPosition, position)
        let mana = combat.runSnapshot.mana
        XCTAssertFalse(combat.shield())
        XCTAssertEqual(combat.lastRejection, .cooldown)
        XCTAssertEqual(combat.runSnapshot.mana, mana)
        time = advance(combat, from: time, seconds: 2.9)
        XCTAssertEqual(combat.runSnapshot.health, 99)
        XCTAssertEqual(combat.runSnapshot.shieldRemaining, 0)
        XCTAssertEqual(combat.runSnapshot.shieldCooldownRemaining, 3, accuracy: 0.001)
        XCTAssertNil(dome.parent)
        time = advance(combat, from: time, seconds: 3.1)
        XCTAssertTrue(combat.shield())
        combat.restart()
        XCTAssertEqual(combat.runSnapshot.shieldRemaining, 0)
        XCTAssertEqual(combat.runSnapshot.shieldCooldownRemaining, 0)
        XCTAssertNil(scene.rootNode.childNode(withName: "Player shield", recursively: true))
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
        let (_, combat) = makeEncounter()
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
        XCTAssertEqual(combat.runSnapshot.shieldRemaining, 3.9166667, accuracy: 0.001)
        combat.restart()
        XCTAssertTrue(combat.startRun())
        time = advance(combat, from: time, seconds: 3.1)
        XCTAssertEqual(combat.summon(kind: .demon) { SCNNode() }, .summoned)
        XCTAssertEqual(combat.summon(kind: .albert) { SCNNode() }, .summoned)
        XCTAssertEqual(combat.summon(kind: .alan) { SCNNode() }, .summoned)
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
        let (scene, combat) = makeEncounter(startsImmediately: false, defaults: defaults)
        XCTAssertTrue(combat.startRun())
        var time = advance(combat, from: 0, seconds: 3.1)
        XCTAssertTrue(combat.nyan())
        time = advance(combat, from: time, seconds: SurvivalState.nyanDuration + 0.1)
        XCTAssertEqual(combat.runSnapshot.score, 1_050)
        XCTAssertEqual(combat.runSnapshot.bestWave, 1)

        combat.restart()
        XCTAssertEqual(combat.runSnapshot.score, 0)
        XCTAssertEqual(combat.runSnapshot.bestScore, 1_050)
        XCTAssertEqual(combat.runSnapshot.bestWave, 1)
        XCTAssertFalse(combat.runSnapshot.hasStarted)
        XCTAssertTrue(combat.startRun())
        time = advance(combat, from: time, seconds: 3.1)
        let slowedEnemy = try XCTUnwrap(combatants(in: scene).first)
        slowedEnemy.simdPosition = SIMD3(0, 0, 2)
        XCTAssertTrue(combat.ice(toward: center(slowedEnemy)))
        let alan = SCNNode()
        alan.simdPosition = SIMD3(2.2, 0, -4.8)
        XCTAssertEqual(combat.summon(kind: .alan) { alan }, .summoned)
        time = advance(combat, from: time, seconds: 4.1)
        XCTAssertGreaterThan(slowedEnemy.slowRemaining, 0)
        XCTAssertTrue(combat.nyan())
        XCTAssertNotNil(alan.parent)
        XCTAssertNotNil(combat.transfigurationPhase)
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
        XCTAssertTrue(
            scene.rootNode.childNode(withName: "Undead horde", recursively: false)?.childNodes.isEmpty == true)
        XCTAssertNil(defaults.object(forKey: "XArcana.bestScore"))
        XCTAssertNil(defaults.object(forKey: "XArcana.bestWave"))
        XCTAssertEqual(defaults.string(forKey: "unrelated.preference"), "keep")
        XCTAssertEqual(SurvivalState(defaults: defaults).snapshot, RunSnapshot())
        time = advance(combat, from: time, seconds: 3.1)
        XCTAssertEqual(combat.wave, 1)
        XCTAssertEqual(combat.remaining, 0)
        XCTAssertTrue(combat.startRun())
        _ = advance(combat, from: time, seconds: 3.1)
        XCTAssertEqual(combat.remaining, 1)
        XCTAssertTrue(combatants(in: scene).allSatisfy { $0.slowRemaining == 0 && !$0.isTransfigured })
    }

    func testNyanCostsEightyAndMaterializesTheWholeWaveAsCachedCats() throws {
        let (scene, combat) = makeEncounter()
        XCTAssertEqual(combat.remaining, 1)
        XCTAssertTrue(combat.nyan())
        XCTAssertEqual(combat.runSnapshot.mana, 20)
        XCTAssertEqual(combat.runSnapshot.nyanRemaining, SurvivalState.nyanDuration)
        XCTAssertEqual(combat.transfigurationPhase, 0)
        XCTAssertEqual(combat.remaining, 8)
        XCTAssertEqual(combat.pendingSpawns, 0)
        let enemies = combatants(in: scene)
        XCTAssertEqual(Set(enemies.map(\.identityID)).count, 8)
        XCTAssertTrue(enemies.allSatisfy { $0.isTransfigured && $0.health == 3 && !$0.isDefeated })
        let cats = try enemies.map {
            try XCTUnwrap($0.childNode(withName: "Transfigured Nyan cat", recursively: false))
        }
        XCTAssertEqual(cats.count, 8)
        XCTAssertNil(scene.rootNode.childNode(withName: "Rainbow cat", recursively: true))
        for (enemy, cat) in zip(enemies, cats) {
            XCTAssertEqual(cat.categoryBitMask, 2)
            XCTAssertTrue(enemy.childNodes.filter { $0 !== cat }.allSatisfy(\.isHidden))
            XCTAssertEqual(cat.childNodes.filter { $0.name?.hasPrefix("Rainbow cat leg") == true }.count, 4)
            XCTAssertEqual(cat.childNodes.filter { $0.name == "Rainbow trail" }.count, 6)
            var nodes = 1
            cat.enumerateChildNodes { _, _ in nodes += 1 }
            XCTAssertLessThanOrEqual(nodes, 24)
        }
        let firstBody = try XCTUnwrap(cats[0].childNode(withName: "Pastry cat body", recursively: false)?.geometry)
        let secondBody = try XCTUnwrap(cats[1].childNode(withName: "Pastry cat body", recursively: false)?.geometry)
        XCTAssertTrue(firstBody === secondBody)
        XCTAssertFalse(combat.nyan())
        XCTAssertEqual(combat.lastRejection, .cooldown)
        XCTAssertEqual(combat.runSnapshot.mana, 20)
        XCTAssertEqual(combat.runSnapshot.nyanRemaining, SurvivalState.nyanDuration)
    }

    func testTransfigurationCancelsPendingMeleeAndClearsWaveExactlyOnceAtSongEnd() throws {
        let (scene, combat) = makeEncounter()
        let first = try XCTUnwrap(combatants(in: scene).first)
        first.simdPosition = SIMD3(0, 0, 3.85)
        var time = advance(combat, from: 0, seconds: 1.1)
        XCTAssertEqual(first.meleeAttackCount, 1)
        XCTAssertTrue(combat.nyan())
        let enemies = combatants(in: scene)
        let positions = enemies.map(\.simdPosition)
        let cats = try enemies.map {
            try XCTUnwrap($0.childNode(withName: "Transfigured Nyan cat", recursively: false))
        }
        let catPositions = cats.map(\.simdWorldPosition)
        time = advance(combat, from: time, seconds: SurvivalState.nyanDuration - 0.1)
        XCTAssertEqual(enemies.map(\.simdPosition), positions)
        for (cat, position) in zip(cats, catPositions) {
            XCTAssertGreaterThan(simd_distance(cat.simdWorldPosition, position), 0.3)
        }
        XCTAssertEqual(combat.runSnapshot.health, 100)
        XCTAssertEqual(combat.kills, 0)
        XCTAssertEqual(combat.runSnapshot.score, 0)
        XCTAssertEqual(combat.wave, 1)
        XCTAssertEqual(first.meleeAttackCount, 1)
        time = advance(combat, from: time, seconds: 0.2)
        XCTAssertEqual(combat.runSnapshot.nyanRemaining, 0)
        XCTAssertNil(combat.transfigurationPhase)
        XCTAssertTrue(enemies.allSatisfy { $0.isDefeated && $0.health == 0 && !$0.isTransfigured })
        XCTAssertTrue(enemies.allSatisfy { $0.childNode(withName: "Transfigured Nyan cat", recursively: false) == nil })
        XCTAssertEqual(combat.kills, 8)
        XCTAssertEqual(combat.runSnapshot.score, 1_050)
        XCTAssertEqual(combat.runSnapshot.level, 2)
        XCTAssertEqual(combat.runSnapshot.xp, 40)
        XCTAssertEqual(combat.runSnapshot.bestWave, 1)
        XCTAssertEqual(combat.remaining, 0)
        XCTAssertEqual(combat.pendingSpawns, 0)
        let cleared = combat.runSnapshot
        XCTAssertFalse(combat.nyan())
        XCTAssertEqual(combat.runSnapshot, cleared)
        time = advance(combat, from: time, seconds: Combat.waveBreakDuration - 0.5)
        XCTAssertEqual(combat.wave, 1)
        XCTAssertEqual(combat.remaining, 0)
        _ = advance(combat, from: time, seconds: 0.7)
        XCTAssertEqual(combat.wave, 2)
        XCTAssertEqual(combat.remaining, 1)
        XCTAssertEqual(combat.pendingSpawns, 7)
        XCTAssertEqual(combat.kills, 8)
        XCTAssertEqual(combat.runSnapshot.score, 1_050)
        XCTAssertTrue(combatants(in: scene).allSatisfy { !$0.isTransfigured })
    }

    func testNyanEmitsLevelAndWaveEventsOnceWithPauseAndRestart() {
        let (_, combat) = makeEncounter()
        var events: [Combat.Event] = []
        var clearedScore: Int?
        combat.onEvent = { event in
            events.append(event)
            if case .waveCleared = event { clearedScore = combat.runSnapshot.score }
        }
        XCTAssertTrue(combat.nyan())
        var time = advance(combat, from: 0, seconds: 10)
        combat.setPaused(true)
        time = advance(combat, from: time, seconds: 30)
        XCTAssertTrue(events.isEmpty)
        combat.setPaused(false)
        time = advance(combat, from: time, seconds: SurvivalState.nyanDuration - 9.9)
        let clearedEvents: [Combat.Event] = [
            .levelUp(level: 2, maxHealth: 110, maxMana: 110), .waveCleared(1),
        ]
        XCTAssertEqual(events, clearedEvents)
        XCTAssertEqual(clearedScore, 1_050)

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
        let (scene, combat) = makeEncounter()
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
        XCTAssertEqual(combat.kills, 0)
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
        XCTAssertFalse(combat.runSnapshot.hasStarted)
        XCTAssertEqual(combat.remaining, 0)
    }

    func testTransfiguredCatsCannotBeDamagedByProjectilesOrIce() throws {
        let (scene, combat) = makeEncounter()
        let enemy = try XCTUnwrap(combatants(in: scene).first)
        enemy.simdPosition = SIMD3(0, 0, 3.85)
        XCTAssertTrue(combat.shoot(toward: center(enemy)))
        XCTAssertTrue(combat.nyan())
        var time = advance(combat, from: 0, seconds: 0.7)
        XCTAssertTrue(combat.ice(toward: center(enemy)))
        time = advance(combat, from: time, seconds: 4)
        XCTAssertTrue(combat.fireball(toward: center(enemy)))
        _ = advance(combat, from: time, seconds: 1)
        XCTAssertEqual(combat.kills, 0)
        XCTAssertEqual(combat.runSnapshot.score, 0)
        XCTAssertTrue(combatants(in: scene).allSatisfy { $0.health == 3 && $0.isTransfigured })
    }

    func testPhysicalAllyRemainsButCannotTargetOrDamageTransfiguredCats() throws {
        let (scene, combat) = makeEncounter()
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
        XCTAssertEqual(combat.kills, 0)
    }

    func testNyanInsufficientManaDoesNotMaterializeOrTransformHorde() {
        let (scene, combat) = makeEncounter()
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

    func testKillsAwardScoreAndXPExactlyOnce() throws {
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
        XCTAssertEqual(combat.runSnapshot.xp, 10)
        XCTAssertTrue(combat.fireball(toward: center(enemy)))
        _ = advance(combat, from: time, seconds: 1)
        XCTAssertEqual(combat.kills, 1)
        XCTAssertEqual(combat.runSnapshot.score, 100)
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
            let (_, combat) = makeEncounter()
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
        let time = advance(combat, from: 0, seconds: 1.5)
        XCTAssertEqual(combat.runSnapshot.mana, 84, accuracy: 0.000001)
        let snapshot = combat.runSnapshot
        combat.update(at: time)
        combat.update(at: time - 0.05)
        combat.update(at: .nan)
        combat.update(at: time)
        XCTAssertEqual(combat.runSnapshot, snapshot, "Previously counted frame time must not regenerate mana twice.")
        combat.update(at: time + 0.05)
        XCTAssertEqual(combat.runSnapshot.mana, snapshot.mana + 0.4, accuracy: 0.000001)
        combat.setPaused(true)
        let paused = combat.runSnapshot
        combat.update(at: time + 5)
        XCTAssertEqual(combat.runSnapshot, paused)
        combat.setPaused(false)
        combat.update(at: time + 10)
        XCTAssertEqual(combat.runSnapshot, paused, "The first resumed frame establishes a fresh clock.")
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
        startsImmediately: Bool = true, defaults: UserDefaults? = nil, cameraHeight: Float = 1.65
    ) -> (SCNScene, Combat) {
        let scene = SCNScene()
        let camera = SCNNode()
        camera.name = "Test camera"
        camera.simdPosition = SIMD3(0, cameraHeight, 4.8)
        scene.rootNode.addChildNode(camera)
        let combat = Combat(
            scene: scene, camera: camera, floorY: 0, defaults: defaults, startsImmediately: startsImmediately)
        combat.update(at: 0)
        return (scene, combat)
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
    func testManaDelayRegenerationAndFreeActions() {
        let state = SurvivalState(defaults: nil)
        XCTAssertTrue(state.spend(15))
        XCTAssertEqual(state.snapshot.mana, 85)
        state.update(deltaTime: 0.9)
        XCTAssertEqual(state.snapshot.mana, 85)
        XCTAssertTrue(state.spend(0))
        state.update(deltaTime: 0.2)
        XCTAssertEqual(state.snapshot.mana, 85.8, accuracy: 0.0001)
        XCTAssertFalse(state.spend(100))
        state.update(deltaTime: 1)
        XCTAssertEqual(state.snapshot.mana, 93.8, accuracy: 0.0001)
        state.update(deltaTime: 10)
        XCTAssertEqual(state.snapshot.mana, 100)
    }

    func testLevelThresholdCarryoverHealingAndRefill() {
        let state = SurvivalState(defaults: nil)
        state.damage(60)
        XCTAssertTrue(state.spend(90))
        for _ in 0..<4 { state.recordKill() }
        XCTAssertEqual(state.snapshot.level, 2)
        XCTAssertEqual(state.snapshot.xp, 0)
        XCTAssertEqual(state.snapshot.xpToNextLevel, 60)
        XCTAssertEqual(state.snapshot.maxHealth, 110)
        XCTAssertEqual(state.snapshot.health, 60)
        XCTAssertEqual(state.snapshot.mana, 110)
        for _ in 0..<7 { state.recordKill() }
        XCTAssertEqual(state.snapshot.level, 3)
        XCTAssertEqual(state.snapshot.xp, 10)
        XCTAssertEqual(state.snapshot.xpToNextLevel, 80)
        XCTAssertEqual(state.snapshot.health, 80)
        XCTAssertEqual(state.snapshot.maxMana, 120)
        XCTAssertEqual(state.snapshot.score, 1_100)
    }

    func testOlderSnapshotDecodesWithoutShieldFields() throws {
        let snapshot = try JSONDecoder().decode(RunSnapshot.self, from: Data(#"{"health":75,"mana":80}"#.utf8))
        XCTAssertEqual(snapshot.health, 75)
        XCTAssertEqual(snapshot.mana, 80)
        XCTAssertEqual(snapshot.shieldRemaining, 0)
        XCTAssertEqual(snapshot.shieldCooldownRemaining, 0)
        XCTAssertTrue(snapshot.hasStarted)
        XCTAssertEqual(snapshot.countdownRemaining, 0)
        XCTAssertEqual(snapshot.nyanRemaining, 0)
        XCTAssertEqual(try JSONDecoder().decode(RunSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }

    func testShieldTimersStopAtGameOverAndRestartClearsThem() {
        let state = SurvivalState(defaults: nil)
        XCTAssertTrue(state.activateShield())
        state.damage(100)
        let ended = state.snapshot
        state.update(deltaTime: 20)
        XCTAssertEqual(state.snapshot, ended)
        XCTAssertFalse(state.activateShield())
        state.restart()
        XCTAssertEqual(state.snapshot.shieldRemaining, 0)
        XCTAssertEqual(state.snapshot.shieldCooldownRemaining, 0)
    }

    func testNyanEndsOnDeathAndRestartAndCannotStartBeforeCountdown() {
        let waiting = SurvivalState(defaults: nil, hasStarted: false)
        XCTAssertFalse(waiting.activateNyan())
        XCTAssertTrue(waiting.beginCountdown())
        XCTAssertFalse(waiting.activateNyan())
        waiting.advanceCountdown(deltaTime: 3)
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
        state.damage(100)
        let ended = state.snapshot
        state.update(deltaTime: 100)
        state.recordKill()
        state.clearWave()
        XCTAssertFalse(state.spend(0))
        XCTAssertEqual(state.snapshot, ended)
        state.restart()
        XCTAssertEqual(state.snapshot.health, 100)
        XCTAssertEqual(state.snapshot.score, 0)
        XCTAssertEqual(state.snapshot.bestScore, 350)
        XCTAssertEqual(state.snapshot.bestWave, 1)
        let restored = SurvivalState(defaults: defaults)
        XCTAssertEqual(restored.snapshot.bestScore, 350)
        XCTAssertEqual(restored.snapshot.bestWave, 1)
    }
}
