import Foundation

@MainActor
final class ContractSearchStore: ObservableObject {
    @Published var query = ""
    @Published private(set) var symbols: [TickerSymbol]
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?

    private let provider: ContractSymbolProviding
    private var hasLoadedRemoteSymbols = false
    private var loadTask: Task<Void, Never>?

    init(
        provider: ContractSymbolProviding = RemoteContractSymbolClient(),
        defaultSymbols: [TickerSymbol] = TickerSymbolCatalog.symbols
    ) {
        self.provider = provider
        symbols = defaultSymbols
    }

    deinit {
        loadTask?.cancel()
    }

    var results: [TickerSymbol] {
        let keyword = TickerSymbolCatalog.normalize(query)
        guard !keyword.isEmpty else { return [] }

        return symbols
            .filter { symbol in
                symbol.id.contains(keyword)
                    || symbol.shortName.uppercased().contains(keyword)
                    || symbol.name.uppercased().contains(keyword)
            }
            .prefix(8)
            .map { $0 }
    }

    func symbol(for id: String) -> TickerSymbol? {
        let normalizedID = TickerSymbolCatalog.normalize(id)
        return symbols.first { $0.id == normalizedID } ?? TickerSymbolCatalog.symbol(for: normalizedID)
    }

    func loadIfNeeded() {
        guard !hasLoadedRemoteSymbols, loadTask == nil else { return }

        isLoading = true
        errorText = nil
        let provider = provider
        loadTask = Task { [weak self] in
            do {
                let fetchedSymbols = try await provider.fetchSymbols()
                guard let self, !Task.isCancelled else { return }
                self.symbols = Self.merge(defaultSymbols: self.symbols, remoteSymbols: fetchedSymbols)
                self.hasLoadedRemoteSymbols = true
                self.isLoading = false
                self.errorText = nil
                self.loadTask = nil
                DebugLogger.log("contract symbols loaded; count=\(self.symbols.count)")
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.isLoading = false
                self.errorText = error.localizedDescription
                self.loadTask = nil
                DebugLogger.log("contract symbols load failed; error=\(error.localizedDescription)")
            }
        }
    }

    private static func merge(
        defaultSymbols: [TickerSymbol],
        remoteSymbols: [TickerSymbol]
    ) -> [TickerSymbol] {
        var symbolsByID: [String: TickerSymbol] = [:]
        for symbol in remoteSymbols {
            symbolsByID[symbol.id] = symbol
        }
        for symbol in defaultSymbols {
            symbolsByID[symbol.id] = symbol
        }
        return symbolsByID.values.sorted { lhs, rhs in
            lhs.shortName.localizedStandardCompare(rhs.shortName) == .orderedAscending
        }
    }
}
