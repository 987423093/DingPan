import Foundation
import XCTest
@testable import SKHynixMenuBar

@MainActor
final class PriceTrendStoreTests: XCTestCase {
    func testOpenRestoresSelectionLoadsRangeAndCalculatesChange() async {
        let provider = RecordingHistoryProvider(results: [
            HistoryRequest(symbol: "NVDAUSDT", interval: .oneHour, limit: 1_500): .success([
                candle(symbol: "NVDAUSDT", close: "200", second: 1),
                candle(symbol: "NVDAUSDT", close: "210", second: 2)
            ])
        ])
        let preferences = InMemoryTrendPreferences(symbol: "NVDAUSDT", range: .oneDay)
        let store = PriceTrendStore(provider: provider, preferences: preferences)

        store.open(selectedSymbols: ["SKHYNIXUSDT", "NVDAUSDT"])
        await store.waitUntilIdle()

        XCTAssertEqual(store.selectedSymbol, "NVDAUSDT")
        XCTAssertEqual(store.selectedRange, .oneDay)
        XCTAssertEqual(store.candles.count, 2)
        XCTAssertEqual(store.priceChange, Decimal(10))
        XCTAssertEqual(store.changePercent, Decimal(5))
        let requests = await provider.requests
        XCTAssertEqual(requests, [
            HistoryRequest(symbol: "NVDAUSDT", interval: .oneHour, limit: 1_500)
        ])
    }

    func testChangeUsesSelectedTimeframeReferenceInsteadOfOldestLoadedCandle() async {
        let provider = RecordingHistoryProvider(results: [
            HistoryRequest(symbol: "NVDAUSDT", interval: .oneHour, limit: 1_500): .success([
                candle(symbol: "NVDAUSDT", close: "100", second: 0),
                candle(symbol: "NVDAUSDT", close: "110", second: 3_600),
                candle(symbol: "NVDAUSDT", close: "120", second: 7_200)
            ])
        ])
        let store = PriceTrendStore(
            provider: provider,
            preferences: InMemoryTrendPreferences(symbol: "NVDAUSDT", range: .oneDay)
        )

        store.open(selectedSymbols: ["NVDAUSDT"])
        await store.waitUntilIdle()

        XCTAssertEqual(store.priceChange, Decimal(10))
        XCTAssertEqual(
            NSDecimalNumber(decimal: store.changePercent ?? 0).doubleValue,
            9.0909,
            accuracy: 0.0001
        )
    }

    func testMissingPersistedSymbolFallsBackToFirstSelectedSymbol() async {
        let provider = RecordingHistoryProvider(results: [:])
        let preferences = InMemoryTrendPreferences(symbol: "TSLAUSDT", range: .oneHour)
        let store = PriceTrendStore(provider: provider, preferences: preferences)

        store.open(selectedSymbols: ["SKHYNIXUSDT", "MUUSDT"])
        await store.waitUntilIdle()

        XCTAssertEqual(store.selectedSymbol, "SKHYNIXUSDT")
        XCTAssertEqual(preferences.symbol, "SKHYNIXUSDT")
    }

    func testTimeframeSelectionPersistsAndReloadsCandles() async {
        let provider = RecordingHistoryProvider(results: [
            HistoryRequest(symbol: "SKHYNIXUSDT", interval: .oneHour, limit: 1_500): .success([
                candle(symbol: "SKHYNIXUSDT", close: "100", second: 0),
                candle(symbol: "SKHYNIXUSDT", close: "105", second: 3_600)
            ]),
            HistoryRequest(symbol: "SKHYNIXUSDT", interval: .fourHours, limit: 1_500): .success([
                candle(symbol: "SKHYNIXUSDT", close: "100", second: 0),
                candle(symbol: "SKHYNIXUSDT", close: "110", second: 14_400)
            ])
        ])
        let preferences = InMemoryTrendPreferences(symbol: "SKHYNIXUSDT", range: .oneHour)
        let store = PriceTrendStore(provider: provider, preferences: preferences)

        store.open(selectedSymbols: ["SKHYNIXUSDT"])
        await store.waitUntilIdle()
        store.selectTimeframe(.fourHours)
        await store.waitUntilIdle()

        XCTAssertEqual(store.selectedTimeframe, .fourHours)
        XCTAssertEqual(preferences.timeframe, .fourHours)
        XCTAssertEqual(store.candles.last?.close, Decimal(110))
        let requests = await provider.requests
        XCTAssertEqual(requests, [
            HistoryRequest(symbol: "SKHYNIXUSDT", interval: .oneHour, limit: 1_500),
            HistoryRequest(symbol: "SKHYNIXUSDT", interval: .fourHours, limit: 1_500)
        ])
    }

