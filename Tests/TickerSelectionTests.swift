import XCTest
@testable import SKHynixMenuBar

final class TickerSelectionTests: XCTestCase {
    func testSelectionKeepsAtLeastOneSymbol() {
        var selection = TickerSelection(selectedSymbols: ["SKHYNIXUSDT"])

        let result = selection.toggle("SKHYNIXUSDT")

        XCTAssertEqual(result, .requiresOneSymbol)
        XCTAssertEqual(selection.selectedSymbols, ["SKHYNIXUSDT"])
    }

    func testSelectionAllowsMoreThanFourSymbolsForTrend() {
        var selection = TickerSelection(
            selectedSymbols: ["SKHYNIXUSDT", "SAMSUNGUSDT", "MUUSDT", "NVDAUSDT"]
        )

        let result = selection.toggle("TSMUSDT")

        XCTAssertEqual(result, .updated)
        XCTAssertEqual(
            selection.selectedSymbols,
            ["SKHYNIXUSDT", "SAMSUNGUSDT", "MUUSDT", "NVDAUSDT", "TSMUSDT"]
        )
    }

    func testMenuBarSymbolsDefaultToFirstEightSelections() {
        let selection = TickerSelection(
            selectedSymbols: [
                "SKHYNIXUSDT", "SAMSUNGUSDT", "MUUSDT", "NVDAUSDT", "TSMUSDT",
                "ETHUSDT", "BTCUSDT", "BANKUSDT", "SOLUSDT"
            ]
        )

        XCTAssertEqual(
            selection.menuBarSymbols,
            [
                "SKHYNIXUSDT", "SAMSUNGUSDT", "MUUSDT", "NVDAUSDT", "TSMUSDT",
                "ETHUSDT", "BTCUSDT", "BANKUSDT"
            ]
        )
    }

    func testMenuBarSymbolsCanBeSelectedIndependentlyFromSelectionOrder() {
        var selection = TickerSelection(
            selectedSymbols: ["SKHYNIXUSDT", "SAMSUNGUSDT", "MUUSDT", "NVDAUSDT"],
            menuBarSymbols: ["NVDAUSDT", "SKHYNIXUSDT"]
        )

        XCTAssertEqual(selection.menuBarSymbols, ["NVDAUSDT", "SKHYNIXUSDT"])
        XCTAssertEqual(selection.toggleMenuBarSymbol("MUUSDT"), .updated)
        XCTAssertEqual(selection.menuBarSymbols, ["NVDAUSDT", "SKHYNIXUSDT", "MUUSDT"])
    }

    func testRemovingSelectedSymbolRemovesItFromMenuBar() {
        var selection = TickerSelection(
            selectedSymbols: ["SKHYNIXUSDT", "NVDAUSDT"],
            menuBarSymbols: ["NVDAUSDT", "SKHYNIXUSDT"]
        )

        XCTAssertEqual(selection.toggle("NVDAUSDT"), .updated)
        XCTAssertEqual(selection.menuBarSymbols, ["SKHYNIXUSDT"])
    }

    func testSelectionAllowsAtMostThirtySymbols() {
        let initialSymbols = (1 ... 30).map { "TOKEN\($0)USDT" }
        var selection = TickerSelection(selectedSymbols: initialSymbols)

        let result = selection.toggle("TOKEN31USDT")

        XCTAssertEqual(result, .maximumReached)
        XCTAssertEqual(selection.selectedSymbols, initialSymbols)
    }

    func testSelectionAppendsAndRemovesSymbolsInUserOrder() {
        var selection = TickerSelection(selectedSymbols: ["SKHYNIXUSDT"])

        XCTAssertEqual(selection.toggle("NVDAUSDT"), .updated)
        XCTAssertEqual(selection.toggle("MUUSDT"), .updated)
        XCTAssertEqual(selection.toggle("NVDAUSDT"), .updated)

        XCTAssertEqual(selection.selectedSymbols, ["SKHYNIXUSDT", "MUUSDT"])
    }

    func testSelectionMovesSymbolToDroppedSymbolPosition() {
        var selection = TickerSelection(
            selectedSymbols: ["BANKUSDT", "MUUSDT", "SKHYNIXUSDT", "ETHUSDT", "SAMSUNGUSDT"]
        )

        XCTAssertTrue(selection.move("SAMSUNGUSDT", to: "MUUSDT"))
        XCTAssertEqual(
            selection.selectedSymbols,
            ["BANKUSDT", "SAMSUNGUSDT", "MUUSDT", "SKHYNIXUSDT", "ETHUSDT"]
        )

        XCTAssertTrue(selection.move("BANKUSDT", to: "ETHUSDT"))
        XCTAssertEqual(
            selection.selectedSymbols,
            ["SAMSUNGUSDT", "MUUSDT", "SKHYNIXUSDT", "ETHUSDT", "BANKUSDT"]
        )
    }

    func testSelectionAcceptsSearchedBinanceSymbol() {
        var selection = TickerSelection(selectedSymbols: ["SKHYNIXUSDT"])

        let result = selection.toggle("btcusdt")

        XCTAssertEqual(result, .updated)
        XCTAssertEqual(selection.selectedSymbols, ["SKHYNIXUSDT", "BTCUSDT"])
    }

    func testSelectionRemovesSearchedBinanceSymbol() {
        var selection = TickerSelection(selectedSymbols: ["SKHYNIXUSDT", "BANKUSDT"])

        let result = selection.toggle("BANKUSDT")

        XCTAssertEqual(result, .updated)
        XCTAssertEqual(selection.selectedSymbols, ["SKHYNIXUSDT"])
    }

    func testMenuBarTextCombinesSelectedQuotesInSelectionOrder() {
        let quotes = [
            LatestPrice(symbol: "NVDAUSDT", value: Decimal(string: "207.66")!, updatedAt: .now),
            LatestPrice(symbol: "SKHYNIXUSDT", value: Decimal(string: "1297.21")!, updatedAt: .now)
        ]

        let text = PriceMenuBarTextBuilder().makeText(
            selectedSymbols: ["SKHYNIXUSDT", "NVDAUSDT"],
            prices: quotes
        )

        XCTAssertEqual(text, "SKH 1297.2 · NVDA 207.7")
    }

    func testMenuBarTextUsesOnlyFirstEightSelectedQuotes() {
        let symbols = [
            "SKHYNIXUSDT", "SAMSUNGUSDT", "MUUSDT", "NVDAUSDT", "TSMUSDT",
            "ETHUSDT", "BTCUSDT", "BANKUSDT", "SOLUSDT"
        ]
        let quotes = symbols.enumerated().map { index, symbol in
            LatestPrice(symbol: symbol, value: Decimal(index + 1), updatedAt: .now)
        }

        let text = PriceMenuBarTextBuilder().makeText(selectedSymbols: symbols, prices: quotes)

        XCTAssertEqual(text, "SKH 1.0 · 三星 2.0 · MU 3.0 · NVDA 4.0 · TSM 5.0 · ETH 6.0 · BTC 7.0 · BANK 8.0")
    }
}
