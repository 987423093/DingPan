import Foundation

struct PriceDisplayFormatter: Sendable {
    func string(from value: Decimal) -> String {
        format(value, minimumFractionDigits: 2, maximumFractionDigits: fractionDigits(for: value))
    }

    func compactString(from value: Decimal) -> String {
        format(value, minimumFractionDigits: 1, maximumFractionDigits: compactFractionDigits(for: value))
    }

    func axisString(from value: Double) -> String {
        guard value.isFinite else { return "" }
        let decimal = Decimal(value)
        return format(decimal, minimumFractionDigits: 1, maximumFractionDigits: compactFractionDigits(for: decimal))
    }

    private func format(
        _ value: Decimal,
        minimumFractionDigits: Int,
        maximumFractionDigits: Int
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = min(minimumFractionDigits, maximumFractionDigits)
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.groupingSeparator = ""
        let number = NSDecimalNumber(decimal: value)
        return formatter.string(from: number) ?? number.stringValue
    }

    private func fractionDigits(for value: Decimal) -> Int {
        let absoluteValue = abs(NSDecimalNumber(decimal: value).doubleValue)
        if absoluteValue >= 100 {
            return 2
        }
        if absoluteValue >= 1 {
            return 4
        }
        if absoluteValue >= 0.01 {
            return 6
        }
        return 8
    }

    private func compactFractionDigits(for value: Decimal) -> Int {
        let absoluteValue = abs(NSDecimalNumber(decimal: value).doubleValue)
        if absoluteValue >= 100 {
            return 1
        }
        if absoluteValue >= 1 {
            return 3
        }
        if absoluteValue >= 0.01 {
            return 5
        }
        return 8
    }

    func menuTimestamp(from date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }
}
