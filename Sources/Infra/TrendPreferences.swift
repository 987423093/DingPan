import Foundation

@MainActor
protocol TrendPreferencesPersisting: AnyObject {
    func loadSymbol() -> String?
    func saveSymbol(_ symbol: String)
    func loadRange() -> TrendRange
    func saveRange(_ range: TrendRange)
    /// 读取用户上次选择的 K 线周期，未保存时返回默认周期。
    func loadTimeframe() -> TrendTimeframe
    /// 保存用户选择的 K 线周期。
    func saveTimeframe(_ timeframe: TrendTimeframe)
}

@MainActor
final class UserDefaultsTrendPreferences: TrendPreferencesPersisting {
    private let defaults: UserDefaults
    private let symbolKey: String
    private let rangeKey: String
    private let timeframeKey: String

    init(
        defaults: UserDefaults = .standard,
        symbolKey: String = "trendSelectedSymbol",
        rangeKey: String = "trendSelectedRange",
        timeframeKey: String = "trendTimeframe"
    ) {
        self.defaults = defaults
        self.symbolKey = symbolKey
        self.rangeKey = rangeKey
        self.timeframeKey = timeframeKey
    }

    func loadSymbol() -> String? {
        defaults.string(forKey: symbolKey)
    }

    func saveSymbol(_ symbol: String) {
        defaults.set(symbol, forKey: symbolKey)
    }

    func loadRange() -> TrendRange {
        defaults.string(forKey: rangeKey)
            .flatMap(TrendRange.init(rawValue:)) ?? .oneHour
    }

    func saveRange(_ range: TrendRange) {
        defaults.set(range.rawValue, forKey: rangeKey)
    }

    func loadTimeframe() -> TrendTimeframe {
        defaults.string(forKey: timeframeKey)
            .flatMap(TrendTimeframe.init(rawValue:)) ?? .oneHour
    }

    /// 保存 K 线周期到用户偏好设置。
    func saveTimeframe(_ timeframe: TrendTimeframe) {
        defaults.set(timeframe.rawValue, forKey: timeframeKey)
    }
}
