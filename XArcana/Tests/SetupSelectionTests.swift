import UIKit
import XCTest

@testable import XArcana

@MainActor
final class SetupSelectionTests: XCTestCase {
    private func setupHost() -> Encounter {
        let game = Encounter(defaults: nil)
        game.stage.external = true
        game.stage.frame = CGRect(x: 0, y: 0, width: 1280, height: 720)
        game.start()
        game.stage.layoutIfNeeded()
        return game
    }

    private func point(_ game: Encounter, yaw: Float, pitch: Float = 0) {
        game.receive(WandInput(kind: .sample, gesture: 0, timestamp: 10, yaw: yaw, pitch: pitch))
    }

    func testPhonePointerHoversActualChoicesAndTapPreviewsWithoutCycling() {
        let game = setupHost()
        defer { game.stop() }
        let frames = game.stage.setupChoiceFrames
        XCTAssertEqual(frames.count, 2)
        XCTAssertTrue(frames.allSatisfy { $0.width >= 150 && $0.height >= 80 && game.stage.bounds.contains($0) })
        XCTAssertLessThan(frames[0].maxX, frames[1].minX)
        point(game, yaw: 0.19)
        XCTAssertEqual(game.stage.hoveredSetupChoice, 1)
        XCTAssertFalse(game.room.isSeeThrough, "Hover must not change the selected preview")
        let pointer = CGPoint(
            x: game.stage.aim.x * game.stage.bounds.width, y: game.stage.aim.y * game.stage.bounds.height)
        XCTAssertTrue(frames[1].contains(pointer))
        game.receive(WandInput(kind: .nextSetupChoice))
        XCTAssertTrue(game.room.isSeeThrough)
        game.receive(WandInput(kind: .nextSetupChoice))
        XCTAssertTrue(game.room.isSeeThrough, "A second tap on the same choice must not cycle away")
        point(game, yaw: -0.19)
        XCTAssertEqual(game.stage.hoveredSetupChoice, 0)
        XCTAssertTrue(game.room.isSeeThrough)
        game.receive(WandInput(kind: .nextSetupChoice))
        XCTAssertFalse(game.room.isSeeThrough)
        point(game, yaw: 1)
        XCTAssertNil(game.stage.hoveredSetupChoice)
        game.receive(WandInput(kind: .nextSetupChoice))
        XCTAssertFalse(game.room.isSeeThrough, "A tap outside both rectangles must not cycle")
    }

    func testSetupMotionAndHeldEdgesNeverCastAndBothStepsRequireConfirmation() {
        let game = setupHost()
        defer { game.stop() }
        point(game, yaw: 0.19)
        game.receive(WandInput(kind: .begin, gesture: 1, timestamp: 10, yaw: 0, pitch: 0))
        game.receive(WandInput(kind: .sample, gesture: 1, timestamp: 11, yaw: 0.5, pitch: 0.5))
        game.receive(WandInput(kind: .end, gesture: 1, timestamp: 12, yaw: 0, pitch: 0))
        game.receive(WandInput(kind: .voice, command: "summonDemon"))
        XCTAssertFalse(game.isHolding)
        XCTAssertEqual(game.runSnapshot.mana, 100)
        XCTAssertEqual(game.combat.remaining, 0)
        XCTAssertFalse(game.runSnapshot.hasStarted)
        game.receive(WandInput(kind: .nextSetupChoice))
        XCTAssertTrue(game.room.isSeeThrough)
        game.receive(WandInput(kind: .confirmSetupChoice))
        XCTAssertEqual(game.setupStep, "weapon")
        XCTAssertFalse(game.runSnapshot.hasStarted)
        point(game, yaw: 0.19)
        game.receive(WandInput(kind: .nextSetupChoice))
        XCTAssertEqual(game.fightingMode, .bow)
        game.combat.update(at: 0)
        game.combat.update(at: 20)
        XCTAssertEqual(game.combat.remaining, 0)
        XCTAssertEqual(game.runSnapshot.countdownRemaining, 0)
        game.receive(WandInput(kind: .confirmSetupChoice))
        XCTAssertTrue(game.runSnapshot.hasStarted)
        XCTAssertEqual(game.runSnapshot.countdownRemaining, 3)
        XCTAssertFalse(game.stage.hasSetupPointer)
    }

