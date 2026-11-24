import XCTest

@testable import XArcana

final class PhonePositionTrackingTests: XCTestCase {
    func testDisableInvalidatesPermissionCallbacksAndReenableUsesFreshRequest() throws {
        var lifecycle = PhonePositionLifecycle()
        XCTAssertNil(lifecycle.request)
        XCTAssertFalse(lifecycle.setEnabled(false))
        XCTAssertTrue(lifecycle.setEnabled(true))
        let first = try XCTUnwrap(lifecycle.request)
        XCTAssertTrue(lifecycle.isCurrent(first))
        XCTAssertFalse(lifecycle.setEnabled(true))
        XCTAssertEqual(lifecycle.request, first)
        XCTAssertTrue(lifecycle.setEnabled(false))
        XCTAssertFalse(lifecycle.isCurrent(first))
        XCTAssertTrue(lifecycle.setEnabled(true))
        XCTAssertNotEqual(lifecycle.request, first)
        XCTAssertFalse(lifecycle.isCurrent(first))
    }

    func testHoldingAndLoweringSuspendMovementWithoutChangingSession() throws {
        var lifecycle = PhonePositionLifecycle()
        lifecycle.setEnabled(true)
        let request = try XCTUnwrap(lifecycle.request)
        XCTAssertEqual(lifecycle.quality(.tracking, at: 1), .tracking)
        lifecycle.setHolding(true, at: 2)
        XCTAssertEqual(lifecycle.quality(.tracking, at: 20), .suspended)
        XCTAssertEqual(lifecycle.quality(.unavailable, at: 20), .unavailable)
        lifecycle.setHolding(false, at: 20)
        XCTAssertEqual(lifecycle.quality(.tracking, at: 20.79), .suspended)
        lifecycle.setHolding(false, at: 20.5)
        XCTAssertEqual(lifecycle.quality(.tracking, at: 20.8), .tracking)
        XCTAssertEqual(lifecycle.request, request)
        lifecycle.setHolding(true, at: 21)
        lifecycle.setHolding(false, at: 22)
        XCTAssertEqual(lifecycle.quality(.tracking, at: 22.79), .suspended)
        XCTAssertEqual(lifecycle.quality(.limited, at: 22.8), .limited)
    }

    func testHeadingMatchesMacCameraYawConvention() {
        XCTAssertEqual(PhonePositionLifecycle.heading(cameraBackwardX: 0, cameraBackwardZ: 1), 0, accuracy: 0.0001)
        XCTAssertEqual(
            PhonePositionLifecycle.heading(cameraBackwardX: 1, cameraBackwardZ: 0), .pi / 2, accuracy: 0.0001)
        XCTAssertEqual(
            PhonePositionLifecycle.heading(cameraBackwardX: -1, cameraBackwardZ: 0), -.pi / 2, accuracy: 0.0001)
    }
}
