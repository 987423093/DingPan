import Foundation

struct LatestPrice: Equatable, Sendable {
    let symbol: String
    let value: Decimal
    let updatedAt: Date
}

protocol LatestPriceProviding: Sendable {
    func fetchLatestPrice(for symbol: String) async throws -> LatestPrice
}
