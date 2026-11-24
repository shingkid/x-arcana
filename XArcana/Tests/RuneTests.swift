import XCTest

@testable import XArcana

final class RuneTests: XCTestCase {
    private let bolt = [
        CGPoint(x: 0, y: 0), CGPoint(x: -0.22, y: -0.24),
        CGPoint(x: 0.02, y: -0.24), CGPoint(x: -0.20, y: -0.50),
    ]

    private func trace(_ corners: [CGPoint], samples: Int = 20, jitter: CGFloat = 0) -> [CGPoint] {
        var result = [corners[0]]
        for segment in 1..<corners.count {
            let a = corners[segment - 1]
            let b = corners[segment]
            for i in 1...samples {
                let t = CGFloat(i) / CGFloat(samples)
                let noise = sin(CGFloat(i) * 1.7) * jitter
                result.append(
                    CGPoint(
                        x: a.x + (b.x - a.x) * t + noise,
                        y: a.y + (b.y - a.y) * t - noise * 0.6))
            }
        }
        return result
    }

    private func circle(
        radius: CGFloat = 0.3, phase: CGFloat = 0, clockwise: Bool = false,
        jitter: CGFloat = 0
    ) -> [CGPoint] {
        (0...90).map { i in
            let angle = phase + CGFloat(i) * .pi / 45 * (clockwise ? -1 : 1)
            let r = radius + sin(CGFloat(i) * 2.3) * jitter
            return CGPoint(x: r * cos(angle), y: r * sin(angle))
        }
    }

    private func polygon(sides: Int, radius: CGFloat = 0.14) -> [CGPoint] {
        trace(
            (0...sides).map { i in
                let angle = CGFloat(i) * 2 * .pi / CGFloat(sides)
                return CGPoint(x: radius * cos(angle), y: radius * sin(angle))
            }, samples: 10)
    }

    private func star(
        radius: CGFloat = 0.3, phase: CGFloat = 0, start: Int = 0,
        clockwise: Bool = false, outline: Bool = false, imperfect: Bool = false
    ) -> [CGPoint] {
        let count = outline ? 10 : 5
        let corners = (0...count).map { i -> CGPoint in
            let vertex = outline ? (start * 2 + i) % 10 : (start + i * 2) % 5
            let angle = phase + CGFloat(vertex) * 2 * .pi / CGFloat(count) * (clockwise ? -1 : 1)
            let variation: CGFloat = imperfect ? 1 + 0.09 * sin(CGFloat(vertex) * 2.4) : 1
            let r = radius * variation * (outline && vertex % 2 == 1 ? 0.46 : 1)
            return CGPoint(x: r * cos(angle) * (imperfect ? 1.1 : 1), y: r * sin(angle))
        }
        return trace(corners, samples: 20, jitter: imperfect ? 0.004 : 0)
    }

    private func sample(_ path: [CGPoint], fraction: Double) -> CGPoint {
        let position = max(0, min(1, fraction)) * Double(path.count - 1)
        let index = min(path.count - 2, Int(position))
        let t = position - Double(index)
        return CGPoint(
            x: path[index].x + (path[index + 1].x - path[index].x) * t,
            y: path[index].y + (path[index + 1].y - path[index].y) * t)
    }

    @discardableResult
    private func feed(
        _ path: [CGPoint], into rune: inout RuneCasting, fps: Int = 60,
        duration: TimeInterval = 1.5, start: SIMD2<Float> = .zero,
        at beginning: TimeInterval = 0, jitter: CGFloat = 0
    ) -> SIMD2<Float> {
        let frames = max(1, Int(round(duration * Double(fps))))
        var angles = start
        for frame in 0...frames {
            let elapsed = duration * (Double(frame) / Double(frames))
            let point = sample(path, fraction: elapsed / duration)
            let noise = jitter * sin(elapsed * 23)
            let yaw = Double(start.x) + Double(point.x - path[0].x + noise)
            angles = SIMD2(Float(atan2(sin(yaw), cos(yaw))), start.y + Float(point.y - path[0].y - noise * 0.7))
            rune.update(angles: angles, at: beginning + elapsed)
        }
        return angles
    }

    func testRecognizesStarFromEveryTipInEitherDirectionAndRotation() {
        for clockwise in [false, true] {
            for start in 0..<5 {
                for phase: CGFloat in [0, 0.4, 1.2] {
                    for radius: CGFloat in [0.15, 0.3, 0.5] {
                        XCTAssertEqual(
                            RuneRecognizer.recognize(
                                star(
                                    radius: radius, phase: phase, start: start,
                                    clockwise: clockwise)), .summon)
                    }
                }
            }
        }
    }

