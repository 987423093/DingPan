import AppKit

enum TickerPanelLayout {
    static func frame(contentSize: NSSize, safeArea: NSRect) -> NSRect {
        let horizontalInset: CGFloat = 12
        let availableWidth = max(1, safeArea.width - horizontalInset * 2)
        let width = min(contentSize.width, availableWidth)
        let x = max(safeArea.minX + horizontalInset, safeArea.maxX - horizontalInset - width)
        let y = safeArea.midY - contentSize.height / 2
        return NSRect(x: x, y: y, width: width, height: contentSize.height)
    }

    static func freeFrame(contentSize: NSSize, screenFrame: NSRect, origin: NSPoint) -> NSRect {
        let width = min(contentSize.width, screenFrame.width)
        let height = min(contentSize.height, screenFrame.height)
        let x = min(max(origin.x, screenFrame.minX), screenFrame.maxX - width)
        let y = min(max(origin.y, screenFrame.minY), screenFrame.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
