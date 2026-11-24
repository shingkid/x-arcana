import SceneKit
import UIKit
import XCTest

@testable import XArcana

final class EnvironmentTests: XCTestCase {
    func testBundledFantasyMatchesExistingWorldContract() throws {
        let definition = try EnvironmentDefinition.load()
        XCTAssertEqual(definition, .fantasy)
        XCTAssertNoThrow(try definition.sceneURL())
        let room = GameWorld()
        XCTAssertNil(room.errorMessage)
        XCTAssertEqual(room.environment, definition)
        XCTAssertEqual(room.camera.simdPosition, definition.camera.position.vector)
    }

    func testAlternateBundleLoadsItsOwnSceneCameraLightingAndFloor() throws {
        let (bundle, definition, directory) = try alternateBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertEqual(try EnvironmentDefinition.load(named: "courtyard", bundle: bundle), definition)
        XCTAssertEqual(try EnvironmentDefinition.configuredName(bundle: bundle), "courtyard")
        let room = GameWorld(bundle: bundle)
        XCTAssertNil(room.errorMessage)
        XCTAssertEqual(room.environment.id, "test-courtyard")
        XCTAssertNotNil(room.scene.rootNode.childNode(withName: "Alternate floor", recursively: true))
        XCTAssertEqual(room.camera.simdPosition, SIMD3(8, 2.9, 3.3))
        XCTAssertEqual(room.camera.camera?.fieldOfView, 61)
        let lights = room.scene.rootNode.childNodes.compactMap(\.light)
        XCTAssertEqual(lights.count, 1)
        XCTAssertEqual(lights.first?.intensity, 140)
        room.setSeeThrough(true)
        XCTAssertEqual(room.camera.camera?.fieldOfView, 40)
        room.setSeeThrough(false)
        XCTAssertEqual(room.camera.camera?.fieldOfView, 61)
    }

    func testAlternateCombatUsesConfiguredSpawnsBoundsFloorAndProjectileExtent() throws {
        let definition = try alternateDefinition()
        let scene = SCNScene()
        let camera = SCNNode()
        camera.simdPosition = definition.camera.position.vector
        scene.rootNode.addChildNode(camera)
        let combat = Combat(scene: scene, camera: camera, environment: definition, defaults: nil)
        combat.update(at: 0)
        let enemy = try XCTUnwrap(
            scene.rootNode.childNode(withName: "Undead horde", recursively: false)?
                .childNodes.compactMap { $0 as? Combat.CombatantNode }.first)
        XCTAssertEqual(enemy.simdPosition, definition.enemySpawns[0].vector)
        for step in 1...300 { combat.update(at: Double(step) / 60) }
        XCTAssertTrue(definition.movementBounds.contains(enemy.simdPosition))
        XCTAssertEqual(enemy.simdPosition.y, definition.floorY)
        // X=8 lies outside the old hall's projectile boundary. A valid shot must survive there.
        XCTAssertTrue(combat.shoot(toward: camera.simdPosition + SIMD3(0, 4, -6)))
        combat.update(at: 5.05)
        XCTAssertNotNil(scene.rootNode.childNode(withName: "Flying arrow", recursively: true))
        let ally = SCNNode()
        ally.simdPosition = SIMD3(100, -9, 100)
        XCTAssertEqual(combat.summon(kind: .alan) { ally }, .summoned)
        XCTAssertEqual(ally.simdPosition, SIMD3(9, 1.25, 2))
    }

    func testAlternateCompanionsUseSelectedBoundsDuringPursuit() throws {
        let definition = try alternateDefinition()
        let scene = SCNScene()
        let combat = SummonCombat(scene: scene, environment: definition)
        let ally = SCNNode()
        ally.simdPosition = SIMD3(8, 0, 0)
        combat.register(kind: .alan, node: ally)
        let target = SCNNode()
        target.simdPosition = SIMD3(50, 2.25, 50)
        scene.rootNode.addChildNode(target)
        for _ in 0..<400 {
            _ = combat.update(deltaTime: 0.05, targets: [.init(node: target, center: target.simdPosition)])
        }
        XCTAssertTrue(definition.movementBounds.contains(ally.simdPosition))
        XCTAssertEqual(ally.simdPosition.y, definition.floorY)
        XCTAssertGreaterThan(ally.simdPosition.x, 8.9)
        XCTAssertGreaterThan(ally.simdPosition.z, 1.9)
    }

