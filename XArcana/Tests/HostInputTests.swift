import SceneKit
import XCTest
import simd

@testable import XArcana

@MainActor
final class HostInputTests: XCTestCase {
    func testLiveResetReturnsToLevelOneAndCancelsAnUnfinishedRune() {
        let game = Encounter(defaults: nil, state: chargedNyanState())
        game.start()
        defer { game.stop() }
        confirmSetup(on: game)
        game.combat.update(at: 0)
        for frame in 1...62 { game.combat.update(at: Double(frame) * 0.05) }
        let castTime = prepareFullHorde(on: game, from: 3.1)
        XCTAssertTrue(game.combat.nyan())
        for frame in 1...542 { game.combat.update(at: castTime + Double(frame) * 0.05) }
        XCTAssertEqual(game.runSnapshot.level, 1, "Clearing the horde does not start the next stage immediately")
        XCTAssertEqual(game.runSnapshot.xp, 0)
        XCTAssertEqual(game.runSnapshot.score, 3050)
        game.handleVoice(.summonAlan)
        XCTAssertFalse(game.runSnapshot.isGameOver)
        game.receive(WandInput(kind: .begin, gesture: 20, timestamp: 100, yaw: 0, pitch: 0))
        XCTAssertTrue(game.isHolding)
        game.receive(WandInput(kind: .restartRun, timestamp: 101))
        let fresh = game.runSnapshot
        XCTAssertEqual(fresh.level, 1)
        XCTAssertEqual(fresh.health, 100)
        XCTAssertEqual(fresh.maxHealth, 100)
        XCTAssertEqual(fresh.mana, 100)
        XCTAssertEqual(fresh.maxMana, 100)
        XCTAssertEqual(fresh.score, 0)
        XCTAssertEqual(fresh.kills, 0)
        XCTAssertEqual(fresh.bestScore, 3050)
        XCTAssertEqual(fresh.bestWave, 1)
        XCTAssertFalse(fresh.hasStarted)
        XCTAssertEqual(game.setupStep, "world")
        XCTAssertEqual(fresh.countdownRemaining, 0)
        XCTAssertEqual(game.combat.remaining, 0)
        XCTAssertFalse(game.isHolding)
        XCTAssertFalse(game.room.scene.rootNode.childNodes.contains { $0.name?.hasPrefix("summon.") == true })
        game.receive(WandInput(kind: .end, gesture: 20, timestamp: 102, yaw: 0, pitch: 0))
        XCTAssertEqual(game.runSnapshot.mana, 100)
        XCTAssertFalse(game.isHolding)
        confirmSetup(on: game)
        game.receive(WandInput(kind: .resetScores, timestamp: 103))
        XCTAssertEqual(game.runSnapshot.bestScore, 0)
        XCTAssertEqual(game.runSnapshot.bestWave, 0)
        XCTAssertEqual(game.runSnapshot.level, 1)
        XCTAssertFalse(game.runSnapshot.hasStarted)
        XCTAssertEqual(game.setupStep, "world")
        XCTAssertEqual(game.runSnapshot.countdownRemaining, 0)
    }

    func testSetupTapsPreviewWorldAndWeaponBeforeConfirmingStart() {
        let game = Encounter(defaults: nil)
        game.start()
        defer { game.stop() }
        XCTAssertEqual(game.setupStep, "world")
        game.receive(WandInput(kind: .nextSetupChoice))
        XCTAssertTrue(game.room.isSeeThrough)
        XCTAssertFalse(game.runSnapshot.hasStarted)
        game.receive(WandInput(kind: .confirmSetupChoice))
        XCTAssertEqual(game.setupStep, "weapon")
        XCTAssertFalse(game.runSnapshot.hasStarted)
        game.receive(WandInput(kind: .nextSetupChoice))
        XCTAssertEqual(game.fightingMode, .bow)
        XCTAssertEqual(game.combat.remaining, 0)
        XCTAssertEqual(game.runSnapshot.mana, 100)
        game.receive(WandInput(kind: .confirmSetupChoice))
        XCTAssertTrue(game.runSnapshot.hasStarted)
        XCTAssertEqual(game.runSnapshot.countdownRemaining, 3)
        game.receive(WandInput(kind: .nextSetupChoice))
        game.receive(WandInput(kind: .confirmSetupChoice))
        XCTAssertEqual(game.fightingMode, .bow)
        XCTAssertEqual(game.runSnapshot.countdownRemaining, 3)
        XCTAssertFalse(game.isHolding)
        game.combat.update(at: 0)
        for frame in 1...62 { game.combat.update(at: Double(frame) * 0.05) }
        XCTAssertTrue(game.status.contains("Tap anywhere to shoot"))
    }

