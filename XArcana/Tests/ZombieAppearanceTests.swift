import SceneKit
import UIKit
import XCTest

@testable import XArcana

final class ZombieAppearanceTests: XCTestCase {
    func testPublicRosterDefaultsToNeutralAndUnknownIdentityStaysNeutral() {
        XCTAssertEqual(Combat.identities.count, 42)
        XCTAssertTrue(ZombieAppearance.metadataValidationIssues(identityIDs: Combat.identities.map(\.id)).isEmpty)
        for identity in Combat.identities {
            XCTAssertEqual(ZombieAppearance.bodyStyle(for: identity.id), .neutral)
        }
        XCTAssertEqual(ZombieAppearance.bodyStyle(for: "new-identity"), .neutral)
        XCTAssertEqual(ZombieAppearance.bodyStyle(for: "Amber"), .neutral)
    }

    func testMetadataValidationReportsMissingAndStaleAssignments() {
        let metadata = ZombieAppearance.BodyStyleMetadata(
            schemaVersion: 1,
            assignments: ["known": .female, "stale": .male])
        let issues = metadata.validationIssues(identityIDs: ["known", "new"])
        XCTAssertEqual(issues.count, 2)
        XCTAssertTrue(issues.contains { $0.contains("new") && $0.contains("neutral") })
        XCTAssertTrue(issues.contains { $0.contains("stale") })
        let invalid = Data("{\"schemaVersion\":1,\"assignments\":{\"id\":\"guessed\"}}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ZombieAppearance.BodyStyleMetadata.self, from: invalid))
    }

    func testBothBodiesKeepMappedFacesAndDistinctAuthoredGeometry() throws {
        let male = try XCTUnwrap(Combat.identities.first { $0.id == "aditya" })
        let female = try XCTUnwrap(Combat.identities.first { $0.id == "amber" })
        let maleNode = ZombieAppearance.make(identity: male, index: 0, style: .male)
        let femaleNode = ZombieAppearance.make(identity: female, index: 0, style: .female)
        XCTAssertEqual(maleNode.name, "ZombieBodyStyle.male")
        XCTAssertEqual(femaleNode.name, "ZombieBodyStyle.female")
        func bodyGeometry(_ node: SCNNode) throws -> SCNGeometry {
            var result: SCNGeometry?
            node.enumerateChildNodes { child, _ in
                if child.geometry?.materials.contains(where: { ($0.name ?? "").lowercased().contains("shirt") }) == true
                {
                    result = child.geometry
                }
            }
            return try XCTUnwrap(result)
        }
        let maleGeometry = try bodyGeometry(maleNode)
        let femaleGeometry = try bodyGeometry(femaleNode)
        XCTAssertNotEqual(
            maleGeometry.sources(for: .vertex).first?.data,
            femaleGeometry.sources(for: .vertex).first?.data)
        for (node, identity) in [(maleNode, male), (femaleNode, female)] {
            let face = try XCTUnwrap(node.childNode(withName: "Face.\(identity.id)", recursively: true)?.geometry)
            XCTAssertNotNil(face.firstMaterial?.diffuse.contents)
            XCTAssertEqual(face.sources(for: .texcoord).count, 1)
            XCTAssertEqual(face.sources(for: .color).count, 1)
            let name = try XCTUnwrap(node.childNode(withName: "Name.\(identity.id)", recursively: true))
            let text = try XCTUnwrap(name.childNodes.first?.geometry as? SCNText)
            XCTAssertEqual(text.string as? String, identity.name)
            XCTAssertGreaterThan(text.boundingBox.max.y - text.boundingBox.min.y, 0)
        }
    }
    func testPortraitMappingPreservesImagePixelProportionsAndEyeLine() throws {
        let data = Data(
            """
            {"id":"test","faceRect":{"x":0,"y":0,"width":1,"height":1},
             "leftEye":{"x":0.3,"y":0.6},"rightEye":{"x":0.7,"y":0.6},
             "mouth":{"x":0.5,"y":0.2},"sourceWidth":400,"sourceHeight":200}
            """.utf8)
        let region = try JSONDecoder().decode(ZombieAppearance.FaceRegion.self, from: data)
        let model = try JSONDecoder().decode(
            ZombieAppearance.ModelFace.self,
            from: Data(
                """
                {"leftEye":{"x":0.3,"y":0.6},"rightEye":{"x":0.7,"y":0.6},
                 "mouth":{"x":0.5,"y":0.3}}
                """.utf8))
        let left = ZombieAppearance.portraitUV(model.leftEye.vector, region: region, model: model)
        let right = ZombieAppearance.portraitUV(model.rightEye.vector, region: region, model: model)
        XCTAssertEqual(left.x, region.leftEye.x, accuracy: 0.0001)
        XCTAssertEqual(right.x, region.rightEye.x, accuracy: 0.0001)
        let horizontal = ZombieAppearance.portraitUV(SIMD2(0.4, 0.6), region: region, model: model)
        let vertical = ZombieAppearance.portraitUV(SIMD2(0.3, 0.7), region: region, model: model)
        XCTAssertEqual((horizontal.x - left.x) * 400, (vertical.y - left.y) * 200, accuracy: 0.001)
    }

    func testWeightedMotionKeepsIndependentActorsAndMappedFaces() throws {
        let identity = try XCTUnwrap(Combat.identities.first)
        for style in [ZombieAppearance.BodyStyle.neutral, .male, .female] {
            let first = ZombieAppearance.make(identity: identity, index: 0, style: style)
            let second = ZombieAppearance.make(identity: identity, index: 0, style: style)
            let hand = try XCTUnwrap(CharacterAnimation.attachment("leftHand", on: first))
            let otherHand = try XCTUnwrap(CharacterAnimation.attachment("leftHand", on: second))
            XCTAssertFalse(hand === otherHand)
            let otherRest = otherHand.simdTransform
            let root = first.simdTransform
            for clip in ["walk", "swipe", "bite"] {
                XCTAssertTrue(ZombieAppearance.sampleMotion(clip, at: 0, on: first))
                let rest = hand.simdWorldPosition
                XCTAssertTrue(ZombieAppearance.sampleMotion(clip, at: 0.34, on: first))
                XCTAssertGreaterThan(simd_distance(rest, hand.simdWorldPosition), 0.01, clip)
                XCTAssertEqual(first.simdTransform, root)
                XCTAssertEqual(otherHand.simdTransform, otherRest)
            }
            XCTAssertTrue(ZombieAppearance.sampleMotion("walk", at: 0.3, on: first))
            let loop = hand.simdTransform
            XCTAssertTrue(ZombieAppearance.sampleMotion("walk", at: 1.4666666667, on: first))
            XCTAssertEqual(hand.simdPosition.x, loop.columns.3.x, accuracy: 0.0001)
            let face = try XCTUnwrap(first.childNode(withName: "Face.\(identity.id)", recursively: true))
            XCTAssertEqual(face.skinner?.bones.count, 17)
            XCTAssertEqual(face.skinner?.baseGeometry?.firstMaterial?.name, "NPC face.\(identity.id)")
            XCTAssertFalse(ZombieAppearance.sampleMotion("walk", at: .nan, on: first))
        }
    }

    func testShirtVariantsBindToTheRenderedSkinGeometry() throws {
        let identity = try XCTUnwrap(Combat.identities.first)
        var colours: [UIColor] = []
        for variant in 0..<4 {
            let node = ZombieAppearance.make(identity: identity, index: variant)
            var shirt: SCNMaterial?
            node.enumerateChildNodes { child, _ in
                if let material = child.skinner?.baseGeometry?.materials.first(where: {
                    ($0.name ?? "").lowercased().contains("shirt")
                }) {
                    shirt = material
                }
            }
            let material = try XCTUnwrap(shirt)
            colours.append(try XCTUnwrap(material.multiply.contents as? UIColor))
            XCTAssertEqual((material.metalness.contents as? NSNumber)?.floatValue, 0)
            XCTAssertEqual((material.roughness.contents as? NSNumber)?.floatValue ?? 0, 0.94, accuracy: 0.001)
        }
        for index in 1..<colours.count { XCTAssertFalse(colours[0].isEqual(colours[index])) }
    }

}
