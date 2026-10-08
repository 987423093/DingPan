import Foundation

struct PriceMenuBarTextBuilder: Sendable {
    private let formatter = PriceDisplayFormatter()

    func makeText(selectedSymbols: [String], prices: [LatestPrice]) -> String {
        let pricesBySymbol = Dictionary(uniqueKeysWithValues: prices.map { ($0.symbol, $0) })
        let parts = selectedSymbols.prefix(TickerSelection.menuBarMaximumCount).compactMap { symbolID -> String? in
            let normalizedSymbolID = TickerSymbolCatalog.normalize(symbolID)
            guard let symbol = TickerSymbolCatalog.symbol(for: normalizedSymbolID),
                  let price = pricesBySymbol[normalizedSymbolID] else {
                return nil
            }
            return "\(symbol.shortName) \(formatter.compactString(from: price.value))"
        }
        return parts.isEmpty ? "行情 --" : parts.joined(separator: " · ")
    }
}
