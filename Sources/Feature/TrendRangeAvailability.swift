import Foundation

struct TrendRangeAvailability: Sendable {
    func availableRanges(
        earliestDate: Date?,
        now: Date = .now,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [TrendRange] {
        guard let earliestDate else { return TrendRange.allCases }

        return TrendRange.allCases.filter { range in
            guard let cutoffDate = cutoffDate(for: range, now: now, calendar: calendar) else {
                return true
            }
            return earliestDate <= cutoffDate
        }
    }

    private func cutoffDate(
        for range: TrendRange,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        switch range {
        case .oneHour, .allHistory:
            return nil
        case .oneDay:
            return calendar.date(byAdding: .day, value: -1, to: now)
        case .oneWeek:
            return calendar.date(byAdding: .day, value: -7, to: now)
        case .oneMonth:
            return calendar.date(byAdding: .month, value: -1, to: now)
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: now)
        case .oneYear:
            return calendar.date(byAdding: .year, value: -1, to: now)
        case .threeYears:
            return calendar.date(byAdding: .year, value: -3, to: now)
        }
    }
}
