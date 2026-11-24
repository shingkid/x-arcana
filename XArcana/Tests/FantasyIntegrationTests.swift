import SceneKit
import XCTest

@testable import XArcana

final class FantasyIntegrationTests: XCTestCase {
    func testVoiceCommandsHandlePunctuationAndOnlyConsumeEachPhraseOnce() {
        var parser = VoiceCommandParser()
        XCTAssertEqual(parser.consume("Cast"), [.cast])
        XCTAssertEqual(parser.consume("Cast"), [])
        XCTAssertEqual(parser.consume("Cast, shoot. Albert, I summon"), [.shoot, .summonAlbert])
        XCTAssertEqual(parser.consume("Cast, shoot. Albert, I summon thee!"), [])
        XCTAssertEqual(parser.consume("Cast, shoot. Albert, I summon thee! Alan, I summon thee."), [.summonAlan])
        XCTAssertEqual(
            parser.consume("Cast, shoot. Albert, I summon thee! Alan, I summon thee. Albert, I summon thee."),
            [.summonAlbert])
        var unrelated = VoiceCommandParser()
        XCTAssertEqual(unrelated.consume("shooting stars castaway Alana"), [])
        var shortened = VoiceCommandParser()
        XCTAssertEqual(shortened.consume("please cast"), [.cast])
        XCTAssertEqual(shortened.consume("cast shoot"), [.shoot])
        var expanded = VoiceCommandParser()
        XCTAssertEqual(expanded.consume("cast"), [.cast])
        XCTAssertEqual(expanded.consume("please cast"), [])
        var timed = VoiceCommandParser()
        XCTAssertEqual(timed.consume("cast", wordTimes: [(NSRange(location: 0, length: 4), 0.6)]), [.cast])
        XCTAssertEqual(timed.consume("please cast", wordTimes: [(NSRange(location: 7, length: 4), 0.6)]), [])
        // The recognizer corrected an earlier word, but a new command still has its own audio time.
        XCTAssertEqual(timed.consume("cat shoot", wordTimes: [(NSRange(location: 4, length: 5), 1.4)]), [.shoot])
    }

    func testShortSummonsAndUtilityVoicesDoNotRepeatAsTranscriptionGrows() {
        var parser = VoiceCommandParser()
        XCTAssertEqual(parser.consume("Albert", wordTimes: [(NSRange(location: 0, length: 6), 1)]), [.summonAlbert])
        XCTAssertEqual(
            parser.consume(
                "Albert I summon thee",
                wordTimes: [
                    (NSRange(location: 0, length: 6), 1), (NSRange(location: 7, length: 1), 1.4),
                    (NSRange(location: 9, length: 6), 1.6), (NSRange(location: 16, length: 4), 2),
                ]), [])
        XCTAssertEqual(parser.consume("Alan", wordTimes: [(NSRange(location: 0, length: 4), 3)]), [.summonAlan])
        var phrases = VoiceCommandParser()
        XCTAssertEqual(
            phrases.consume("Alan. Albert. Summon demon. Expecto Patronum. Lumos! Revelio!"),
            [.summonAlan, .summonAlbert, .summonPatronus, .lumos, .revelio])
        XCTAssertTrue(phrases.consume("Alan. Albert. Summon demon. Expecto Patronum. Lumos! Revelio!").isEmpty)
    }

