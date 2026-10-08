import XCTest
@testable import SKHynixMenuBar

@MainActor
final class ContractSearchStoreTests: XCTestCase {
    func testSearchFiltersLoadedRemoteSymbols() async {
        let store = ContractSearchStore(
            provider: StubContractSymbolProvider(symbols: [
                TickerSymbol(id: "BTCUSDT", name: "BTC/USDT", shortName: "BTC"),
                TickerSymbol(id: "SOLUSDT", name: "SOL/USDT", shortName: "SOL")
            ]),
            defaultSymbols: []
        )

        store.loadIfNeeded()
        try? await Task.sleep(for: .milliseconds(50))
        store.query = "bt"

        XCTAssertEqual(store.results.map(\.id), ["BTCUSDT"])
    }
}

private struct StubContractSymbolProvider: ContractSymbolProviding {
    let symbols: [TickerSymbol]

    func fetchSymbols() async throws -> [TickerSymbol] {
        symbols
    }
}
