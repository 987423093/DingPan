import XCTest
@testable import SKHynixMenuBar

final class TrendDisplayFormatterTests: XCTestCase {
    func testFormatsPriceAndPositiveChange() {
        let formatter = TrendDisplayFormatter()

        XCTAssertEqual(formatter.price(Decimal(string: "1268.7")!), "1268.70")
        XCTAssertEqual(formatter.change(Decimal(10)), "+10.00")
        XCTAssertEqual(formatter.percent(Decimal(5)), "+5.00%")
    }

    func testFormatsNegativeChangeWithoutExtraSign() {
        let formatter = TrendDisplayFormatter()

        XCTAssertEqual(formatter.change(Decimal(string: "-8.25")!), "-8.25")
        XCTAssertEqual(formatter.percent(Decimal(string: "-0.65")!), "-0.65%")
    }

    func testFormatsAmountWithChineseUnits() {
        let formatter = TrendDisplayFormatter()

        XCTAssertEqual(formatter.amount(Decimal(string: "9999")!), "9999")
        XCTAssertEqual(formatter.amount(Decimal(string: "10000")!), "1万")
        XCTAssertEqual(formatter.amount(Decimal(string: "12345678")!), "1234.57万")
        XCTAssertEqual(formatter.amount(Decimal(string: "100000000")!), "1亿")
        XCTAssertEqual(formatter.amount(Decimal(string: "1500000000000")!), "1.5万亿")
    }
}
