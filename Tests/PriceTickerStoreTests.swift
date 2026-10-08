import XCTest
@testable import SKHynixMenuBar

@MainActor
final class PriceTickerStoreTests: XCTestCase {
    func testRefreshFetchesEverySelectedSymbolAndBuildsCombinedTitle() async {
        let provider = StubPriceProvider(prices: [
            "SKHYNIXUSDT": Decimal(string: "1297.21")!,
            "NVDAUSDT": Decimal(string: "207.66")!
        ])
        let preferences = InMemorySelectionPreferences(
            selectedSymbols: ["SKHYNIXUSDT", "NVDAUSDT"]
        )
        let store = PriceTickerStore(priceProvider: provider, selectionPreferences: preferences)

        await store.refreshNow()

        XCTAssertEqual(store.titleText, "SKH 1297.2 · NVDA 207.7")
        let requestedSymbols = await provider.requestedSymbols
        XCTAssertEqual(Set(requestedSymbols), Set(["SKHYNIXUSDT", "NVDAUSDT"]))
    }

    func testRefreshRequestsOnlyConfiguredMenuBarSymbolsWhenTrendSelectionIsLarger() async {
        let symbols = ["SKHYNIXUSDT", "SAMSUNGUSDT", "MUUSDT", "NVDAUSDT", "TSMUSDT"]
        let provider = StubPriceProvider(prices: Dictionary(
            uniqueKeysWithValues: symbols.enumerated().map { ($0.element, Decimal($0.offset + 1)) }
        ))
        let store = PriceTickerStore(
            priceProvider: provider,
            selectionPreferences: InMemorySelectionPreferences(
                selectedSymbols: symbols,
                menuBarSymbols: ["TSMUSDT", "SKHYNIXUSDT"]
            )
        )

        await store.refreshNow()

        let requestedSymbols = await provider.requestedSymbols
        XCTAssertEqual(Set(requestedSymbols), Set(["TSMUSDT", "SKHYNIXUSDT"]))
        XCTAssertEqual(store.titleText, "TSM 5.0 · SKH 1.0")
    }

    func testToggleMenuBarSymbolPersistsIndependentDisplayChoice() {
        let preferences = InMemorySelectionPreferences(
            selectedSymbols: ["SKHYNIXUSDT", "NVDAUSDT"],
            menuBarSymbols: ["SKHYNIXUSDT"]
        )
        let store = PriceTickerStore(
            priceProvider: StubPriceProvider(prices: [:]),
            selectionPreferences: preferences
        )

        XCTAssertEqual(store.menuBarSymbols, ["SKHYNIXUSDT"])
        XCTAssertEqual(store.toggleMenuBarSymbol("NVDAUSDT"), .updated)
        XCTAssertEqual(store.menuBarSymbols, ["SKHYNIXUSDT", "NVDAUSDT"])
        XCTAssertEqual(preferences.menuBarSymbols, ["SKHYNIXUSDT", "NVDAUSDT"])
    }

    func testTogglePersistsUpdatedSelection() {
        let preferences = InMemorySelectionPreferences(selectedSymbols: ["SKHYNIXUSDT"])
        let store = PriceTickerStore(
            priceProvider: StubPriceProvider(prices: [:]),
            selectionPreferences: preferences
        )

        let result = store.toggleSymbol("NVDAUSDT")

        XCTAssertEqual(result, .updated)
        XCTAssertEqual(store.selectedSymbols, ["SKHYNIXUSDT", "NVDAUSDT"])
        XCTAssertEqual(preferences.selectedSymbols, ["SKHYNIXUSDT", "NVDAUSDT"])
    }

    func testMoveSymbolPersistsUpdatedOrder() {
        let preferences = InMemorySelectionPreferences(
            selectedSymbols: ["SKHYNIXUSDT", "NVDAUSDT", "MUUSDT"]
        )
        let store = PriceTickerStore(
            priceProvider: StubPriceProvider(prices: [:]),
            selectionPreferences: preferences
        )

        store.moveSymbol("MUUSDT", to: "SKHYNIXUSDT")

        XCTAssertEqual(store.selectedSymbols, ["MUUSDT", "SKHYNIXUSDT", "NVDAUSDT"])
        XCTAssertEqual(preferences.selectedSymbols, ["MUUSDT", "SKHYNIXUSDT", "NVDAUSDT"])
    }

    func testLoadsPersistedRefreshInterval() {
        let refreshPreferences = InMemoryRefreshIntervalPreferences(interval: .tenSeconds)
        let store = PriceTickerStore(
            priceProvider: StubPriceProvider(prices: [:]),
            selectionPreferences: InMemorySelectionPreferences(selectedSymbols: ["SKHYNIXUSDT"]),
            refreshPreferences: refreshPreferences
        )

        XCTAssertEqual(store.refreshInterval, .tenSeconds)
    }

    func testLoadsPersistedOneSecondRefreshInterval() {
        let refreshPreferences = InMemoryRefreshIntervalPreferences(interval: .oneSecond)
        let store = PriceTickerStore(
            priceProvider: StubPriceProvider(prices: [:]),
            selectionPreferences: InMemorySelectionPreferences(selectedSymbols: ["SKHYNIXUSDT"]),
            refreshPreferences: refreshPreferences
        )

        XCTAssertEqual(store.refreshInterval, .oneSecond)
    }

    func testUpdateRefreshIntervalPersistsSelection() {
        let refreshPreferences = InMemoryRefreshIntervalPreferences(interval: .oneMinute)
        let store = PriceTickerStore(
            priceProvider: StubPriceProvider(prices: [:]),
            selectionPreferences: InMemorySelectionPreferences(selectedSymbols: ["SKHYNIXUSDT"]),
            refreshPreferences: refreshPreferences
        )

        store.updateRefreshInterval(.tenSeconds)

        XCTAssertEqual(store.refreshInterval, .tenSeconds)
        XCTAssertEqual(refreshPreferences.interval, .tenSeconds)
    }
}

private actor StubPriceProvider: LatestPriceProviding {
    private let prices: [String: Decimal]
    private(set) var requestedSymbols: [String] = []

    init(prices: [String: Decimal]) {
        self.prices = prices
    }

    func fetchLatestPrice(for symbol: String) async throws -> LatestPrice {
        requestedSymbols.append(symbol)
        guard let value = prices[symbol] else {
            throw PriceClientError.noAvailableEndpoint
        }
        return LatestPrice(symbol: symbol, value: value, updatedAt: .now)
    }
}

private final class InMemorySelectionPreferences: TickerSelectionPersisting {
    var selectedSymbols: [String]
    var menuBarSymbols: [String]

    init(selectedSymbols: [String], menuBarSymbols: [String]? = nil) {
        self.selectedSymbols = selectedSymbols
        self.menuBarSymbols = menuBarSymbols ?? []
    }

    func loadSelectedSymbols() -> [String] {
        selectedSymbols
    }

    func saveSelectedSymbols(_ symbols: [String]) {
        selectedSymbols = symbols
    }

    func loadMenuBarSymbols() -> [String] {
        menuBarSymbols
    }

    func saveMenuBarSymbols(_ symbols: [String]) {
        menuBarSymbols = symbols
    }
}

private final class InMemoryRefreshIntervalPreferences: PriceRefreshIntervalPersisting {
    var interval: PriceRefreshInterval

    init(interval: PriceRefreshInterval) {
        self.interval = interval
    }

    func loadRefreshInterval() -> PriceRefreshInterval {
        interval
    }

    func saveRefreshInterval(_ interval: PriceRefreshInterval) {
        self.interval = interval
    }
}
