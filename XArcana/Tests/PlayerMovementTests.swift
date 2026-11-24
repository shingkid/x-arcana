import SceneKit
import XCTest
import simd

@testable import XArcana

final class PlayerMovementTests: XCTestCase {
    private func world() throws -> GameWorld {
        try GameWorld(environment: .fantasy, scene: SCNScene())
    }

    func testWASDMovesAtSameSpeedDiagonallyAndPreservesEyeHeight() throws {
        let straight = try world()
        let diagonal = try world()
        let origin = straight.camera.simdPosition
        for _ in 0..<60 {
            straight.moveDesktop(.init(move: SIMD2(0, 1)), deltaTime: 1.0 / 60)
            diagonal.moveDesktop(.init(move: SIMD2(1, 1)), deltaTime: 1.0 / 60)
        }
        XCTAssertEqual(origin.z - straight.camera.simdPosition.z, 1.4, accuracy: 0.001)
        XCTAssertEqual(simd_distance(origin, diagonal.camera.simdPosition), 1.4, accuracy: 0.001)
        XCTAssertEqual(diagonal.camera.simdPosition.y, origin.y)
    }

    func testForwardMovementFollowsHorizontalViewEvenWhenLookingUp() throws {
        let room = try world()
        room.camera.simdOrientation =
            simd_quatf(angle: .pi / 2, axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: 0.7, axis: SIMD3(1, 0, 0))
        let origin = room.camera.simdPosition
        room.moveDesktop(.init(move: SIMD2(0, 1)), deltaTime: 0.05)
        XCTAssertEqual(room.camera.simdPosition.x, origin.x - 0.07, accuracy: 0.0001)
        XCTAssertEqual(room.camera.simdPosition.y, origin.y)
        XCTAssertEqual(room.camera.simdPosition.z, origin.z, accuracy: 0.0001)
    }

    func testLookArrowsClampPitchAndCenterDoesNotTeleportPlayer() throws {
        let room = try world()
        for _ in 0..<100 { room.moveDesktop(.init(look: SIMD2(1, 1)), deltaTime: 0.05) }
        let forward = room.camera.simdOrientation.act(SIMD3<Float>(0, 0, -1))
        XCTAssertEqual(forward.y, sin(Float.pi / 3), accuracy: 0.001)
        room.movePlayer(by: SIMD3(0.5, 0, -0.5))
        let position = room.camera.simdPosition
        room.centerView()
        XCTAssertEqual(room.camera.simdPosition, position)
        room.resetPlayerPosition()
        XCTAssertEqual(room.camera.simdPosition, room.environment.camera.position.vector)
    }

    func testBoundsIncludeStartingEyeAndRejectInvalidMovement() throws {
        let room = try world()
        let origin = room.camera.simdPosition
        room.movePlayer(by: .zero)
        XCTAssertEqual(room.camera.simdPosition, origin)
        room.movePlayer(by: SIMD3(.infinity, 0, -1))
        room.moveDesktop(.init(move: SIMD2(.nan, 1)), deltaTime: 0.05)
        room.moveDesktop(.init(move: SIMD2(1, 1)), deltaTime: -.infinity)
        XCTAssertEqual(room.camera.simdPosition, origin)
        room.movePlayer(by: SIMD3(100, 100, -100))
        XCTAssertEqual(room.camera.simdPosition, SIMD3(2.2, origin.y, -4.8))
        room.movePlayer(by: SIMD3(-100, 0, 100))
        XCTAssertEqual(room.camera.simdPosition, SIMD3(-2.2, origin.y, origin.z))
    }

