import AppKit

@MainActor
final class UserDefaultsTickerPanelPositionPreferences {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "tickerPanelPosition") {
        self.defaults = defaults
        self.key = key
    }

    func loadPosition() -> NSPoint? {
        guard let values = defaults.dictionary(forKey: key),
              let x = values["x"] as? Double,
              let y = values["y"] as? Double else {
            return nil
        }
        return NSPoint(x: x, y: y)
    }

    func savePosition(_ position: NSPoint) {
        defaults.set(["x": position.x, "y": position.y], forKey: key)
    }
}
