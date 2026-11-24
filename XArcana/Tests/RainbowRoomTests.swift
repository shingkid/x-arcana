import SceneKit
import UIKit
import XCTest

@testable import XArcana

final class RainbowRoomTests: XCTestCase {
    private func surfaces(_ room: GameWorld) -> [SCNGeometry] {
        var geometries: [SCNGeometry] = []
        room.scene.rootNode.enumerateChildNodes { node, _ in
            if let geometry = node.geometry { geometries.append(geometry) }
        }
        return geometries
    }

    func testRainbowCachesMaterialsAndRestoresExactOriginalObjects() throws {
        let room = GameWorld()
        XCTAssertNil(room.errorMessage)
        let geometry = surfaces(room)
        XCTAssertFalse(geometry.isEmpty)
        let originals = geometry.map(\.materials)
        let rootCount = room.scene.rootNode.childNodes.count
        var lightCount = 0
        room.scene.rootNode.enumerateChildNodes { node, _ in if node.light != nil { lightCount += 1 } }
        let target = SCNNode(geometry: SCNSphere(radius: 0.2))
        let targetMaterial = try XCTUnwrap(target.geometry?.firstMaterial)
        room.scene.rootNode.addChildNode(target)
        room.setTransfigurationPhase(0)
        let cached = geometry.map(\.materials)
        XCTAssertTrue(cached.flatMap { $0 }.allSatisfy { $0.name?.hasPrefix("Rainbow hall:") == true })
        XCTAssertTrue(target.geometry?.firstMaterial === targetMaterial, "Only authored room surfaces change.")
        for frame in 1...600 { room.setTransfigurationPhase(Double(frame) / 60) }
        XCTAssertEqual(room.transfigurationPhase, 10)
        room.setTransfigurationPhase(10)
        XCTAssertEqual(room.transfigurationPhase, 10, "A paused simulation keeps the same color phase.")
        for (index, item) in geometry.enumerated() {
            XCTAssertEqual(item.materials.count, cached[index].count)
            for (actual, expected) in zip(item.materials, cached[index]) { XCTAssertTrue(actual === expected) }
        }
        XCTAssertEqual(room.scene.rootNode.childNodes.count, rootCount + 1)
        var finalLightCount = 0
        room.scene.rootNode.enumerateChildNodes { node, _ in if node.light != nil { finalLightCount += 1 } }
        XCTAssertEqual(finalLightCount, lightCount)
        room.setTransfigurationPhase(nil)
        for (index, item) in geometry.enumerated() {
            for (actual, expected) in zip(item.materials, originals[index]) { XCTAssertTrue(actual === expected) }
        }
        room.setTransfigurationPhase(0)
        for (index, item) in geometry.enumerated() {
            for (actual, expected) in zip(item.materials, cached[index]) { XCTAssertTrue(actual === expected) }
        }
        for invalid in [SurvivalState.nyanDuration, -Double.infinity, Double.nan] {
            room.setTransfigurationPhase(invalid)
            XCTAssertNil(room.transfigurationPhase)
        }
    }

    func testSeeThroughHidesRainbowAndRestoresAcrossModeChanges() {
        let room = GameWorld()
        let environment = room.scene.rootNode.childNodes.filter { $0.camera == nil && $0.light == nil }
        XCTAssertFalse(environment.isEmpty)
        let geometry = surfaces(room)
        let originals = geometry.map(\.materials)
        room.setSeeThrough(true)
        room.setTransfigurationPhase(4)
        XCTAssertTrue(environment.allSatisfy(\.isHidden))
        XCTAssertTrue((room.scene.background.contents as? UIColor)?.isEqual(UIColor.clear) == true)
        room.setSeeThrough(false)
        XCTAssertTrue(environment.allSatisfy { !$0.isHidden })
        XCTAssertTrue(geometry.flatMap(\.materials).allSatisfy { $0.name?.hasPrefix("Rainbow hall:") == true })
        room.setSeeThrough(true)
        room.setTransfigurationPhase(nil)
        XCTAssertTrue(environment.allSatisfy(\.isHidden))
        XCTAssertTrue((room.scene.background.contents as? UIColor)?.isEqual(UIColor.clear) == true)
        room.setSeeThrough(false)
        for (index, item) in geometry.enumerated() {
            for (actual, expected) in zip(item.materials, originals[index]) { XCTAssertTrue(actual === expected) }
        }
    }

    @MainActor
    func testNativeRainbowRenderIsVisibleAndCleanupRestoresImage() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let room = GameWorld()
        XCTAssertNil(room.errorMessage)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = room.scene
        renderer.pointOfView = room.camera
        func snapshot(_ name: String) throws -> [UInt8] {
            SCNTransaction.flush()
            XCTAssertTrue(renderer.prepare(room.scene, shouldAbortBlock: nil))
            let image = renderer.snapshot(
                atTime: 0, with: CGSize(width: 640, height: 400), antialiasingMode: .multisampling4X)
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
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
        func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
            Double(zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(a.count * 255)
        }
        let before = try snapshot("Hall before transfiguration")
        room.setTransfigurationPhase(3)
        let rainbow = try snapshot("Rainbow hall")
        XCTAssertGreaterThan(difference(before, rainbow), 0.035, "The curse must visibly recolor the hall.")
        var hueBins = Set<Int>()
        for index in stride(from: 0, to: rainbow.count, by: 4) {
            let color = UIColor(
                red: CGFloat(rainbow[index]) / 255, green: CGFloat(rainbow[index + 1]) / 255,
                blue: CGFloat(rainbow[index + 2]) / 255, alpha: 1)
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            if color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil),
                saturation > 0.35, brightness > 0.2
            {
                hueBins.insert(min(5, Int(hue * 6)))
            }
        }
        XCTAssertGreaterThanOrEqual(hueBins.count, 5, "The hall must show a rainbow, not a flat shader-error color.")
        room.setTransfigurationPhase(9)
        let later = try snapshot("Rainbow hall later simulation phase")
        XCTAssertGreaterThan(difference(rainbow, later), 0.025)
        room.setTransfigurationPhase(nil)
        let restored = try snapshot("Hall restored")
        XCTAssertLessThan(difference(before, restored), 0.005)
        room.setSeeThrough(true)
        let clear = try snapshot("See-through before rainbow")
        room.setTransfigurationPhase(3)
        let activeClear = try snapshot("See-through during rainbow")
        XCTAssertLessThan(difference(clear, activeClear), 0.001, "Never fill the real-world view with the hall.")
        room.setTransfigurationPhase(nil)
        let endedClear = try snapshot("See-through after rainbow")
        XCTAssertLessThan(difference(clear, endedClear), 0.001)
    }
}
