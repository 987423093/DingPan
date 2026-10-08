import AppKit
import XCTest
@testable import SKHynixMenuBar

@MainActor
final class TickerPanelPositionPreferencesTests: XCTestCase {
    func testSavesAndLoadsDraggedPosition() {
        let suiteName = "TickerPanelPositionPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserDefaultsTickerPanelPositionPreferences(
            defaults: defaults,
            key: "tickerPanelPosition"
        )
        let position = NSPoint(x: 520, y: 860)

        preferences.savePosition(position)

        XCTAssertEqual(preferences.loadPosition(), position)
    }
}
