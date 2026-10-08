import Foundation

struct TrendChartDomainCalculator: Sendable {
    func domain(for values: [Double]) -> ClosedRange<Double> {
        let finiteValues = values.filter(\.isFinite)
        guard let minimum = finiteValues.min(), let maximum = finiteValues.max() else {
            return 0 ... 1
        }

        let span = maximum - minimum
        let reference = max(abs(minimum), abs(maximum))
        let padding = padding(span: span, reference: reference)
        return (minimum - padding) ... (maximum + padding)
    }

    private func padding(span: Double, reference: Double) -> Double {
        if span > 0 {
            return max(span * 0.12, reference * 0.001, 0.00000001)
        }

        if reference > 0 {
            return max(reference * 0.002, 0.00000001)
        }

        return 1
    }
}
