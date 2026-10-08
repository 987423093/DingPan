import Foundation
import XCTest
@testable import SKHynixMenuBar

final class PriceHistoryTests: XCTestCase {
    func testTrendRangesMapToExpectedIntervalsAndLimits() {
        let configurations = TrendRange.allCases.map {
            "\($0.title)|\($0.interval.rawValue)|\($0.limit)"
        }

        XCTAssertEqual(configurations, [
            "1小时|1m|60",
            "1天|5m|288",
            "1周|1h|168",
            "1月|4h|180",
            "3月|4h|540",
            "1年|1d|365",
            "3年|1d|1095",
            "历史|1w|1500"
        ])
    }

    func testTrendTimeframesMapToExpectedKlineIntervalsAndHistoryWindow() {
        XCTAssertEqual(
            TrendTimeframe.allCases.map { "\($0.title)|\($0.interval.rawValue)|\($0.historyLimit)" },
            [
                "15分钟|15m|1500",
                "1小时|1h|1500",
                "4小时|4h|1500",
                "1天|1d|1500"
            ]
        )
    }

    func testOneHourTimeframeDefaultsToAReadableDailyWindow() {
        XCTAssertEqual(TrendTimeframe.oneHour.defaultVisibleDuration, 24 * 60 * 60)
    }

    func testEndpointProviderBuildsKlineURLForEveryMirror() {
        let provider = MirrorEndpointProvider(
            mirrorBaseURLs: [
                URL(string: "https://one.example")!,
                URL(string: "https://two.example")!
            ]
        )

        let endpoints = provider.klineEndpoints(
            for: "NVDAUSDT",
            interval: .fiveMinutes,
            limit: 288
        )

        XCTAssertEqual(endpoints.count, 2)
        XCTAssertEqual(
            endpoints.first?.absoluteString,
            "https://one.example/fapi/v1/klines?symbol=NVDAUSDT&interval=5m&limit=288"
        )
    }

    func testEndpointProviderBuildsEarliestKlineURL() {
        let provider = MirrorEndpointProvider(
            mirrorBaseURLs: [URL(string: "https://one.example")!]
        )

        let endpoint = provider.klineEndpoints(
            for: "SAMSUNGUSDT",
            interval: .oneDay,
            limit: 1,
            startTime: Date(timeIntervalSince1970: 0)
        ).first

        XCTAssertEqual(
            endpoint?.absoluteString,
            "https://one.example/fapi/v1/klines?symbol=SAMSUNGUSDT&interval=1d&limit=1&startTime=0"
        )
    }

    func testAvailableRangesHideDurationsLongerThanContractHistory() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tenMonthsAgo = Calendar(identifier: .gregorian).date(
            byAdding: .month,
            value: -10,
            to: now
        )!

        let ranges = TrendRangeAvailability().availableRanges(
            earliestDate: tenMonthsAgo,
            now: now
        )

