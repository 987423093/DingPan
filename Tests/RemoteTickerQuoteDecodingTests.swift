import XCTest
@testable import SKHynixMenuBar

final class RemoteTickerQuoteDecodingTests: XCTestCase {
    func testDecodesTickerPayload() throws {
        let payload = """
        {
          "price": "1391.25000",
          "symbol": "SKHYNIXUSDT",
          "time": 1783497013757
        }
        """.data(using: .utf8)!

        let quote = try JSONDecoder().decode(RemoteTickerQuote.self, from: payload)

        XCTAssertEqual(quote.price, "1391.25000")
        XCTAssertEqual(quote.symbol, "SKHYNIXUSDT")
        XCTAssertEqual(quote.time, 1783497013757)
    }

    func testEndpointProviderBuildsEveryMirrorForRequestedSymbol() {
        let provider = MirrorEndpointProvider(
            mirrorBaseURLs: [
                URL(string: "https://one.example")!,
                URL(string: "https://two.example")!
            ]
        )

        let endpoints = provider.tickerEndpoints(for: "NVDAUSDT")

        XCTAssertEqual(endpoints.count, 2)
        XCTAssertTrue(endpoints.allSatisfy { $0.query == "symbol=NVDAUSDT" })
    }

    func testFetchUsesResponsiveMirrorWithoutWaitingForSlowerMirror() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RacingURLProtocol.self]
        let client = SKHynixRemotePriceClient(
            session: URLSession(configuration: configuration),
            endpointProvider: MirrorEndpointProvider(
                mirrorBaseURLs: [
                    URL(string: "https://slow.example")!,
                    URL(string: "https://fast.example")!
                ]
            ),
            formatter: PriceDisplayFormatter()
        )
        let clock = ContinuousClock()
        let startedAt = clock.now

        let price = try await client.fetchLatestPrice(for: "SKHYNIXUSDT")

        XCTAssertEqual(price.value, Decimal(string: "1391.25"))
        XCTAssertLessThan(startedAt.duration(to: clock.now), .seconds(1))
    }

    func testDecodesExchangeInfoSymbols() throws {
        let payload = """
        {
          "symbols": [
            {
              "symbol": "BTCUSDT",
              "baseAsset": "BTC",
              "quoteAsset": "USDT",
              "contractType": "PERPETUAL",
              "status": "TRADING"
            },
            {
              "symbol": "OLDUSDT",
              "baseAsset": "OLD",
              "quoteAsset": "USDT",
              "contractType": "PERPETUAL",
              "status": "BREAK"
            }
          ]
        }
        """.data(using: .utf8)!

        let exchangeInfo = try JSONDecoder().decode(RemoteExchangeInfo.self, from: payload)
        let symbols = exchangeInfo.symbols.compactMap { $0.makeTickerSymbol() }

        XCTAssertEqual(symbols, [
            TickerSymbol(id: "BTCUSDT", name: "BTC/USDT", shortName: "BTC")
        ])
    }
}

private final class RacingURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if request.url?.host == "slow.example" {
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.respond(statusCode: 500, data: Data())
            }
            return
        }

        let payload = """
        { "price": "1391.25", "symbol": "SKHYNIXUSDT", "time": 1783497013757 }
        """.data(using: .utf8)!
        respond(statusCode: 200, data: payload)
    }

    override func stopLoading() {}

    private func respond(statusCode: Int, data: Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
