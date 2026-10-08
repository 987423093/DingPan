import AppKit
import SwiftUI

/// 图表交互桥接视图，负责把 AppKit 的鼠标、滚轮和触控板事件传给 SwiftUI。
struct ChartInteractionView: NSViewRepresentable {
    let onHover: (CGPoint?) -> Void
    let onMouseDown: (CGPoint) -> Void
    let onDrag: (CGFloat, CGPoint) -> Void
    let onMouseUp: (CGPoint, Bool) -> Void
    let onScroll: (CGFloat) -> Void
    let onMagnify: (CGFloat, CGFloat?) -> Void

    /// 创建承载图表交互事件的 AppKit 视图。
    /// - Parameter context: SwiftUI 提供的上下文。
    /// - Returns: 可接收鼠标和触控板事件的原生视图。
    func makeNSView(context: Context) -> ChartInteractionNSView {
        let view = ChartInteractionNSView()
        updateCallbacks(on: view)
        return view
    }

    /// 更新交互视图的事件回调，确保 SwiftUI 状态始终使用最新闭包。
    /// - Parameters:
    ///   - nsView: 已创建的 AppKit 交互视图。
    ///   - context: SwiftUI 提供的上下文。
    /// - Returns: 无。
    func updateNSView(_ nsView: ChartInteractionNSView, context: Context) {
        updateCallbacks(on: nsView)
    }

    /// 将 SwiftUI 的事件处理闭包写入 AppKit 视图。
    /// - Parameter view: 需要更新回调的原生交互视图。
    /// - Returns: 无。
    private func updateCallbacks(on view: ChartInteractionNSView) {
        view.onHover = onHover
        view.onMouseDown = onMouseDown
        view.onDrag = onDrag
        view.onMouseUp = onMouseUp
        view.onScroll = onScroll
        view.onMagnify = onMagnify
    }
}

/// 接收图表区域内原生指针和触控板事件的透明 NSView。
/// @auther 周涛
final class ChartInteractionNSView: NSView {
    var onHover: ((CGPoint?) -> Void)?
    var onMouseDown: ((CGPoint) -> Void)?
    var onDrag: ((CGFloat, CGPoint) -> Void)?
    var onMouseUp: ((CGPoint, Bool) -> Void)?
    var onScroll: ((CGFloat) -> Void)?
    var onMagnify: ((CGFloat, CGFloat?) -> Void)?

    private var lastDragX: CGFloat?
    private var dragStartLocation: CGPoint?
    private var didDrag = false

    /// 使用左上角作为坐标原点，和 SwiftUI ChartProxy 的坐标系保持一致。
    override var isFlipped: Bool { true }

    /// 允许透明交互层接收鼠标和触控板事件。
    override var acceptsFirstResponder: Bool { true }

