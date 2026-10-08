import Foundation

struct TickerSelection: Equatable, Sendable {
    static let maximumCount = 30
    static let menuBarMaximumCount = 8

    enum ToggleResult: Equatable, Sendable {
        case updated
        case requiresOneSymbol
        case maximumReached
    }

    enum MenuBarToggleResult: Equatable, Sendable {
        case updated
        case requiresOneSymbol
        case maximumReached
        case notSelected
    }

    private(set) var selectedSymbols: [String]
    private(set) var menuBarSymbols: [String]

    /// 初始化自选列表和顶部展示列表。
    /// - Parameters:
    ///   - selectedSymbols: 用户加入自选的合约 ID，最多保留 30 个。
    ///   - menuBarSymbols: 用户希望展示在顶部的合约 ID；为空或无效时按自选顺序补齐。
    /// - Returns: 一个保证至少有一个自选合约和一个顶部指标的选择状态。
    init(selectedSymbols: [String], menuBarSymbols: [String] = []) {
        let validSymbols = selectedSymbols
            .map(TickerSymbolCatalog.normalize)
            .filter { TickerSymbolCatalog.symbol(for: $0) != nil }
        var normalizedSelectedSymbols = Array(validSymbols.prefix(Self.maximumCount))
        if normalizedSelectedSymbols.isEmpty {
            normalizedSelectedSymbols = [TickerSymbolCatalog.symbols[0].id]
        }
        self.selectedSymbols = normalizedSelectedSymbols

        let validMenuBarSymbols = menuBarSymbols
            .map(TickerSymbolCatalog.normalize)
            .filter { normalizedSelectedSymbols.contains($0) }
        var seenSymbols = Set<String>()
        var normalizedMenuBarSymbols = validMenuBarSymbols.filter { seenSymbols.insert($0).inserted }
        if normalizedMenuBarSymbols.isEmpty {
            normalizedMenuBarSymbols = Array(normalizedSelectedSymbols.prefix(Self.menuBarMaximumCount))
        }
        self.menuBarSymbols = Array(normalizedMenuBarSymbols.prefix(Self.menuBarMaximumCount))
    }

    /// 切换一个合约是否显示在顶部指标区域。
    /// - Parameter symbol: 要切换的合约 ID。
    /// - Returns: 更新结果；顶部至少保留一个指标，且最多展示 8 个。
    mutating func toggleMenuBarSymbol(_ symbol: String) -> MenuBarToggleResult {
        let normalizedSymbol = TickerSymbolCatalog.normalize(symbol)
        guard selectedSymbols.contains(normalizedSymbol) else {
            return .notSelected
        }

        if let index = menuBarSymbols.firstIndex(of: normalizedSymbol) {
            guard menuBarSymbols.count > 1 else {
                return .requiresOneSymbol
            }
            menuBarSymbols.remove(at: index)
            return .updated
        }

        guard menuBarSymbols.count < Self.menuBarMaximumCount else {
            return .maximumReached
        }
        menuBarSymbols.append(normalizedSymbol)
        return .updated
    }

    mutating func toggle(_ symbol: String) -> ToggleResult {
        let normalizedSymbol = TickerSymbolCatalog.normalize(symbol)
        guard TickerSymbolCatalog.symbol(for: normalizedSymbol) != nil else {
            return .updated
        }

        if let index = selectedSymbols.firstIndex(of: normalizedSymbol) {
            guard selectedSymbols.count > 1 else {
                return .requiresOneSymbol
            }
            selectedSymbols.remove(at: index)
            menuBarSymbols.removeAll { $0 == normalizedSymbol }
            if menuBarSymbols.isEmpty {
                menuBarSymbols = [selectedSymbols[0]]
            }
            return .updated
        }

        guard selectedSymbols.count < Self.maximumCount else {
            return .maximumReached
        }
        selectedSymbols.append(normalizedSymbol)
        if menuBarSymbols.count < Self.menuBarMaximumCount {
            menuBarSymbols.append(normalizedSymbol)
        }
        return .updated
    }

    mutating func move(_ symbol: String, to destinationSymbol: String) -> Bool {
        guard let sourceIndex = selectedSymbols.firstIndex(of: symbol),
              let destinationIndex = selectedSymbols.firstIndex(of: destinationSymbol),
              sourceIndex != destinationIndex else {
            return false
        }

        let movedSymbol = selectedSymbols.remove(at: sourceIndex)
        selectedSymbols.insert(movedSymbol, at: destinationIndex)
        return true
    }
}
