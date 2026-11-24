import XCTest

@testable import XArcana

final class WandMeleeTests: XCTestCase {
    func testComfortableHorizontalAndVerticalSwingsTriggerOnce() {
        for direction in [SIMD2<Float>(1, 0), SIMD2<Float>(0, -1), SIMD2<Float>(0.7, 0.7)] {
            var detector = WandMelee()
            var hits = 0
            for step in 0...30 {
                if detector.sample(angles: direction * Float(step) * 0.04, at: Double(step) * 0.02, enabled: true) {
                    hits += 1
                }
            }
            XCTAssertEqual(hits, 1)
        }
    }

    func testStationaryJitterAndSlowAimCannotTrigger() {
        var detector = WandMelee()
        for step in 0...120 {
            XCTAssertFalse(
                detector.sample(
                    angles: SIMD2(sin(Float(step)) * 0.01, cos(Float(step)) * 0.01),
                    at: Double(step) / 60, enabled: true))
        }
        detector.reset(newController: true)
        for step in 0...120 {
            XCTAssertFalse(
                detector.sample(
                    angles: SIMD2(Float(step) * 0.005, 0),
                    at: Double(step) / 60, enabled: true))
        }
    }

    func testRestAndReversalRearmTheDetector() {
        var detector = WandMelee()
        XCTAssertFalse(detector.sample(angles: .zero, at: 0, enabled: true))
        XCTAssertTrue(detector.sample(angles: SIMD2(0.2, 0), at: 0.1, enabled: true))
        XCTAssertFalse(detector.sample(angles: SIMD2(0.21, 0), at: 0.2, enabled: true))
        XCTAssertTrue(detector.sample(angles: SIMD2(0.43, 0), at: 0.3, enabled: true))
        XCTAssertTrue(detector.sample(angles: SIMD2(0.2, 0), at: 0.4, enabled: true))
    }

    func testDisabledMissingInvalidGappedAndReplayedSamplesCannotCompleteASwing() {
        var detector = WandMelee()
        XCTAssertFalse(detector.sample(angles: .zero, at: 1, enabled: true))
        XCTAssertFalse(detector.sample(angles: SIMD2(0.2, 0), at: 1.1, enabled: false))
        XCTAssertFalse(detector.sample(angles: SIMD2(0.4, 0), at: 1.2, enabled: true))
        XCTAssertFalse(detector.sample(angles: nil, at: 1.3, enabled: true))
        XCTAssertFalse(detector.sample(angles: SIMD2(0.6, 0), at: 1.4, enabled: true))
        XCTAssertFalse(detector.sample(angles: SIMD2(.nan, 0), at: 1.5, enabled: true))
        XCTAssertFalse(detector.sample(angles: .zero, at: 1.6, enabled: true))
        XCTAssertFalse(detector.sample(angles: SIMD2(0.3, 0), at: 2, enabled: true))
        XCTAssertFalse(detector.sample(angles: SIMD2(0.5, 0), at: 2.1, enabled: true))
        XCTAssertFalse(detector.sample(angles: SIMD2(0.7, 0), at: 2.1, enabled: true))
        XCTAssertFalse(detector.sample(angles: SIMD2(0.9, 0), at: 2.2, enabled: true))
        detector.reset()
        XCTAssertFalse(detector.sample(angles: .zero, at: 1, enabled: true))
        XCTAssertFalse(detector.sample(angles: SIMD2(0.2, 0), at: 1.1, enabled: true))
    }

    func testYawWrapDoesNotBecomeAnArtificialSwing() {
        var detector = WandMelee()
        XCTAssertFalse(detector.sample(angles: SIMD2(.pi - 0.02, 0), at: 0, enabled: true))
        XCTAssertFalse(detector.sample(angles: SIMD2(-.pi + 0.02, 0), at: 0.1, enabled: true))
    }
}
