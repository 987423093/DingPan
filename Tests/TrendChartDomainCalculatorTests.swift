import XCTest
@testable import SKHynixMenuBar

final class TrendChartDomainCalculatorTests: XCTestCase {
    func testSmallPriceDomainDoesNotUseLargeFixedPadding() {
        let domain = TrendChartDomainCalculator().domain(for: [
            0.2381,
            0.2407,
            0.2358,
            0.2420
        ])

        XCTAssertGreaterThan(domain.lowerBound, 0.23)
        XCTAssertLessThan(domain.upperBound, 0.25)
    }

    func testFlatSmallPriceStillGetsVisiblePadding() {
        let domain = TrendChartDomainCalculator().domain(for: [
            0.2407,
            0.2407,
            0.2407
        ])

        XCTAssertLessThan(domain.lowerBound, 0.2407)
        XCTAssertGreaterThan(domain.upperBound, 0.2407)
        XCTAssertLessThan(domain.upperBound - domain.lowerBound, 0.002)
    }

    func testZeroValuesUseSafeFallbackDomain() {
        let domain = TrendChartDomainCalculator().domain(for: [0, 0])

        XCTAssertEqual(domain.lowerBound, -1)
        XCTAssertEqual(domain.upperBound, 1)
    }
}
