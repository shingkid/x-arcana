import SceneKit
import XCTest

@testable import XArcana

@MainActor
final class HostInputTests: XCTestCase {
    func testLiveResetReturnsToLevelOneAndCancelsAnUnfinishedRune() {
        let game = Encounter(defaults: nil)
        game.start()
        defer { game.stop() }
        confirmSetup(on: game)
        game.combat.update(at: 0)
        for frame in 1...62 { game.combat.update(at: Double(frame) * 0.05) }
        XCTAssertTrue(game.combat.nyan())
        for frame in 63...610 { game.combat.update(at: Double(frame) * 0.05) }
        XCTAssertEqual(game.runSnapshot.level, 2)
        XCTAssertEqual(game.runSnapshot.score, 1050)
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
        XCTAssertEqual(fresh.bestScore, 1050)
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
        XCTAssertEqual(game.runSnapshot.shieldRemaining, 5)
        XCTAssertFalse(game.shieldReady)
        game.receive(WandInput(kind: .end, gesture: 4, timestamp: 11.19, yaw: 0, pitch: 0))
        XCTAssertEqual(game.runSnapshot.mana, 80)
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
