import Foundation

@MainActor
protocol TickerSelectionPersisting: AnyObject {
    func loadSelectedSymbols() -> [String]
    func saveSelectedSymbols(_ symbols: [String])
    func loadMenuBarSymbols() -> [String]
    func saveMenuBarSymbols(_ symbols: [String])
}

@MainActor
final class UserDefaultsTickerSelectionPreferences: TickerSelectionPersisting {
    private let defaults: UserDefaults
    private let key: String
    private let menuBarKey: String

    /// 创建基于 UserDefaults 的自选和顶部展示偏好存储。
    /// - Parameters:
    ///   - defaults: 用于读写配置的 UserDefaults 实例。
    ///   - key: 自选合约列表对应的键名。
    /// - Returns: 一个可持久化自选合约及顶部展示列表的偏好对象。
    init(
        defaults: UserDefaults = .standard,
        key: String = "selectedTickerSymbols",
        menuBarKey: String = "menuBarTickerSymbols"
    ) {
        self.defaults = defaults
        self.key = key
        self.menuBarKey = menuBarKey
    }

    func loadSelectedSymbols() -> [String] {
        defaults.stringArray(forKey: key) ?? [TickerSymbolCatalog.symbols[0].id]
    }

    func saveSelectedSymbols(_ symbols: [String]) {
        defaults.set(symbols, forKey: key)
    }

    /// 读取顶部展示合约；旧版本没有该配置时返回空数组，由领域模型按自选顺序兼容初始化。
    /// - Returns: 持久化的顶部展示合约 ID 列表，可能为空。
    func loadMenuBarSymbols() -> [String] {
        defaults.stringArray(forKey: menuBarKey) ?? []
    }

    /// 保存顶部展示合约列表。
    /// - Parameter symbols: 要展示在顶部的合约 ID 列表。
    func saveMenuBarSymbols(_ symbols: [String]) {
        defaults.set(symbols, forKey: menuBarKey)
    }
}