    func testPortraitPlacementUsesAlternateFloorBeforeCombatRegistration() throws {
        let definition = try alternateDefinition()
        let scene = SCNScene()
        let camera = SCNNode()
        camera.simdPosition = definition.camera.position.vector
        let ally = try XCTUnwrap(
            PortraitSummons.summon(
                name: "Alan", in: scene, at: SIMD3(8, 0, 0),
                facing: camera, environment: definition))
        XCTAssertEqual(ally.simdPosition.y, definition.floorY)
        XCTAssertTrue(definition.movementBounds.contains(ally.simdPosition))
    }

    func testInvalidConfigurationAndMissingAssetReportFailure() throws {
        let (bundle, original, directory) = try alternateBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        var definition = original
        definition.movementBounds.maxX = definition.movementBounds.minX
        XCTAssertThrowsError(try definition.validated())
        definition = original
        definition.enemySpawns = []
        XCTAssertThrowsError(try definition.validated())
        definition = original
        definition.enemySpawns[0].y = 0
        XCTAssertThrowsError(try definition.validated())
        definition = original
        definition.camera.lookAt = definition.camera.position
        XCTAssertThrowsError(try definition.validated())
        definition = original
        definition.lights[0].intensity = -.infinity
        XCTAssertThrowsError(try definition.validated())
        definition = original
        definition.scene.name = "Missing"
        XCTAssertThrowsError(try GameWorld(environment: definition, bundle: bundle)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Missing.scn"))
        }
        let missing = GameWorld(environmentNamed: "missing", bundle: bundle)
        XCTAssertTrue(try XCTUnwrap(missing.errorMessage).contains("Environments/missing.json"))
        let configuration = directory.appendingPathComponent("Environments/courtyard.json")
        try Data("{broken".utf8).write(to: configuration)
        let invalid = GameWorld(environmentNamed: "courtyard", bundle: bundle)
        XCTAssertTrue(try XCTUnwrap(invalid.errorMessage).contains("configuration is invalid"))
    }

