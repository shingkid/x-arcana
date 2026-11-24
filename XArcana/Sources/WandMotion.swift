import CoreMotion
import simd

final class WandMotion {
    private let manager = CMMotionManager()
    private var latest: CMDeviceMotion?
    private var center: SIMD2<Double>?
    var onFailure: (() -> Void)?
    var hasMotion: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard hasMotion, !manager.isDeviceMotionActive else { return }
        center = nil
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] sample, error in
            self?.latest = sample
            if error != nil {
                self?.stop()
                self?.onFailure?()
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        latest = nil
        center = nil
    }

    // The second row gives the direction of the phone's top edge in a gravity-aligned frame.
    static func angles(from r: CMRotationMatrix) -> SIMD2<Double>? {
        let horizontal = hypot(r.m21, r.m22)
        guard horizontal > 0.035 else { return nil }
        return SIMD2(atan2(r.m21, r.m22), atan2(r.m23, horizontal))
    }

    func relativeAngles() -> SIMD2<Float>? {
        guard let latest, ProcessInfo.processInfo.systemUptime - latest.timestamp < 0.25,
            let angles = Self.angles(from: latest.attitude.rotationMatrix)
        else { return nil }
        let origin = center ?? angles
        center = origin
        let delta = angles - origin
        return SIMD2(Float(atan2(sin(delta.x), cos(delta.x))), Float(delta.y))
    }
}
