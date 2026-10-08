import Foundation

struct RemoteContractSymbolClient: ContractSymbolProviding {
    private let session: URLSession
    private let endpointProvider: MirrorEndpointProvider

    init(
        session: URLSession = .shared,
        endpointProvider: MirrorEndpointProvider = MirrorEndpointProvider()
    ) {
        self.session = session
        self.endpointProvider = endpointProvider
    }

    func fetchSymbols() async throws -> [TickerSymbol] {
        var lastError: Error?

        for endpoint in endpointProvider.exchangeInfoEndpoints() {
            do {
                var request = URLRequest(url: endpoint)
                request.timeoutInterval = 12
                request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await session.data(for: request)
                try validate(response: response)
                let exchangeInfo = try JSONDecoder().decode(RemoteExchangeInfo.self, from: data)
                return exchangeInfo.symbols.compactMap { $0.makeTickerSymbol() }
            } catch {
                lastError = error
            }
        }

        throw lastError ?? PriceClientError.noAvailableEndpoint
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PriceClientError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw PriceClientError.httpStatus(httpResponse.statusCode)
        }
    }
}

struct RemoteExchangeInfo: Decodable {
    let symbols: [RemoteContractSymbol]
}

struct RemoteContractSymbol: Decodable {
    let symbol: String
    let baseAsset: String
    let quoteAsset: String
    let contractType: String?
    let status: String

    func makeTickerSymbol() -> TickerSymbol? {
        let normalizedSymbol = TickerSymbolCatalog.normalize(symbol)
        guard status == "TRADING",
              quoteAsset == "USDT" || quoteAsset == "USDC" || quoteAsset == "BUSD",
              TickerSymbolCatalog.symbol(for: normalizedSymbol) != nil else {
            return nil
        }
        return TickerSymbol(
            id: normalizedSymbol,
            name: "\(baseAsset)/\(quoteAsset)",
            shortName: baseAsset
        )
    }
}
