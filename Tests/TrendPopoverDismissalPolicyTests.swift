import XCTest
@testable import SKHynixMenuBar

final class TrendPopoverDismissalPolicyTests: XCTestCase {
    func testTickerButtonClickDoesNotPreemptButtonToggle() {
        XCTAssertFalse(TrendPopoverDismissalPolicy.shouldDismiss(for: .tickerButton))
    }

    func testClickInsidePopoverKeepsPopoverOpen() {
        XCTAssertFalse(TrendPopoverDismissalPolicy.shouldDismiss(for: .popover))
    }

    func testClickInsideManagementMenuKeepsPopoverOpen() {
        XCTAssertFalse(TrendPopoverDismissalPolicy.shouldDismiss(for: .popUpMenu))
    }

    func testClickOutsideDismissesPopover() {
        XCTAssertTrue(TrendPopoverDismissalPolicy.shouldDismiss(for: .outside))
    }
}