    func testInvalidEnvironmentSelectionFailsWithoutLoadingAnotherScene() throws {
        let (bundle, _, directory) = try alternateBundle(environmentName: 42)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try EnvironmentDefinition.configuredName(bundle: bundle))
        let room = GameWorld(bundle: bundle)
        XCTAssertTrue(try XCTUnwrap(room.errorMessage).contains("XArcanaEnvironment"))
        XCTAssertNil(room.scene.rootNode.childNode(withName: "Alternate floor", recursively: true))
    }

    @MainActor
    func testSeeThroughRendersZombiesCompanionsAndEffectsForBothEnvironments() throws {
        let (bundle, definition, directory) = try alternateBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let worlds = [GameWorld(), try GameWorld(environment: definition, bundle: bundle)]
        for room in worlds {
            XCTAssertNil(room.errorMessage)
            let environmentRoots = room.scene.rootNode.childNodes.filter { $0.camera == nil && $0.light == nil }
            let originalMaterials = environmentRoots.flatMap { root -> [SCNMaterial] in
                var materials = root.geometry?.materials ?? []
                root.enumerateChildNodes { node, _ in materials += node.geometry?.materials ?? [] }
                return materials
            }
            room.setSeeThrough(true)
            let renderer = SCNRenderer(device: try XCTUnwrap(MTLCreateSystemDefaultDevice()), options: nil)
            renderer.scene = room.scene
            renderer.pointOfView = room.camera
            let empty = try pixels(renderer)
            XCTAssertTrue(
                stride(from: 3, to: empty.count, by: 4).allSatisfy { empty[$0] == 0 },
                "An empty AR frame must retain transparent alpha.")
            let combat = Combat(scene: room.scene, camera: room.camera, environment: room.environment, defaults: nil)
            let enemy = try XCTUnwrap(
                room.scene.rootNode.childNode(withName: "Undead horde", recursively: false)?
                    .childNodes.compactMap { $0 as? Combat.CombatantNode }.first)
            enemy.simdPosition = room.camera.simdWorldPosition + SIMD3(-0.32, -1.65, -3)
            let zombie = try pixels(renderer)
            XCTAssertTrue(
                stride(from: 3, to: zombie.count, by: 4).contains { zombie[$0] > 0 },
                "The zombie must render nontransparent actor pixels.")
            XCTAssertGreaterThan(
                difference(empty, zombie), 0.001, "The zombie must produce visible pixels in optical AR.")
            let ally = SCNNode()
            let companionBody = SCNNode(geometry: SCNSphere(radius: 0.22))
            let companionMaterial = SCNMaterial()
            companionMaterial.lightingModel = .constant
            companionMaterial.diffuse.contents = UIColor.green
            companionBody.geometry?.materials = [companionMaterial]
            companionBody.position.y = 1.3
            ally.addChildNode(companionBody)
            ally.simdPosition = room.camera.simdWorldPosition + SIMD3(0.45, -0.8, -2)
            XCTAssertEqual(combat.summon(kind: .alan) { ally }, .summoned)
            let summoned = try pixels(renderer)
            XCTAssertGreaterThan(difference(zombie, summoned), 0.0001)
            XCTAssertTrue(combat.shield())
            XCTAssertNotNil(room.scene.rootNode.childNode(withName: "Player shield", recursively: true))
            room.setTransfigurationPhase(3)
            XCTAssertTrue(environmentRoots.allSatisfy(\.isHidden))
            XCTAssertFalse(room.camera.isHidden)
            XCTAssertFalse(enemy.isHidden)
            XCTAssertFalse(ally.isHidden)
            let actorsWithRainbow = try pixels(renderer)
            room.setTransfigurationPhase(nil)
            XCTAssertLessThan(
                difference(actorsWithRainbow, try pixels(renderer)), 0.001,
                "Hidden environment materials must not obscure actors.")
            room.setSeeThrough(false)
            XCTAssertTrue(environmentRoots.allSatisfy { !$0.isHidden })
            var restored: [SCNMaterial] = []
            for root in environmentRoots {
                restored += root.geometry?.materials ?? []
                root.enumerateChildNodes { node, _ in restored += node.geometry?.materials ?? [] }
            }
            XCTAssertEqual(restored.count, originalMaterials.count)
            for (actual, original) in zip(restored, originalMaterials) { XCTAssertTrue(actual === original) }
        }
    }

    @MainActor
    private func pixels(_ renderer: SCNRenderer) throws -> [UInt8] {
        SCNTransaction.flush()
        XCTAssertTrue(renderer.prepare(try XCTUnwrap(renderer.scene), shouldAbortBlock: nil))
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 320, height: 200), antialiasingMode: .none)
        let cg = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: 160 * 100 * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(
                CGContext(
                    data: buffer.baseAddress, width: 160, height: 100,
                    bitsPerComponent: 8, bytesPerRow: 160 * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 160, height: 100))
        }
        return pixels
    }

    private func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        Double(zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(a.count * 255)
    }

    private func alternateDefinition() throws -> EnvironmentDefinition {
        try JSONDecoder().decode(
            EnvironmentDefinition.self,
            from: Data(
                #"""
                {
                  "id":"test-courtyard", "displayName":"Test courtyard",
                  "scene":{"name":"Courtyard","fileExtension":"scn","subdirectory":"Scenes"},
                  "floorY":1.25,
                  "movementBounds":{"minX":7,"maxX":9,"minZ":-2,"maxZ":2},
                  "projectileBounds":{"minX":6,"maxX":10,"minZ":-5,"maxZ":6},
                  "enemySpawns":[{"x":8,"y":1.25,"z":-1.2}],
                  "camera":{"position":{"x":8,"y":2.9,"z":3.3},
                            "lookAt":{"x":8,"y":2.9,"z":-1},"horizontalFieldOfView":61},
                  "background":{"red":0.2,"green":0.1,"blue":0.05},
                  "lights":[{"kind":"ambient","color":{"red":1,"green":1,"blue":1},"intensity":140,
                             "position":{"x":8,"y":4,"z":0},"attenuationStart":0.2,"attenuationEnd":8,"falloffExponent":2}]
                }
                """#.utf8)
        ).validated()
    }

    private func alternateBundle(environmentName: Any = "courtyard") throws -> (Bundle, EnvironmentDefinition, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Environment-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Environments"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Scenes"), withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "test.xarcana.environment.\(UUID().uuidString)",
            "CFBundlePackageType": "BNDL", "XArcanaEnvironment": environmentName,
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: directory.appendingPathComponent("Info.plist"))
        let definition = try alternateDefinition()
        try JSONEncoder().encode(definition).write(to: directory.appendingPathComponent("Environments/courtyard.json"))
        let scene = SCNScene()
        let floor = SCNNode(geometry: SCNBox(width: 2, height: 0.1, length: 4, chamferRadius: 0))
        floor.name = "Alternate floor"
        floor.simdPosition = SIMD3(8, 1.2, 0)
        scene.rootNode.addChildNode(floor)
        XCTAssertTrue(
            scene.write(
                to: directory.appendingPathComponent("Scenes/Courtyard.scn"),
                options: nil, delegate: nil, progressHandler: nil))
        return (try XCTUnwrap(Bundle(path: directory.path)), definition, directory)
    }
}