    @MainActor
    func testSpokenModesNeverAttackAndOnlyBowReleaseShoots() throws {
        let encounter = Encounter(startsImmediately: true, defaults: nil)
        encounter.stage.frame = CGRect(x: 0, y: 0, width: 640, height: 360)
        encounter.stage.layoutIfNeeded()
        encounter.start()
        defer { encounter.stop() }
        let root = encounter.room.scene.rootNode
        func count(_ name: String) -> Int {
            var total = 0
            root.enumerateChildNodes { node, _ in if node.name == name { total += 1 } }
            return total
        }
        encounter.handleVoice(.shoot)
        XCTAssertEqual(encounter.fightingMode, .bow)
        XCTAssertEqual(count("Flying arrow"), 0)
        XCTAssertEqual(count("Magic bolt"), 0)
        encounter.endDrawing()
        XCTAssertEqual(count("Flying arrow"), 0)
        encounter.beginDrawing()
        XCTAssertTrue(encounter.isHolding)
        XCTAssertEqual(count("Flying arrow"), 0)
        encounter.endDrawing()
        XCTAssertFalse(encounter.isHolding)
        XCTAssertEqual(count("Flying arrow"), 1)
        encounter.endDrawing()
        XCTAssertEqual(count("Flying arrow"), 1)
        encounter.beginDrawing()
        encounter.endDrawing()
        XCTAssertFalse(encounter.status.contains("Lift"))
        XCTAssertEqual(count("Flying arrow"), 1)
        encounter.beginDrawing()
        encounter.handleVoice(.cast)
        XCTAssertFalse(encounter.isHolding)
        XCTAssertEqual(encounter.fightingMode, .wand)
        encounter.endDrawing()
        XCTAssertEqual(count("Flying arrow"), 1)
        XCTAssertEqual(count("Magic bolt"), 0)
        encounter.beginDrawing()
        encounter.handleVoice(.shoot)
        XCTAssertFalse(encounter.isHolding)
        encounter.endDrawing()
        XCTAssertEqual(count("Flying arrow"), 1)
    }

