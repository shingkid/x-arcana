import SceneKit
import UIKit
import XCTest
import simd

@testable import XArcana

final class SpellVisualTests: XCTestCase {
    func testRepeatedEffectsAreBoundedAndDoNotRemoveActorsOrProjectiles() {
        let scene = SCNScene()
        let actor = SCNNode()
        actor.name = "Lightning impact"  // A matching name is not enough to identify a visual.
        let projectile = SCNNode()
        projectile.name = "Combat fireball"
        scene.rootNode.addChildNode(actor)
        scene.rootNode.addChildNode(projectile)
        for index in 0..<40 {
            if index.isMultiple(of: 2) {
                SpellVisuals.fireball(at: .zero, radius: 2, floorY: 0, on: scene.rootNode)
            } else {
                SpellVisuals.lightning(at: .zero, on: scene.rootNode)
            }
            XCTAssertLessThanOrEqual(scene.rootNode.childNodes.count, 14)
        }
        XCTAssertTrue(actor.parent === scene.rootNode)
        XCTAssertTrue(projectile.parent === scene.rootNode)
        let effects = scene.rootNode.childNodes.filter { $0 !== actor && $0 !== projectile }
        XCTAssertEqual(effects.count, 12)
        XCTAssertTrue(effects.allSatisfy { $0.action(forKey: "visual.cleanup") != nil })
        var lights = 0
        for effect in effects {
            effect.enumerateChildNodes { node, _ in
                if node.light != nil { lights += 1 }
                if node.geometry != nil {
                    XCTAssertFalse(node.castsShadow, "Transient effects must not add shadow work")
                }
            }
        }
        XCTAssertEqual(lights, 0)
    }

    func testDevilWingsKeepWeightedBodyAndSmallIndependentArticulation() throws {
        let room = GameWorld()
        let demon = try XCTUnwrap(
            RuneEffects.summon(in: room.scene, at: SIMD3(0, 0, -2), facing: room.camera.simdWorldPosition))
        let body = try XCTUnwrap(demon.childNode(withName: "DemonSculpture", recursively: true))
        let chest = try XCTUnwrap(CharacterAnimation.attachment("chest", on: demon))
        var weightedVertices = 0
        var wingTriangles = 0
        body.enumerateChildNodes { node, _ in
            if let skin = node.skinner { weightedVertices += skin.boneWeights.vectorCount }
            if node.name == "DevilWingMembrane" || node.name == "DevilWingFinger" {
                wingTriangles += node.geometry?.elements.reduce(0) { $0 + $1.primitiveCount } ?? 0
            }
        }
        XCTAssertGreaterThan(weightedVertices, 20000)
        XCTAssertGreaterThanOrEqual(wingTriangles, 14)
        XCTAssertLessThan(wingTriangles, 300, "Accessories must remain small beside the original body")
        for side in ["L", "R"] {
            let mount = try XCTUnwrap(body.childNode(withName: "DevilWingMount." + side, recursively: true))
            XCTAssertTrue(mount.parent === chest)
            XCTAssertNotNil(mount.childNode(withName: "DevilWing." + side, recursively: false))
        }
        let left = try XCTUnwrap(body.childNode(withName: "DevilWing.L", recursively: true))
        let right = try XCTUnwrap(body.childNode(withName: "DevilWing.R", recursively: true))
        _ = CharacterAnimation.sample("idle", at: 0.1, on: demon)
        DemonFlight.sample(on: demon, time: 0.1)
        let initial = left.simdEulerAngles.z
        _ = CharacterAnimation.sample("idle", at: 0.4, on: demon)
        DemonFlight.sample(on: demon, time: 0.4)
        if !UIAccessibility.isReduceMotionEnabled { XCTAssertNotEqual(initial, left.simdEulerAngles.z) }
        XCTAssertEqual(left.simdEulerAngles.z, -right.simdEulerAngles.z, accuracy: 0.0001)
        XCTAssertGreaterThan(body.simdPosition.y, 0.5)
        XCTAssertEqual(demon.simdPosition.y, 0)
    }