    func testImperfectCrossingAndOutlineStarsAreRecognized() {
        for outline in [false, true] {
            for clockwise in [false, true] {
                for phase: CGFloat in [0, 0.7, 2.5] {
                    XCTAssertEqual(
                        RuneRecognizer.recognize(
                            star(
                                phase: phase, clockwise: clockwise,
                                outline: outline, imperfect: true)), .summon)
                }
            }
        }
    }

    func testAllRunesCastOnReleaseAtDifferentFrameRatesWithoutAStillnessWait() {
        for fps in [30, 60, 120] {
            for (path, kind, duration) in [
                (trace(bolt), RuneKind.zap, 1.5), (circle(), .fireball, 1.8),
                (star(imperfect: true), .summon, 2.2),
                (star(outline: true), .summon, 2.8),
            ] {
                var rune = RuneCasting()
                rune.begin(angles: .zero, at: 0)
                let end = feed(path, into: &rune, fps: fps, duration: duration, jitter: 0.003)
                XCTAssertTrue(rune.isDrawing)
                XCTAssertEqual(rune.finish(angles: end, at: duration), kind, "Rate \(fps), kind \(kind)")
                XCTAssertFalse(rune.isDrawing)
                XCTAssertTrue(rune.normalizedTrace.isEmpty)
                XCTAssertNil(rune.finish(angles: end, at: duration + 0.01))
            }
        }
    }

    func testRetiredWStaysUnrecognizedAcrossScaleSpeedDirectionAndOffset() {
        let variants = [
            [
                CGPoint(x: 0, y: 0), CGPoint(x: 0.10, y: -0.3), CGPoint(x: 0.2, y: 0),
                CGPoint(x: 0.3, y: -0.3), CGPoint(x: 0.4, y: 0),
            ],
            [
                CGPoint(x: 0, y: 0.04), CGPoint(x: 0.07, y: -0.27), CGPoint(x: 0.21, y: -0.05),
                CGPoint(x: 0.32, y: -0.36), CGPoint(x: 0.49, y: 0),
            ],
        ]
        for corners in variants {
            for scale: CGFloat in [0.3, 0.65, 1, 2.2] {
                let path = trace(
                    corners.map { CGPoint(x: $0.x * scale + 0.73, y: $0.y * scale - 0.24) },
                    jitter: 0.002 * scale)
                for reverse in [false, true] {
                    let drawn = reverse ? Array(path.reversed()) : path
                    XCTAssertNil(RuneRecognizer.recognize(drawn))
                    for fps in [30, 60, 120] {
                        for duration in [0.2, 0.75, 2.8] {
                            var rune = RuneCasting()
                            rune.begin(angles: .zero, at: 0)
                            let end = feed(drawn, into: &rune, fps: fps, duration: duration)
                            XCTAssertNil(rune.preview, "scale \(scale), fps \(fps), duration \(duration)")
                            XCTAssertTrue(rune.isDrawing)
                            XCTAssertNil(rune.finish(angles: end, at: duration))
                            XCTAssertNil(rune.preview)
                        }
                    }
                }
            }
        }
    }

    func testRetiredWStaysUnrecognizedWithShallowRoundedShortAndUnevenStrokes() {
        let uneven = [
            CGPoint(x: 0, y: -0.07), CGPoint(x: 0.06, y: -0.32),
            CGPoint(x: 0.19, y: -0.19), CGPoint(x: 0.27, y: -0.36), CGPoint(x: 0.43, y: -0.1),
        ]
        let shallow = [
            CGPoint.zero, CGPoint(x: 0.1, y: -0.07), CGPoint(x: 0.2, y: -0.01),
            CGPoint(x: 0.29, y: -0.08), CGPoint(x: 0.4, y: -0.005),
        ]
        var rounded = [
            CGPoint.zero, CGPoint(x: 0.1, y: -0.3), CGPoint(x: 0.2, y: -0.01),
            CGPoint(x: 0.3, y: -0.33), CGPoint(x: 0.4, y: 0),
        ]
        for _ in 0..<3 {
            var smoothed = [rounded[0]]
            for (a, b) in zip(rounded, rounded.dropFirst()) {
                smoothed.append(CGPoint(x: a.x * 0.75 + b.x * 0.25, y: a.y * 0.75 + b.y * 0.25))
                smoothed.append(CGPoint(x: a.x * 0.25 + b.x * 0.75, y: a.y * 0.25 + b.y * 0.75))
            }
            smoothed.append(rounded.last!)
            rounded = smoothed
        }
        for (variant, path) in [trace(uneven, jitter: 0.001), trace(shallow), rounded].enumerated() {
            for scale: CGFloat in [0.65, 1, 2] {
                let translated = path.map { CGPoint(x: $0.x * scale + 0.7, y: $0.y * scale - 0.2) }
                for reverse in [false, true] {
                    let drawn = reverse ? Array(translated.reversed()) : translated
                    XCTAssertNil(RuneRecognizer.recognize(drawn), "variant \(variant), scale \(scale)")
                    for duration in [0.3, 0.6, 1.3, 4.0] {
                        for fps in [30, 60] {
                            var rune = RuneCasting()
                            let start = SIMD2<Float>(3.08, -0.2)
                            rune.begin(angles: start, at: 0)
                            let end = feed(drawn, into: &rune, fps: fps, duration: duration, start: start)
                            XCTAssertNil(
                                rune.finish(angles: end, at: duration),
                                "variant \(variant), scale \(scale), duration \(duration), fps \(fps)")
                        }
                    }
                }
            }
        }
    }

