import Foundation

protocol ContractSymbolProviding: Sendable {
    func fetchSymbols() async throws -> [TickerSymbol]
}
