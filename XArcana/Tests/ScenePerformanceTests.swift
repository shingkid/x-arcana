import SceneKit
import XCTest

@testable import XArcana

final class ScenePerformanceTests: XCTestCase {
    func testNearestFourLightsRestoreWhenCameraMovesWithoutRemovingCompanions() {
        let scene = SCNScene()
        let camera = SCNNode()
        scene.rootNode.addChildNode(camera)
        let companions = (0..<8).map { index -> SCNNode in
            let node = companion(index.isMultiple(of: 2) ? "Patronus" : "SummonedDemon", in: scene)
            node.position.x = Float(index)
            return node
        }
        let lights = companions.map { $0.light! }
        let performance = ScenePerformance(scene: scene, camera: camera)
        performance.update(at: 0)
        XCTAssertEqual(companions.filter { $0.light != nil }.count, 4)
        XCTAssertTrue(companions[0].light === lights[0])
        XCTAssertNil(companions[7].light)
        camera.position.x = 7
        performance.update(at: 0.25)
        XCTAssertEqual(companions.filter { $0.light != nil }.count, 4)
        XCTAssertNil(companions[0].light)
        XCTAssertTrue(companions[7].light === lights[7])
        XCTAssertTrue(companions.allSatisfy { $0.parent === scene.rootNode && !$0.isHidden })
    }

    func testDistantMistRestoresItsOriginalRateAndUnrelatedLightsStayOn() {
        let scene = SCNScene()
        let camera = SCNNode()
        scene.rootNode.addChildNode(camera)
        let stag = companion("Patronus", in: scene)
        let particles = SCNParticleSystem()
        particles.birthRate = 35
        stag.addParticleSystem(particles)
        let roomLamp = companion("RoomLamp", in: scene)
        let originalRoomLight = roomLamp.light
        let performance = ScenePerformance(scene: scene, camera: camera)
        camera.position.x = 12
        performance.update(at: 0)
        XCTAssertEqual(particles.birthRate, 0)
        XCTAssertNil(stag.light)
        XCTAssertTrue(roomLamp.light === originalRoomLight)
        camera.position.x = 7
        performance.update(at: 0.25)
        XCTAssertEqual(particles.birthRate, 35 * 0.35, accuracy: 0.001)
        camera.position.x = 1
        performance.update(at: 0.5)
        XCTAssertEqual(particles.birthRate, 35)
        XCTAssertNotNil(stag.light)
        camera.position.x = 12
        performance.update(at: 0.75)
        stag.removeFromParentNode()
        performance.update(at: 1)
        XCTAssertEqual(particles.birthRate, 35)
        XCTAssertNotNil(stag.light)
    }

