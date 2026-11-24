import UIKit
import XCTest

@testable import XArcana

@MainActor
final class RunAnnouncementTests: XCTestCase {
    func testStageStartAndClearAnnouncementsStaySeparateAndPauseWithGameTime() {
        let banner = RunAnnouncementView()
        banner.announce(title: "Level 1", detail: "Max HP 110 · Max mana 110")
        banner.announce(title: "Level 1 cleared!", detail: "+250 bonus score")
        XCTAssertTrue(banner.accessibilityLabel?.contains("Level 1.") == true)
        banner.advance(deltaTime: 2.9)
        banner.advance(deltaTime: 0)
        banner.advance(deltaTime: .nan)
        XCTAssertTrue(banner.accessibilityLabel?.contains("Level 1.") == true)
        banner.advance(deltaTime: 0.2)
        XCTAssertTrue(banner.accessibilityLabel?.contains("Level 1 cleared") == true)
        XCTAssertFalse(banner.isHidden)
        banner.advance(deltaTime: 3.1)
        XCTAssertTrue(banner.isHidden)
    }

    func testRestartOrDeathRemovesPendingAnnouncements() {
        let banner = RunAnnouncementView()
        banner.announce(title: "Level 1", detail: "")
        banner.announce(title: "Level 1 cleared!", detail: "")
        banner.clear()
        banner.advance(deltaTime: 10)
        XCTAssertTrue(banner.isHidden)
        XCTAssertNil(banner.accessibilityLabel)
        banner.announce(title: "Level 1", detail: "Survive the horde")
        XCTAssertEqual(banner.accessibilityLabel, "Level 1. Survive the horde")
    }
}
