import Foundation
import XCTest
@testable import SKHynixMenuBar

final class TrendCandleHoverSelectorTests: XCTestCase {
    func testSelectsCandleNearestToHoveredDate() {
        let candles = [
            candle(close: "30", second: 300),
            candle(close: "10", second: 100),
            candle(close: "20", second: 200)
        ]

        let selected = TrendCandleHoverSelector().nearestCandle(
            to: Date(timeIntervalSince1970: 240),
            in: candles
        )

        XCTAssertEqual(selected?.close, Decimal(20))
        XCTAssertEqual(selected?.openTime, Date(timeIntervalSince1970: 200))
    }

    func testReturnsNilWhenNoCandlesExist() {
        let selected = TrendCandleHoverSelector().nearestCandle(
            to: Date(timeIntervalSince1970: 240),
            in: []
        )

        XCTAssertNil(selected)
    }
}

private func candle(close: String, second: Int) -> PriceCandle {
    let value = Decimal(string: close)!
    return PriceCandle(
        symbol: "SKHYNIXUSDT",
        open: value,
        high: value,
        low: value,
        close: value,
        volume: 1,
        quoteVolume: 1,
        openTime: Date(timeIntervalSince1970: TimeInterval(second)),
        closeTime: Date(timeIntervalSince1970: TimeInterval(second + 1))
    )
}