    func testUnavailablePersistedRangeFallsBackToLongestSupportedRange() async {
        let now = Date.now
        let provider = RecordingHistoryProvider(
            results: [
                HistoryRequest(symbol: "SAMSUNGUSDT", interval: .oneHour, limit: 1_500): .success([
                    candle(symbol: "SAMSUNGUSDT", close: "150", second: 1)
                ])
            ],
            earliestDate: Calendar(identifier: .gregorian).date(
                byAdding: .month,
                value: -10,
                to: now
            )
        )
        let preferences = InMemoryTrendPreferences(symbol: "SAMSUNGUSDT", range: .threeYears)
        let store = PriceTrendStore(provider: provider, preferences: preferences)

        store.open(selectedSymbols: ["SAMSUNGUSDT"])
        await store.waitUntilIdle()

        XCTAssertEqual(
            store.availableRanges,
            [.oneHour, .oneDay, .oneWeek, .oneMonth, .threeMonths, .allHistory]
        )
        XCTAssertEqual(store.selectedRange, .threeMonths)
        XCTAssertEqual(preferences.range, .threeMonths)
        let requests = await provider.requests
        XCTAssertEqual(requests, [
            HistoryRequest(symbol: "SAMSUNGUSDT", interval: .oneHour, limit: 1_500)
        ])
    }

    func testFailureKeepsCachedCandlesVisible() async {
        let provider = SequencedHistoryProvider(results: [
            .success([
                candle(symbol: "SKHYNIXUSDT", close: "100", second: 1),
                candle(symbol: "SKHYNIXUSDT", close: "105", second: 2)
            ]),
            .failure(PriceClientError.noAvailableEndpoint)
        ])
        let store = PriceTrendStore(
            provider: provider,
            preferences: InMemoryTrendPreferences(symbol: "SKHYNIXUSDT", range: .oneHour)
        )

        store.open(selectedSymbols: ["SKHYNIXUSDT"])
        await store.waitUntilIdle()
        store.refreshNow()
        await store.waitUntilIdle()

        XCTAssertEqual(store.candles.map(\.close), [Decimal(100), Decimal(105)])
        XCTAssertNotNil(store.errorText)
    }

    func testSlowOldRequestCannotOverwriteNewSelection() async {
        let provider = DelayedHistoryProvider()
        let store = PriceTrendStore(
            provider: provider,
            preferences: InMemoryTrendPreferences(symbol: "SKHYNIXUSDT", range: .oneHour)
        )

        store.open(selectedSymbols: ["SKHYNIXUSDT", "NVDAUSDT"])
        try? await Task.sleep(for: .milliseconds(20))
        store.selectSymbol("NVDAUSDT")
        await store.waitUntilIdle()
        try? await Task.sleep(for: .milliseconds(180))

        XCTAssertEqual(store.selectedSymbol, "NVDAUSDT")
        XCTAssertEqual(store.candles.last?.symbol, "NVDAUSDT")
        XCTAssertEqual(store.candles.last?.close, Decimal(210))
    }

    func testCloseStopsPolling() async {
        let provider = CountingHistoryProvider()
        let store = PriceTrendStore(
            provider: provider,
            preferences: InMemoryTrendPreferences(symbol: "SKHYNIXUSDT", range: .oneHour),
            pollingInterval: .milliseconds(30)
        )

        store.open(selectedSymbols: ["SKHYNIXUSDT"])
        try? await Task.sleep(for: .milliseconds(85))
        store.close()
        let countAtClose = await provider.requestCount
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertGreaterThanOrEqual(countAtClose, 2)
        let countAfterClose = await provider.requestCount
        XCTAssertEqual(countAfterClose, countAtClose)
    }

