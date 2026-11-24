import AppKit
import SceneKit

typealias UIColor = NSColor
typealias UIImage = NSImage
extension NSImage { var cgImage: CGImage? { cgImage(forProposedRect: nil, context: nil, hints: nil) } }
let assetBundle = Bundle(path: CommandLine.arguments[1])!
struct Combat {
    struct Identity: Decodable { let id: String; let name: String; let image: String }
}

@main struct NativeReview {
    static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let roster = try JSONDecoder().decode([Combat.Identity].self, from: Data(contentsOf:
            assetBundle.url(forResource: "roster", withExtension: "json", subdirectory: "NPCPortraits")!))
        precondition(roster.count == 42)
        precondition(ZombieAppearance.metadataValidationIssues(identityIDs: roster.map(\.id)).isEmpty)
        precondition(ZombieAppearance.bodyStyle(for: "unlisted-person") == .neutral)
        let scene = SCNScene()
        scene.background.contents = NSColor(white: 0.055, alpha: 1)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera!.zNear = 0.02
        camera.camera!.fieldOfView = 45
        camera.camera!.wantsHDR = true
        camera.camera!.exposureOffset = -0.45
        scene.rootNode.addChildNode(camera)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 40
        scene.rootNode.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .omni
        key.light!.intensity = 100
        key.position = SCNVector3(-2, 4, 4)
        scene.rootNode.addChildNode(key)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        var nodes: [String: SCNNode] = [:]
        for identity in roster {
            let node = ZombieAppearance.make(identity: identity, index: roster.firstIndex { $0.id == identity.id }! % 4)
            let face = node.childNode(withName: "Face.\(identity.id)", recursively: true)!
            precondition(face.geometry!.sources(for: .texcoord).count == 1)
            precondition(face.geometry!.sources(for: .color).count == 1)
            precondition(face.geometry!.firstMaterial!.diffuse.contents is NSImage)
            var triangles = 0
            node.childNode(withName: "Office zombie", recursively: true)!.enumerateChildNodes { child, _ in
                triangles += child.geometry?.elements.reduce(0) { $0 + $1.primitiveCount } ?? 0
            }
            precondition(triangles == 52013)

            node.isHidden = true
            scene.rootNode.addChildNode(node)
            nodes[identity.id] = node
        }
        let actor = nodes["aditya"]!
        let independent = ZombieAppearance.make(identity: roster.first { $0.id == "aditya" }!, index: 0)
        let firstHand = CharacterAnimation.attachment("leftHand", on: actor)!
        let otherHand = CharacterAnimation.attachment("leftHand", on: independent)!
        precondition(firstHand !== otherHand)
        let otherRest = otherHand.simdTransform
        let firstRest = firstHand.simdWorldPosition
        precondition(ZombieAppearance.sampleMotion("swipe", at: 0.34, on: actor))
        precondition(simd_distance(firstRest, firstHand.simdWorldPosition) > 0.04)
        precondition(otherHand.simdTransform == otherRest)
        let face = actor.childNode(withName: "Face.aditya", recursively: true)!
        precondition(face.skinner?.baseGeometry?.firstMaterial?.name == "NPC face.aditya")
        precondition(face.skinner!.bones.contains { $0 === CharacterAnimation.attachment("head", on: actor) })
        for node in nodes.values { _ = ZombieAppearance.sampleMotion("walk", at: 0, on: node) }
        precondition(renderer.prepare(scene, shouldAbortBlock: nil))
        let nameNode = nodes["aditya"]!.childNode(withName: "Name.aditya", recursively: true)!
        let nameGlyphs = nameNode.childNodes[0]
        print("NAME_GEOMETRY", nameGlyphs.geometry!.boundingBox, nameGlyphs.simdScale,
              (nameGlyphs.geometry as? SCNText)?.string ?? "missing")
        func save(_ name: String, _ size: CGSize) throws {
            SCNTransaction.flush()
            let frame = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
            let data = NSBitmapImageRep(data: frame.tiffRepresentation!)!.representation(using: .png, properties: [:])!
            try data.write(to: output.appendingPathComponent(name))
        }
        let chosen = ["aditya", "amber", "alan", "jane"]
        for (index, id) in chosen.enumerated() {
            let node = nodes[id]!
            node.isHidden = false
            node.simdPosition.x = Float(index) * 0.95 - 1.425
        }
        camera.position = SCNVector3(0, 1.5, 4.5)
        camera.look(at: SCNVector3(0, 0.95, 0))
        try save("office-bodies-native.png", CGSize(width: 1600, height: 1000))
        for (index, id) in chosen.enumerated() {
            _ = ZombieAppearance.sampleMotion("walk", at: Double(index) * 0.21 + 0.18, on: nodes[id]!)
        }
        try save("infected-articulated-strides-native.png", CGSize(width: 1600, height: 1000))
        for (index, id) in chosen.enumerated() {
            _ = ZombieAppearance.sampleMotion(index.isMultiple(of: 2) ? "swipe" : "bite", at: 0.34, on: nodes[id]!)
        }
        try save("infected-melee-contact-native.png", CGSize(width: 1600, height: 1000))
        for node in nodes.values {
            _ = ZombieAppearance.sampleMotion("idle", at: 0, on: node)
            node.isHidden = true; node.position = SCNVector3Zero
        }
        for id in ["aditya", "amber", "jane", "jia-yi"] {
            nodes[id]!.isHidden = false
            camera.position = SCNVector3(-0.07, 1.54, 0.86)
            camera.look(at: SCNVector3(-0.07, 1.54, 0.22))
            try save("\(id)-office-face-native.png", CGSize(width: 650, height: 650))
            nodes[id]!.isHidden = true
        }
        for (index, identity) in roster.enumerated() {
            let node = nodes[identity.id]!
            node.isHidden = false
            node.position = SCNVector3(Float(index % 7) * 0.9 - 2.7, Float(5 - index / 7) * 2.15, 0)
        }
        camera.camera!.usesOrthographicProjection = true
        camera.camera!.orthographicScale = 7
        camera.position = SCNVector3(0, 6.25, 12)
        camera.look(at: SCNVector3(0, 6.25, 0))
        try save("all-42-office-identities-native.png", CGSize(width: 1500, height: 2200))
        print("PASS: 42 identity mappings, independent weighted limbs, mapped face skin bindings, walk/swipe/bite samples, and 52,013 triangles per body")
    }
}
