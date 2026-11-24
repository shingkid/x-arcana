import SceneKit
import UIKit
import XCTest

@testable import XArcana

final class PublicAssetsTests: XCTestCase {
    func testRosterUsesGeneratedRobotImagesAndAuthoredCoordinates() throws {
        XCTAssertEqual(Combat.identities.count, 42)
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "regions", withExtension: "json", subdirectory: "NPCFaces"))
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        XCTAssertEqual(Set(records.compactMap { $0["id"] as? String }), Set(Combat.identities.map(\.id)))
        for identity in Combat.identities {
            let imageURL = try XCTUnwrap(
                Bundle.main.url(forResource: identity.image, withExtension: nil, subdirectory: "NPCPortraits"))
            let image = try XCTUnwrap(UIImage(contentsOfFile: imageURL.path)?.cgImage)
            XCTAssertEqual(image.width, 256)
            XCTAssertEqual(image.height, 256)
            let record = try XCTUnwrap(records.first { $0["id"] as? String == identity.id })
            XCTAssertEqual(record["provenance"] as? String, "procedural-public-placeholder-v1")
            XCTAssertEqual(record["faceDetected"] as? Bool, false)
            for landmark in ["leftEye", "rightEye", "mouth"] {
                let point = try XCTUnwrap(record[landmark] as? [String: Double])
                XCTAssertTrue((0...1).contains(try XCTUnwrap(point["x"])))
                XCTAssertTrue((0...1).contains(try XCTUnwrap(point["y"])))
            }
        }
    }

    func testCompanionBodiesHavePublicMaterialsAndPreserveAnimationContract() throws {
        for name in ["PortraitCharacter", "AlanCharacter"] {
            let url = try XCTUnwrap(
                Bundle.main.url(forResource: name + ".rig", withExtension: "json", subdirectory: "Fantasy"))
            let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            XCTAssertEqual(document["provenance"] as? String, "procedural-public-placeholder-v1")
            XCTAssertEqual(document["license"] as? String, "CC0-1.0")
            XCTAssertEqual((document["bones"] as? [[String: Any]])?.count, 20)
            let attachments = try XCTUnwrap(document["attachments"] as? [String: String])
            XCTAssertEqual(Set(attachments.keys), Set(["rightHand", "leftHand", "mouth", "chest", "hips"]))
            let clips = try XCTUnwrap(document["clips"] as? [String: Any])
            XCTAssertTrue(Set(["idle", "walk", "slap", "slam"]).isSubset(of: Set(clips.keys)))
            let modelURL = try XCTUnwrap(
                Bundle.main.url(forResource: name, withExtension: "usdz", subdirectory: "Fantasy"))
            let scene = try SCNScene(url: modelURL)
            var materialNames = Set<String>()
            scene.rootNode.enumerateChildNodes { node, _ in
                for material in node.geometry?.materials ?? [] {
                    materialNames.insert(material.name ?? "")
                    XCTAssertFalse(
                        material.diffuse.contents is UIImage, "Placeholder materials must not contain portrait textures"
                    )
                }
            }
            XCTAssertFalse(materialNames.isEmpty)
            XCTAssertTrue(materialNames.allSatisfy { $0.hasPrefix("PublicPlaceholder") })
        }
    }
}
