import CoreMotion
import SceneKit
import XCTest

@testable import XArcana

final class SpellTests: XCTestCase {
    private let firstPoint = SIMD3<Float>(-2.5, 1.4, -4)
    private let nextPoint = SIMD3<Float>(3, 2.1, -7)

    @MainActor
    func testDrawnInkAndReleasedSpellStayAtTheOriginalLookDirection() throws {
        let room = GameWorld()
        let stage = GameStage(room: room)
        stage.frame = CGRect(x: 0, y: 0, width: 640, height: 360)
        stage.layoutIfNeeded()
        room.setHeadPose(HeadSample(yaw: 0, pitch: 0, roll: 0).orientation, at: 1)
        let location = room.castingPoint()
        let ink = [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.6, y: 0.6)]
        stage.showRune(points: ink, at: location)
        let trail = try XCTUnwrap(stage.subviews.compactMap { $0 as? RuneTrail }.first)
        XCTAssertFalse(trail.isHidden)
        let initialX = trail.center.x
        XCTAssertEqual(initialX, stage.bounds.midX, accuracy: 2)
        XCTAssertEqual(trail.center.y, stage.bounds.midY, accuracy: 2)
        var spell = Spell()
        spell.begin(at: location, angles: .zero, time: 0)
        drawCircle(into: &spell)
        room.setHeadPose(HeadSample(yaw: 0.3, pitch: 0, roll: 0).orientation, at: 2)
        SCNTransaction.flush()
        stage.showRune(points: ink, at: location)
        XCTAssertGreaterThan(trail.center.x, initialX + 25)
        room.setHeadPose(HeadSample(yaw: 0.3, pitch: 0.17, roll: 0).orientation, at: 3)
        SCNTransaction.flush()
        stage.showRune(points: ink, at: location)
        XCTAssertGreaterThan(trail.center.y, stage.bounds.midY + 15)
        XCTAssertEqual(spell.release(angles: .zero, at: 1.23), CastRune(kind: .fireball, point: location))
    }

    private func drawCircle(into spell: inout Spell) {
        for step in 1...72 {
            let t = Double(step) / 60
            let angle = Double(step) * 2 * .pi / 72
            let angles = SIMD2(Float(0.25 * (cos(angle) - 1)), Float(0.25 * sin(angle)))
            spell.sample(angles, at: t)
        }
    }

    func testOnlyReleaseCastsOnceAtTouchDownPoint() {
        var spell = Spell()
        drawCircle(into: &spell)
        XCTAssertFalse(spell.isHolding)
        XCTAssertNil(spell.release(angles: .zero, at: 1.23))
        spell.begin(at: firstPoint, angles: .zero, time: 0)
        spell.begin(at: nextPoint, angles: nil, time: 0.01)
        drawCircle(into: &spell)
        XCTAssertTrue(spell.isHolding)
        XCTAssertEqual(spell.point, firstPoint)
        XCTAssertEqual(spell.release(angles: .zero, at: 1.23), CastRune(kind: .fireball, point: firstPoint))
        XCTAssertFalse(spell.isHolding)
        XCTAssertNil(spell.release(angles: .zero, at: 1.24))
    }

    func testInterruptedHoldIsSilentAndShortTapCastsSparksOnce() {
        var spell = Spell()
        spell.begin(at: firstPoint, angles: .zero, time: 0)
        drawCircle(into: &spell)
        spell.cancel()
        XCTAssertNil(spell.release(angles: .zero, at: 1.23))
        spell.begin(at: nextPoint, angles: .zero, time: 2)
        XCTAssertEqual(spell.release(angles: .zero, at: 2.01), CastRune(kind: nil, point: nextPoint))
        XCTAssertNil(spell.release(angles: .zero, at: 2.02))
        XCTAssertNil(spell.point)
    }

    func testUnrecognizedMotionReleasesAnimatedSparksAtTheOriginalPoint() throws {
        let room = GameWorld()
        let location = room.castingPoint()
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = room.scene
        renderer.pointOfView = room.camera
        func frame(at time: TimeInterval) -> UIImage {
            renderer.snapshot(atTime: time, with: CGSize(width: 480, height: 270), antialiasingMode: .none)
        }
        let before = frame(at: 0)
        var spell = Spell()
        spell.begin(at: location, angles: .zero, time: 0)
        // A back-and-forth scrub has no overall direction and forms no rune.
        for step in 1...30 {
            spell.sample(SIMD2(Float(min(step, 30 - step)) * 0.02, 0), at: Double(step) / 60)
        }
        let cast = try XCTUnwrap(spell.release(angles: .zero, at: 0.52))
        XCTAssertNil(cast.kind)
        let root = room.scene.rootNode
        let count = root.childNodes.count
        room.performRune(cast.kind, at: cast.point)
        let burst = try XCTUnwrap(root.childNodes.last)
        XCTAssertEqual(root.childNodes.count, count + 1)
        XCTAssertEqual(burst.simdPosition, location)
        XCTAssertTrue(burst.hasActions)
        XCTAssertGreaterThan(burst.childNodes.filter { $0.geometry != nil && $0.hasActions }.count, 3)
        let flash = frame(at: 0.01)
        let scattered = frame(at: 0.24)
        XCTAssertNotEqual(before.pngData(), flash.pngData())
        XCTAssertNotEqual(flash.pngData(), scattered.pngData())
        let capture = XCTAttachment(image: scattered)
        capture.name = "Sparks after a freehand cast"
        capture.lifetime = .keepAlways
        add(capture)
    }

    func testVoiceOnlyEffectsRenderDirectlyWithoutDirectionalGestureMappings() throws {
        let gestures: [(RuneKind, SIMD2<Float>)] = [
            (.revelio, SIMD2(-0.19, 0.045)), (.lumos, SIMD2(0.035, 0.16)), (.patronus, SIMD2(-0.04, -0.17)),
        ]
        for (kind, direction) in gestures {
            let room = GameWorld()
            let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
            renderer.scene = room.scene
            renderer.pointOfView = room.camera
            func frame(_ time: TimeInterval) -> UIImage {
                renderer.snapshot(atTime: time, with: CGSize(width: 768, height: 432), antialiasingMode: .none)
            }
            let before = frame(0)
            var spell = Spell()
            spell.begin(at: room.castingPoint(), angles: .zero, time: 0)
            for step in 1...18 {
                spell.sample(direction * (Float(step) / 18), at: Double(step) / 60)
            }
            let released = try XCTUnwrap(spell.release(angles: direction, at: 0.31))
            XCTAssertNil(released.kind)
            room.performRune(kind, at: released.point)
            _ = frame(0.01)
            _ = frame(0.4)
            let visible = frame(1.3)
            XCTAssertNotEqual(before.pngData(), visible.pngData(), kind.title)
            if kind == .lumos {
                // Sample the top half, away from the wand glow. The room surfaces must brighten.
                XCTAssertGreaterThan(try upperRoomBrightness(visible), try upperRoomBrightness(before) + 4)
                attachImage(before, name: "World before Lumos")
            }
            attachImage(visible, name: "\(kind.title) in the archive")
        }
    }

    @MainActor
    func testPreviewShowsReadyShieldWithoutChangingSceneOrReleasing() {
        let room = GameWorld()
        let count = room.scene.rootNode.childNodes.count
        var spell = Spell()
        spell.begin(at: firstPoint, angles: .zero, time: 0)
        for frame in 1...60 { spell.sample(.zero, at: Double(frame) / 60) }
        XCTAssertEqual(spell.preview, .shield)
        XCTAssertTrue(spell.isHolding)
        XCTAssertEqual(spell.point, firstPoint)
        XCTAssertEqual(room.scene.rootNode.childNodes.count, count)
        XCTAssertEqual(spell.release(angles: .zero, at: 1.01), CastRune(kind: .shield, point: firstPoint))
        XCTAssertNil(spell.preview)
        XCTAssertNil(spell.release(angles: .zero, at: 1.02))
    }

    func testPreviewOfDrawnRuneClearsOnCancellationAndCannotCastTwice() {
        var spell = Spell()
        spell.begin(at: firstPoint, angles: .zero, time: 0)
        drawCircle(into: &spell)
        XCTAssertEqual(spell.preview, .fireball)
        XCTAssertTrue(spell.isHolding)
        spell.cancel()
        XCTAssertNil(spell.preview)
        XCTAssertNil(spell.release(angles: .zero, at: 1.23))
    }

    private func upperRoomBrightness(_ image: UIImage) throws -> Double {
        let full = try XCTUnwrap(image.cgImage)
        let upperHalf = try XCTUnwrap(
            full.cropping(
                to: CGRect(
                    x: 0, y: 0, width: full.width,
                    height: full.height / 2)))
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 32, height: 16, bitsPerComponent: 8,
                bytesPerRow: 32, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.interpolationQuality = .low
        context.draw(upperHalf, in: CGRect(x: 0, y: 0, width: 32, height: 16))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return (0..<512).reduce(0.0) { $0 + Double(pixels[$1]) } / 512
    }

    private func attachImage(_ image: UIImage, name: String) {
        let capture = XCTAttachment(image: image)
        capture.name = name
        capture.lifetime = .keepAlways
        add(capture)
    }

    func testTopEdgeAnglesFollowPhoneRotation() throws {
        let angle = Double.pi / 12
        let straight = CMRotationMatrix(m11: 1, m12: 0, m13: 0, m21: 0, m22: 1, m23: 0, m31: 0, m32: 0, m33: 1)
        let right = CMRotationMatrix(
            m11: cos(angle), m12: -sin(angle), m13: 0,
            m21: sin(angle), m22: cos(angle), m23: 0, m31: 0, m32: 0, m33: 1)
        let up = CMRotationMatrix(
            m11: 1, m12: 0, m13: 0, m21: 0, m22: cos(angle), m23: sin(angle),
            m31: 0, m32: -sin(angle), m33: cos(angle))
        let center = try XCTUnwrap(WandMotion.angles(from: straight))
        let rightAngles = try XCTUnwrap(WandMotion.angles(from: right))
        let upAngles = try XCTUnwrap(WandMotion.angles(from: up))
        XCTAssertEqual(center.x, 0, accuracy: 1e-6)
        XCTAssertEqual(center.y, 0, accuracy: 1e-6)
        XCTAssertEqual(rightAngles.x, angle, accuracy: 1e-6)
        XCTAssertEqual(rightAngles.y, 0, accuracy: 1e-6)
        XCTAssertEqual(upAngles.x, 0, accuracy: 1e-6)
        XCTAssertEqual(upAngles.y, angle, accuracy: 1e-6)
    }
}