    func testCloseClearsTrendCacheAndReloadsWhenReopened() async {
        let provider = RecordingHistoryProvider(results: [
            HistoryRequest(symbol: "SKHYNIXUSDT", interval: .oneHour, limit: 1_500): .success([
                candle(symbol: "SKHYNIXUSDT", close: "100", second: 1)
            ])
        ])
        let store = PriceTrendStore(
            provider: provider,
            preferences: InMemoryTrendPreferences(symbol: "SKHYNIXUSDT", range: .oneHour)
        )

        store.open(selectedSymbols: ["SKHYNIXUSDT"])
        await store.waitUntilIdle()
        store.close()
        store.open(selectedSymbols: ["SKHYNIXUSDT"])
        await store.waitUntilIdle()

        let requests = await provider.requests
        XCTAssertEqual(
            requests,
            [
                HistoryRequest(symbol: "SKHYNIXUSDT", interval: .oneHour, limit: 1_500),
                HistoryRequest(symbol: "SKHYNIXUSDT", interval: .oneHour, limit: 1_500)
            ]
        )
    }

    func testTrendCacheEvictsLeastRecentlyUsedSnapshots() async {
        let symbols = (0 ..< 34).map { "CACHE\($0)USDT" }
        let provider = UniversalHistoryProvider()
        let store = PriceTrendStore(
            provider: provider,
            preferences: InMemoryTrendPreferences(symbol: symbols[0], range: .oneHour)
        )

        store.open(selectedSymbols: symbols)
        await store.waitUntilIdle()
        for symbol in symbols.dropFirst() {
            store.selectSymbol(symbol)
            await store.waitUntilIdle()
        }

        store.selectSymbol(symbols[0])
        await store.waitUntilIdle()

        let requests = await provider.requests
        XCTAssertEqual(requests.filter { $0.symbol == symbols[0] }.count, 2)
    }

    func testLivePriceUpdatesOnlyTheUnclosedLastCandle() async {
        let openTime = Date(timeIntervalSince1970: 1_000)
        let closeTime = Date(timeIntervalSince1970: 2_000)
        let initial = PriceCandle(
            symbol: "SKHYNIXUSDT",
            open: 100,
            high: 110,
            low: 90,
            close: 105,
            volume: 1,
            quoteVolume: 105,
            openTime: openTime,
            closeTime: closeTime
        )
        let provider = RecordingHistoryProvider(results: [
            HistoryRequest(symbol: "SKHYNIXUSDT", interval: .oneHour, limit: 1_500): .success([initial])
        ])
        let store = PriceTrendStore(
            provider: provider,
            preferences: InMemoryTrendPreferences(symbol: "SKHYNIXUSDT", range: .oneHour)
        )

        store.open(selectedSymbols: ["SKHYNIXUSDT"])
        await store.waitUntilIdle()

        store.updateLivePrice(120, for: "SKHYNIXUSDT", at: Date(timeIntervalSince1970: 1_500))

        XCTAssertEqual(store.candles.last?.open, 100)
        XCTAssertEqual(store.candles.last?.high, 120)
        XCTAssertEqual(store.candles.last?.low, 90)
        XCTAssertEqual(store.candles.last?.close, 120)
    }

    func testLivePriceDoesNotChangeClosedOrMismatchedCandle() async {
        let initial = candle(symbol: "SKHYNIXUSDT", close: "105", second: 1)
        let provider = RecordingHistoryProvider(results: [
            HistoryRequest(symbol: "SKHYNIXUSDT", interval: .oneHour, limit: 1_500): .success([initial])
        ])
        let store = PriceTrendStore(
            provider: provider,
            preferences: InMemoryTrendPreferences(symbol: "SKHYNIXUSDT", range: .oneHour)
        )

        store.open(selectedSymbols: ["SKHYNIXUSDT"])
        await store.waitUntilIdle()

        store.updateLivePrice(120, for: "NVDAUSDT", at: Date(timeIntervalSince1970: 1))
        store.updateLivePrice(120, for: "SKHYNIXUSDT", at: Date(timeIntervalSince1970: 3))

        XCTAssertEqual(store.candles.last, initial)
    }
}