    func testStartScreenWaitsForPhoneThenCountsDownWithoutCastingHeldInput() {
        let game = Encounter(defaults: nil)
        game.start()
        defer { game.stop() }
        XCTAssertFalse(game.runSnapshot.hasStarted)
        XCTAssertEqual(game.combat.remaining, 0)
        game.receive(WandInput(kind: .begin, gesture: 1, timestamp: 100, yaw: 0, pitch: 0))
        XCTAssertFalse(game.isHolding)
        game.receive(WandInput(kind: .startRun, timestamp: 100))
        XCTAssertFalse(game.runSnapshot.hasStarted)
        XCTAssertEqual(game.setupStep, "weapon")
        game.receive(WandInput(kind: .startRun, timestamp: 100.01))
        XCTAssertTrue(game.runSnapshot.hasStarted)
        XCTAssertEqual(game.runSnapshot.countdownRemaining, 3)
        game.receive(WandInput(kind: .begin, gesture: 2, timestamp: 100.1, yaw: 0, pitch: 0))
        game.receive(WandInput(kind: .end, gesture: 2, timestamp: 100.2, yaw: 0, pitch: 0))
        XCTAssertFalse(game.isHolding)
        XCTAssertEqual(game.runSnapshot.mana, 100)
        game.combat.update(at: 0)
        for frame in 1...59 { game.combat.update(at: Double(frame) * 0.05) }
        XCTAssertEqual(game.combat.remaining, 0)
        for frame in 60...62 { game.combat.update(at: Double(frame) * 0.05) }
        XCTAssertEqual(game.runSnapshot.countdownRemaining, 0)
        XCTAssertGreaterThan(game.combat.remaining, 0)
        game.receive(WandInput(kind: .end, gesture: 2, timestamp: 104, yaw: 0, pitch: 0))
        XCTAssertEqual(game.runSnapshot.mana, 100)
        game.receive(WandInput(kind: .begin, gesture: 3, timestamp: 105, yaw: 0, pitch: 0))
        XCTAssertTrue(game.isHolding)
    }

    private func chargedNyanState() -> SurvivalState {
        let state = SurvivalState(defaults: nil, hasStarted: false)
        for _ in 0..<20 { state.recordKill() }
        return state
    }

    private func prepareFullHorde(on game: Encounter, from start: TimeInterval) -> TimeInterval {
        let height = game.room.camera.simdPosition.y
        game.room.camera.simdPosition.y = 6
        let frames = Int(ceil((Combat.spawnInterval * 7 + 0.5) / 0.05))
        for frame in 1...frames { game.combat.update(at: start + Double(frame) * 0.05) }
        game.room.camera.simdPosition.y = height
        return start + Double(frames) * 0.05
    }

    private func confirmSetup(on game: Encounter) {
        game.receive(WandInput(kind: .confirmSetupChoice))
        game.receive(WandInput(kind: .confirmSetupChoice))
    }

    private func host() -> Encounter {
        let host = Encounter(startsImmediately: true, defaults: nil)
        host.stage.frame = CGRect(x: 0, y: 0, width: 640, height: 360)
        host.stage.layoutIfNeeded()
        host.start()
        return host
    }

    func testControllerClockDrivesRuneEvenWhenPacketsArriveTogether() {
        let game = host()
        defer { game.stop() }
        game.receive(WandInput(kind: .begin, gesture: 1, timestamp: 10000, yaw: 0, pitch: 0))
        for step in 1...60 {
            let angle = Float(step) * 2 * .pi / 60
            game.receive(
                WandInput(
                    kind: .sample, gesture: 1, timestamp: 10000 + Double(step) / 60,
                    yaw: 0.2 * (cos(angle) - 1), pitch: 0.2 * sin(angle)))
        }
        XCTAssertTrue(game.isHolding)
        game.receive(WandInput(kind: .end, gesture: 1, timestamp: 10001.02, yaw: 0, pitch: 0))
        XCTAssertEqual(game.status, SpellCatalog.fireball.acceptedFeedback)
        XCTAssertFalse(game.isHolding)
    }

