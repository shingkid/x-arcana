import SceneKit
import UIKit
import XCTest
import simd

@testable import XArcana

final class RainbowCatTests: XCTestCase {
    func testPixelCharacterSharesBoundedGeometryWithoutTexturesOrEffects() throws {
        let root = SCNNode()
        let first = RainbowCat(parent: root, floorY: 0, anchored: true)
        let second = RainbowCat(parent: root, floorY: 0, anchored: true)
        let body = try XCTUnwrap(first.node.childNode(withName: "Pastry cat body", recursively: false)?.geometry)
        XCTAssertTrue(body === second.node.childNode(withName: "Pastry cat body", recursively: false)?.geometry)
        XCTAssertEqual(body.materials.count, 1)
        XCTAssertEqual(body.sources(for: .color).count, 1)
        XCTAssertTrue(body.sources(for: .texcoord).isEmpty)
        XCTAssertLessThan(body.elements.reduce(0) { $0 + $1.primitiveCount }, 3_000)
        XCTAssertEqual(first.node.childNodes.filter { $0.name == "Rainbow trail" }.count, 6)
        XCTAssertEqual(first.node.childNodes.filter { $0.name?.hasPrefix("Rainbow cat leg") == true }.count, 4)
        let count = first.node.childNodes.count
        for _ in 0..<1_200 { first.update(deltaTime: 1 / 60) }
        XCTAssertEqual(first.node.childNodes.count, count)
        XCTAssertLessThanOrEqual(count, 12)
        first.node.enumerateChildNodes { child, _ in
            XCTAssertNil(child.light)
            XCTAssertNil(child.particleSystems)
            XCTAssertFalse(child.hasActions)
            XCTAssertFalse(child.geometry?.firstMaterial?.diffuse.contents is UIImage)
            if let box = child.geometry as? SCNBox { XCTAssertEqual(box.chamferRadius, 0) }
        }
        first.remove()
        first.remove()
        XCTAssertNil(first.node.parent)
        XCTAssertTrue(second.node.parent === root)
    }

