import SceneKit
import UIKit
import XCTest

@testable import XArcana

final class CharacterAnimationTests: XCTestCase {
    func testAssetsContainWeightedMovingLimbs() throws {
        for (name, directory, clip, joint, minimumBones) in [
            ("Demon", "Creatures", "clawCombo", "leftHand", 58),
            ("Stag", "Creatures", "run", "mouth", 31),
            ("PortraitCharacter", "Fantasy", "slap", "rightHand", 20),
            ("AlanCharacter", "Fantasy", "slap", "rightHand", 20),
        ] {
            let model = try load(name, directory: directory)
            var skins: [SCNSkinner] = []
            model.enumerateChildNodes { node, _ in if let skin = node.skinner { skins.append(skin) } }
            XCTAssertFalse(skins.isEmpty, name)
            XCTAssertTrue(skins.allSatisfy { $0.bones.count >= minimumBones && $0.boneWeights.vectorCount > 0 }, name)
            let minimumVertices = directory == "Fantasy" ? 1000 : 20000
            XCTAssertGreaterThan(
                skins.reduce(0) { $0 + $1.boneWeights.vectorCount }, minimumVertices, "Retain a complete weighted body")
            let hand = try XCTUnwrap(CharacterAnimation.attachment(joint, on: model))
            XCTAssertTrue(CharacterAnimation.sample(clip, at: 0, on: model))
            let start = hand.simdWorldPosition
            let root = model.simdTransform
            XCTAssertTrue(CharacterAnimation.sample(clip, at: 0.35, on: model))
            XCTAssertGreaterThan(simd_distance(start, hand.simdWorldPosition), 0.05, name)
            XCTAssertEqual(model.simdTransform, root, "Animation must not translate the combat root")
        }
    }

    func testClonedActorsNeverShareBonesOrChangeEachOthersPose() throws {
        for (name, directory, clip, joint) in [
            ("Demon", "Creatures", "clawCombo", "rightHand"),
            ("Stag", "Creatures", "run", "mouth"),
            ("PortraitCharacter", "Fantasy", "slap", "rightHand"),
            ("AlanCharacter", "Fantasy", "slap", "rightHand"),
        ] {
            let template = try load(name, directory: directory)
            let first = ScenePerformance.independentClone(of: template)
            let second = ScenePerformance.independentClone(of: template)
            var firstBones = Set<ObjectIdentifier>()
            first.enumerateChildNodes { node, _ in
                for bone in node.skinner?.bones ?? [] { firstBones.insert(ObjectIdentifier(bone)) }
            }
            second.enumerateChildNodes { node, _ in
                for bone in node.skinner?.bones ?? [] {
                    XCTAssertFalse(firstBones.contains(ObjectIdentifier(bone)), name)
                }
            }
            let control = try XCTUnwrap(CharacterAnimation.attachment(joint, on: second))
            let before = control.simdTransform
            XCTAssertTrue(CharacterAnimation.sample(clip, at: 0.35, on: first))
            XCTAssertEqual(control.simdTransform, before, name)
            CharacterAnimation.play("idle", on: first, loop: true)
            CharacterAnimation.play(clip, on: first)
            var playback = [SCNNode]()
            func collect(_ node: SCNNode) {
                if node.actionKeys.contains(where: { $0.hasPrefix("CharacterAnimation.playback") }) {
                    playback.append(node)
                }
            }
            collect(first)
            first.enumerateChildNodes { node, _ in collect(node) }
            XCTAssertEqual(playback.count, 1)
            CharacterAnimation.setPaused(true, on: first)
            let key = try XCTUnwrap(playback.first?.actionKeys.first { $0.hasPrefix("CharacterAnimation.playback") })
            XCTAssertEqual(playback.first?.action(forKey: key)?.speed, 0)
            CharacterAnimation.stop(on: first)
            XCTAssertNil(playback.first?.action(forKey: key))
        }
    }