    func testZigzagsCannotBecomeRetiredNyanRune() {
        for count in [2, 6, 8] {
            let corners = (0...count).map { i in
                CGPoint(x: CGFloat(i) * 0.1, y: i % 2 == 0 ? 0 : -0.3)
            }
            XCTAssertNotEqual(RuneRecognizer.recognize(trace(corners)), .nyan)
        }
        let upsideDown = trace([
            CGPoint.zero, CGPoint(x: 0.1, y: 0.3), CGPoint(x: 0.2, y: 0),
            CGPoint(x: 0.3, y: 0.3), CGPoint(x: 0.4, y: 0),
        ])
        XCTAssertNotEqual(RuneRecognizer.recognize(upsideDown), .nyan)
        XCTAssertEqual(RuneRecognizer.recognize(trace(bolt)), .zap)
        XCTAssertEqual(RuneRecognizer.recognize(circle()), .fireball)
        XCTAssertEqual(RuneRecognizer.recognize(star(imperfect: true)), .summon)
    }

    func testFormerDirectionalGesturesAreVoiceOnly() {
        XCTAssertEqual(RuneKind.gestureCases, [.zap, .fireball, .ice, .shield, .summon])
        for destination in [
            CGPoint(x: 0.3, y: 0.02), CGPoint(x: -0.3, y: 0.04),
            CGPoint(x: 0.03, y: 0.3), CGPoint(x: -0.02, y: -0.3),
        ] {
            let path = trace([.zero, destination], jitter: 0.002)
            XCTAssertNil(RuneRecognizer.recognize(path))
            for duration in [0.2, 0.8, 3.0] {
                var rune = RuneCasting()
                rune.begin(angles: .zero, at: 0)
                let end = feed(path, into: &rune, duration: duration)
                XCTAssertNil(rune.preview)
                XCTAssertNil(rune.finish(angles: end, at: duration))
            }
        }
    }

    func testLooseZUnevenVAndOpenOvalsAcrossScaleSpeedDirectionAndOffset() {
        let z = trace(
            [
                .zero, CGPoint(x: 0.32, y: 0.025), CGPoint(x: 0.025, y: -0.26),
                CGPoint(x: 0.36, y: -0.235),
            ], jitter: 0.002)
        let v = trace(
            [
                CGPoint(x: 0, y: 0.05), CGPoint(x: 0.14, y: -0.28),
                CGPoint(x: 0.39, y: -0.025),
            ], jitter: 0.002)
        let oval = circle(radius: 0.22, phase: 0.4, jitter: 0.003).dropLast(17).map {
            CGPoint(x: $0.x * 0.58 + $0.y * 0.12, y: $0.y)
        }
        for (path, expected) in [(z, RuneKind.zap), (v, .ice), (oval, .fireball)] {
            for scale: CGFloat in [0.3, 0.65, 1, 2.2] {
                let translated = path.map { CGPoint(x: $0.x * scale + 0.73, y: $0.y * scale - 0.24) }
                for reverse in [false, true] {
                    let drawn = reverse ? Array(translated.reversed()) : translated
                    XCTAssertEqual(RuneRecognizer.recognize(drawn), expected)
                    for fps in [30, 60, 120] {
                        for duration in [0.2, 0.75, 2.8] {
                            var rune = RuneCasting()
                            rune.begin(angles: .zero, at: 0)
                            let end = feed(
                                drawn, into: &rune, fps: fps, duration: duration,
                                jitter: 0.001 * scale)
                            let context = "\(expected), scale \(scale), reverse \(reverse), \(fps)fps, \(duration)s"
                            XCTAssertEqual(rune.preview, expected, context)
                            XCTAssertTrue(rune.isDrawing)
                            XCTAssertEqual(rune.finish(angles: end, at: duration), expected, context)
                            XCTAssertNil(rune.preview)
                        }
                    }
                }
            }
        }
    }

