import SceneKit
import UIKit
import XCTest

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
