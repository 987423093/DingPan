import Foundation

@MainActor
final class PriceTrendStore: ObservableObject {
    @Published private(set) var availableSymbols: [String] = []
    @Published private(set) var candles: [PriceCandle] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var selectedSymbol: String
    @Published private(set) var selectedRange: TrendRange
    @Published private(set) var selectedTimeframe: TrendTimeframe
    @Published private(set) var availableRanges = TrendRange.allCases
    @Published private(set) var availableTimeframes = TrendTimeframe.allCases

    private let provider: PriceHistoryProviding
    private let preferences: TrendPreferencesPersisting
    private let pollingInterval: Duration
    private let rangeAvailability = TrendRangeAvailability()
    private let maxCachedSnapshots = 32
    private var cache: [TrendCacheKey: TrendSnapshot] = [:]
    private var cacheAccessOrder: [TrendCacheKey] = []
    private var availableRangesBySymbol: [String: [TrendRange]] = [:]
    private var loadTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var requestVersion = 0
    private var isOpen = false

    init(
        provider: PriceHistoryProviding = RemotePriceHistoryClient(
            session: .shared,
            endpointProvider: MirrorEndpointProvider()
        ),
        preferences: TrendPreferencesPersisting = UserDefaultsTrendPreferences(),
        pollingInterval: Duration = .seconds(60)
    ) {
        self.provider = provider
        self.preferences = preferences
        self.pollingInterval = pollingInterval
        selectedSymbol = preferences.loadSymbol() ?? TickerSymbolCatalog.symbols[0].id
        selectedRange = preferences.loadRange()
        selectedTimeframe = preferences.loadTimeframe()
    }

    deinit {
        loadTask?.cancel()
        pollingTask?.cancel()
    }

    var currentPrice: Decimal? {
        candles.last?.close
    }

    /// 返回用于右上角同周期涨幅计算的基准 K 线。
    /// - Returns: 最新 K 线往前一个当前选中周期处或更早的最近一根 K 线。
    private var changeReferenceCandle: PriceCandle? {
        guard let latest = candles.last else { return nil }
        let targetTime = latest.openTime.addingTimeInterval(-selectedTimeframe.interval.duration)
        return candles.last(where: { $0.openTime <= targetTime }) ?? candles.first
    }

    var priceChange: Decimal? {
        guard let reference = changeReferenceCandle,
              let last = candles.last?.close else { return nil }
        return last - reference.close
    }

    var changePercent: Decimal? {
        guard let reference = changeReferenceCandle,
              reference.close != 0,
              let change = priceChange else { return nil }
        return change / reference.close * 100
    }

    func open(selectedSymbols: [String]) {
        isOpen = true
        synchronizeSelectedSymbols(selectedSymbols, reloadIfNeeded: false)
        startLoad()
        startPolling()
    }

    func close() {
        isOpen = false
        requestVersion += 1
        loadTask?.cancel()
        loadTask = nil
        pollingTask?.cancel()
        pollingTask = nil
        isLoading = false
        clearTrendCache()
        candles = []
        updatedAt = nil
        errorText = nil
    }

    func synchronizeSelectedSymbols(_ symbols: [String]) {
        synchronizeSelectedSymbols(symbols, reloadIfNeeded: true)
    }

    func selectSymbol(_ symbol: String) {
        guard availableSymbols.contains(symbol), selectedSymbol != symbol else { return }
        selectedSymbol = symbol
        preferences.saveSymbol(symbol)
        applyCachedAvailableRanges()
        applyCachedSnapshot()
        startLoad()
    }

    func selectRange(_ range: TrendRange) {
        guard availableRanges.contains(range), selectedRange != range else { return }
        selectedRange = range
        preferences.saveRange(range)
    }

    /// 设置 K 线周期并重新加载对应周期的历史数据。
    func selectTimeframe(_ timeframe: TrendTimeframe) {
        guard selectedTimeframe != timeframe else { return }
        selectedTimeframe = timeframe
        preferences.saveTimeframe(timeframe)
        applyCachedSnapshot()
        startLoad()
    }

    func refreshNow() {
        startLoad()
    }