    func testRemoteBowReleaseExecutesOnceAndModeWordsDoNotFire() {
        let game = host()
        defer { game.stop() }
        func arrows() -> Int {
            var count = 0
            game.room.scene.rootNode.enumerateChildNodes { node, _ in if node.name == "Flying arrow" { count += 1 } }
            return count
        }
        game.receive(WandInput(kind: .voice, command: "shoot"))
        XCTAssertEqual(arrows(), 0)
        game.receive(WandInput(kind: .begin, gesture: 8, timestamp: 10, yaw: 0, pitch: 0))
        game.receive(WandInput(kind: .end, gesture: 9, timestamp: 10.1, yaw: 0, pitch: 0))
        XCTAssertTrue(game.isHolding)
        XCTAssertEqual(arrows(), 0)
        game.receive(WandInput(kind: .end, gesture: 8, timestamp: 10.2, yaw: 0, pitch: 0))
        game.receive(WandInput(kind: .end, gesture: 8, timestamp: 10.2, yaw: 0, pitch: 0))
        XCTAssertEqual(arrows(), 1)
    }

    func testDisconnectCancelsStrokeAndRetainsAllSummons() {
        let game = host()
        defer { game.stop() }
        for name in ["summonAlbert", "summonAlbert", "summonAlan"] {
            game.receive(WandInput(kind: .voice, command: name))
        }
        let companions = game.room.scene.rootNode.childNodes.filter { $0.name?.hasPrefix("summon.") == true }
        XCTAssertEqual(companions.count, 2)
        game.receive(WandInput(kind: .begin, gesture: 2, timestamp: 1, yaw: 0, pitch: 0))
        game.controllerDisconnected()
        XCTAssertFalse(game.isHolding)
        XCTAssertTrue(companions.allSatisfy { $0.parent === game.room.scene.rootNode })
        game.receive(WandInput(kind: .end, gesture: 2, timestamp: 2, yaw: 0, pitch: 0))
        XCTAssertFalse(game.status.contains("Sparks"))
        game.receive(WandInput(kind: .begin, gesture: 3, timestamp: 3, yaw: 0, pitch: 0))
        XCTAssertTrue(game.isHolding)
    }

    func testDeathCancelsHeldRuneAndRestartDiscardsItsLateRelease() {
        let game = host()
        defer { game.stop() }
        game.receive(WandInput(kind: .begin, gesture: 11, timestamp: 100, yaw: 0, pitch: 0))
        XCTAssertTrue(game.isHolding)
        for step in 0..<7_200 {
            for node in game.room.scene.rootNode.childNode(withName: "Undead horde", recursively: false)?.childNodes
                ?? []
            {
                if let enemy = node as? Combat.CombatantNode, !enemy.isDefeated {
                    enemy.simdPosition = SIMD3(0, 0, 3.85)
                }
            }
            game.combat.update(at: Double(step) / 60)
            if game.runSnapshot.isGameOver { break }
        }
        XCTAssertTrue(game.runSnapshot.isGameOver)
        XCTAssertFalse(game.isHolding)
        game.receive(WandInput(kind: .end, gesture: 11, timestamp: 101, yaw: 0.2, pitch: 0.2))
        XCTAssertTrue(game.runSnapshot.isGameOver)
        game.receive(WandInput(kind: .restartRun, timestamp: 102))
        XCTAssertFalse(game.runSnapshot.isGameOver)
        XCTAssertEqual(game.runSnapshot.health, 100)
        XCTAssertEqual(game.runSnapshot.mana, 100)
        XCTAssertEqual(game.runSnapshot.score, 0)
        game.receive(WandInput(kind: .end, gesture: 11, timestamp: 103, yaw: 0.2, pitch: 0.2))
        XCTAssertEqual(game.runSnapshot.mana, 100)
        XCTAssertFalse(game.isHolding)
        XCTAssertFalse(game.runSnapshot.hasStarted)
        XCTAssertEqual(game.setupStep, "world")
        game.receive(WandInput(kind: .begin, gesture: 12, timestamp: 104, yaw: 0, pitch: 0))
        XCTAssertFalse(game.isHolding)
        confirmSetup(on: game)
        game.combat.update(at: 0)
        for frame in 1...62 { game.combat.update(at: Double(frame) * 0.05) }
        game.receive(WandInput(kind: .begin, gesture: 13, timestamp: 108, yaw: 0, pitch: 0))
        XCTAssertTrue(game.isHolding)
    }