    func testNoMotionAndAccessibilityCycleRemainAvailable() {
        let game = setupHost()
        defer { game.stop() }
        game.receive(WandInput(kind: .nextSetupChoice))
        XCTAssertTrue(game.room.isSeeThrough)
        game.receive(WandInput(kind: .nextSetupChoice))
        XCTAssertFalse(game.room.isSeeThrough)
        point(game, yaw: -0.19)
        game.receive(WandInput(kind: .nextSetupChoice, command: "cycle"))
        XCTAssertTrue(game.room.isSeeThrough, "The explicit accessibility action cycles even with motion")
        game.controllerDisconnected()
        XCTAssertFalse(game.stage.hasSetupPointer)
        game.receive(WandInput(kind: .nextSetupChoice))
        XCTAssertFalse(game.room.isSeeThrough)
    }

    func testRestartAndScoreResetReturnToWorldSetupAndDiscardLateHeldInput() {
        let game = Encounter(startsImmediately: true, defaults: nil)
        game.start()
        defer { game.stop() }
        game.setSeeThrough(true)
        game.handleVoice(.shoot)
        game.receive(WandInput(kind: .begin, gesture: 7, timestamp: 10, yaw: 0, pitch: 0))
        XCTAssertTrue(game.isHolding)
        game.receive(WandInput(kind: .restartRun))
        XCTAssertEqual(game.setupStep, "world")
        XCTAssertFalse(game.room.isSeeThrough)
        XCTAssertEqual(game.fightingMode, .wand)
        XCTAssertFalse(game.isHolding)
        XCTAssertFalse(game.runSnapshot.hasStarted)
        XCTAssertEqual(game.runSnapshot.countdownRemaining, 0)
        game.receive(WandInput(kind: .end, gesture: 7, timestamp: 11, yaw: 0, pitch: 0))
        XCTAssertEqual(game.runSnapshot.mana, 100)
        game.receive(WandInput(kind: .confirmSetupChoice))
        game.receive(WandInput(kind: .confirmSetupChoice))
        game.receive(WandInput(kind: .resetScores))
        XCTAssertEqual(game.setupStep, "world")
        XCTAssertFalse(game.runSnapshot.hasStarted)
        XCTAssertEqual(game.runSnapshot.countdownRemaining, 0)
        XCTAssertEqual(game.runSnapshot.bestScore, 0)
        XCTAssertEqual(game.runSnapshot.bestWave, 0)
        XCTAssertEqual(game.combat.remaining, 0)
    }
    func testWandGuideFollowsModeAndStaysReadableBelowHUDAtBothViewports() throws {
        let stage = GameStage(room: GameWorld())
        stage.external = true
        stage.showRun(RunSnapshot())
        let guide = try XCTUnwrap(stage.subviews.first { $0.accessibilityIdentifier == "wandSpellGuide" })
        let hud = try XCTUnwrap(stage.subviews.first { $0.accessibilityIdentifier == "runHUD" })
        XCTAssertFalse(guide.isHidden)
        for size in [CGSize(width: 1920, height: 1080), CGSize(width: 960, height: 540)] {
            stage.frame = CGRect(origin: .zero, size: size)
            stage.layoutIfNeeded()
            guide.layoutIfNeeded()
            XCTAssertTrue(stage.bounds.contains(guide.frame))
            XCTAssertTrue(stage.bounds.contains(hud.frame))
            XCTAssertGreaterThanOrEqual(guide.frame.minY - hud.frame.maxY, 10)
            let labels = guide.subviews.compactMap { $0 as? UILabel }
            XCTAssertEqual(labels.count, 2)
            for label in labels {
                XCTAssertGreaterThanOrEqual(label.font.pointSize, 14)
                XCTAssertTrue(guide.bounds.contains(label.frame), "The complete spell guide must fit at \(size)")
                let required = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude))
                XCTAssertLessThanOrEqual(required.height, label.bounds.height + 1)
            }
            let text = labels.compactMap(\.text).joined(separator: " ")
            for invocation in [
                "Z:", "O:", "V:", "still", "Star", "W:", "Alan", "Albert", "Patronus", "Lumos", "Revelio", "Nyan",
            ] {
                XCTAssertTrue(text.localizedCaseInsensitiveContains(invocation), invocation)
            }
            let image = UIGraphicsImageRenderer(size: size).image { stage.layer.render(in: $0.cgContext) }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Wand guide \(Int(size.width)) by \(Int(size.height))"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        stage.setMode(.bow)
        XCTAssertTrue(guide.isHidden)
        stage.setMode(.wand)
        XCTAssertFalse(guide.isHidden)
        var waiting = RunSnapshot()
        waiting.hasStarted = false
        stage.showRun(waiting)
        XCTAssertTrue(guide.isHidden)
        var ended = RunSnapshot()
        ended.isGameOver = true
        stage.showRun(ended)
        XCTAssertTrue(guide.isHidden)
    }

}