    func testAlanRacketFollowsHandAndKeepsFloorHaloSeparate() throws {
        let room = GameWorld()
        let scene = room.scene
        let camera = room.camera
        let alan = try XCTUnwrap(PortraitSummons.summon(name: "Alan", in: scene, at: SIMD3(0, 0, -3), facing: camera))
        var torsoPlanes = 0
        alan.enumerateChildNodes { node, _ in if node.geometry is SCNPlane { torsoPlanes += 1 } }
        XCTAssertEqual(torsoPlanes, 0, "The public placeholder must not have portrait planes")
        let hand = try XCTUnwrap(CharacterAnimation.attachment("rightHand", on: alan))
        let racket = try XCTUnwrap(hand.childNode(withName: "AlanBadmintonRacket", recursively: false))
        var racketVertices = racket.geometry?.sources(for: .vertex).first?.vectorCount ?? 0
        racket.enumerateChildNodes { node, _ in
            racketVertices += node.geometry?.sources(for: .vertex).first?.vectorCount ?? 0
        }
        XCTAssertGreaterThan(racketVertices, 800)
        let halo = try XCTUnwrap(alan.childNode(withName: "PortraitHalo", recursively: false))
        let floorTransform = halo.simdTransform
        CharacterAnimation.stop(on: alan)
        _ = CharacterAnimation.sample("slap", at: 0, on: alan)
        let resting = racket.simdWorldTransform
        _ = CharacterAnimation.sample("slap", at: 0.35, on: alan)
        XCTAssertNotEqual(racket.simdWorldTransform, resting)
        XCTAssertEqual(halo.simdTransform, floorTransform)
        alan.removeAllActions()
        alan.opacity = 1
        alan.simdPosition = .zero
        alan.eulerAngles.y = 0
        camera.camera?.fieldOfView = 42
        camera.position = SCNVector3(2.5, 1.7, 4.0)
        camera.look(at: SCNVector3(0, 0.95, 0))
        scene.rootNode.addChildNode(camera)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        let image = renderer.snapshot(
            atTime: 0, with: CGSize(width: 1000, height: 1000), antialiasingMode: .multisampling4X)
        let data = try XCTUnwrap(image.pngData())
        let output = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("XArcana-Alan-racket.png")
        try data.write(to: output)
        print("ALAN_RACKET_RENDER", output.path)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Alan articulated racket contact pose"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAlbertPlaceholderRetainsRigAndLargerRuntimeScale() throws {
        let room = GameWorld()
        let albert = try XCTUnwrap(
            PortraitSummons.summon(
                name: "Albert", in: room.scene,
                at: SIMD3(0, 0, -2), facing: room.camera))
        let model = try XCTUnwrap(albert.childNode(withName: "PortraitBody", recursively: false))
        XCTAssertEqual(model.simdScale, SIMD3<Float>(repeating: 1.2))
        var meshCount = 0
        var portraitPlanes = 0
        albert.enumerateChildNodes { node, _ in
            if node.skinner != nil { meshCount += 1 }
            if node.geometry is SCNPlane { portraitPlanes += 1 }
        }
        XCTAssertEqual(meshCount, 1, "Use one generated weighted placeholder body")
        XCTAssertEqual(portraitPlanes, 0, "Do not add private portrait overlays")
        CharacterAnimation.stop(on: albert)
        XCTAssertTrue(CharacterAnimation.sample("slam", at: 0.35, on: albert))
        albert.removeAllActions()
        albert.opacity = 1
        albert.simdPosition = SIMD3(-0.85, 0, 0)
        albert.eulerAngles.y = 0
        let alan = try XCTUnwrap(
            PortraitSummons.summon(
                name: "Alan", in: room.scene,
                at: SIMD3(0.85, 0, 0), facing: room.camera))
        alan.removeAllActions()
        alan.opacity = 1
        alan.simdPosition = SIMD3(0.85, 0, 0)
        alan.eulerAngles.y = 0
        CharacterAnimation.stop(on: alan)
        _ = CharacterAnimation.sample("slap", at: 0.35, on: alan)
        room.camera.camera?.fieldOfView = 45
        room.camera.position = SCNVector3(3.0, 2.0, 5.3)
        room.camera.look(at: SCNVector3(0, 1, 0))
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = room.scene
        renderer.pointOfView = room.camera
        let image = renderer.snapshot(
            atTime: 0, with: CGSize(width: 1200, height: 1000), antialiasingMode: .multisampling4X)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Public Albert placeholder and Alan racket"
        attachment.lifetime = .keepAlways
        add(attachment)
        _ = CharacterAnimation.sample("idle", at: 0, on: alan)
        room.camera.camera?.fieldOfView = 30
        room.camera.position = SCNVector3(0.85, 1.61, 0.85)
        room.camera.look(at: SCNVector3(0.85, 1.60, 0))
        let closeup = renderer.snapshot(
            atTime: 0, with: CGSize(width: 900, height: 900), antialiasingMode: .multisampling4X)
        let face = XCTAttachment(image: closeup)
        face.name = "Alan public geometric placeholder"
        face.lifetime = .keepAlways
        add(face)

    }

    private func load(_ name: String, directory: String) throws -> SCNNode {
        let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "usdz", subdirectory: directory))
        let scene = try SCNScene(url: url, options: [.convertToYUp: true])
        XCTAssertTrue(CharacterAnimation.install(on: scene.rootNode, asset: name, directory: directory))
        return scene.rootNode
    }
}