    func testRoamingCrossesBothScreenAxesAndFacesTravelDespiteEnemyTransform() {
        let scene = SCNScene()
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.projectionDirection = .horizontal
        camera.camera?.fieldOfView = 74
        camera.simdPosition = SIMD3(2, 1.65, 4.8)
        camera.simdOrientation = simd_quatf(angle: 0.7, axis: SIMD3(0, 1, 0))
        scene.rootNode.addChildNode(camera)
        let enemy = SCNNode()
        enemy.simdScale = SIMD3(0.7, 1.4, 0.9)
        enemy.simdPosition = SIMD3(-2, 0, -4)
        enemy.simdOrientation = simd_quatf(angle: -1.2, axis: SIMD3(0, 1, 0))
        scene.rootNode.addChildNode(enemy)
        let originalTransform = enemy.simdTransform
        let cat = RainbowCat(parent: enemy, floorY: 0, anchored: true, camera: camera)
        var positions: [SIMD3<Float>] = []
        var headings = Set<Int>()
        var directions = Set<Int>()
        let halfWidth = Float(4 * tan(37.0 * .pi / 180))
        let halfHeight = halfWidth * 9 / 16
        for frame in 0..<Int(SurvivalState.nyanDuration * 60) {
            cat.update(deltaTime: 1 / 60)
            let transform = simd_inverse(camera.simdWorldTransform) * cat.node.simdWorldTransform
            positions.append(SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z))
            headings.insert(transform.columns.0.x > 0 ? 1 : -1)
            if positions.count > 1 {
                let delta = positions[positions.count - 1] - positions[positions.count - 2]
                if abs(delta.x) > 0.002, abs(delta.y) > 0.002 {
                    directions.insert((delta.x > 0 ? 1 : 0) + (delta.y > 0 ? 2 : 0))
                }
            }
            XCTAssertEqual(transform.columns.3.z, -4, accuracy: 0.0001)
            XCTAssertEqual(simd_length(transform.columns.0), simd_length(transform.columns.1), accuracy: 0.0001)
            XCTAssertEqual(transform.columns.0.y, 0, accuracy: 0.0001)
            if frame == 600 {
                camera.simdPosition += SIMD3(0.5, 0.2, -0.3)
                camera.simdOrientation = simd_quatf(angle: -0.6, axis: SIMD3(1, 0, 0))
            }
        }
        XCTAssertEqual(enemy.simdTransform, originalTransform)
        XCTAssertEqual(headings, [-1, 1])
        XCTAssertEqual(
            directions, [0, 1, 2, 3], "Random routes must include diagonal travel and reversals on both axes.")
        XCTAssertGreaterThan(
            ((positions.map(\.x).max() ?? 0) - (positions.map(\.x).min() ?? 0)) / (2 * halfWidth), 0.5,
            "A cat crosses more than half the visible width.")
        XCTAssertGreaterThan(
            ((positions.map(\.y).max() ?? 0) - (positions.map(\.y).min() ?? 0)) / (2 * halfHeight), 0.3,
            "A cat crosses several vertical regions while leaving the HUD margins clear.")
        XCTAssertTrue(positions.allSatisfy { abs($0.x) < halfWidth * 0.75 && abs($0.y) < halfHeight * 0.55 })
        for x: Float in [-1, 1] {
            for y: Float in [-1, 1] {
                XCTAssertTrue(positions.contains { $0.x * x > halfWidth * 0.25 && $0.y * y > halfHeight * 0.2 })
            }
        }
    }

    func testDistinctRoutesUseOnlySimulationTimeAndPreserveGeometry() {
        let root = SCNNode()
        let camera = SCNNode()
        let first = RainbowCat(parent: root, floorY: 0, anchored: true, phaseOffset: 1.7, camera: camera)
        let split = RainbowCat(parent: root, floorY: 0, anchored: true, phaseOffset: 1.7, camera: camera)
        let different = RainbowCat(parent: root, floorY: 0, anchored: true, phaseOffset: 3.4, camera: camera)
        let geometries = first.node.childNodes.map(\.geometry)
        first.update(deltaTime: 4.75)
        for _ in 0..<285 { split.update(deltaTime: 1 / 60) }
        different.update(deltaTime: 4.75)
        XCTAssertLessThan(simd_distance(first.node.simdPosition, split.node.simdPosition), 0.0001)
        XCTAssertGreaterThan(simd_distance(first.node.simdPosition, different.node.simdPosition), 1)
        let paused = first.node.simdTransform
        for delta in [0, -1, .infinity, .nan] { first.update(deltaTime: delta) }
        XCTAssertEqual(first.node.simdTransform, paused)
        for (child, original) in zip(first.node.childNodes, geometries) { XCTAssertTrue(child.geometry === original) }
    }

    @MainActor
    func testNativeHordeRoamsAcrossCurrentViewAndDisappearsAtSongEnd() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let room = GameWorld()
        XCTAssertNil(room.errorMessage)
        let state = SurvivalState(defaults: nil)
        for _ in 0..<20 { state.recordKill() }
        let combat = Combat(
            scene: room.scene, camera: room.camera, environment: room.environment, defaults: nil, state: state)
        combat.update(at: 0)
        let height = room.camera.simdPosition.y
        room.camera.simdPosition.y = 6
        let spawnFrames = Int(ceil((Combat.spawnInterval * 7 + 0.5) * 60))
        for frame in 1...spawnFrames { combat.update(at: Double(frame) / 60) }
        room.camera.simdPosition.y = height
        let castTime = Double(spawnFrames) / 60
        XCTAssertTrue(combat.nyan())
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = room.scene
        renderer.pointOfView = room.camera
        var time: TimeInterval = 0
        var firstPositions: [SIMD3<Float>] = []
        for mark in [0.0, 7, 17, 26] {
            while time + 1 / 60 <= mark {
                time += 1 / 60
                combat.update(at: castTime + time)
            }
            if mark == 17 {
                room.camera.simdOrientation *= simd_quatf(angle: 0.45, axis: SIMD3(0, 1, 0))
                time += 1 / 60
                combat.update(at: castTime + time)
            }
            room.setTransfigurationPhase(combat.transfigurationPhase)
            var positions: [SIMD3<Float>] = []
            room.scene.rootNode.enumerateChildNodes { node, _ in
                if node.name == "Transfigured Nyan cat" {
                    positions.append(room.camera.simdConvertPosition(node.simdWorldPosition, from: nil))
                }
            }
            XCTAssertEqual(positions.count, 8)
            XCTAssertTrue(positions.allSatisfy { abs($0.x) < 2.3 && abs($0.y) < 0.9 && abs($0.z + 4) < 0.0001 })
            if mark == 0 { firstPositions = positions }
            if mark > 0 {
                let totalTravel = zip(positions, firstPositions).reduce(Float(0)) { $0 + simd_distance($1.0, $1.1) }
                XCTAssertGreaterThan(
                    totalTravel / Float(positions.count), 0.5,
                    "The horde changes screen regions; a random walker can return near its starting point.")
            }
            SCNTransaction.flush()
            XCTAssertTrue(renderer.prepare(room.scene, shouldAbortBlock: nil))
            let image = renderer.snapshot(
                atTime: 0, with: CGSize(width: 1_920, height: 1_080), antialiasingMode: .multisampling4X)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Roaming Nyan horde - simulation second \(Int(mark))"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        while time < SurvivalState.nyanDuration + 0.1 {
            time += 1 / 60
            combat.update(at: castTime + time)
        }
        XCTAssertEqual(combat.kills, 28)
        XCTAssertNil(room.scene.rootNode.childNode(withName: "Transfigured Nyan cat", recursively: true))
    }

    @MainActor
    func testNativePixelCharacterShowsPastryGreyFaceOutlineAndSixBandRainbow() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 1)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 40
        camera.simdPosition = SIMD3(0, 0, 2.5)
        scene.rootNode.addChildNode(camera)
        let cat = RainbowCat(parent: scene.rootNode, floorY: -1.05, anchored: true)
        cat.node.simdPosition.x = 0.35
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        XCTAssertTrue(renderer.prepare(scene, shouldAbortBlock: nil))
        SCNTransaction.flush()
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1_000, height: 600), antialiasingMode: .none)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Nyan pixel extrusion - native SceneKit"
        attachment.lifetime = .keepAlways
        add(attachment)
        let cg = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: 1_000 * 600 * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(
                CGContext(
                    data: bytes.baseAddress, width: 1_000, height: 600, bitsPerComponent: 8, bytesPerRow: 4_000,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 1_000, height: 600))
        }
        func count(_ red: Int, _ green: Int, _ blue: Int, tolerance: Int = 12) -> Int {
            stride(from: 0, to: pixels.count, by: 4).reduce(0) { count, offset in
                count
                    + (abs(Int(pixels[offset]) - red) <= tolerance
                        && abs(Int(pixels[offset + 1]) - green) <= tolerance
                        && abs(Int(pixels[offset + 2]) - blue) <= tolerance ? 1 : 0)
            }
        }
        XCTAssertGreaterThan(count(255, 153, 204), 3_000, "Pink frosting must remain distinct from the crust.")
        XCTAssertGreaterThan(count(255, 51, 153), 150, "Sprinkles use dark pink square pixels.")
        XCTAssertGreaterThan(count(153, 153, 153), 1_000, "The overlapping head must remain grey.")
        XCTAssertGreaterThan(count(4, 4, 5), 1_000, "The character needs its stepped black outline.")
        XCTAssertGreaterThan(count(255, 255, 255), 20, "Eyes need white pixel highlights.")
        // Each full-height band must retain its characteristic color.
        for color in [(255, 0, 0), (255, 153, 0), (255, 255, 0), (51, 255, 0), (0, 153, 255), (102, 51, 255)] {
            XCTAssertGreaterThan(count(color.0, color.1, color.2, tolerance: 25), 500)
        }
    }
}
