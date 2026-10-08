import Foundation

enum PriceRefreshInterval: Int, CaseIterable, Identifiable, Sendable {
    case oneSecond = 1
    case tenSeconds = 10
    case oneMinute = 60

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .oneSecond:
            return "每1秒"
        case .tenSeconds:
            return "每10秒"
        case .oneMinute:
            return "每1分钟"
        }
    }

    static let defaultValue: PriceRefreshInterval = .oneMinute

    static func from(seconds: Int) -> PriceRefreshInterval {
        PriceRefreshInterval(rawValue: seconds) ?? defaultValue
    }
}

@MainActor
protocol PriceRefreshIntervalPersisting: AnyObject {
    func loadRefreshInterval() -> PriceRefreshInterval
    func saveRefreshInterval(_ interval: PriceRefreshInterval)
}

@MainActor
final class UserDefaultsPriceRefreshIntervalPreferences: PriceRefreshIntervalPersisting {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "priceRefreshIntervalSeconds") {
        self.defaults = defaults
        self.key = key
    }

    func loadRefreshInterval() -> PriceRefreshInterval {
        let seconds = defaults.integer(forKey: key)
        guard seconds > 0 else { return .defaultValue }
        return .from(seconds: seconds)
    }

    func saveRefreshInterval(_ interval: PriceRefreshInterval) {
        defaults.set(interval.rawValue, forKey: key)
    }
}
