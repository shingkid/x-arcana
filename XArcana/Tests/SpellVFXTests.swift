import SceneKit
import UIKit
import XCTest

@testable import XArcana

final class SpellVFXTests: XCTestCase {
    func testAtlasesShareImagesButKeepPlaybackMaterialsIndependent() throws {
        XCTAssertEqual(SpellVFX.prewarm().count, SpellVFX.Effect.allCases.count)
        for effect in SpellVFX.Effect.allCases {
            let first = try XCTUnwrap(SpellVFX.card(effect, size: 1))
            let second = try XCTUnwrap(SpellVFX.card(effect, size: 1))
            let a = try XCTUnwrap(first.geometry?.firstMaterial)
            let b = try XCTUnwrap(second.geometry?.firstMaterial)
            XCTAssertFalse(a === b)
            let firstImage = try XCTUnwrap(a.diffuse.contents as? UIImage)
            let secondImage = try XCTUnwrap(b.diffuse.contents as? UIImage)
            XCTAssertTrue(firstImage === secondImage)
            XCTAssertLessThanOrEqual(try XCTUnwrap(firstImage.cgImage).width, 1024)
            XCTAssertLessThanOrEqual(try XCTUnwrap(firstImage.cgImage).height, 1024)
            XCTAssertEqual(first.categoryBitMask, 2)
            XCTAssertNil(first.light)
            XCTAssertFalse(a.writesToDepthBuffer)
            XCTAssertTrue(a.readsFromDepthBuffer)
            XCTAssertEqual(a.blendMode, .add)
        }
        XCTAssertNil(SpellVFX.card(.fire, size: .nan))
        XCTAssertNil(SpellVFX.card(.fire, size: 1, duration: 0))
    }

    func testFlipbookChangesTextureFrameThenRemovesItself() throws {
        let scene = SCNScene()
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.position = SCNVector3(0, 0, 3)
        scene.rootNode.addChildNode(camera)
        let card = try XCTUnwrap(SpellVFX.card(.lightning, size: 2, duration: 0.6))
        scene.rootNode.addChildNode(card)
        let material = try XCTUnwrap(card.geometry?.firstMaterial)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        _ = renderer.snapshot(atTime: 0, with: CGSize(width: 320, height: 320), antialiasingMode: .none)
        let first = material.diffuse.contentsTransform
        let image = renderer.snapshot(atTime: 0.22, with: CGSize(width: 320, height: 320), antialiasingMode: .none)
        let cgImage = try XCTUnwrap(image.cgImage)
        var rgba = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        let context = try XCTUnwrap(
            CGContext(
                data: &rgba, width: cgImage.width, height: cgImage.height,
                bitsPerComponent: 8, bytesPerRow: cgImage.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        let visible = stride(from: 0, to: rgba.count, by: 4).filter { max(rgba[$0], rgba[$0 + 1], rgba[$0 + 2]) > 30 }
            .count
        XCTAssertGreaterThan(visible, 200, "The atlas cell must contain visible animation, not empty padding")
        XCTAssertFalse(SCNMatrix4EqualToMatrix4(first, material.diffuse.contentsTransform))
        _ = renderer.snapshot(atTime: 1.2, with: CGSize(width: 320, height: 320), antialiasingMode: .none)
        XCTAssertNil(card.parent)
        let attachment = XCTAttachment(image: image)
        attachment.name = "CC0 lightning atlas frame"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