    /// 允许非激活的弹出窗口首次点击就开始拖动图表。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 初始化图表交互视图，保留鼠标、悬停和横向滚动事件能力。
    /// - Parameter frameRect: 交互视图的初始边界。
    /// - Returns: 已配置鼠标、悬停和滚动事件的图表交互视图。
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureTouchInteraction()
    }

    /// 从归档数据初始化交互视图，并保持与代码创建路径一致的手势能力。
    /// - Parameter coder: AppKit 解码器。
    /// - Returns: 初始化成功的图表交互视图。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTouchInteraction()
    }

    /// 配置图表区域接收触控板的间接触摸，为双指距离缩放提供原始触点数据。
    /// - Returns: 无；只开启当前透明交互视图的间接触摸接收能力。
    private func configureTouchInteraction() {
        wantsRestingTouches = true
    }

    /// 建立鼠标移动追踪区域，让悬停提示可以继续工作。
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
        super.updateTrackingAreas()
    }

    /// 处理鼠标按下，记录拖动起点并更新悬停位置。
    /// - Parameter event: AppKit 鼠标事件。
    /// - Returns: 无。
    override func mouseDown(with event: NSEvent) {
        let location = location(for: event)
        lastDragX = location.x
        dragStartLocation = location
        didDrag = false
        onHover?(location)
        onMouseDown?(location)
        window?.makeFirstResponder(self)
    }

    /// 处理鼠标拖动，按增量平移图表时间窗口。
    /// - Parameter event: AppKit 鼠标拖动事件。
    /// - Returns: 无。
    override func mouseDragged(with event: NSEvent) {
        let location = location(for: event)
        let x = location.x
        if let lastDragX {
            let start = dragStartLocation ?? location
            didDrag = didDrag || hypot(location.x - start.x, location.y - start.y) >= 5
            if didDrag {
                onDrag?(x - lastDragX, location)
            }
        }
        lastDragX = x
        onHover?(location)
    }

    /// 处理鼠标释放，结束本次拖动。
    /// - Parameter event: AppKit 鼠标释放事件。
    /// - Returns: 无。
    override func mouseUp(with event: NSEvent) {
        let location = location(for: event)
        onMouseUp?(location, didDrag)
        lastDragX = nil
        dragStartLocation = nil
        didDrag = false
        onHover?(location)
    }

    /// 直接接收当前图表区域的 macOS 捏合事件，避免依赖全局事件监听导致双指缩放丢失或重复触发。
    /// - Parameter event: AppKit 生成的捏合事件，正值表示放大，负值表示缩小。
    /// - Returns: 无；将缩放增量和手势中心点转发给 SwiftUI 图表。
    override func magnify(with event: NSEvent) {
        let value = event.magnification
        guard value.isFinite, abs(value) > 0.0001 else { return }
        let midpointRatio: CGFloat? = {
            guard let point = chartPoint(for: event), bounds.width > 0 else { return nil }
            return min(max(point.x / bounds.width, 0), 1)
        }()
        onMagnify?(value, midpointRatio)
    }

    /// 处理鼠标或触控板滚轮事件，实现双指横向平移。
    /// - Parameter event: AppKit 滚轮事件。
    /// - Returns: 无。
    override func scrollWheel(with event: NSEvent) {
        let deltaX = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.deltaX
        let deltaY = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        guard abs(deltaX) > abs(deltaY) else { return }
        onScroll?(deltaX)
    }

    /// 将本地或全局手势事件转换到图表交互视图坐标系。
    /// - Parameter event: AppKit 本地或全局事件。
    /// - Returns: 图表内的本地坐标；窗口不存在时返回 nil。
    private func chartPoint(for event: NSEvent) -> CGPoint? {
        guard let viewWindow = window else { return nil }
        let screenPoint: NSPoint
        if let eventWindow = event.window {
            screenPoint = eventWindow.convertPoint(toScreen: event.locationInWindow)
        } else {
            screenPoint = NSEvent.mouseLocation
        }
        let windowPoint = viewWindow.convertPoint(fromScreen: screenPoint)
        return convert(windowPoint, from: nil)
    }

    /// 将窗口坐标转换为当前交互视图的本地坐标。
    /// - Parameter event: 需要转换坐标的 AppKit 事件。
    /// - Returns: 视图本地坐标。
    private func location(for event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    /// 鼠标进入图表时更新悬停位置。
    /// - Parameter event: AppKit 鼠标进入事件。
    /// - Returns: 无。
    override func mouseEntered(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onHover?(location(for: event))
    }

    /// 鼠标移动时更新悬停位置。
    /// - Parameter event: AppKit 鼠标移动事件。
    /// - Returns: 无。
    override func mouseMoved(with event: NSEvent) {
        onHover?(location(for: event))
    }

    /// 鼠标离开图表时清除悬停提示。
    /// - Parameter event: AppKit 鼠标离开事件。
    /// - Returns: 无。
    override func mouseExited(with event: NSEvent) {
        onHover?(nil)
    }

}
