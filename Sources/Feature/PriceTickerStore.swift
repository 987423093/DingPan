import Foundation

@MainActor
final class PriceTickerStore: ObservableObject {
    @Published private(set) var titleText = "行情 --"
    @Published private(set) var statusText = "正在加载..."
    @Published private(set) var selectedSymbols: [String]
    @Published private(set) var menuBarSymbols: [String]
    @Published private(set) var latestPrices: [LatestPrice] = []
    @Published private(set) var refreshInterval: PriceRefreshInterval

    private let priceProvider: LatestPriceProviding
    private let formatter: PriceDisplayFormatter
    private let textBuilder: PriceMenuBarTextBuilder
    private let selectionPreferences: TickerSelectionPersisting
    private let refreshPreferences: PriceRefreshIntervalPersisting
    private var selection: TickerSelection
    private var pollingTask: Task<Void, Never>?

    init(
        priceProvider: LatestPriceProviding = SKHynixRemotePriceClient(
            session: .shared,
            endpointProvider: MirrorEndpointProvider(),
            formatter: PriceDisplayFormatter()
        ),
        formatter: PriceDisplayFormatter = PriceDisplayFormatter(),
        selectionPreferences: TickerSelectionPersisting = UserDefaultsTickerSelectionPreferences(),
        refreshPreferences: PriceRefreshIntervalPersisting = UserDefaultsPriceRefreshIntervalPreferences()
    ) {
        self.priceProvider = priceProvider
        self.formatter = formatter
        textBuilder = PriceMenuBarTextBuilder()
        self.selectionPreferences = selectionPreferences
        self.refreshPreferences = refreshPreferences
        selection = TickerSelection(
            selectedSymbols: selectionPreferences.loadSelectedSymbols(),
            menuBarSymbols: selectionPreferences.loadMenuBarSymbols()
        )
        selectedSymbols = selection.selectedSymbols
        menuBarSymbols = selection.menuBarSymbols
        refreshInterval = refreshPreferences.loadRefreshInterval()
    }

    deinit {
        pollingTask?.cancel()
    }

    func start() {
        guard pollingTask == nil else { return }
        startPolling()
    }

    func refreshNow() async {
        await refreshPrices()
    }

    func updateRefreshInterval(_ interval: PriceRefreshInterval) {
        guard refreshInterval != interval else { return }

        refreshInterval = interval
        refreshPreferences.saveRefreshInterval(interval)
        statusText = "已切换为\(interval.title)刷新"
        DebugLogger.log("price refresh interval changed; seconds=\(interval.rawValue)")

        let shouldRestart = pollingTask != nil
        pollingTask?.cancel()
        pollingTask = nil
        if shouldRestart {
            startPolling()
        }
    }

    func toggleSymbol(_ symbol: String) -> TickerSelection.ToggleResult {
        let result = selection.toggle(symbol)
        guard result == .updated else { return result }

        selectedSymbols = selection.selectedSymbols
        menuBarSymbols = selection.menuBarSymbols
        selectionPreferences.saveSelectedSymbols(selectedSymbols)
        selectionPreferences.saveMenuBarSymbols(menuBarSymbols)
        latestPrices.removeAll { !selectedSymbols.contains($0.symbol) }
        titleText = textBuilder.makeText(selectedSymbols: menuBarSymbols, prices: latestPrices)
        Task { [weak self] in
            await self?.refreshPrices()
        }
        return result
    }

    /// 切换合约是否展示在顶部指标区域，并持久化用户选择。
    /// - Parameter symbol: 要切换的合约 ID。
    /// - Returns: 顶部展示切换结果。
    func toggleMenuBarSymbol(_ symbol: String) -> TickerSelection.MenuBarToggleResult {
        let result = selection.toggleMenuBarSymbol(symbol)
        guard result == .updated else { return result }

        menuBarSymbols = selection.menuBarSymbols
        selectionPreferences.saveMenuBarSymbols(menuBarSymbols)
        titleText = textBuilder.makeText(selectedSymbols: menuBarSymbols, prices: latestPrices)
        Task { [weak self] in
            await self?.refreshPrices()
        }
        return result
    }

    func isSelected(_ symbol: String) -> Bool {
        selectedSymbols.contains(symbol)
    }

    func moveSymbol(_ symbol: String, to destinationSymbol: String) {
        guard selection.move(symbol, to: destinationSymbol) else { return }

        selectedSymbols = selection.selectedSymbols
        selectionPreferences.saveSelectedSymbols(selectedSymbols)
        titleText = textBuilder.makeText(selectedSymbols: menuBarSymbols, prices: latestPrices)
        Task { [weak self] in
            await self?.refreshPrices()
        }
    }

    private func startPolling() {
        pollingTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let interval = refreshInterval
                let nextRefresh = ContinuousClock.now.advanced(by: .seconds(interval.rawValue))
                await refreshPrices()
                if Task.isCancelled {
                    break
                }
                try? await Task.sleep(until: nextRefresh, clock: .continuous)
            }
        }
    }

    private func refreshPrices() async {
        statusText = "刷新中..."
        let symbols = selection.menuBarSymbols
        let provider = priceProvider
        let outcomes = await withTaskGroup(of: PriceFetchOutcome.self) { group in
            for symbol in symbols {
                group.addTask {
                    do {
                        return PriceFetchOutcome(
                            symbol: symbol,
                            price: try await provider.fetchLatestPrice(for: symbol),
                            errorDescription: nil
                        )
                    } catch {
                        return PriceFetchOutcome(
                            symbol: symbol,
                            price: nil,
                            errorDescription: error.localizedDescription
                        )
                    }
                }
            }

            var results: [PriceFetchOutcome] = []
            for await outcome in group {
                results.append(outcome)
            }
            return results
        }
        let fetchedPrices = outcomes.compactMap(\.price)

        guard !fetchedPrices.isEmpty else {
            let firstError = outcomes.compactMap(\.errorDescription).first ?? "所有行情接口均不可用"
            statusText = "刷新失败：\(firstError)"
            DebugLogger.log("price refresh failed; error=\(firstError)")
            return
        }

        latestPrices = fetchedPrices
        let nextTitle = textBuilder.makeText(selectedSymbols: symbols, prices: fetchedPrices)
        titleText = nextTitle
        let newestDate = fetchedPrices.map(\.updatedAt).max() ?? .now
        statusText = "上次更新：\(formatter.menuTimestamp(from: newestDate))"
    }
}

private struct PriceFetchOutcome: Sendable {
    let symbol: String
    let price: LatestPrice?
    let errorDescription: String?
}