private struct HistoryRequest: Hashable, Sendable {
    let symbol: String
    let interval: KlineInterval
    let limit: Int
}

private actor RecordingHistoryProvider: PriceHistoryProviding {
    let results: [HistoryRequest: Result<[PriceCandle], Error>]
    let earliestDate: Date?
    private(set) var requests: [HistoryRequest] = []

    init(
        results: [HistoryRequest: Result<[PriceCandle], Error>],
        earliestDate: Date? = nil
    ) {
        self.results = results
        self.earliestDate = earliestDate
    }

    func fetchEarliestAvailableDate(for symbol: String) async throws -> Date? {
        earliestDate
    }

    func fetchPriceHistory(
        for symbol: String,
        interval: KlineInterval,
        limit: Int
    ) async throws -> [PriceCandle] {
        let request = HistoryRequest(symbol: symbol, interval: interval, limit: limit)
        requests.append(request)
        return try results[request]?.get() ?? { throw PriceClientError.noAvailableEndpoint }()
    }
}

private actor SequencedHistoryProvider: PriceHistoryProviding {
    var results: [Result<[PriceCandle], Error>]

    init(results: [Result<[PriceCandle], Error>]) {
        self.results = results
    }

    func fetchPriceHistory(
        for symbol: String,
        interval: KlineInterval,
        limit: Int
    ) async throws -> [PriceCandle] {
        try results.removeFirst().get()
    }
}

private actor DelayedHistoryProvider: PriceHistoryProviding {
    func fetchPriceHistory(
        for symbol: String,
        interval: KlineInterval,
        limit: Int
    ) async throws -> [PriceCandle] {
        if symbol == "SKHYNIXUSDT" {
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                try? await Task.sleep(for: .milliseconds(150))
            }
            return [candle(symbol: symbol, close: "100", second: 1)]
        }
        try? await Task.sleep(for: .milliseconds(10))
        return [candle(symbol: symbol, close: "210", second: 2)]
    }
}

private actor CountingHistoryProvider: PriceHistoryProviding {
    private(set) var requestCount = 0

    func fetchPriceHistory(
        for symbol: String,
        interval: KlineInterval,
        limit: Int
    ) async throws -> [PriceCandle] {
        requestCount += 1
        return [candle(symbol: symbol, close: "100", second: requestCount)]
    }
}

private actor UniversalHistoryProvider: PriceHistoryProviding {
    private(set) var requests: [HistoryRequest] = []

    func fetchPriceHistory(
        for symbol: String,
        interval: KlineInterval,
        limit: Int
    ) async throws -> [PriceCandle] {
        requests.append(HistoryRequest(symbol: symbol, interval: interval, limit: limit))
        return [candle(symbol: symbol, close: "100", second: requests.count)]
    }
}

@MainActor
private final class InMemoryTrendPreferences: TrendPreferencesPersisting {
    var symbol: String?
    var range: TrendRange
    var timeframe: TrendTimeframe = .oneHour

    init(symbol: String?, range: TrendRange) {
        self.symbol = symbol
        self.range = range
    }

    func loadSymbol() -> String? { symbol }
    func saveSymbol(_ symbol: String) { self.symbol = symbol }
    func loadRange() -> TrendRange { range }
    func saveRange(_ range: TrendRange) { self.range = range }
    func loadTimeframe() -> TrendTimeframe { timeframe }
    func saveTimeframe(_ timeframe: TrendTimeframe) { self.timeframe = timeframe }
}

private func candle(symbol: String, close: String, second: Int) -> PriceCandle {
    let closeValue = Decimal(string: close)!
    return PriceCandle(
        symbol: symbol,
        open: closeValue,
        high: closeValue,
        low: closeValue,
        close: closeValue,
        volume: 1,
        quoteVolume: closeValue,
        openTime: Date(timeIntervalSince1970: TimeInterval(second)),
        closeTime: Date(timeIntervalSince1970: TimeInterval(second + 1))
    )
}