    func testUnevenSpeedPausesAndYawWrapKeepZAndV() {
        for corners in [
            [CGPoint.zero, CGPoint(x: 0.3, y: 0.01), CGPoint(x: 0, y: -0.3), CGPoint(x: 0.3, y: -0.3)],
            [CGPoint.zero, CGPoint(x: 0.15, y: -0.3), CGPoint(x: 0.4, y: -0.04)],
        ] {
            let expected: RuneKind = corners.count == 4 ? .zap : .ice
            let path = trace(corners)
            for accelerating in [false, true] {
                let sampled = (0...90).map { i -> CGPoint in
                    let t = Double(i) / 90
                    return sample(path, fraction: accelerating ? t * t * t : 1 - pow(1 - t, 3))
                }
                let start = SIMD2<Float>(3.1, 0.2)
                var rune = RuneCasting()
                rune.begin(angles: start, at: 0)
                let middle = feed(Array(sampled.prefix(46)), into: &rune, duration: 0.4, start: start)
                for frame in 1...60 { rune.update(angles: middle, at: 0.4 + Double(frame) / 60) }
                let end = feed(Array(sampled.suffix(46)), into: &rune, duration: 0.7, start: middle, at: 1.4)
                XCTAssertEqual(rune.finish(angles: end, at: 2.1), expected)
            }
        }
    }

    func testSymmetricAndRoundedVsStayIceInsteadOfFire() {
        let sharp = trace([
            CGPoint(x: 0, y: 0), CGPoint(x: 0.18, y: -0.36), CGPoint(x: 0.36, y: 0),
        ])
        let rounded = sharp.indices.map { i -> CGPoint in
            let neighbors = sharp[max(0, i - 3)...min(sharp.count - 1, i + 3)]
            return CGPoint(
                x: neighbors.reduce(0) { $0 + $1.x } / CGFloat(neighbors.count),
                y: neighbors.reduce(0) { $0 + $1.y } / CGFloat(neighbors.count))
        }
        for (variant, path) in [sharp, rounded].enumerated() {
            for scale: CGFloat in [0.3, 1, 2.2] {
                let translated = path.map { CGPoint(x: $0.x * scale + 0.7, y: $0.y * scale - 0.2) }
                for reverse in [false, true] {
                    let drawn = reverse ? Array(translated.reversed()) : translated
                    let context = "variant \(variant), scale \(scale), reverse \(reverse)"
                    XCTAssertEqual(RuneRecognizer.recognize(drawn), .ice, context)
                    for duration in [0.3, 0.8, 3.5] {
                        for fps in [30, 60, 120] {
                            var rune = RuneCasting()
                            rune.begin(angles: .zero, at: 0)
                            let end = feed(drawn, into: &rune, fps: fps, duration: duration)
                            let capture = "\(context), \(duration)s at \(fps)fps"
                            XCTAssertEqual(rune.preview, .ice, capture)
                            XCTAssertEqual(rune.finish(angles: end, at: duration), .ice, capture)
                        }
                    }
                }
            }
        }
    }

    func testShieldReadinessNeedsAContinuousSecondAndOnlyReleaseCasts() {
        var rune = RuneCasting()
        rune.begin(angles: .zero, at: 0)
        for frame in 1...59 {
            rune.update(angles: .zero, at: Double(frame) / 60)
            XCTAssertNil(rune.preview)
        }
        rune.update(angles: .zero, at: 1)
        XCTAssertEqual(rune.preview, .shield)
        XCTAssertTrue(rune.isDrawing)
        for frame in 61...120 { rune.update(angles: .zero, at: Double(frame) / 60) }
        XCTAssertEqual(rune.preview, .shield)
        XCTAssertEqual(rune.finish(angles: .zero, at: 2), .shield)
        XCTAssertNil(rune.preview)
        XCTAssertNil(rune.finish(angles: .zero, at: 2.1))
        rune.begin(angles: .zero, at: 3)
        for frame in 1...59 { rune.update(angles: .zero, at: 3 + Double(frame) / 60) }
        XCTAssertNil(rune.finish(angles: .zero, at: 3.99))
    }

    func testShieldAllowsTremorButDrawingThenPausingCannotChargeIt() {
        var rune = RuneCasting()
        rune.begin(angles: .zero, at: 0)
        for frame in 1...90 {
            let time = Double(frame) / 60
            rune.update(angles: SIMD2(Float(sin(time * 23) * 0.028), Float(cos(time * 17) * 0.023)), at: time)
        }
        XCTAssertEqual(rune.preview, .shield)
        XCTAssertEqual(rune.finish(angles: .zero, at: 1.51), .shield)
        rune.begin(angles: .zero, at: 2)
        let end = feed(trace([.zero, CGPoint(x: 0.2, y: 0)]), into: &rune, duration: 0.4, at: 2)
        for frame in 1...90 { rune.update(angles: end, at: 2.4 + Double(frame) / 60) }
        XCTAssertNil(rune.preview)
        XCTAssertNil(rune.finish(angles: end, at: 3.91))
    }

