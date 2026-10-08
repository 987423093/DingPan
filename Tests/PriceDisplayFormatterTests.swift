import XCTest
@testable import SKHynixMenuBar

final class PriceDisplayFormatterTests: XCTestCase {
    func testFormatsTwoFractionDigits() {
        let formatter = PriceDisplayFormatter()

        XCTAssertEqual(formatter.string(from: Decimal(string: "1391.2")!), "1391.20")
        XCTAssertEqual(formatter.string(from: Decimal(string: "1391.256")!), "1391.26")
    }

    func testCompactFormatterKeepsPrecisionForSmallPrices() {
        let formatter = PriceDisplayFormatter()

        XCTAssertEqual(formatter.compactString(from: Decimal(string: "0.201234")!), "0.20123")
        XCTAssertEqual(formatter.compactString(from: Decimal(string: "0.00234567")!), "0.00234567")
    }

    func testDisplayFormatterKeepsPrecisionForSmallPrices() {
        let formatter = PriceDisplayFormatter()

        XCTAssertEqual(formatter.string(from: Decimal(string: "0.201234")!), "0.201234")
        XCTAssertEqual(formatter.string(from: Decimal(string: "1.23456")!), "1.2346")
    }
}
