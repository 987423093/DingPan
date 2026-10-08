import Foundation

struct TrendCandleHoverSelector: Sendable {
    func nearestCandle(to date: Date, in candles: [PriceCandle]) -> PriceCandle? {
        candles.min { lhs, rhs in
            abs(lhs.openTime.timeIntervalSince(date)) < abs(rhs.openTime.timeIntervalSince(date))
        }
    }
}
