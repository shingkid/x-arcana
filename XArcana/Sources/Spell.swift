import CoreGraphics
import Foundation

struct CastRune: Equatable {
    /// An unrecognized stroke releases a burst of sparks.
    let kind: RuneKind?
    let point: SIMD3<Float>
}

/// Pairs one continuous touch with the place the player was looking at on touch-down.
struct Spell {
    private var rune = RuneCasting()
    private(set) var point: SIMD3<Float>?
    var isHolding: Bool { point != nil }
    var trace: [CGPoint] { rune.normalizedTrace }
    var preview: RuneKind? { isHolding ? rune.preview : nil }

    mutating func begin(at location: SIMD3<Float>, angles: SIMD2<Float>?, time: TimeInterval) {
        guard !isHolding else { return }
        point = location
        rune.begin(angles: angles, at: time)
    }

    mutating func sample(_ angles: SIMD2<Float>?, at time: TimeInterval) {
        guard isHolding else { return }
        rune.update(angles: angles, at: time)
    }

    mutating func release(angles: SIMD2<Float>?, at time: TimeInterval) -> CastRune? {
        guard let point else { return nil }
        self.point = nil
        return CastRune(kind: rune.finish(angles: angles, at: time), point: point)
    }

    mutating func cancel() {
        point = nil
        rune.cancel()
    }
}