    func testShieldPreviewsBeforeReleaseAndOnlySpendsOnce() {
        let game = host()
        defer { game.stop() }
        game.receive(WandInput(kind: .begin, gesture: 4, timestamp: 10, yaw: 0, pitch: 0))
        for step in 1...70 {
            game.receive(
                WandInput(
                    kind: .sample, gesture: 4, timestamp: 10 + Double(step) / 60,
                    yaw: 0.003 * sin(Float(step)), pitch: 0.002 * cos(Float(step))))
        }
        XCTAssertTrue(game.shieldReady)
        XCTAssertEqual(game.castPreview, "Shield ready · Release")
        XCTAssertEqual(game.runSnapshot.mana, 100)
        XCTAssertEqual(game.runSnapshot.shieldRemaining, 0)
        game.receive(WandInput(kind: .end, gesture: 4, timestamp: 11.18, yaw: 0, pitch: 0))
        XCTAssertEqual(game.runSnapshot.mana, 80)
        XCTAssertEqual(game.runSnapshot.shieldRemaining, 0)
        XCTAssertEqual(game.runSnapshot.shieldHealth, 20)
        XCTAssertFalse(game.shieldReady)
        game.receive(WandInput(kind: .end, gesture: 4, timestamp: 11.19, yaw: 0, pitch: 0))
        XCTAssertEqual(game.runSnapshot.mana, 80)
    }

    func testActiveShieldShowsHealthInsteadOfReadiness() {
        let game = host()
        defer { game.stop() }
        XCTAssertTrue(game.combat.shield())
        game.receive(WandInput(kind: .begin, gesture: 6, timestamp: 20, yaw: 0, pitch: 0))
        for step in 1...70 {
            game.receive(WandInput(kind: .sample, gesture: 6, timestamp: 20 + Double(step) / 60, yaw: 0, pitch: 0))
        }
        XCTAssertFalse(game.shieldReady)
        XCTAssertEqual(game.castPreview, "Shield active · 20 HP")
        game.receive(WandInput(kind: .end, gesture: 6, timestamp: 21.18, yaw: 0, pitch: 0))
        XCTAssertEqual(game.runSnapshot.mana, 80)
        XCTAssertEqual(game.runSnapshot.shieldHealth, 20)
    }

    func testUnheldWaveUsesHostMeleeReachAndCostsNoMana() throws {
        let game = host()
        defer { game.stop() }
        let enemy = try XCTUnwrap(
            game.room.scene.rootNode.childNode(withName: "Undead horde", recursively: false)?
                .childNodes.compactMap { $0 as? Combat.CombatantNode }.first)
        let eye = game.room.camera.simdWorldPosition
        let direction = simd_normalize(game.stage.aimedWorldPoint() - eye)
        enemy.simdPosition = eye + direction * 1.3 - SIMD3(0, 1.05 * enemy.simdScale.y, 0)
        wave(on: game, at: 100)
        XCTAssertEqual(enemy.health, 1)
        XCTAssertEqual(game.runSnapshot.mana, 100)
        XCTAssertTrue(game.status.hasPrefix("Wand strike"))
        XCTAssertNotNil(
            game.room.camera.childNode(withName: "wandMeleeSweep", recursively: false)?.action(forKey: "melee"))

        game.combat.update(at: 0)
        for frame in 1...12 { game.combat.update(at: Double(frame) * 0.05) }
        enemy.simdPosition = eye + direction * 3 - SIMD3(0, 1.05 * enemy.simdScale.y, 0)
        game.receive(WandInput(kind: .sample, timestamp: 100.7, yaw: 0.2, pitch: 0))
        wave(on: game, at: 100.8)
        XCTAssertEqual(enemy.health, 1, "The host rejects targets beyond two metres.")
    }

    func testUnheldWavesCannotStrikeWhileHoldingOrUsingBow() {
        let game = host()
        defer { game.stop() }
        game.receive(WandInput(kind: .begin, gesture: 30, timestamp: 99, yaw: 0, pitch: 0))
        wave(on: game, at: 100)
        XCTAssertTrue(game.isHolding)
        XCTAssertFalse(game.status.hasPrefix("Wand strike"))
        game.controllerDisconnected()
        game.handleVoice(.shoot)
        wave(on: game, at: 101)
        XCTAssertFalse(game.status.hasPrefix("Wand strike"))
        XCTAssertFalse(game.isHolding)
        XCTAssertEqual(game.runSnapshot.mana, 100)
    }

    func testPauseDisconnectAndRestartDiscardIncompleteSwings() {
        let game = host()
        defer { game.stop() }
        func sample(_ time: Double, _ yaw: Float) {
            game.receive(WandInput(kind: .sample, timestamp: time, yaw: yaw, pitch: 0))
        }
        sample(10, 0)
        game.simulationActive = false
        game.simulationActive = true
        sample(10.12, 0.2)
        XCTAssertFalse(game.status.hasPrefix("Wand strike"))
        game.controllerDisconnected()
        sample(10.24, 0.4)
        XCTAssertFalse(game.status.hasPrefix("Wand strike"))
        game.restartRun()
        wave(on: game, at: 11)
        XCTAssertFalse(game.status.hasPrefix("Wand strike"))
        confirmSetup(on: game)
        wave(on: game, at: 12)
        XCTAssertEqual(game.runSnapshot.countdownRemaining, 3)
        XCTAssertFalse(game.status.hasPrefix("Wand strike"))
    }

