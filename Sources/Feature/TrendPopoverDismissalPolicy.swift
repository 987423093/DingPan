enum TrendPopoverClickTarget {
    case tickerButton
    case popover
    case popUpMenu
    case outside
}

enum TrendPopoverDismissalPolicy {
    static func shouldDismiss(for target: TrendPopoverClickTarget) -> Bool {
        switch target {
        case .tickerButton, .popover, .popUpMenu:
            false
        case .outside:
            true
        }
    }
}