    func testNativeFlyingDevilAndPatronusEntryRenders() throws {
        let room = GameWorld()
        let demon = try XCTUnwrap(
            RuneEffects.summon(in: room.scene, at: SIMD3(0, 0, -2), facing: room.camera.simdWorldPosition))
        demon.simdPosition = SIMD3(0, 0, 0)
        demon.eulerAngles.y = 0
        _ = CharacterAnimation.sample("idle", at: 0.3, on: demon)
        DemonFlight.sample(on: demon, time: 0.3)
        room.camera.position = SCNVector3(3.2, 2.5, 5.8)
        room.camera.look(at: SCNVector3(0, 1.5, 0))
        room.camera.camera?.fieldOfView = 48
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = room.scene
        renderer.pointOfView = room.camera
        attachRender(renderer, time: 0, name: "Native winged devil in flight")
        _ = CharacterAnimation.sample("slam", at: 0.35, on: demon)
        DemonFlight.sample(on: demon, time: 0.35, slamTime: 0.35)
        attachRender(renderer, time: 0.1, name: "Native devil ground contact before takeoff")
        demon.removeFromParentNode()
        room.camera.position = SCNVector3(0, 1.65, 4.8)
        room.camera.eulerAngles = SCNVector3Zero
        room.camera.camera?.fieldOfView = 74
        let patronus = try XCTUnwrap(RuneEffects.patronus(in: room.scene, at: SIMD3(0, 0, -2), from: room.camera))
        let relative = room.camera.simdConvertPosition(patronus.simdWorldPosition, from: nil)
        XCTAssertGreaterThan(relative.x, 1)
        XCTAssertLessThan(relative.z, -1)
        XCTAssertEqual(patronus.simdPosition.y, 0)
        let combat = SummonCombat(scene: room.scene)
        combat.register(kind: .patronus, node: patronus)
        CharacterAnimation.stop(on: patronus)
        XCTAssertTrue(CharacterAnimation.sample("run", at: 0.12, on: patronus))
        attachRender(renderer, time: 0.2, name: "Native Patronus lower-right foreground entry")
        let a = SCNNode()
        let b = SCNNode()
        room.scene.rootNode.addChildNode(a)
        room.scene.rootNode.addChildNode(b)
        let targets = [
            SummonCombat.Target(node: a, center: SIMD3(-0.3, 1, -1.8)),
            SummonCombat.Target(node: b, center: SIMD3(0.4, 1, -2)),
        ]
        for _ in 0..<12 { _ = combat.update(deltaTime: 0.05, targets: targets) }
        XCTAssertTrue(CharacterAnimation.sample("run", at: 0.36, on: patronus))
        attachRender(renderer, time: 0.3, name: "Native ethereal stag curving toward cluster")
        combat.reset()
        XCTAssertNil(patronus.parent)
    }

    func testPatronusEntranceFollowsTurnedCameraAndRetainsWeightedRun() throws {
        let room = GameWorld()
        room.camera.position = SCNVector3(1, 1.65, 1)
        room.camera.eulerAngles.y = .pi / 2
        let node = try XCTUnwrap(RuneEffects.patronus(in: room.scene, at: SIMD3(-3, 0, 0), from: room.camera))
        let relative = room.camera.simdConvertPosition(node.simdWorldPosition, from: nil)
        XCTAssertEqual(relative.x, 1.25, accuracy: 0.001)
        XCTAssertEqual(relative.z, -1.65, accuracy: 0.001)
        let mouth = try XCTUnwrap(CharacterAnimation.attachment("mouth", on: node))
        CharacterAnimation.stop(on: node)
        XCTAssertTrue(CharacterAnimation.sample("run", at: 0, on: node))
        let before = mouth.simdWorldPosition
        XCTAssertTrue(CharacterAnimation.sample("run", at: 0.25, on: node))
        XCTAssertGreaterThan(simd_distance(before, mouth.simdWorldPosition), 0.05)
        XCTAssertEqual(node.simdPosition.y, 0)
    }

    private func attachRender(_ renderer: SCNRenderer, time: TimeInterval, name: String) {
        let image = renderer.snapshot(
            atTime: time, with: CGSize(width: 1200, height: 800), antialiasingMode: .multisampling4X)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNativeSpellPeakRendersAndTransientCleanup() throws {
        for spell in ["lightning", "fireball", "ice", "shield"] {
            let room = GameWorld()
            let camera = room.camera
            camera.position = SCNVector3(0, 1.65, 4.2)
            camera.eulerAngles = SCNVector3Zero
            let shield = SCNNode()
            switch spell {
            case "lightning": SpellVisuals.lightning(at: SIMD3(0, 1.3, 0), on: room.scene.rootNode)
            case "fireball": SpellVisuals.fireball(at: SIMD3(0, 1.1, 0), radius: 2, floorY: 0, on: room.scene.rootNode)
            case "ice": SpellVisuals.ice(from: SIMD3(0.1, 1.4, 3), direction: SIMD3(0, 0, -1), on: room.scene.rootNode)
            default:
                shield.position = SCNVector3(0, 1, 0)
                room.scene.rootNode.addChildNode(shield)
                SpellVisuals.shieldActivation(on: shield)
                SpellVisuals.shieldContact(on: shield, at: SIMD3(0.8, 1.2, 0.8))
            }
            let renderer = SCNRenderer(device: nil, options: nil)
            renderer.scene = room.scene
            renderer.pointOfView = camera
            renderer.isPlaying = true
            _ = renderer.snapshot(atTime: 0, with: CGSize(width: 8, height: 8), antialiasingMode: .none)
            let image = renderer.snapshot(
                atTime: 0.16, with: CGSize(width: 960, height: 540), antialiasingMode: .multisampling2X)
            let capture = XCTAttachment(image: image)
            capture.name = "Native \(spell) peak"
            capture.lifetime = .keepAlways
            add(capture)
            for frame in 4...34 {
                _ = renderer.snapshot(
                    atTime: Double(frame) * 0.05, with: CGSize(width: 8, height: 8), antialiasingMode: .none)
            }
            var active = 0
            room.scene.rootNode.enumerateChildNodes { node, _ in
                if node.action(forKey: "visual.cleanup") != nil { active += 1 }
            }
            XCTAssertEqual(active, 0, "\(spell) must leave the central view clear after its impact")
        }
    }
}