    func testMovingAfterShieldReadinessCancelsItAndCanDrawARune() {
        var rune = RuneCasting()
        rune.begin(angles: .zero, at: 0)
        for frame in 1...60 { rune.update(angles: .zero, at: Double(frame) / 60) }
        XCTAssertEqual(rune.preview, .shield)
        let path = trace([.zero, CGPoint(x: 0.3, y: 0), CGPoint(x: 0, y: -0.3), CGPoint(x: 0.3, y: -0.3)])
        let end = feed(path, into: &rune, duration: 0.8, at: 1)
        XCTAssertEqual(rune.preview, .zap)
        XCTAssertEqual(rune.finish(angles: end, at: 1.8), .zap)
    }

    func testTrackingLossInvalidAnglesAndCancellationClearShieldReadiness() {
        for failure in 0..<5 {
            var rune = RuneCasting()
            rune.begin(angles: .zero, at: 0)
            for frame in 1...60 { rune.update(angles: .zero, at: Double(frame) / 60) }
            XCTAssertEqual(rune.preview, .shield)
            switch failure {
            case 0: rune.update(angles: nil, at: 1.01)
            case 1: rune.update(angles: SIMD2(.nan, 0), at: 1.01)
            case 2: rune.update(angles: SIMD2(1, 0), at: 1.01)
            case 3: rune.update(angles: .zero, at: 1.5)
            default: rune.cancel()
            }
            XCTAssertNil(rune.preview)
            XCTAssertNil(rune.finish(angles: .zero, at: 1.51))
        }
        var lost = RuneCasting()
        lost.begin(angles: .zero, at: 0)
        for frame in 1...30 { lost.update(angles: .zero, at: Double(frame) / 60) }
        lost.update(angles: nil, at: 0.51)
        for frame in 32...120 { lost.update(angles: .zero, at: Double(frame) / 60) }
        XCTAssertNil(lost.preview)
        XCTAssertNil(lost.finish(angles: .zero, at: 2))
    }

    func testLegacyLightningTurnsRemainValidOnRelease() {
        for scale: CGFloat in [0.36, 0.7, 1.4] {
            for mirror: CGFloat in [-1, 1] {
                let path = trace(bolt.map { CGPoint(x: $0.x * scale * mirror, y: $0.y * scale) })
                for reverse in [false, true] {
                    for duration in [0.3, 1.2, 3.0] {
                        var rune = RuneCasting()
                        rune.begin(angles: .zero, at: 0)
                        let end = feed(
                            reverse ? path.reversed() : path, into: &rune,
                            duration: duration, jitter: 0.002)
                        XCTAssertEqual(rune.finish(angles: end, at: duration), .zap)
                    }
                }
            }
        }
    }

    func testForgivingHandDrawnRunesOnRelease() {
        let oval = circle(radius: 0.17, jitter: 0.006).prefix(79).map {
            CGPoint(x: $0.x * 0.53 + $0.y * 0.19, y: $0.y)
        }
        let zigzag = trace([
            .zero, CGPoint(x: -0.09, y: -0.11),
            CGPoint(x: -0.035, y: -0.055), CGPoint(x: -0.12, y: -0.21),
        ])
        let openStar = star(radius: 0.19, phase: 0.4, imperfect: true).dropLast(7).map {
            CGPoint(x: $0.x * 0.70 + $0.y * 0.13, y: $0.y)
        }
        let openOutline = star(radius: 0.20, phase: 0.5, outline: true, imperfect: true)
            .dropLast(12).map { CGPoint(x: $0.x, y: $0.y * 0.73) }
        let cases: [([CGPoint], RuneKind)] = [
            (oval, .fireball), (zigzag, .zap),
            (zigzag.map { CGPoint(x: -$0.x, y: $0.y) }, .zap), (openStar, .summon), (openOutline, .summon),
        ]
        for fps in [30, 60, 120] {
            for (path, expected) in cases {
                var rune = RuneCasting()
                rune.begin(angles: .zero, at: 0)
                let end = feed(path, into: &rune, fps: fps, duration: 1.2)
                XCTAssertEqual(rune.finish(angles: end, at: 1.2), expected, "\(expected) at \(fps) fps")
            }
        }
    }

