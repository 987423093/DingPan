import AppKit

enum PriceMenuBarTitleRenderer {
    static func makeImage(text: String) -> NSImage {
        let displayText = text.isEmpty ? "行情 --" : text
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        let textWidth = ceil((displayText as NSString).size(withAttributes: [.font: font]).width)
        let barSize = NSSize(width: max(60, textWidth + 6), height: 18)
        let image = NSImage(size: barSize)
        image.isTemplate = false
        image.lockFocus()

        NSColor.clear.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: image.size)).fill()

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
        shadow.shadowBlurRadius = 1
        shadow.shadowOffset = NSSize(width: 0, height: -1)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .shadow: shadow
        ]
        let point = CGPoint(
            x: (barSize.width - textWidth) / 2,
            y: image.size.height / 2 - (font.ascender - font.descender) / 2 - 1
        )
        (displayText as NSString).draw(at: point, withAttributes: attributes)
        image.unlockFocus()
        return image
    }

    static func placeholderImage() -> NSImage {
        makeImage(text: "行情 --")
    }
}
