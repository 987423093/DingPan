import AppKit
import XCTest
@testable import SKHynixMenuBar

final class TickerPanelLayoutTests: XCTestCase {
    func testFrameStaysInsideLeftSafeAreaAndCentersVertically() {
        let safeArea = NSRect(x: 0, y: 1085, width: 771, height: 32)

        let frame = TickerPanelLayout.frame(contentSize: NSSize(width: 280, height: 20), safeArea: safeArea)

        XCTAssertEqual(frame.maxX, safeArea.maxX - 12)
        XCTAssertEqual(frame.midY, safeArea.midY)
        XCTAssertGreaterThanOrEqual(frame.minX, safeArea.minX + 12)
    }

    func testFreeFrameKeepsDraggedPositionWhenItFitsOnScreen() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)

        let frame = TickerPanelLayout.freeFrame(
            contentSize: NSSize(width: 280, height: 20),
            screenFrame: screenFrame,
            origin: NSPoint(x: 520, y: 860)
        )

        XCTAssertEqual(frame.origin, NSPoint(x: 520, y: 860))
    }

    func testFreeFrameClampsDraggedPositionToScreenEdges() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)

        let frame = TickerPanelLayout.freeFrame(
            contentSize: NSSize(width: 280, height: 20),
            screenFrame: screenFrame,
            origin: NSPoint(x: 1400, y: 920)
        )

        XCTAssertEqual(frame.maxX, screenFrame.maxX)
        XCTAssertEqual(frame.maxY, screenFrame.maxY)
    }
}
