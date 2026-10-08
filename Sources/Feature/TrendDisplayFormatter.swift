import Foundation

struct TrendDisplayFormatter: Sendable {
    func price(_ value: Decimal) -> String {
        PriceDisplayFormatter().string(from: value)
    }

    func change(_ value: Decimal) -> String {
        format(value, maximumFractionDigits: fractionDigits(for: value), signed: true)
    }

    func percent(_ value: Decimal) -> String {
        "\(format(value, maximumFractionDigits: 2, signed: true))%"
    }

    /// 将成交额按中文数量级转换为易读的万、亿或万亿格式。
    /// - Parameter value: 原始成交额，支持正数和负数。
    /// - Returns: 最多保留两位小数的中文单位金额；小于一万时返回原数值。
    func amount(_ value: Decimal) -> String {
        let absoluteValue = abs(value)
        let unit: Decimal
        let suffix: String

        if absoluteValue >= Decimal(string: "1000000000000")! {
            unit = Decimal(string: "1000000000000")!
            suffix = "万亿"
        } else if absoluteValue >= Decimal(string: "100000000")! {
            unit = Decimal(string: "100000000")!
            suffix = "亿"
        } else if absoluteValue >= Decimal(string: "10000")! {
            unit = Decimal(string: "10000")!
            suffix = "万"
        } else {
            return format(value, maximumFractionDigits: 2, minimumFractionDigits: 0, signed: false)
        }

        return "\(format(value / unit, maximumFractionDigits: 2, minimumFractionDigits: 0, signed: false))\(suffix)"
    }

    private func format(
        _ value: Decimal,
        maximumFractionDigits: Int,
        minimumFractionDigits: Int? = nil,
        signed: Bool
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = minimumFractionDigits ?? min(2, maximumFractionDigits)
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.groupingSeparator = ""
        if signed {
            formatter.positivePrefix = "+"
        }
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
}
