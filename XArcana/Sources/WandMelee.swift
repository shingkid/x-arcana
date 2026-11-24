import Foundation
import simd

/// Recognizes deliberate unheld swings. Combat owns reach, damage, and the simulation cooldown.
struct WandMelee {
    private struct Sample {
        let point: SIMD2<Float>
        let time: TimeInterval
    }

    private var previousAngles: SIMD2<Float>?
    private var previousTime: TimeInterval?
    private var latestTime: TimeInterval?
    private var point = SIMD2<Float>.zero
    private var samples: [Sample] = []
    private var swingDirection: SIMD2<Float>?

    mutating func reset(newController: Bool = false) {
        previousAngles = nil
        previousTime = nil
        point = .zero
        samples.removeAll(keepingCapacity: true)
        swingDirection = nil
        if newController { latestTime = nil }
    }

    mutating func sample(angles: SIMD2<Float>?, at time: TimeInterval, enabled: Bool) -> Bool {
        guard time.isFinite, time >= 0, latestTime.map({ time > $0 }) ?? true else {
            reset()
            return false
        }
        latestTime = time
        guard enabled, let angles, angles.x.isFinite, angles.y.isFinite else {
            reset()
            return false
        }
        guard let previousAngles, let previousTime else {
            self.previousAngles = angles
            self.previousTime = time
            samples = [Sample(point: point, time: time)]
            return false
        }
        let elapsed = time - previousTime
        let yaw = angles.x - previousAngles.x
        let delta = SIMD2(atan2(sin(yaw), cos(yaw)), angles.y - previousAngles.y)
        self.previousAngles = angles
        self.previousTime = time
        let speed = simd_length(delta) / Float(elapsed)
        guard elapsed <= 0.3, speed <= 12 else {
            reset()
            return false
        }
        point += delta
        if let swingDirection {
            guard speed < 0.35 || simd_dot(delta, swingDirection) < 0 else { return false }
            self.swingDirection = nil
            samples = [Sample(point: point - delta, time: previousTime)]
        }
        samples.append(Sample(point: point, time: time))
        samples.removeAll { time - $0.time > 0.3 }
        guard let first = samples.first else { return false }
        let duration = time - first.time
        let travel = point - first.point
        let distance = simd_length(travel)
        guard duration >= 0.08, distance >= 0.18, distance / Float(duration) >= 0.8 else { return false }
        let path = zip(samples, samples.dropFirst()).reduce(Float.zero) {
            $0 + simd_distance($1.0.point, $1.1.point)
        }
        guard path > 0, distance / path >= 0.65 else { return false }
        swingDirection = simd_normalize(travel)
        samples.removeAll(keepingCapacity: true)
        return true
    }
}