    private func wave(on game: Encounter, at time: TimeInterval) {
        for step in 0...6 {
            game.receive(
                WandInput(
                    kind: .sample, timestamp: time + Double(step) * 0.02,
                    yaw: Float(step) / 6 * 0.22, pitch: 0))
        }
    }

    func testHoldingKeepsTheCurrentWandAimAndStartsInkThere() throws {
        let game = host()
        defer { game.stop() }
        game.stage.frame = CGRect(x: 0, y: 0, width: 960, height: 540)
        game.stage.layoutIfNeeded()
        for (index, angles) in [SIMD2<Float>(0.3, 0.12), SIMD2<Float>(-0.25, -0.15)].enumerated() {
            let time = 10 + Double(index)
            game.receive(WandInput(kind: .sample, timestamp: time, yaw: angles.x, pitch: angles.y))
            let before = game.stage.aimedWorldPoint()
            game.receive(
                WandInput(
                    kind: .begin, gesture: UInt64(index + 1), timestamp: time + 0.01,
                    yaw: angles.x, pitch: angles.y))
            XCTAssertTrue(game.isHolding)
            let after = game.stage.aimedWorldPoint()
            XCTAssertLessThan(simd_distance(before, after), 0.01, "Touch-down must not recenter aim")
            let trail = try XCTUnwrap(game.stage.subviews.compactMap { $0 as? RuneTrail }.first)
            XCTAssertFalse(trail.isHidden)
            XCTAssertGreaterThan(abs(trail.center.x - game.stage.bounds.midX), 100)
            game.receive(WandInput(kind: .cancel, gesture: UInt64(index + 1), timestamp: time + 0.02))
        }
    }

    func testStageAnnouncementsFollowTheHordeInsteadOfExperience() throws {
        let game = Encounter(defaults: nil, state: chargedNyanState())
        game.start()
        defer { game.stop() }
        confirmSetup(on: game)
        game.combat.update(at: 0)
        for frame in 1...62 { game.combat.update(at: Double(frame) * 0.05) }
        let banner = try XCTUnwrap(game.stage.subviews.compactMap { $0 as? RunAnnouncementView }.first)
        XCTAssertEqual(banner.accessibilityLabel, "Level 1. Survive the horde · Health and mana full")
        game.stage.advanceAnnouncements(deltaTime: 3.1)
        let castTime = prepareFullHorde(on: game, from: 3.1)
        XCTAssertTrue(game.combat.nyan())
        for frame in 1...542 { game.combat.update(at: castTime + Double(frame) * 0.05) }
        XCTAssertEqual(game.runSnapshot.level, 1)
        XCTAssertEqual(game.runSnapshot.xp, 0)
        XCTAssertTrue(banner.accessibilityLabel?.hasPrefix("Level 1 cleared!") == true)
        game.stage.advanceAnnouncements(deltaTime: 3.1)
        for frame in 543...950 { game.combat.update(at: castTime + Double(frame) * 0.05) }
        XCTAssertEqual(game.runSnapshot.level, 2)
        XCTAssertEqual(game.runSnapshot.wave, 2)
        XCTAssertEqual(game.runSnapshot.health, Double(game.runSnapshot.maxHealth))
        XCTAssertEqual(game.runSnapshot.mana, game.runSnapshot.maxMana)
        XCTAssertEqual(banner.accessibilityLabel, "Level 2. Survive the horde · Health and mana full")
    }

    func testMissingMotionAtReleaseCannotCastReadyShield() {
        let game = host()
        defer { game.stop() }
        game.receive(WandInput(kind: .begin, gesture: 5, timestamp: 10, yaw: 0, pitch: 0))
        for step in 1...70 {
            game.receive(
                WandInput(
                    kind: .sample, gesture: 5, timestamp: 10 + Double(step) / 60,
                    yaw: 0, pitch: 0))
        }
        XCTAssertTrue(game.shieldReady)
        game.receive(WandInput(kind: .end, gesture: 5, timestamp: 11.18))
        XCTAssertFalse(game.shieldReady)
        XCTAssertEqual(game.runSnapshot.mana, 100)
        XCTAssertEqual(game.runSnapshot.shieldRemaining, 0)
        XCTAssertFalse(game.isHolding)
    }
}