    func testHeadTrackingTakesPriorityOverKeyboard() throws {
        let room = try world()
        room.setHeadPose(simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)), at: 0)
        let origin = room.camera.simdPosition
        let orientation = room.camera.simdOrientation
        room.moveDesktop(.init(move: SIMD2(1, 1), look: SIMD2(1, 1)), deltaTime: 0.05)
        XCTAssertEqual(room.camera.simdPosition, origin)
        XCTAssertEqual(room.camera.simdOrientation.vector, orientation.vector)
    }

    func testHeldKeyboardRequiresReleaseAfterPauseOrRestart() {
        var input = DesktopMovement()
        let held = DesktopMovementInput(move: SIMD2(0, 1))
        XCTAssertEqual(input.update(held, enabled: true), held)
        XCTAssertTrue(input.update(held, enabled: false).isNeutral)
        XCTAssertTrue(input.update(held, enabled: true).isNeutral)
        XCTAssertTrue(input.update(.init(), enabled: true).isNeutral)
        XCTAssertEqual(input.update(held, enabled: true), held)
        input.reset()
        XCTAssertTrue(input.update(held, enabled: true).isNeutral)
    }

    private func sample(
        session: UUID, x: Float = 0, z: Float = 0, heading: Float = 0,
        quality: PhonePositionSample.Quality = .tracking
    ) -> PhonePositionSample {
        PhonePositionSample(session: session, x: x, y: 1.2, z: z, heading: heading, quality: quality)
    }

    func testMeasuredPhoneWalkingMovesForwardAndIgnoresSmallJitter() {
        var walking = PhoneWalking()
        let session = UUID()
        var total = SIMD3<Float>.zero
        for i in 0...30 {
            total += walking.update(
                sample(session: session, z: -Float(i) / 30), at: Double(i) / 30, viewHeading: 0, enabled: true)
        }
        XCTAssertLessThan(total.z, -0.85)
        XCTAssertGreaterThan(total.z, -1.01)
        XCTAssertEqual(total.x, 0, accuracy: 0.001)
        XCTAssertEqual(total.y, 0)
        walking.reset()
        total = .zero
        for i in 0...60 {
            total += walking.update(
                sample(session: session, x: i.isMultiple(of: 2) ? 0.005 : -0.005), at: Double(i) / 30, viewHeading: 0,
                enabled: true)
        }
        XCTAssertEqual(total, .zero)
    }

    func testPhoneCoordinateAlignmentAndDrawingRebaseDoNotRotateWithHeadTurns() {
        var walking = PhoneWalking()
        let session = UUID()
        _ = walking.update(sample(session: session, heading: .pi / 2), at: 0, viewHeading: 0, enabled: true)
        var total = SIMD3<Float>.zero
        for i in 1...10 {
            total += walking.update(
                sample(session: session, x: -Float(i) / 30, heading: .pi / 2), at: Double(i) / 30, viewHeading: 0,
                enabled: true)
        }
        XCTAssertLessThan(total.z, -0.2)
        XCTAssertEqual(total.x, 0, accuracy: 0.001)
        _ = walking.update(sample(session: session, x: -1, quality: .suspended), at: 0.4, viewHeading: 0, enabled: true)
        XCTAssertEqual(
            walking.update(
                sample(session: session, x: -2, heading: .pi / 2), at: 0.5, viewHeading: .pi / 2, enabled: true), .zero)
        let moved = walking.update(
            sample(session: session, x: -2.1, heading: .pi / 2), at: 0.6, viewHeading: .pi / 2, enabled: true)
        XCTAssertLessThan(moved.z, -0.025)
        XCTAssertEqual(moved.x, 0, accuracy: 0.001)
    }

    func testTrackingLossTeleportSessionChangeAndStaleSamplesCannotMovePlayer() {
        var walking = PhoneWalking()
        let session = UUID()
        _ = walking.update(sample(session: session), at: 1, viewHeading: 0, enabled: true)
        XCTAssertEqual(walking.update(sample(session: session, z: -0.1), at: 1, viewHeading: 0, enabled: true), .zero)
        XCTAssertEqual(walking.update(sample(session: session, z: -10), at: 1.05, viewHeading: 0, enabled: true), .zero)
        XCTAssertEqual(
            walking.update(sample(session: session, z: -11, quality: .limited), at: 1.1, viewHeading: 0, enabled: true),
            .zero)
        XCTAssertEqual(walking.update(sample(session: session, z: -12), at: 1.15, viewHeading: 0, enabled: true), .zero)
        XCTAssertEqual(walking.update(sample(session: session, z: -12.1), at: 2, viewHeading: 0, enabled: true), .zero)
        XCTAssertEqual(walking.update(sample(session: UUID(), z: 5), at: 0, viewHeading: 0, enabled: true), .zero)
    }

    func testDisabledWalkingAndInvalidSamplesAreIgnored() {
        var walking = PhoneWalking()
        let session = UUID()
        _ = walking.update(sample(session: session), at: 0, viewHeading: 0, enabled: true)
        XCTAssertEqual(
            walking.update(sample(session: session, z: -0.1), at: 0.1, viewHeading: 0, enabled: false), .zero)
        XCTAssertEqual(walking.update(sample(session: session, z: -0.2), at: 0.2, viewHeading: 0, enabled: true), .zero)
        XCTAssertEqual(walking.update(sample(session: session, z: .nan), at: 0.3, viewHeading: 0, enabled: true), .zero)
    }

    @MainActor
    func testHostMovementPausesAndRestartRestoresSpawnPosition() {
        let game = Encounter(startsImmediately: true, defaults: nil)
        game.start()
        defer { game.stop() }
        let origin = game.room.camera.simdPosition
        let held = DesktopMovementInput(move: SIMD2(1, 0))
        game.updateDesktopMovement(held, deltaTime: 0.05)
        XCTAssertGreaterThan(game.room.camera.simdPosition.x, origin.x)
        game.simulationActive = false
        let paused = game.room.camera.simdPosition
        game.updateDesktopMovement(held, deltaTime: 0.05)
        XCTAssertEqual(game.room.camera.simdPosition, paused)
        game.simulationActive = true
        game.updateDesktopMovement(held, deltaTime: 0.05)
        XCTAssertEqual(game.room.camera.simdPosition, paused)
        game.restartRun()
        XCTAssertEqual(game.room.camera.simdPosition, origin)
        game.updateDesktopMovement(held, deltaTime: 0.05)
        XCTAssertEqual(game.room.camera.simdPosition, origin)
    }

    func testShieldVisualFollowsPlayerMovement() throws {
        let room = try world()
        let combat = Combat(scene: room.scene, camera: room.camera, environment: room.environment, defaults: nil)
        XCTAssertTrue(combat.shield())
        let shield = try XCTUnwrap(room.scene.rootNode.childNode(withName: "Player shield", recursively: true))
        room.movePlayer(by: SIMD3(0.6, 0, -0.6))
        combat.update(at: 0)
        combat.update(at: 0.05)
        XCTAssertEqual(shield.simdWorldPosition, room.camera.simdWorldPosition + SIMD3(0, -0.55, 0))
    }

    @MainActor
    func testPhoneWalkingContinuesWithoutActiveKeyboardAndStopsDuringDrawing() {
        let game = Encounter(startsImmediately: true, defaults: nil)
        game.start()
        defer { game.stop() }
        game.phoneWalkingEnabled = true
        let session = UUID()
        let origin = game.room.camera.simdPosition
        for frame in 0...30 {
            game.resetDesktopInput()
            game.receive(
                WandInput(
                    kind: .position, timestamp: Double(frame) / 30,
                    position: sample(session: session, z: -Float(frame) / 30)))
            game.updatePhoneMovement()
        }
        XCTAssertLessThan(game.room.camera.simdPosition.z, origin.z - 0.85)
        game.beginDrawing()
        let drawingPosition = game.room.camera.simdPosition
        for frame in 31...60 {
            game.receive(
                WandInput(
                    kind: .position, timestamp: Double(frame) / 30,
                    position: sample(session: session, z: -Float(frame) / 30)))
            game.updatePhoneMovement()
        }
        XCTAssertEqual(game.room.camera.simdPosition, drawingPosition)
    }

    @MainActor
    func testBufferedPhonePacketsCannotReplayWalkingInOneFrame() {
        let game = Encounter(startsImmediately: true, defaults: nil)
        game.start()
        defer { game.stop() }
        game.phoneWalkingEnabled = true
        let session = UUID()
        let origin = game.room.camera.simdPosition
        game.receive(WandInput(kind: .position, timestamp: 0, position: sample(session: session)))
        game.updatePhoneMovement()
        for frame in 1...30 {
            game.receive(
                WandInput(
                    kind: .position, timestamp: Double(frame) / 30,
                    position: sample(session: session, z: -Float(frame) / 30)))
        }
        XCTAssertEqual(game.room.camera.simdPosition, origin)
        game.updatePhoneMovement()
        XCTAssertEqual(game.room.camera.simdPosition, origin)
    }
}
