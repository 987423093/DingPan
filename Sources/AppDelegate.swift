import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

enum DebugLogger {
    static func log(_ message: String) {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SKHynixMenuBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("debug.log")
        let line = "[\(ISO8601DateFormatter().string(from: .now))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: fileURL.path),
           let handle = try? FileHandle(forWritingTo: fileURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let viewModel = PriceTickerStore()
    private let trendStore = PriceTrendStore()
    private let contractSearchStore = ContractSearchStore()
    private let tickerPositionPreferences = UserDefaultsTickerPanelPositionPreferences()
    private var tickerPanel: NSPanel?
    private var tickerView: DraggableTickerView?
    private var trendPopover: NSPopover?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var tickerPointerLocalMonitor: Any?
    private var tickerPointerGlobalMonitor: Any?
    private var bossKeyRef: EventHotKeyRef?
    private var panelToggleKeyRef: EventHotKeyRef?
    private var bossKeyEventHandlerRef: EventHandlerRef?
    private var tickerDragState: TickerDragState?
    private var isTickerPanelHidden = false
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLogger.log("applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)
        DebugLogger.log("activation policy switched to accessory")
        registerLaunchAtLogin()
        createTickerPanel()
        installTickerPointerMonitors()
        installKeyboardShortcutMonitors()
        bindViewModel()
        viewModel.start()
    }

    private func createTickerPanel() {
        let image = PriceMenuBarTitleRenderer.placeholderImage()
        let tickerView = DraggableTickerView(image: image)
        tickerView.toolTip = "自选行情"

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: image.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = tickerView

        self.tickerView = tickerView
        tickerPanel = panel
        createTrendPopover()
        updateTickerPanel(text: "行情 --")
        panel.orderFrontRegardless()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.positionTickerPanel()
            }
            .store(in: &cancellables)
        DebugLogger.log("ticker panel created")
    }

    private func bindViewModel() {
        viewModel.$titleText
            .sink { [weak self] text in
                self?.updateTickerPanel(text: text)
            }
            .store(in: &cancellables)

        viewModel.$selectedSymbols
            .sink { [weak self] symbols in
                self?.trendStore.synchronizeSelectedSymbols(symbols)
            }
            .store(in: &cancellables)
    }

    private func createTrendPopover() {
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentSize = TrendPopoverView.contentSize
        popover.delegate = self
        trendPopover = popover
    }

    /// 在趋势图真正打开前创建 SwiftUI 内容，避免应用启动后后台持续维护 Chart 视图树。
    /// - Returns: 无；将当前行情和趋势状态注入到弹窗内容控制器。
    private func installTrendPopoverContent() {
        guard let trendPopover,
              trendPopover.contentViewController == nil else {
            return
        }
        trendPopover.contentViewController = NSHostingController(
            rootView: TrendPopoverView(
                tickerStore: viewModel,
                trendStore: trendStore,
                searchStore: contractSearchStore
            )
        )
    }

    private func updateTickerPanel(text: String) {
        let image = PriceMenuBarTitleRenderer.makeImage(text: text)
        tickerView?.image = image
        tickerView?.setAccessibilityLabel(text)
        tickerView?.frame = NSRect(origin: .zero, size: image.size)
        positionTickerPanel(contentSize: image.size)
        if !isTickerPanelHidden {
            tickerPanel?.orderFrontRegardless()
        }
    }

    private func positionTickerPanel(contentSize: NSSize? = nil) {
        guard let panel = tickerPanel else {
            return
        }
        let size = contentSize ?? panel.frame.size
        if let savedOrigin = tickerPositionPreferences.loadPosition(),
           let screen = screen(containing: savedOrigin) ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first {
            panel.setFrame(
                TickerPanelLayout.freeFrame(contentSize: size, screenFrame: screen.frame, origin: savedOrigin),
                display: true
            )
            return
        }
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            return
        }
        let safeArea: NSRect
        if #available(macOS 12.0, *), let leftArea = screen.auxiliaryTopLeftArea {
            safeArea = leftArea
        } else {
            safeArea = NSRect(
                x: screen.frame.minX,
                y: screen.frame.maxY - 24,
                width: screen.frame.width / 2,
                height: 24
            )
        }
        panel.setFrame(TickerPanelLayout.frame(contentSize: size, safeArea: safeArea), display: true)
    }

    private func moveTickerPanel(to mouseLocation: NSPoint, offset: NSPoint) {
        guard let panel = tickerPanel,
              let screen = screen(containing: mouseLocation) ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            return
        }
        closeTrendPopover()
        let origin = NSPoint(
            x: mouseLocation.x - offset.x,
            y: mouseLocation.y - offset.y
        )
        let frame = TickerPanelLayout.freeFrame(
            contentSize: panel.frame.size,
            screenFrame: screen.frame,
            origin: origin
        )
        panel.setFrame(frame, display: true)
        tickerPositionPreferences.savePosition(frame.origin)
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func toggleTrendPopover() {
        guard let trendPopover, let tickerView else { return }
        if trendPopover.isShown {
            closeTrendPopover()
            DebugLogger.log("trend popover closed by toggle")
        } else {
            if isTickerPanelHidden {
                isTickerPanelHidden = false
                tickerPanel?.orderFrontRegardless()
                DebugLogger.log("ticker panel shown for trend popover")
            }
            NSApp.activate(ignoringOtherApps: true)
            installTrendPopoverContent()
            trendPopover.show(relativeTo: tickerView.bounds, of: tickerView, preferredEdge: .minY)
            DebugLogger.log("trend popover opened by toggle")
        }
    }

    func popoverDidShow(_ notification: Notification) {
        installPopoverEventMonitors()
    }

    func popoverDidClose(_ notification: Notification) {
        removePopoverEventMonitors()
        trendStore.close()
        trendPopover?.contentViewController = nil
        DebugLogger.log("trend popover closed")
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeTickerPointerMonitors()
        removeKeyboardShortcutMonitors()
        removePopoverEventMonitors()
    }

    /// 注册 macOS 原生全局快捷键，使 Command + G 和 Command + T 在其他应用前台时也能使用。
    /// - Returns: 无返回值；快捷键句柄和事件处理器句柄保存在实例属性中。
    private func installKeyboardShortcutMonitors() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            bossKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &bossKeyEventHandlerRef
        )
        guard installStatus == noErr else {
            DebugLogger.log("boss key event handler install failed; status=\(installStatus)")
            return
        }

        let bossKeyID = EventHotKeyID(
            signature: Self.bossKeySignature,
            id: Self.bossKeyIdentifier
        )
        let bossKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_G),
            UInt32(cmdKey),
            bossKeyID,
            GetApplicationEventTarget(),
            0,
            &bossKeyRef
        )
        guard bossKeyStatus == noErr else {
            if let bossKeyEventHandlerRef {
                RemoveEventHandler(bossKeyEventHandlerRef)
                self.bossKeyEventHandlerRef = nil
            }
            DebugLogger.log("boss key registration failed; status=\(bossKeyStatus)")
            return
        }

        let panelToggleID = EventHotKeyID(
            signature: Self.bossKeySignature,
            id: Self.panelToggleKeyIdentifier
        )
        let panelToggleStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_T),
            UInt32(cmdKey),
            panelToggleID,
            GetApplicationEventTarget(),
            0,
            &panelToggleKeyRef
        )
        guard panelToggleStatus == noErr else {
            UnregisterEventHotKey(bossKeyRef)
            bossKeyRef = nil
            if let bossKeyEventHandlerRef {
                RemoveEventHandler(bossKeyEventHandlerRef)
                self.bossKeyEventHandlerRef = nil
            }
            DebugLogger.log("panel toggle key registration failed; status=\(panelToggleStatus)")
            return
        }
        DebugLogger.log("global hotkeys installed with Carbon; shortcuts=Command+G,Command+T")
    }

    /// 移除原生全局快捷键，避免应用退出后残留系统事件回调。
    /// - Returns: 无返回值。
    private func removeKeyboardShortcutMonitors() {
        if let bossKeyRef {
            UnregisterEventHotKey(bossKeyRef)
            self.bossKeyRef = nil
        }
        if let panelToggleKeyRef {
            UnregisterEventHotKey(panelToggleKeyRef)
            self.panelToggleKeyRef = nil
        }
        if let bossKeyEventHandlerRef {
            RemoveEventHandler(bossKeyEventHandlerRef)
            self.bossKeyEventHandlerRef = nil
        }
    }

    /// 切换顶部指标面板的隐藏与显示状态，并在显示时恢复原位置。
    /// - Returns: 无返回值。
    private func toggleTickerPanelVisibility() {
        guard let panel = tickerPanel else { return }
        closeTrendPopover()
        isTickerPanelHidden.toggle()
        if isTickerPanelHidden {
            panel.orderOut(nil)
            DebugLogger.log("ticker panel hidden by boss key")
        } else {
            panel.orderFrontRegardless()
            DebugLogger.log("ticker panel shown by boss key")
        }
    }

    /// 提供给 Carbon 全局快捷键回调的主线程入口。
    /// - Returns: 无返回值；实际切换逻辑由面板状态方法完成。
    func toggleTickerPanelVisibilityFromHotKey() {
        toggleTickerPanelVisibility()
    }

    /// 提供给 Carbon 全局快捷键回调的趋势图展开/收起入口。
    /// - Returns: 无返回值；Command + T 会在打开和关闭趋势图之间切换。
    func toggleTrendPopoverFromHotKey() {
        toggleTrendPopover()
    }

    private static let bossKeySignature: OSType = 0x534B4847
    private static let bossKeyIdentifier: UInt32 = 1
    private static let panelToggleKeyIdentifier: UInt32 = 2

    private func installTickerPointerMonitors() {
        let eventMask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        tickerPointerLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            self?.handleTickerPointerEvent(event)
            return event
        }
        tickerPointerGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleTickerPointerEvent(event)
            }
        }
    }

    private func removeTickerPointerMonitors() {
        if let tickerPointerLocalMonitor {
            NSEvent.removeMonitor(tickerPointerLocalMonitor)
            self.tickerPointerLocalMonitor = nil
        }
        if let tickerPointerGlobalMonitor {
            NSEvent.removeMonitor(tickerPointerGlobalMonitor)
            self.tickerPointerGlobalMonitor = nil
        }
    }

    private func handleTickerPointerEvent(_ event: NSEvent) {
        guard let panel = tickerPanel else { return }
        let mouseLocation = NSEvent.mouseLocation

        switch event.type {
        case .leftMouseDown:
            guard panel.frame.contains(mouseLocation) else { return }
            tickerDragState = TickerDragState(
                startMouseLocation: mouseLocation,
                offset: NSPoint(
                    x: mouseLocation.x - panel.frame.minX,
                    y: mouseLocation.y - panel.frame.minY
                )
            )
        case .leftMouseDragged:
            guard var state = tickerDragState else { return }
            let distance = hypot(
                mouseLocation.x - state.startMouseLocation.x,
                mouseLocation.y - state.startMouseLocation.y
            )
            guard distance >= 3 else { return }
            state.isDragging = true
            tickerDragState = state
            moveTickerPanel(to: mouseLocation, offset: state.offset)
        case .leftMouseUp:
            guard let state = tickerDragState else { return }
            tickerDragState = nil
            if !state.isDragging {
                toggleTrendPopover()
            }
        default:
            return
        }
    }

    private func installPopoverEventMonitors() {
        removePopoverEventMonitors()

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            let target = self.clickTarget(for: event)
            if TrendPopoverDismissalPolicy.shouldDismiss(for: target) {
                self.closeTrendPopover()
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closeTrendPopover()
            }
        }
    }

    private func removePopoverEventMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func clickTarget(for event: NSEvent) -> TrendPopoverClickTarget {
        guard let eventWindow = event.window else { return .outside }
        if eventWindow == tickerPanel {
            return .tickerButton
        }
        if eventWindow == trendPopover?.contentViewController?.view.window {
            return .popover
        }
        if eventWindow.level == .popUpMenu {
            return .popUpMenu
        }
        return .outside
    }

    private func closeTrendPopover() {
        guard trendPopover?.isShown == true else { return }
        trendPopover?.performClose(nil)
    }

    private func registerLaunchAtLogin() {
        do {
            if #available(macOS 13.0, *) {
                try SMAppService.mainApp.register()
                DebugLogger.log("launch at login registered")
            }
        } catch {
            DebugLogger.log("launch at login register failed: \(error.localizedDescription)")
        }
    }

}

private struct TickerDragState {
    let startMouseLocation: NSPoint
    let offset: NSPoint
    var isDragging = false
}

/// 接收 Carbon 全局快捷键事件并切回主线程更新顶部指标面板。
/// - Parameters:
///   - nextHandler: Carbon 事件链中的下一个处理器，当前不需要继续转发。
///   - event: 收到的系统快捷键事件。
///   - userData: 注册监听时传入的 AppDelegate 非拥有指针。
/// - Returns: Carbon 处理状态；始终返回 noErr 表示事件已处理。
private func bossKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard event != nil,
          let userData else {
        return noErr
    }
    var hotKeyID = EventHotKeyID()
    let parameterStatus = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard parameterStatus == noErr else {
        return parameterStatus
    }
    let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor [weak appDelegate] in
        guard let appDelegate else { return }
        if hotKeyID.id == 1 {
            appDelegate.toggleTickerPanelVisibilityFromHotKey()
        } else if hotKeyID.id == 2 {
            appDelegate.toggleTrendPopoverFromHotKey()
        }
    }
    return noErr
}
