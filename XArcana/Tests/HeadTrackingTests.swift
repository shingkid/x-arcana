import SceneKit
import XCTest
import simd

@testable import XArcana

final class HeadTrackingTests: XCTestCase {
    func testHorizonLockRemovesRollWithoutChangingLookDirection() {
        let previous = simd_quatf(angle: 0.3, axis: SIMD3<Float>(0, 1, 0))
        for roll in [Float(0), .pi / 2, -.pi / 2, .pi] {
            let pose =
                simd_quatf(angle: 0.7, axis: SIMD3<Float>(0, 1, 0))
                * simd_quatf(angle: 0.4, axis: SIMD3<Float>(1, 0, 0))
                * simd_quatf(angle: roll, axis: SIMD3<Float>(0, 0, 1))
            let fixed = HeadHorizon.upright(pose, previous: previous)
            XCTAssertLessThan(simd_distance(pose.act(SIMD3(0, 0, -1)), fixed.act(SIMD3(0, 0, -1))), 0.0001)
            XCTAssertGreaterThan(fixed.act(SIMD3(0, 1, 0)).y, 0.9)
        }
        let vertical = simd_quatf(angle: Float.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        let fixed = HeadHorizon.upright(vertical, previous: previous)
        XCTAssertTrue(fixed.vector.x.isFinite)
        XCTAssertGreaterThan(fixed.act(SIMD3(0, 1, 0)).y, 0)
    }

    func testBridgeStatusDoesNotPretendToBeHeadMotion() throws {
        let waiting = Data(#"{"state":"waitingForGlasses"}"#.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(HeadBridgeStatus.self, from: waiting).message,
            "Mac connected · plug Air 2 into Mac")
        XCTAssertThrowsError(try JSONDecoder().decode(HeadSample.self, from: waiting))
        let streaming = Data(#"{"state":"streaming"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(HeadBridgeStatus.self, from: streaming).message)
    }

    @MainActor
    func testHeadTurnChangesRenderedRoom() throws {
        let room = GameWorld()
        XCTAssertNil(room.errorMessage)
        let stage = GameStage(room: room)
        stage.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        stage.layoutIfNeeded()
        let view = try XCTUnwrap(stage.subviews.compactMap { $0 as? SCNView }.first)
        XCTAssertTrue(view.rendersContinuously)
        room.setHeadPose(HeadSample(yaw: 0, pitch: 0, roll: 0).orientation, at: 0)
        let forward = try XCTUnwrap(view.snapshot().pngData())
        room.setHeadPose(HeadSample(yaw: 0.6, pitch: 0, roll: 0).orientation, at: 0.4)
        let turned = try XCTUnwrap(view.snapshot().pngData())
        XCTAssertNotEqual(forward, turned)
        for (name, image) in [("Level neutral view", forward), ("Head turned left", turned)] {
            let attachment = XCTAttachment(data: image, uniformTypeIdentifier: "public.png")
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testReducedGainIsIndependentOfPacketRateAndSuppressesJitter() {
        let target = simd_quatf(angle: 0.6, axis: SIMD3<Float>(0, 1, 0))
        func filtered(rate: Int) -> simd_quatf {
            var filter = HeadPoseFilter()
            filter.reset(at: 0)
            for i in 1...rate { _ = filter.update(target, at: Double(i) / Double(rate)) }
            return filter.orientation
        }
        let slow = filtered(rate: 30)
        let fast = filtered(rate: 120)
        XCTAssertEqual(slow.angle, 0.6 - 0.12 * sin(0.6), accuracy: 0.002)
        XCTAssertEqual(slow.angle, fast.angle, accuracy: 0.002)
        XCTAssertGreaterThan(slow.axis.y, 0.99)
        var filter = HeadPoseFilter()
        filter.reset(at: 0)
        for i in 1...120 {
            let jitter: Float = i.isMultiple(of: 2) ? 0.0004 : -0.0004
            _ = filter.update(simd_quatf(angle: jitter, axis: SIMD3(0, 1, 0)), at: Double(i) / 120)
        }
        XCTAssertEqual(filter.orientation.imag, .zero)
        filter.reset(at: 1)
        let response = filter.update(target, at: 1.1)
        XCTAssertGreaterThan(response.angle, 0.6 * 0.88 * 0.85)
    }

    func testTurningPastBehindHasNoGainDiscontinuity() {
        var filter = HeadPoseFilter()
        filter.reset(at: 0)
        let before = filter.update(simd_quatf(angle: .pi - 0.01, axis: SIMD3(0, 1, 0)), at: 1)
        let after = filter.update(simd_quatf(angle: .pi + 0.01, axis: SIMD3(0, 1, 0)), at: 2)
        XCTAssertGreaterThan(abs(simd_dot(before.vector, after.vector)), cos(0.03 / 2))
    }

    func testBowedStartupReturnsToTheSameLevelView() throws {
        let level = GameWorld()
        let bowed = GameWorld()
        let neutral = try XCTUnwrap(
            HeadSample(
                yaw: 0, pitch: 0, roll: 0,
                gravityPitch: 0, gravityRoll: 0, heading: 0.7
            ).orientation)
        let down = try XCTUnwrap(
            HeadSample(
                yaw: 0, pitch: 0, roll: 0,
                gravityPitch: -0.55, gravityRoll: 0.08, heading: 0.7
            ).orientation)
        level.setHeadPose(neutral, gravityReferenced: true, at: 0)
        bowed.setHeadPose(down, gravityReferenced: true, at: 0)
        bowed.setHeadPose(down, gravityReferenced: true, at: 0.2)
        for i in 1...60 {
            let time = 0.2 + Double(i) / 60
            level.setHeadPose(neutral, gravityReferenced: true, at: time)
            bowed.setHeadPose(neutral, gravityReferenced: true, at: time)
        }
        XCTAssertGreaterThan(
            abs(
                simd_dot(
                    level.camera.simdOrientation.vector,
                    bowed.camera.simdOrientation.vector)), 0.99999)
        let forward = level.camera.simdOrientation.act(SIMD3<Float>(0, 0, -1))
        XCTAssertLessThan(abs(forward.y), 0.04)
        bowed.centerView()
        bowed.setHeadPose(neutral, gravityReferenced: true, at: 1.3)
        XCTAssertGreaterThan(
            abs(
                simd_dot(
                    level.camera.simdOrientation.vector,
                    bowed.camera.simdOrientation.vector)), 0.99999)
    }

    func testHeadDirectionRecenterAndInvalidSamples() {
        let room = GameWorld()
        let home = room.camera.simdOrientation
        let origin = room.camera.simdWorldPosition
        room.setHeadPose(HeadSample(yaw: 0.4, pitch: 0, roll: 0).orientation, at: 0)
        room.setHeadPose(HeadSample(yaw: 0.7, pitch: 0.12, roll: 0.08).orientation, at: 0.4)
        let delta = home.inverse * room.camera.simdOrientation
        XCTAssertGreaterThan(delta.imag.y, 0)
        XCTAssertGreaterThan(delta.imag.x, 0)
        #if targetEnvironment(macCatalyst)
            XCTAssertEqual(room.camera.simdOrientation.act(SIMD3(1, 0, 0)).y, 0, accuracy: 0.0001)
        #else
            XCTAssertGreaterThan(delta.imag.z, 0)
        #endif
        XCTAssertEqual(room.camera.simdWorldPosition, origin)
        room.centerView()
        XCTAssertGreaterThan(abs(simd_dot(home.vector, room.camera.simdOrientation.vector)), 0.99999)
        room.setHeadPose(nil)
        XCTAssertFalse(room.isHeadTracked)
        XCTAssertNil(HeadSample(yaw: .nan, pitch: 0, roll: 0).orientation)
        XCTAssertNil(HeadSample(yaw: 23, pitch: 0, roll: 0).orientation)
        XCTAssertNil(
            HeadSample(
                yaw: 0, pitch: 0, roll: 0,
                gravityPitch: .nan, gravityRoll: 0, heading: 0
            ).orientation)
    }

    func testGazeUsesNearestSurfaceAndIgnoresEffects() {
        let room = GameWorld()
        for node in room.scene.rootNode.childNodes where node !== room.camera { node.removeFromParentNode() }
        let origin = room.camera.simdWorldPosition
        let forward = room.camera.simdWorldOrientation.act(SIMD3<Float>(0, 0, -1))
        XCTAssertEqual(simd_distance(room.castingPoint(), origin + forward * 2), 0, accuracy: 0.001)
        let wall = SCNNode(geometry: SCNSphere(radius: 0.25))
        wall.simdPosition = origin + forward * 3
        room.scene.rootNode.addChildNode(wall)
        let near = SCNNode(geometry: SCNSphere(radius: 0.25))
        near.simdPosition = origin + forward * 1.5
        room.scene.rootNode.addChildNode(near)
        XCTAssertEqual(simd_distance(room.castingPoint(), origin), 1.01, accuracy: 0.02)
        near.categoryBitMask = 2
        XCTAssertEqual(simd_distance(room.castingPoint(), origin), 2.51, accuracy: 0.02)
        room.camera.simdOrientation *= simd_quatf(angle: .pi / 2, axis: SIMD3(0, 1, 0))
        XCTAssertEqual(simd_distance(room.castingPoint(), origin), 2, accuracy: 0.02)
    }

    func testWorldEffectFactoriesCanRenderAtAnEmptyWorldPoint() throws {
        for kind: RuneKind in [.zap, .fireball, .summon, .revelio, .lumos, .patronus] {
            let room = GameWorld()
            let root = room.scene.rootNode
            let point = room.camera.simdConvertPosition(SIMD3(0, 0, -1.5), to: nil)
            let effectParent = kind == .lumos ? room.camera : root
            let before = effectParent.childNodes.count
            room.performRune(kind, at: point)
            let effect = try XCTUnwrap(effectParent.childNodes.last)
            XCTAssertEqual(effectParent.childNodes.count, before + 1)
            switch kind {
            case .zap:
                XCTAssertEqual(effect.simdWorldPosition, point)
                XCTAssertNotNil(effect.light)
                XCTAssertEqual(effect.childNodes.filter { $0.geometry is SCNCylinder }.count, 4)
            case .fireball:
                XCTAssertEqual(effect.particleSystems?.count, 1)
                XCTAssertTrue(effect.hasActions)
            case .summon:
                XCTAssertEqual(effect.name, "SummonedDemon")
                room.performRune(kind, at: point + SIMD3(0.3, 0, 0))
                XCTAssertEqual(root.childNodes.count, before + 2)
                XCTAssertNotNil(effect.parent)
            case .patronus:
                XCTAssertEqual(effect.name, kind.title)
                room.performRune(kind, at: point + SIMD3(0.3, 0, 0))
                XCTAssertEqual(root.childNodes.filter { $0.name == kind.title }.count, 2)
                XCTAssertNotNil(effect.parent)
            case .revelio, .lumos:
                XCTAssertEqual(effect.name, kind.title)
                room.performRune(kind, at: point + SIMD3(0.3, 0, 0))
                XCTAssertEqual(effectParent.childNodes.filter { $0.name == kind.title }.count, 1)
            case .ice, .shield, .nyan:
                XCTFail("Combat owns resource-checked ice and shield effects")
            }
        }
    }
}
