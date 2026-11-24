import SceneKit
import UIKit

/// Two sections show bow hits; partial sections retain spell damage precisely.
final class ZombieHealthBar: SCNNode {
    private var fills: [SCNNode] = []
    private var continuousFill: SCNNode?

    func useContinuousFill() {
        guard continuousFill == nil else { return }
        let fill = addPlane(
            width: 0.71, height: 0.05, color: UIColor(red: 1, green: 0.34, blue: 0.27, alpha: 1), z: 0.002)
        fill.pivot = SCNMatrix4MakeTranslation(-0.355, 0, 0)
        fill.position.x = -0.355
        continuousFill = fill
        for segment in fills { segment.isHidden = true }
    }

    override init() {
        super.init()
        name = "Zombie health"
        position = SCNVector3(0, 1.79, 0)
        categoryBitMask = 2
        castsShadow = false
        constraints = [SCNBillboardConstraint()]
        addPlane(width: 0.75, height: 0.086, color: UIColor(white: 0.88, alpha: 1), z: 0)
        addPlane(width: 0.73, height: 0.066, color: UIColor(white: 0.055, alpha: 1), z: 0.001)
        for index in 0..<2 {
            let fill = addPlane(
                width: 0.35, height: 0.05, color: UIColor(red: 1, green: 0.34, blue: 0.27, alpha: 1), z: 0.002)
            fill.name = "Health segment \(index + 1)"
            // Scale around the left edge so fractional damage drains each section in place.
            fill.pivot = SCNMatrix4MakeTranslation(-0.175, 0, 0)
            fill.position.x = -0.355 + Float(index) * 0.36
            fills.append(fill)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(health: Double, maximum: Double) {
        let fraction = health.isFinite && maximum.isFinite && maximum > 0 ? min(1, max(0, health / maximum)) : 0
        isHidden = fraction <= 0
        if let continuousFill {
            continuousFill.simdScale.x = Float(fraction)
            return
        }
        for (index, fill) in fills.enumerated() {
            let raw = min(1, max(0, fraction * 2 - Double(index)))
            let amount = raw < 1e-9 ? 0 : (raw > 1 - 1e-9 ? 1 : raw)
            fill.simdScale.x = Float(amount)
            fill.isHidden = amount <= 0
        }
    }

    @discardableResult
    private func addPlane(width: CGFloat, height: CGFloat, color: UIColor, z: Float) -> SCNNode {
        let geometry = SCNPlane(width: width, height: height)
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.position.z = z
        node.categoryBitMask = 2
        node.castsShadow = false
        addChildNode(node)
        return node
    }
}
