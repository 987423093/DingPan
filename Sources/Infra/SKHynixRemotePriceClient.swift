import Foundation

struct SKHynixRemotePriceClient: LatestPriceProviding {
    private let session: URLSession
    private let endpointProvider: MirrorEndpointProvider

    init(session: URLSession, endpointProvider: MirrorEndpointProvider, formatter _: PriceDisplayFormatter) {
        self.session = session
        self.endpointProvider = endpointProvider
    }

    func fetchLatestPrice(for symbol: String) async throws -> LatestPrice {
        let endpoints = endpointProvider.tickerEndpoints(for: symbol)
        var lastError: Error?

        return try await withThrowingTaskGroup(of: LatestPrice.self) { group in
            for endpoint in endpoints {
                group.addTask {
                    try await Self.fetchLatestPrice(from: endpoint, session: session)
                }
            }

            for _ in endpoints {
                do {
                    if let price = try await group.next() {
                        group.cancelAll()
                        return price
                    }
                } catch {
                    lastError = error
                }
            }

            throw lastError ?? PriceClientError.noAvailableEndpoint
        }
    }

    private static func fetchLatestPrice(from endpoint: URL, session: URLSession) async throws -> LatestPrice {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        try validate(response: response)

        let quote = try JSONDecoder().decode(RemoteTickerQuote.self, from: data)
        guard let value = Decimal(string: quote.price) else {
            throw PriceClientError.invalidPrice(quote.price)
        }

        return LatestPrice(
            symbol: quote.symbol,
            value: value,
            updatedAt: Date(timeIntervalSince1970: TimeInterval(quote.time) / 1_000)
        )
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

struct RemoteTickerQuote: Decodable {
    let price: String
    let symbol: String
    let time: Int64
}

enum PriceClientError: LocalizedError {
    case httpStatus(Int)
    case invalidPrice(String)
    case invalidResponse
    case noAvailableEndpoint

    var errorDescription: String? {
        switch self {
        case let .httpStatus(statusCode):
            return "接口状态异常：\(statusCode)"
        case let .invalidPrice(price):
            return "价格格式异常：\(price)"
        case .invalidResponse:
            return "接口返回无效"
        case .noAvailableEndpoint:
            return "所有镜像均不可用"
        }
    }
}