    func testRegisteredCompanionsStillAttackWithTheEffectBudget() {
        let scene = SCNScene()
        let camera = SCNNode()
        scene.rootNode.addChildNode(camera)
        let combat = SummonCombat(scene: scene)
        let alan = companion("summon.alan.one", in: scene)
        let albert = companion("summon.albert.one", in: scene)
        combat.register(kind: .alan, node: alan)
        combat.register(kind: .albert, node: albert)
        let performance = ScenePerformance(scene: scene, camera: camera)
        let enemy = SCNNode()
        enemy.simdPosition = SIMD3(0, 0, 1)
        scene.rootNode.addChildNode(enemy)
        let target = SummonCombat.Target(node: enemy, center: SIMD3(0, 1, 1))
        var hits: [SummonCombat.Impact] = []
        for step in 0..<24 {
            performance.update(at: Double(step) * 0.05)
            hits += combat.update(deltaTime: 0.05, targets: [target])
        }
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits.map(\.damage), [1, 1])
        XCTAssertTrue(hits.allSatisfy { $0.node === enemy })
        XCTAssertTrue([alan, albert].allSatisfy { $0.parent === scene.rootNode && !$0.isHidden })
    }

    @MainActor
    func testPreparedZombieIdentitiesReuseTexturesButKeepNamesAndMaterialsIndependent() throws {
        let first = try XCTUnwrap(Combat.identities.first)
        let second = try XCTUnwrap(Combat.identities.dropFirst().first)
        let templates = ZombieAppearance.prewarm(identities: [first, second])
        let repeated = ZombieAppearance.prewarm(identities: [first, second])
        XCTAssertEqual(templates.count, 8)
        XCTAssertTrue(zip(templates, repeated).allSatisfy { $0 === $1 })
        XCTAssertFalse(templates[0] === templates[4])
        let one = ZombieAppearance.make(identity: first, index: 0)
        let two = ZombieAppearance.make(identity: first, index: 0)
        let other = ZombieAppearance.make(identity: second, index: 0)
        let faceOne = try XCTUnwrap(one.childNode(withName: "Face.\(first.id)", recursively: true)?.geometry)
        let faceTwo = try XCTUnwrap(two.childNode(withName: "Face.\(first.id)", recursively: true)?.geometry)
        let faceOther = try XCTUnwrap(other.childNode(withName: "Face.\(second.id)", recursively: true)?.geometry)
        let materialOne = try XCTUnwrap(faceOne.firstMaterial)
        let materialTwo = try XCTUnwrap(faceTwo.firstMaterial)
        XCTAssertFalse(materialOne === materialTwo)
        XCTAssertTrue((materialOne.diffuse.contents as? UIImage) === (materialTwo.diffuse.contents as? UIImage))
        XCTAssertFalse(
            (materialOne.diffuse.contents as? UIImage) === (faceOther.firstMaterial?.diffuse.contents as? UIImage))
        materialOne.transparency = 0.2
        XCTAssertEqual(materialTwo.transparency, 1)
        XCTAssertNotNil(one.childNode(withName: "Name.\(first.id)", recursively: true))
        XCTAssertNotNil(other.childNode(withName: "Name.\(second.id)", recursively: true))
    }

    @MainActor
    func testPortraitTemplatesAndSpiritShadersSurviveRepeatedSummons() throws {
        let portraits = PortraitSummons.prewarm()
        let repeated = PortraitSummons.prewarm()
        XCTAssertEqual(portraits.count, 2)
        XCTAssertTrue(zip(portraits, repeated).allSatisfy { $0 === $1 })
        let scene = SCNScene()
        let camera = SCNNode()
        scene.rootNode.addChildNode(camera)
        let alan = try XCTUnwrap(PortraitSummons.summon(name: "Alan", in: scene, at: SIMD3(1, 0, -2), facing: camera))
        let another = try XCTUnwrap(
            PortraitSummons.summon(name: "Alan", in: scene, at: SIMD3(-1, 0, -2), facing: camera))
        XCTAssertNotEqual(alan.name, another.name)
        let halo = try XCTUnwrap(alan.childNode(withName: "PortraitHalo", recursively: false)?.geometry?.firstMaterial)
        let otherHalo = try XCTUnwrap(
            another.childNode(withName: "PortraitHalo", recursively: false)?.geometry?.firstMaterial)
        XCTAssertFalse(halo === otherHalo)
        halo.transparency = 0.1
        XCTAssertEqual(otherHalo.transparency, 1)
        let spells = RuneEffects.prewarm()
        XCTAssertEqual(spells.count, 4)
        var spiritSurfaces = 0
        spells[1].enumerateChildNodes { node, _ in
            for material in node.geometry?.materials ?? [] {
                XCTAssertNotNil(material.shaderModifiers?[.fragment])
                XCTAssertFalse(material.writesToDepthBuffer)
                spiritSurfaces += 1
            }
        }
        XCTAssertGreaterThan(spiritSurfaces, 0)
        XCTAssertEqual(spells[2].childNodes.count, 5)
        let mistOne = ScenePerformance.independentClone(of: spells[3])
        let mistTwo = ScenePerformance.independentClone(of: spells[3])
        let particlesOne = try XCTUnwrap(mistOne.particleSystems?.first)
        let particlesTwo = try XCTUnwrap(mistTwo.particleSystems?.first)
        XCTAssertFalse(particlesOne === particlesTwo)
        particlesOne.birthRate = 0
        XCTAssertEqual(particlesTwo.birthRate, 35)
    }

    private func companion(_ name: String, in scene: SCNScene) -> SCNNode {
        let node = SCNNode()
        node.name = name
        node.light = SCNLight()
        node.light?.type = .omni
        scene.rootNode.addChildNode(node)
        return node
    }
}