    func testEasyStarsCastOnReleaseDespiteMissedClosureAndUnevenTips() {
        let crossing = star(radius: 0.19, phase: 0.4)
        let lastDirection = CGPoint(
            x: crossing.last!.x - crossing[80].x,
            y: crossing.last!.y - crossing[80].y)
        let overshoot =
            crossing
            + trace([
                crossing.last!,
                CGPoint(
                    x: crossing.last!.x + lastDirection.x * 0.24,
                    y: crossing.last!.y + lastDirection.y * 0.24),
            ])
        let uneven = star(radius: 0.20, phase: 0.8, clockwise: true, imperfect: true)
            .map { CGPoint(x: $0.x * 0.56 + $0.y * 0.18, y: $0.y) }
        let rounded = uneven.indices.map { i -> CGPoint in
            let neighbors = uneven[max(0, i - 3)...min(uneven.count - 1, i + 3)]
            return CGPoint(
                x: neighbors.reduce(0) { $0 + $1.x } / CGFloat(neighbors.count),
                y: neighbors.reduce(0) { $0 + $1.y } / CGFloat(neighbors.count))
        }
        let irregularOutline = trace(
            (0...10).map { i -> CGPoint in
                let vertex = i % 10
                let angle = CGFloat(vertex) * .pi / 5 + 0.15 * sin(CGFloat(vertex) * 1.9)
                let radius: CGFloat =
                    vertex % 2 == 0
                    ? 0.20 * (1 + 0.22 * sin(CGFloat(vertex) * 2.4))
                    : 0.20 * (0.38 + 0.16 * sin(CGFloat(vertex)))
                return CGPoint(x: radius * cos(angle), y: radius * sin(angle) * 0.76)
            }, samples: 14, jitter: 0.002)
        let fourPointOutline = trace(
            (0...8).map { i -> CGPoint in
                let angle = CGFloat(i) * .pi / 4 + 0.3
                let radius: CGFloat = i % 2 == 0 ? 0.20 : 0.065
                return CGPoint(x: radius * cos(angle), y: radius * sin(angle))
            }, samples: 16)
        let shallowSparkle = trace(
            (0...8).map { i -> CGPoint in
                let angle = CGFloat(i) * .pi / 4 + 0.6
                let radius: CGFloat = i % 2 == 0 ? 0.20 : 0.116
                return CGPoint(x: radius * cos(angle), y: radius * sin(angle) * 0.85)
            }, samples: 16, jitter: 0.002)
        let cases: [(String, [CGPoint], Int, TimeInterval)] = [
            ("3.7 segments", Array(crossing.prefix(75)), 30, 0.9),
            ("four segments", Array(crossing.prefix(81)), 60, 1.3),
            ("partial fifth segment", Array(crossing.prefix(89)), 120, 1.8),
            ("last-line overshoot", overshoot, 60, 1.5),
            ("rounded uneven flattened tips", rounded, 30, 1.1),
            ("irregular outline", irregularOutline, 60, 2.4),
            ("four-point outline", fourPointOutline, 120, 1.6),
            ("shallow four-tip sparkle", shallowSparkle, 60, 1.4),
        ]
        for (name, path, fps, duration) in cases {
            var rune = RuneCasting()
            rune.begin(angles: .zero, at: 0)
            let end = feed(path, into: &rune, fps: fps, duration: duration, jitter: 0.002)
            XCTAssertTrue(rune.isDrawing, name)
            XCTAssertEqual(rune.finish(angles: end, at: duration), .summon, name)
            XCTAssertFalse(rune.isDrawing, name)
            XCTAssertNil(rune.finish(angles: end, at: duration + 0.01), name)
        }
    }

    func testExtraLoopsAndLongScribblesCannotSummonOnRelease() {
        let outer = circle()
        let inner = polygon(sides: 5)
        let scribble = trace(
            (0...24).map { i in
                CGPoint(
                    x: CGFloat(i % 2) * 0.4 - 0.2,
                    y: sin(CGFloat(i) * 2.3) * 0.23)
            }, samples: 5)
        let cases: [(String, [CGPoint])] = [
            ("double star", star() + star()),
            ("double circle", outer + outer),
            ("circle and pentagon", outer + trace([outer.last!, inner[0]]) + inner),
            ("long scribble", scribble),
        ]
        for (name, path) in cases {
            var rune = RuneCasting()
            rune.begin(angles: .zero, at: 0)
            let end = feed(path, into: &rune, fps: 60, duration: 3.5)
            XCTAssertNil(rune.finish(angles: end, at: 3.5), name)
        }
    }

    func testShallowRipplesOnACircleStillCastFireballOnRelease() {
        for phase: CGFloat in [0, 0.3, 0.8, 1.4] {
            let path = (0...120).map { i -> CGPoint in
                let angle = phase + CGFloat(i) * .pi / 60
                let radius = 0.17 * (1 + 0.09 * sin(6 * angle))
                return CGPoint(x: radius * cos(angle) * 0.8, y: radius * sin(angle))
            }
            var rune = RuneCasting()
            rune.begin(angles: .zero, at: 0)
            let end = feed(path, into: &rune, fps: 60, duration: 1.6)
            XCTAssertEqual(rune.finish(angles: end, at: 1.6), .fireball, "Phase \(phase)")
        }
    }

