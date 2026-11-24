import Foundation
import simd

struct DesktopMovementInput: Equatable {
    var move = SIMD2<Float>.zero
    var look = SIMD2<Float>.zero
    var isNeutral: Bool { move == .zero && look == .zero }
}

/// Requires a fresh key press after a pause, restart, or tracking-mode change.
struct DesktopMovement {
    private var awaitingRelease = false

    mutating func reset() { awaitingRelease = true }

    mutating func update(_ input: DesktopMovementInput, enabled: Bool) -> DesktopMovementInput {
        guard enabled else {
            reset()
            return DesktopMovementInput()
        }
        if awaitingRelease {
            awaitingRelease = !input.isNeutral
            return DesktopMovementInput()
        }
        return input
    }
}

/// Converts measured phone translation into floor movement, never inertial integration.
struct PhoneWalking {
    private var session: UUID?
    private var lastTimestamp: TimeInterval?
    private var previous: SIMD3<Float>?
    private var filtered: SIMD3<Float>?
    private var applied: SIMD3<Float>?
    private var alignment: simd_quatf?

    mutating func reset() {
        session = nil
        lastTimestamp = nil
        rebase()
        alignment = nil
    }

    mutating func rebase() {
        previous = nil
        filtered = nil
        applied = nil
    }

    mutating func update(
        _ sample: PhonePositionSample, at time: TimeInterval, viewHeading: Float, enabled: Bool
    ) -> SIMD3<Float> {
        guard time.isFinite, time >= 0 else { return .zero }
        if session != sample.session {
            reset()
            session = sample.session
        }
        if let lastTimestamp, time <= lastTimestamp { return .zero }
        let elapsed = lastTimestamp.map { time - $0 }
        lastTimestamp = time
        guard enabled, sample.quality == .tracking,
            [sample.x, sample.y, sample.z, sample.heading, viewHeading].allSatisfy(\.isFinite)
        else {
            rebase()
            return .zero
        }
        let position = SIMD3(sample.x, sample.y, sample.z)
        guard let previous, let elapsed, elapsed <= 0.3,
            simd_distance(position, previous) <= min(0.4, Float(elapsed) * 3 + 0.08)
        else {
            self.previous = position
            filtered = position
            applied = position
            if alignment == nil {
                alignment = simd_quatf(angle: viewHeading - sample.heading, axis: SIMD3(0, 1, 0))
            }
            return .zero
        }
        self.previous = position
        let weight = Float(1 - exp(-elapsed / 0.10))
        let next = simd_mix(filtered ?? position, position, SIMD3(repeating: weight))
        filtered = next
        var displacement = next - (applied ?? next)
        displacement.y = 0
        guard simd_length(displacement) >= 0.025 else { return .zero }
        applied = next
        // A delayed batch must not turn accumulated travel into one visual jump.
        guard simd_length(displacement) <= 0.15 else {
            rebase()
            return .zero
        }
        return (alignment ?? simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))).act(displacement)
    }
}