    @MainActor
    func testWandAndBowAimAtTheVisibleRunePointAcrossViewports() throws {
        let room = GameWorld()
        let prop = WandPresentation(camera: room.camera)
        let view = SCNView()
        view.scene = room.scene
        view.pointOfView = room.camera
        for size in [CGSize(width: 1280, height: 720), CGSize(width: 384, height: 240)] {
            view.frame.size = size
            view.layoutIfNeeded()
            _ = view.snapshot()
            prop.updateViewport(size: size)
            for mode in [WandPresentation.Mode.wand, .bow] {
                prop.setMode(mode)
                for aim in [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.8, y: 0.7)] {
                    prop.update(aim: aim, isDrawing: true)
                    SCNTransaction.flush()
                    let screen = view.projectPoint(prop.aimingNode.worldPosition)
                    XCTAssertEqual(CGFloat(screen.x), aim.x * size.width, accuracy: 2)
                    XCTAssertEqual(CGFloat(screen.y), aim.y * size.height, accuracy: 2)
                    XCTAssertEqual(prop.mode, mode)
                }
                prop.cast()
                prop.shoot()
                prop.update(aim: CGPoint(x: 0.5, y: 0.5), isDrawing: false)
                XCTAssertEqual(prop.mode, mode)
            }
        }
    }

    @MainActor
    func testAllCompanionsAccumulateAndStayAfterThirtySeconds() throws {
        let room = GameWorld()
        XCTAssertNil(room.errorMessage)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = room.scene
        renderer.pointOfView = room.camera
        let size = CGSize(width: 960, height: 540)
        _ = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .none)
        var portraits: [SCNNode] = []
        for index in 0..<2 {
            for (name, x) in [("Alan", Float(-1.2)), ("Albert", Float(1.2))] {
                let node = try XCTUnwrap(
                    PortraitSummons.summon(
                        name: name, in: room.scene,
                        at: SIMD3(x, 0, Float(index) * -2), facing: room.camera))
                portraits.append(node)
            }
            room.performRune(.summon, at: SIMD3(-1.5, 0, -3.5))
            room.performRune(.patronus, at: SIMD3(1, 0, -3.5))
        }
        _ = renderer.snapshot(atTime: 0.01, with: size, antialiasingMode: .none)
        _ = renderer.snapshot(atTime: 1, with: size, antialiasingMode: .none)
        let image = renderer.snapshot(atTime: 31, with: size, antialiasingMode: .multisampling2X)
        XCTAssertEqual(room.scene.rootNode.childNodes.filter { $0.name == "SummonedDemon" }.count, 2)
        XCTAssertEqual(room.scene.rootNode.childNodes.filter { $0.name == "Patronus" }.count, 2)
        XCTAssertEqual(room.scene.rootNode.childNodes.filter { $0.name?.hasPrefix("summon.") == true }.count, 4)
        XCTAssertEqual(Set(portraits.compactMap(\.name)).count, 4)
        XCTAssertTrue(portraits.allSatisfy { $0.parent != nil && $0.presentation.opacity > 0.9 })
        attach(image, name: "Persistent Alan Albert demons and stags")
    }

    @MainActor
    func testDetailedSummonsImportAndPatronusHasASpiritMaterial() throws {
        let room = GameWorld()
        room.performRune(.summon, at: SIMD3(-1, 0, -1))
        room.performRune(.patronus, at: SIMD3(1, 0, -1))
        let demon = try XCTUnwrap(room.scene.rootNode.childNode(withName: "DemonSculpture", recursively: true))
        let stag = try XCTUnwrap(room.scene.rootNode.childNode(withName: "SilverStag", recursively: true))
        for model in [demon, stag] {
            var triangles = 0
            var mappedSurfaces = 0
            model.enumerateChildNodes { node, _ in
                guard let geometry = node.geometry else { return }
                triangles += geometry.elements.filter { $0.primitiveType == .triangles }.reduce(0) {
                    $0 + $1.primitiveCount
                }
                mappedSurfaces += geometry.materials.filter { $0.normal.contents != nil }.count
            }
            XCTAssertGreaterThan(triangles, 40_000)
            XCTAssertLessThan(triangles, 65_000)
            XCTAssertGreaterThan(mappedSurfaces, 0)
        }
        var spiritMaterials = 0
        stag.enumerateChildNodes { node, _ in
            for material in node.geometry?.materials ?? [] {
                XCTAssertNotNil(material.shaderModifiers?[.fragment])
                XCTAssertFalse(material.writesToDepthBuffer)
                XCTAssertLessThan(material.transparency, 1)
                spiritMaterials += 1
            }
        }
        XCTAssertGreaterThan(spiritMaterials, 0)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = room.scene
        renderer.pointOfView = room.camera
        _ = renderer.snapshot(atTime: 0, with: CGSize(width: 1280, height: 720), antialiasingMode: .none)
        attach(
            renderer.snapshot(atTime: 1.5, with: CGSize(width: 1280, height: 720), antialiasingMode: .multisampling2X),
            name: "Detailed demon and ethereal Patronus in the hall")
    }

    @MainActor
    func testSeeThroughHidesRoomAndKeepsCompanionsAndHeadTracking() throws {
        let room = GameWorld()
        let originalPoint = room.camera.simdWorldPosition
        let alan = try XCTUnwrap(
            PortraitSummons.summon(
                name: "Alan", in: room.scene,
                at: SIMD3(1, 0, 0), facing: room.camera))
        room.setSeeThrough(true)
        XCTAssertTrue(room.isSeeThrough)
        XCTAssertEqual(room.scene.background.contents as? UIColor, .clear)
        XCTAssertFalse(alan.isHidden)
        XCTAssertNotNil(alan.parent)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = room.scene
        renderer.pointOfView = room.camera
        _ = renderer.snapshot(atTime: 0, with: CGSize(width: 960, height: 540), antialiasingMode: .none)
        attach(
            renderer.snapshot(atTime: 1, with: CGSize(width: 960, height: 540), antialiasingMode: .none),
            name: "See-through AR output with transparent background")
        room.setHeadPose(HeadSample(yaw: 0, pitch: 0, roll: 0).orientation, at: 0)
        let home = room.camera.simdOrientation
        room.setHeadPose(HeadSample(yaw: 0.4, pitch: 0, roll: 0).orientation, at: 1)
        XCTAssertNotEqual(room.camera.simdOrientation, home)
        XCTAssertEqual(room.camera.simdWorldPosition, originalPoint)
        XCTAssertEqual(simd_distance(room.castingPoint(), originalPoint), 2, accuracy: 0.001)
        room.setSeeThrough(false)
        XCTAssertEqual(room.camera.camera?.fieldOfView, 74)
        XCTAssertNotNil(alan.parent)
    }

    @MainActor
    func testNewHallWeaponsAndZombiesRenderTogether() throws {
        let room = GameWorld()
        XCTAssertNil(room.errorMessage)
        let prop = WandPresentation(camera: room.camera)
        prop.updateViewport(size: CGSize(width: 1280, height: 720))
        let combat = Combat(scene: room.scene, camera: room.camera, floorY: 0, defaults: nil)
        XCTAssertEqual(combat.remaining, 1)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = room.scene
        renderer.pointOfView = room.camera
        func frame(_ time: TimeInterval) -> UIImage {
            renderer.snapshot(atTime: time, with: CGSize(width: 1280, height: 720), antialiasingMode: .multisampling2X)
        }
        combat.update(at: 0)
        _ = frame(0)
        let wandImage = frame(0.1)
        attach(wandImage, name: "Fantasy hall wand and NPC zombies")
        prop.setMode(.bow)
        let bowImage = frame(0.2)
        XCTAssertNotEqual(wandImage.pngData(), bowImage.pngData())
        attach(bowImage, name: "Persistent archery mode")
        prop.setMode(.wand)
        for step in 1...840 { combat.update(at: Double(step) / 60) }
        _ = frame(14)
        attach(frame(14.7), name: "NPC faces and names on arriving zombies")
    }

    @MainActor
    func testFinalBossAndContinuousHealthBarRenderAtFullAndHalfHealth() throws {
        let room = GameWorld()
        let state = SurvivalState(defaults: nil)
        for _ in 1..<10 { state.nextWave() }
        let combat = Combat(scene: room.scene, camera: room.camera, environment: room.environment, state: state)
        let root = try XCTUnwrap(room.scene.rootNode.childNode(withName: "Undead horde", recursively: false))
        let boss = try XCTUnwrap(root.childNodes.compactMap { $0 as? Combat.CombatantNode }.first)
        XCTAssertEqual(boss.kind, .demonBoss)
        XCTAssertEqual(boss.health, 30)
        XCTAssertNotNil(boss.childNode(withName: "DemonSculpture", recursively: true))
        boss.simdPosition = SIMD3(0, room.environment.floorY + 0.7, 0)
        room.camera.simdPosition = SIMD3(0, room.environment.floorY + 2.8, 7.8)
        room.camera.simdLook(at: SIMD3(0, room.environment.floorY + 2.7, 0))
        let renderer = SCNRenderer(device: try XCTUnwrap(MTLCreateSystemDefaultDevice()), options: nil)
        renderer.scene = room.scene
        renderer.pointOfView = room.camera
        let size = CGSize(width: 1920, height: 1080)
        SCNTransaction.flush()
        _ = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .none)
        let full = renderer.snapshot(atTime: 0.1, with: size, antialiasingMode: .multisampling2X)
        XCTAssertEqual(full.cgImage?.width, 1920)
        XCTAssertFalse(boss.healthBar.isHidden)
        attach(full, name: "Level 10 Demon boss - 30 of 30 HP")
        boss.setHealth(15)
        SCNTransaction.flush()
        let half = renderer.snapshot(atTime: 0.2, with: size, antialiasingMode: .multisampling2X)
        XCTAssertEqual(boss.health, 15)
        XCTAssertFalse(boss.healthBar.isHidden)
        XCTAssertNotEqual(full.pngData(), half.pngData())
        attach(half, name: "Level 10 Demon boss - 15 of 30 HP")
        withExtendedLifetime(combat) {}
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