    func testFireAcceptsLargeGapsThinOvalsAndAngularLoops() {
        let open = circle(radius: 0.22, phase: 0.5).prefix(66).map { $0 }
        let narrow = circle(radius: 0.25, jitter: 0.009).map {
            CGPoint(x: $0.x * 0.24, y: $0.y)
        }
        let uneven = circle(radius: 0.2).map {
            CGPoint(x: $0.x + 0.05 * sin($0.y * 18), y: $0.y * (1 + $0.x))
        }
        for (variant, path) in [open, narrow, uneven, polygon(sides: 5)].enumerated() {
            for reverse in [false, true] {
                for duration in [0.3, 1.2, 3.5] {
                    for fps in [30, 60] {
                        let drawn = reverse ? Array(path.reversed()) : path
                        var rune = RuneCasting()
                        rune.begin(angles: .zero, at: 0)
                        let end = feed(drawn, into: &rune, fps: fps, duration: duration)
                        XCTAssertEqual(
                            rune.finish(angles: end, at: duration), .fireball,
                            "variant \(variant), reverse \(reverse), \(duration)s at \(fps)fps")
                    }
                }
            }
        }
    }

    func testNothingCapturesWithoutAnExplicitPress() {
        var rune = RuneCasting()
        let end = feed(star(), into: &rune)
        XCTAssertFalse(rune.isDrawing)
        XCTAssertTrue(rune.normalizedTrace.isEmpty)
        XCTAssertNil(rune.finish(angles: end, at: 1.5))
    }

    func testCompactQuickWristDrawings() {
        let smallBolt = trace(bolt.map { CGPoint(x: $0.x * 0.36, y: $0.y * 0.36) })
        let cases: [([CGPoint], RuneKind)] = [
            (smallBolt, .zap), (circle(radius: 0.065), .fireball),
            (star(radius: 0.11, imperfect: true), .summon),
            (star(radius: 0.12, outline: true, imperfect: true), .summon),
        ]
        for (path, expected) in cases {
            var rune = RuneCasting()
            rune.begin(angles: .zero, at: 0)
            let end = feed(path, into: &rune, fps: 60, duration: 0.74)
            XCTAssertEqual(rune.finish(angles: end, at: 0.75), expected)
        }
    }

    func testMomentaryLossAtReleaseKeepsTheCompletedRune() {
        var rune = RuneCasting()
        rune.begin(angles: .zero, at: 0)
        feed(circle(), into: &rune)
        rune.update(angles: nil, at: 1.52)
        XCTAssertEqual(rune.finish(angles: nil, at: 1.55), .fireball)
    }

    func testNoInitialMotionSampleWaitsUntilTrackingArrives() {
        var rune = RuneCasting()
        rune.begin(angles: nil, at: 0)
        XCTAssertTrue(rune.isDrawing)
        rune.update(angles: nil, at: 0.1)
        let end = feed(trace(bolt), into: &rune, at: 0.2)
        XCTAssertEqual(rune.finish(angles: end, at: 1.7), .zap)
        rune.begin(angles: nil, at: 2)
        XCTAssertNil(rune.finish(angles: nil, at: 3))
        XCTAssertFalse(rune.isDrawing)
    }

    func testHoldingStillAndPausingInsideTheRuneNeverFinishesCapture() {
        var rune = RuneCasting()
        rune.begin(angles: .zero, at: 0)
        for frame in 1...120 { rune.update(angles: .zero, at: Double(frame) / 60) }
        XCTAssertTrue(rune.isDrawing)
        let first = trace(Array(bolt.prefix(2)))
        let endFirst = feed(first, into: &rune, duration: 0.6, at: 2)
        for frame in 1...120 { rune.update(angles: endFirst, at: 2.6 + Double(frame) / 60) }
        XCTAssertTrue(rune.isDrawing)
        let remaining = trace(Array(bolt.dropFirst()))
        let end = feed(remaining, into: &rune, duration: 1.2, start: endFirst, at: 4.6)
        XCTAssertEqual(rune.finish(angles: end, at: 5.8), .zap)
    }

    func testTapsAndBriefStrokesCannotCastButLongStationaryTremorChargesShield() {
        var tap = RuneCasting()
        tap.begin(angles: .zero, at: 0)
        XCTAssertNil(tap.finish(angles: .zero, at: 0.01))
        var brief = RuneCasting()
        brief.begin(angles: .zero, at: 0)
        let end = feed(trace(bolt), into: &brief, duration: 0.1)
        XCTAssertNil(brief.finish(angles: end, at: 0.1))
        var tremor = RuneCasting()
        tremor.begin(angles: .zero, at: 0)
        for frame in 1...180 {
            let t = Double(frame) / 60
            tremor.update(angles: SIMD2(Float(sin(t * 30) * 0.008), Float(cos(t * 21) * 0.006)), at: t)
        }
        XCTAssertEqual(tremor.finish(angles: .zero, at: 3), .shield)
    }