    /// 用实时行情更新当前未收盘的最后一根 K 线。
    /// - Parameters:
    ///   - price: 实时成交价，用于更新收盘价、最高价和最低价。
    ///   - symbol: 行情所属合约，必须与当前趋势图合约一致。
    ///   - now: 行情时间，用于判断最后一根 K 线是否仍在进行中。
    /// - Returns: 无；如果当前没有未收盘 K 线或合约不匹配则不修改数据。
    func updateLivePrice(_ price: Decimal, for symbol: String, at now: Date = .now) {
        guard symbol == selectedSymbol,
              let lastCandle = candles.last,
              lastCandle.symbol == symbol,
              now >= lastCandle.openTime,
              now < lastCandle.closeTime else {
            return
        }

        let updatedCandle = PriceCandle(
            symbol: lastCandle.symbol,
            open: lastCandle.open,
            high: max(lastCandle.high, price),
            low: min(lastCandle.low, price),
            close: price,
            volume: lastCandle.volume,
            quoteVolume: lastCandle.quoteVolume,
            openTime: lastCandle.openTime,
            closeTime: lastCandle.closeTime
        )
        guard updatedCandle != lastCandle else { return }

        var updatedCandles = candles
        updatedCandles[updatedCandles.count - 1] = updatedCandle
        candles = updatedCandles
        updatedAt = now
        storeSnapshot(
            TrendSnapshot(candles: updatedCandles, updatedAt: now),
            for: currentCacheKey
        )
    }

    func waitUntilIdle() async {
        while true {
            let version = requestVersion
            let task = loadTask
            await task?.value
            if version == requestVersion {
                return
            }
        }
    }

    private func synchronizeSelectedSymbols(_ symbols: [String], reloadIfNeeded: Bool) {
        let validSymbols = symbols
            .map(TickerSymbolCatalog.normalize)
            .filter { TickerSymbolCatalog.symbol(for: $0) != nil }
        availableSymbols = validSymbols
        guard let fallback = validSymbols.first else {
            candles = []
            return
        }

        let selectionChanged = !validSymbols.contains(selectedSymbol)
        if selectionChanged {
            selectedSymbol = fallback
            preferences.saveSymbol(fallback)
            applyCachedAvailableRanges()
            applyCachedSnapshot()
        }
        if selectionChanged, reloadIfNeeded, isOpen {
            startLoad()
        }
    }

    private func applyCachedSnapshot() {
        guard let snapshot = cache[currentCacheKey] else {
            candles = []
            updatedAt = nil
            errorText = nil
            return
        }
        touchCacheKey(currentCacheKey)
        candles = snapshot.candles
        updatedAt = snapshot.updatedAt
        errorText = nil
    }

