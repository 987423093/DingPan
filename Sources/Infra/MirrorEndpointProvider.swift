import Foundation

struct MirrorEndpointProvider: Sendable {
    let mirrorBaseURLs: [URL]

    init(
        mirrorBaseURLs: [URL] = [
            URL(string: "https://www.bmwweb.ninja")!,
            URL(string: "https://www.usnbweb.red")!,
            URL(string: "https://www.edhojmmldkl.com")!
        ]
    ) {
        self.mirrorBaseURLs = mirrorBaseURLs
    }

    func tickerEndpoints(for symbol: String) -> [URL] {
        endpoints(path: "fapi/v1/ticker/price") { components in
            components.queryItems = [URLQueryItem(name: "symbol", value: symbol)]
        }
    }

    func exchangeInfoEndpoints() -> [URL] {
        endpoints(path: "fapi/v1/exchangeInfo") { components in
            components.queryItems = nil
        }
    }

    func klineEndpoints(
        for symbol: String,
        interval: KlineInterval,
        limit: Int,
        startTime: Date? = nil
    ) -> [URL] {
        endpoints(path: "fapi/v1/klines") { components in
            var queryItems = [
                URLQueryItem(name: "symbol", value: symbol),
                URLQueryItem(name: "interval", value: interval.rawValue),
                URLQueryItem(name: "limit", value: String(limit))
            ]
            if let startTime {
                let milliseconds = Int64(startTime.timeIntervalSince1970 * 1_000)
                queryItems.append(URLQueryItem(name: "startTime", value: String(milliseconds)))
            }
            components.queryItems = queryItems
        }
    }

    private func endpoints(
        path: String,
        configure: (inout URLComponents) -> Void
    ) -> [URL] {
        mirrorBaseURLs.compactMap { baseURL in
            let endpoint = baseURL.appendingPathComponent(path)
            guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
                return nil
            }
            configure(&components)
            return components.url
        }
    }
}
