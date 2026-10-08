import Foundation

struct RemotePriceHistoryClient: PriceHistoryProviding {
    private let session: URLSession
    private let endpointProvider: MirrorEndpointProvider

    init(session: URLSession, endpointProvider: MirrorEndpointProvider) {
        self.session = session
        self.endpointProvider = endpointProvider
    }

    func fetchPriceHistory(
        for symbol: String,
        interval: KlineInterval,
        limit: Int
    ) async throws -> [PriceCandle] {
        try await fetchCandles(
            for: symbol,
            endpoints: endpointProvider.klineEndpoints(
                for: symbol,
                interval: interval,
                limit: limit
            )
        )
    }

    func fetchEarliestAvailableDate(for symbol: String) async throws -> Date? {
        let candles = try await fetchCandles(
            for: symbol,
            endpoints: endpointProvider.klineEndpoints(
                for: symbol,
                interval: .oneDay,
                limit: 1,
                startTime: Date(timeIntervalSince1970: 0)
            )
        )
        return candles.first?.openTime
    }

    private func fetchCandles(for symbol: String, endpoints: [URL]) async throws -> [PriceCandle] {
        var lastError: Error?

        return try await withThrowingTaskGroup(of: [PriceCandle].self) { group in
            for endpoint in endpoints {
                group.addTask {
                    try await Self.fetchCandles(from: endpoint, symbol: symbol, session: session)
                }
            }

            for _ in endpoints {
                do {
                    if let candles = try await group.next() {
                        group.cancelAll()
                        return candles
                    }
                } catch {
                    lastError = error
                }
            }

            throw lastError ?? PriceClientError.noAvailableEndpoint
        }
    }

    private static func fetchCandles(
        from endpoint: URL,
        symbol: String,
        session: URLSession
    ) async throws -> [PriceCandle] {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        let remoteKlines = try JSONDecoder().decode([RemoteKline].self, from: data)
        let candles = try remoteKlines.map { try $0.makeCandle(symbol: symbol) }
        let deduplicated = Dictionary(
            candles.map { ($0.openTime, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        return deduplicated.values.sorted { $0.openTime < $1.openTime }
    }

    private static func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PriceClientError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw PriceClientError.httpStatus(httpResponse.statusCode)
        }
    }
}

private struct RemoteKline: Decodable {
    let openTime: Int64
    let open: String
    let high: String
    let low: String
    let close: String
    let volume: String
    let closeTime: Int64
    let quoteVolume: String

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        openTime = try container.decode(Int64.self)
        open = try container.decode(String.self)
        high = try container.decode(String.self)
        low = try container.decode(String.self)
        close = try container.decode(String.self)
        volume = try container.decode(String.self)
        closeTime = try container.decode(Int64.self)
        quoteVolume = try container.decode(String.self)
    }

    func makeCandle(symbol: String) throws -> PriceCandle {
        guard let openValue = Decimal(string: open),
              let highValue = Decimal(string: high),
              let lowValue = Decimal(string: low),
              let closeValue = Decimal(string: close),
              let volumeValue = Decimal(string: volume),
              let quoteVolumeValue = Decimal(string: quoteVolume) else {
            throw PriceClientError.invalidResponse
        }
        return PriceCandle(
            symbol: symbol,
            open: openValue,
            high: highValue,
            low: lowValue,
            close: closeValue,
            volume: volumeValue,
            quoteVolume: quoteVolumeValue,
            openTime: Date(timeIntervalSince1970: TimeInterval(openTime) / 1_000),
            closeTime: Date(timeIntervalSince1970: TimeInterval(closeTime) / 1_000)
        )
    }
}
