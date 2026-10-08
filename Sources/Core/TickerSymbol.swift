import Foundation

struct TickerSymbol: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let shortName: String

    init(id: String, name: String, shortName: String) {
        self.id = id
        self.name = name
        self.shortName = shortName
    }
}

enum TickerSymbolCatalog {
    static let builtInSymbols: [TickerSymbol] = [
        TickerSymbol(id: "SKHYNIXUSDT", name: "SK 海力士", shortName: "SKH"),
        TickerSymbol(id: "SAMSUNGUSDT", name: "三星电子", shortName: "三星"),
        TickerSymbol(id: "MUUSDT", name: "美光科技", shortName: "MU"),
        TickerSymbol(id: "SNDKUSDT", name: "闪迪", shortName: "SNDK"),
        TickerSymbol(id: "NVDAUSDT", name: "英伟达", shortName: "NVDA"),
        TickerSymbol(id: "AMDUSDT", name: "AMD", shortName: "AMD"),
        TickerSymbol(id: "TSMUSDT", name: "台积电", shortName: "TSM"),
        TickerSymbol(id: "AAPLUSDT", name: "苹果", shortName: "AAPL"),
        TickerSymbol(id: "MSFTUSDT", name: "微软", shortName: "MSFT"),
        TickerSymbol(id: "GOOGLUSDT", name: "谷歌", shortName: "GOOGL"),
        TickerSymbol(id: "METAUSDT", name: "Meta", shortName: "META"),
        TickerSymbol(id: "TSLAUSDT", name: "特斯拉", shortName: "TSLA"),
        TickerSymbol(id: "SPYUSDT", name: "标普 500 ETF", shortName: "SPY"),
        TickerSymbol(id: "QQQUSDT", name: "纳指 100 ETF", shortName: "QQQ")
    ]

    static var symbols: [TickerSymbol] {
        builtInSymbols
    }

    static func symbol(for id: String) -> TickerSymbol? {
        let normalizedID = normalize(id)
        if let builtInSymbol = builtInSymbols.first(where: { $0.id == normalizedID }) {
            return builtInSymbol
        }
        guard isSupportedIdentifier(normalizedID) else { return nil }
        let baseAsset = baseAsset(from: normalizedID)
        return TickerSymbol(id: normalizedID, name: normalizedID, shortName: baseAsset)
    }

    static func normalize(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func isSupportedIdentifier(_ id: String) -> Bool {
        guard !id.isEmpty,
              id.count <= 30,
              id.range(of: #"^[A-Z0-9]+(USDT|USDC|BUSD)$"#, options: .regularExpression) != nil else {
            return false
        }
        return true
    }

    private static func baseAsset(from id: String) -> String {
        for suffix in ["USDT", "USDC", "BUSD"] where id.hasSuffix(suffix) {
            return String(id.dropLast(suffix.count))
        }
        return id
    }
}