    func testCancellationTrackingLossAndDiscontinuitiesRejectTheWholeHold() {
        for failure in 0..<6 {
            var rune = RuneCasting()
            rune.begin(angles: .zero, at: 0)
            let end = feed(trace(bolt), into: &rune)
            switch failure {
            case 0: rune.update(angles: nil, at: 1.6)
            case 1: rune.update(angles: SIMD2(.nan, 0), at: 1.6)
            case 2: rune.update(angles: SIMD2(2, 2), at: 1.6)
            case 3: rune.update(angles: end, at: 0.1)
            case 4: rune.update(angles: end, at: 4)
            default: rune.cancel()
            }
            XCTAssertNil(rune.finish(angles: end, at: 4.1))
            XCTAssertFalse(rune.isDrawing)
            rune.begin(angles: .zero, at: 5)
            let next = feed(star(), into: &rune, duration: 2, at: 5)
            XCTAssertEqual(rune.finish(angles: next, at: 7), .summon)
        }
    }

    func testDuplicatePressDoesNotEraseInkAndYawWrapIsContinuous() {
        var rune = RuneCasting()
        let start = SIMD2<Float>(-3.05, 0.6)
        rune.begin(angles: start, at: 0)
        let end = feed(trace(bolt), into: &rune, start: start)
        let before = rune.normalizedTrace
        rune.begin(angles: .zero, at: 1.5)
        XCTAssertEqual(rune.normalizedTrace, before)
        XCTAssertEqual(rune.finish(angles: end, at: 1.5), .zap)
    }

    func testFixedInkDoesNotMoveWhenMoreSamplesArrive() {
        var rune = RuneCasting()
        rune.begin(angles: .zero, at: 0)
        let end = feed(trace(Array(bolt.prefix(2))), into: &rune, duration: 0.5)
        let before = rune.normalizedTrace
        XCTAssertEqual(before.first, CGPoint(x: 0.5, y: 0.5))
        rune.update(angles: end + SIMD2(0.02, 0), at: 0.52)
        XCTAssertEqual(Array(rune.normalizedTrace.prefix(before.count)), before)
    }

    func testCompoundPolygonsAndExtraStrokesReject() {
        let outer = circle()
        let inner = polygon(sides: 5)
        XCTAssertNil(RuneRecognizer.recognize(outer + trace([outer.last!, inner[0]]) + inner))
        for sides in [3, 4] {
            XCTAssertNotEqual(RuneRecognizer.recognize(polygon(sides: sides, radius: 0.3)), .summon)
        }
        for sides in [5, 6] {
            XCTAssertEqual(RuneRecognizer.recognize(polygon(sides: sides, radius: 0.3)), .fireball)
        }
        XCTAssertNil(RuneRecognizer.recognize(star() + trace([star().last!, CGPoint(x: -0.5, y: -0.5)])))
        XCTAssertNil(RuneRecognizer.recognize(star() + star()))
        XCTAssertNil(RuneRecognizer.recognize(circle() + circle()))
    }

    func testCirclesAndLightningRemainDistinctFromStars() {
        for clockwise in [false, true] {
            XCTAssertEqual(RuneRecognizer.recognize(circle(phase: 0.4, clockwise: clockwise, jitter: 0.008)), .fireball)
        }
        for scale: CGFloat in [0.5, 1, 2] {
            let path = trace(bolt.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }, jitter: 0.003 * scale)
            XCTAssertEqual(RuneRecognizer.recognize(path), .zap)
            XCTAssertEqual(RuneRecognizer.recognize(path.flatMap { [$0, $0, $0] }), .zap)
        }
        XCTAssertNil(RuneRecognizer.recognize(trace([.zero, CGPoint(x: -0.4, y: -0.5)])))
        XCTAssertEqual(RuneRecognizer.recognize(trace(bolt.reversed())), .zap)
        XCTAssertEqual(RuneRecognizer.recognize(trace(bolt.map { CGPoint(x: -$0.x, y: $0.y) })), .zap)
        XCTAssertEqual(RuneRecognizer.recognize(Array(circle().prefix(65))), .fireball)
    }

    func testRandomScribblesAndInvalidDataCannotCast() {
        var seed: UInt64 = 12345
        func random() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return CGFloat(Double(seed >> 32) / Double(UInt32.max)) - 0.5
        }
        for _ in 0..<200 {
            var p = CGPoint.zero
            let path = (0..<60).map { _ -> CGPoint in
                p.x += random() * 0.15
                p.y += random() * 0.15
                return p
            }
            XCTAssertNil(RuneRecognizer.recognize(path))
        }
        XCTAssertNil(RuneRecognizer.recognize([.zero, CGPoint(x: CGFloat.nan, y: 0), .zero, .zero]))
        XCTAssertNil(RuneRecognizer.recognize(Array(repeating: .zero, count: 100)))
    }
}