    private func startLoad() {
        guard !selectedSymbol.isEmpty else { return }
        let symbol = selectedSymbol
        let timeframe = selectedTimeframe
        let cacheKey = TrendCacheKey(symbol: symbol, timeframe: timeframe)
        if let snapshot = cache[cacheKey] {
            touchCacheKey(cacheKey)
            candles = snapshot.candles
            updatedAt = snapshot.updatedAt
        }

        requestVersion += 1
        let version = requestVersion
        loadTask?.cancel()
        isLoading = true
        errorText = nil
        let provider = provider
        let cachedAvailableRanges = availableRangesBySymbol[symbol]
        let rangeAvailability = rangeAvailability

        loadTask = Task { [weak self] in
            let resolvedAvailableRanges: [TrendRange]
            if let cachedAvailableRanges {
                resolvedAvailableRanges = cachedAvailableRanges
            } else {
                let earliestDate = try? await provider.fetchEarliestAvailableDate(for: symbol)
                resolvedAvailableRanges = rangeAvailability.availableRanges(earliestDate: earliestDate)
            }

            guard let self,
                  !Task.isCancelled,
                  version == self.requestVersion,
                  symbol == self.selectedSymbol else {
                return
            }

            self.availableRangesBySymbol[symbol] = resolvedAvailableRanges
            self.availableRanges = resolvedAvailableRanges

            guard resolvedAvailableRanges.contains(self.selectedRange) else {
                let fallbackRange = resolvedAvailableRanges.reversed().first { $0 != .allHistory } ?? .oneHour
                self.selectedRange = fallbackRange
                self.preferences.saveRange(fallbackRange)
                self.isLoading = false
                self.startLoad()
                return
            }

            do {
                let fetchedCandles = try await provider.fetchPriceHistory(
                    for: symbol,
                    interval: timeframe.interval,
                    limit: timeframe.historyLimit
                )
                if let first = fetchedCandles.first,
                   let last = fetchedCandles.last {
                    DebugLogger.log(
                        "trend history loaded; symbol=\(symbol), timeframe=\(timeframe.rawValue), count=\(fetchedCandles.count), start=\(first.openTime.timeIntervalSince1970), end=\(last.openTime.timeIntervalSince1970)"
                    )
                } else {
                    DebugLogger.log(
                        "trend history loaded empty; symbol=\(symbol), timeframe=\(timeframe.rawValue)"
                    )
                }
                guard !Task.isCancelled,
                      version == self.requestVersion,
                      symbol == self.selectedSymbol,
                      timeframe == self.selectedTimeframe else {
                    return
                }
                let snapshot = TrendSnapshot(candles: fetchedCandles, updatedAt: .now)
                self.storeSnapshot(snapshot, for: cacheKey)
                self.candles = fetchedCandles
                self.updatedAt = snapshot.updatedAt
                self.errorText = nil
                self.isLoading = false
            } catch {
                DebugLogger.log(
                    "trend history failed; symbol=\(symbol), timeframe=\(timeframe.rawValue), error=\(error.localizedDescription)"
                )
                guard !Task.isCancelled,
                      version == self.requestVersion else {
                    return
                }
                self.errorText = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func applyCachedAvailableRanges() {
        availableRanges = availableRangesBySymbol[selectedSymbol] ?? TrendRange.allCases
        guard !availableRanges.contains(selectedRange) else { return }

        let fallbackRange = availableRanges.reversed().first { $0 != .allHistory } ?? .oneHour
        selectedRange = fallbackRange
        preferences.saveRange(fallbackRange)
    }

    private func startPolling() {
        pollingTask?.cancel()
        let interval = pollingInterval
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled, self.isOpen else { break }
                self.startLoad()
            }
        }
    }

    private var currentCacheKey: TrendCacheKey {
        TrendCacheKey(symbol: selectedSymbol, timeframe: selectedTimeframe)
    }

    /// 保存趋势快照并更新访问顺序，超过上限时淘汰最久未使用的快照。
    /// - Parameters:
    ///   - snapshot: 当前合约和周期对应的 K 线快照。
    ///   - key: 快照对应的合约及 K 线周期键。
    /// - Returns: 无；缓存最多保留 `maxCachedSnapshots` 个快照。
    private func storeSnapshot(_ snapshot: TrendSnapshot, for key: TrendCacheKey) {
        cache[key] = snapshot
        touchCacheKey(key)
        while cache.count > maxCachedSnapshots,
              let leastRecentlyUsedKey = cacheAccessOrder.first {
            cacheAccessOrder.removeFirst()
            cache.removeValue(forKey: leastRecentlyUsedKey)
        }
    }

    /// 标记趋势快照最近被访问，保证 LRU 淘汰顺序准确。
    /// - Parameter key: 被访问的合约和周期键。
    /// - Returns: 无；将键移动到访问队列末尾。
    private func touchCacheKey(_ key: TrendCacheKey) {
        cacheAccessOrder.removeAll { $0 == key }
        cacheAccessOrder.append(key)
    }

    /// 关闭趋势图时释放历史 K 线和可用范围缓存，避免长期运行持续占用内存。
    /// - Returns: 无；清空趋势缓存和缓存访问顺序。
    private func clearTrendCache() {
        cache.removeAll(keepingCapacity: false)
        cacheAccessOrder.removeAll(keepingCapacity: false)
        availableRangesBySymbol.removeAll(keepingCapacity: false)
    }
}

private struct TrendCacheKey: Hashable {
    let symbol: String
    let timeframe: TrendTimeframe
}

private struct TrendSnapshot {
    let candles: [PriceCandle]
    let updatedAt: Date
}