        XCTAssertEqual(
            ranges,
            [.oneHour, .oneDay, .oneWeek, .oneMonth, .threeMonths, .allHistory]
        )
    }

    func testAvailableRangesHideThreeMonthsWhenHistoryIsTooShort() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let twoMonthsAgo = Calendar(identifier: .gregorian).date(
            byAdding: .month,
            value: -2,
            to: now
        )!

        let ranges = TrendRangeAvailability().availableRanges(
            earliestDate: twoMonthsAgo,
            now: now
        )

        XCTAssertEqual(ranges, [.oneHour, .oneDay, .oneWeek, .oneMonth, .allHistory])
    }

    func testEndpointProviderBuildsExchangeInfoURLForEveryMirror() {
        let provider = MirrorEndpointProvider(
            mirrorBaseURLs: [
                URL(string: "https://one.example")!,
                URL(string: "https://two.example")!
            ]
        )

        let endpoints = provider.exchangeInfoEndpoints()

        XCTAssertEqual(endpoints.map(\.absoluteString), [
            "https://one.example/fapi/v1/exchangeInfo",
            "https://two.example/fapi/v1/exchangeInfo"
        ])
    }

    func testClientDecodesSortsAndDeduplicatesKlines() async throws {
        let payload = """
        [
          [2000, "12.0", "14.0", "11.0", "13.0", "20.0", 2999, "260.0", 0, "0", "0", "0"],
          [1000, "10.0", "12.0", "9.0", "11.0", "10.0", 1999, "110.0", 0, "0", "0", "0"],
          [2000, "12.0", "15.0", "11.0", "14.0", "30.0", 2999, "420.0", 0, "0", "0", "0"]
        ]
        """.data(using: .utf8)!
        let session = makeStubSession { request in
            XCTAssertEqual(request.url?.host, "one.example")
            return (200, payload)
        }
        let client = RemotePriceHistoryClient(
            session: session,
            endpointProvider: MirrorEndpointProvider(
                mirrorBaseURLs: [URL(string: "https://one.example")!]
            )
        )

        let candles = try await client.fetchPriceHistory(
            for: "SKHYNIXUSDT",
            interval: .oneMinute,
            limit: 60
        )

        XCTAssertEqual(candles.map(\.openTime), [Date(timeIntervalSince1970: 1), Date(timeIntervalSince1970: 2)])
        XCTAssertEqual(candles.last?.close, Decimal(string: "14.0"))
        XCTAssertEqual(candles.last?.volume, Decimal(string: "30.0"))
        XCTAssertEqual(candles.last?.quoteVolume, Decimal(string: "420.0"))
    }

    func testClientFallsBackToSecondMirror() async throws {
        let payload = """
        [[1000, "10", "12", "9", "11", "10", 1999, "0", 0, "0", "0", "0"]]
        """.data(using: .utf8)!
        let requestedHosts = LockedBox<[String]>([])
        let session = makeStubSession { request in
            let host = request.url?.host ?? ""
            requestedHosts.withValue { $0.append(host) }
            return host == "one.example" ? (500, Data()) : (200, payload)
        }
        let client = RemotePriceHistoryClient(
            session: session,
            endpointProvider: MirrorEndpointProvider(
                mirrorBaseURLs: [
                    URL(string: "https://one.example")!,
                    URL(string: "https://two.example")!
                ]
            )
        )

        let candles = try await client.fetchPriceHistory(
            for: "SKHYNIXUSDT",
            interval: .oneMinute,
            limit: 60
        )

        XCTAssertEqual(candles.count, 1)
        XCTAssertEqual(Set(requestedHosts.value), Set(["one.example", "two.example"]))
    }

    func testClientUsesResponsiveMirrorWithoutWaitingForSlowerMirror() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HistoryRacingURLProtocol.self]
        let client = RemotePriceHistoryClient(
            session: URLSession(configuration: configuration),
            endpointProvider: MirrorEndpointProvider(
                mirrorBaseURLs: [
                    URL(string: "https://slow.example")!,
                    URL(string: "https://fast.example")!
                ]
            )
        )
        let clock = ContinuousClock()
        let startedAt = clock.now

        let candles = try await client.fetchPriceHistory(
            for: "BTCUSDC",
            interval: .fiveMinutes,
            limit: 60
        )

        XCTAssertEqual(candles.count, 1)
        XCTAssertLessThan(startedAt.duration(to: clock.now), .seconds(1))
    }

    private func makeStubSession(
        handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)
    ) -> URLSession {
        StubURLProtocol.requestHandler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.requestHandler else {
                throw URLError(.badServerResponse)
            }
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class HistoryRacingURLProtocol: URLProtocol, @unchecked Sendable {
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
        [[1000, "10", "12", "9", "11", "10", 1999, "0", 0, "0", "0", "0"]]
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

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        lock.withLock { storedValue }
    }

    func withValue(_ body: (inout Value) -> Void) {
        lock.withLock { body(&storedValue) }
    }
}
