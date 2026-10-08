import Foundation

struct PriceCandle: Equatable, Sendable {
    let symbol: String
    let open: Decimal
    let high: Decimal
    let low: Decimal
    let close: Decimal
    let volume: Decimal
    let quoteVolume: Decimal
    let openTime: Date
    let closeTime: Date
}

enum KlineInterval: String, Hashable, Sendable {
    case oneMinute = "1m"
    case fifteenMinutes = "15m"
    case fiveMinutes = "5m"
    case oneHour = "1h"
    case fourHours = "4h"
    case oneDay = "1d"
    case oneWeek = "1w"

    /// 返回当前 K 线周期对应的秒数，用于计算同周期涨跌幅。
    /// - Returns: 一个 K 线周期的时间长度，单位为秒。
    var duration: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .fiveMinutes: 5 * 60
        case .fifteenMinutes: 15 * 60
        case .oneHour: 60 * 60
        case .fourHours: 4 * 60 * 60
        case .oneDay: 24 * 60 * 60
        case .oneWeek: 7 * 24 * 60 * 60
        }
    }
}

enum TrendTimeframe: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case fifteenMinutes
    case oneHour
    case fourHours
    case oneDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fifteenMinutes: "15分钟"
        case .oneHour: "1小时"
        case .fourHours: "4小时"
        case .oneDay: "1天"
        }
    }

    var interval: KlineInterval {
        switch self {
        case .fifteenMinutes: .fifteenMinutes
        case .oneHour: .oneHour
        case .fourHours: .fourHours
        case .oneDay: .oneDay
        }
    }

    /// 返回默认可视窗口时长，用于首次打开图表时展示最近一段数据。
    var defaultVisibleDuration: TimeInterval {
        switch self {
        case .fifteenMinutes: 4 * 60 * 60
        // 小时线至少展示一天，避免窗口内只有一两根 K 线而看起来像直线。
        case .oneHour: 24 * 60 * 60
        case .fourHours: 7 * 24 * 60 * 60
        case .oneDay: 30 * 24 * 60 * 60
        }
    }

    var historyLimit: Int { 1_500 }
}

enum TrendRange: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case oneHour
    case oneDay
    case oneWeek
    case oneMonth
    case threeMonths
    case oneYear
    case threeYears
    case allHistory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneHour: "1小时"
        case .oneDay: "1天"
        case .oneWeek: "1周"
        case .oneMonth: "1月"
        case .threeMonths: "3月"
        case .oneYear: "1年"
        case .threeYears: "3年"
        case .allHistory: "历史"
        }
    }

    var interval: KlineInterval {
        switch self {
        case .oneHour: .oneMinute
        case .oneDay: .fiveMinutes
        case .oneWeek: .oneHour
        case .oneMonth, .threeMonths: .fourHours
        case .oneYear: .oneDay
        case .threeYears: .oneDay
        case .allHistory: .oneWeek
        }
    }

    var limit: Int {
        switch self {
        case .oneHour: 60
        case .oneDay: 288
        case .oneWeek: 168
        case .oneMonth: 180
        case .threeMonths: 540
        case .oneYear: 365
        case .threeYears: 1095
        case .allHistory: 1500
        }
    }
}

protocol PriceHistoryProviding: Sendable {
    func fetchPriceHistory(
        for symbol: String,
        interval: KlineInterval,
        limit: Int
    ) async throws -> [PriceCandle]

    func fetchEarliestAvailableDate(for symbol: String) async throws -> Date?
}

extension PriceHistoryProviding {
    func fetchEarliestAvailableDate(for symbol: String) async throws -> Date? {
        nil
    }
}
