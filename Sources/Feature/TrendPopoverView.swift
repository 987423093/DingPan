import Charts
import SwiftUI

struct TrendPopoverView: View {
    static let contentSize = CGSize(width: 528, height: 440)

    @ObservedObject var tickerStore: PriceTickerStore
    @ObservedObject var trendStore: PriceTrendStore
    @ObservedObject var searchStore: ContractSearchStore
    @State private var hoveredCandle: PriceCandle?
    @State private var hoverLocation: CGPoint?
    @State private var chartViewport: ChartViewport?
    @State private var measurementPressCandle: PriceCandle?
    @State private var measurementStartCandle: PriceCandle?
    @State private var measurementEndCandle: PriceCandle?

    private let formatter = TrendDisplayFormatter()
    private let priceFormatter = PriceDisplayFormatter()
    private let domainCalculator = TrendChartDomainCalculator()
    private let hoverSelector = TrendCandleHoverSelector()

    var body: some View {
        VStack(spacing: 10) {
            searchSection

            HStack(alignment: .top, spacing: 18) {
                symbolSidebar

                VStack(spacing: 10) {
                    timeframePicker
                    summary
                    chartContent
                    hoverDetails
                    footer
                }
            }
        }
        .padding(14)
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .background(BinanceTheme.background)
        .foregroundStyle(BinanceTheme.primaryText)
        .environment(\.colorScheme, .dark)
        .onAppear {
            trendStore.open(selectedSymbols: tickerStore.selectedSymbols)
            searchStore.loadIfNeeded()
            syncLivePrice(from: tickerStore.latestPrices)
        }
        .onChange(of: tickerStore.selectedSymbols) { symbols in
            trendStore.synchronizeSelectedSymbols(symbols)
        }
        .onChange(of: tickerStore.latestPrices) { prices in
            syncLivePrice(from: prices)
        }
        .onChange(of: trendStore.selectedSymbol) { _ in
            hoveredCandle = nil
            hoverLocation = nil
            clearMeasurement()
        }
        .onChange(of: trendStore.selectedTimeframe) { _ in
            hoveredCandle = nil
            hoverLocation = nil
            clearMeasurement()
            resetChartViewport()
        }
        .onDisappear {
            hoveredCandle = nil
            hoverLocation = nil
            clearMeasurement()
        }
    }

    private var symbolSidebar: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 2) {
                ForEach(tickerStore.selectedSymbols, id: \.self) { symbolID in
                    Button {
                        trendStore.selectSymbol(symbolID)
                    } label: {
                        Text(menuSymbol(for: symbolID).shortName)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 23)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(trendStore.selectedSymbol == symbolID ? Color.white : Color.primary)
                    .background(
                        trendStore.selectedSymbol == symbolID
                            ? BinanceTheme.selected
                            : BinanceTheme.surface
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .help(menuSymbol(for: symbolID).name)
                    .draggable(symbolID)
                    .dropDestination(for: String.self) { droppedSymbols, _ in
                        guard let sourceSymbolID = droppedSymbols.first else { return false }
                        tickerStore.moveSymbol(sourceSymbolID, to: symbolID)
                        return true
                    }
                }
            }
            .frame(width: 76)
            .padding(.trailing, 12)
        }
        .frame(width: 88)
        .frame(maxHeight: .infinity)
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索合约，例如 BTC / SOL / ETHUSDT", text: $searchStore.query)
                    .textFieldStyle(.plain)
                if searchStore.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                managementMenu
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(BinanceTheme.input)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(BinanceTheme.border, lineWidth: 0.75)
            }

            searchResults
        }
        .frame(height: 58, alignment: .top)
    }

    @ViewBuilder
    private var searchResults: some View {
        if !searchStore.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if searchStore.results.isEmpty {
                Text(searchStore.errorText ?? "没有匹配的合约")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(searchStore.results) { symbol in
                            Button {
                                addSearchResult(symbol.id)
                            } label: {
                                Text(searchResultTitle(for: symbol))
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(searchResultIsDisabled(symbol.id))
                            .help(searchResultHelp(for: symbol.id))
                        }
                    }
                }
            }
        }
    }

    private var timeframePicker: some View {
        Picker("K线周期", selection: timeframeBinding) {
            ForEach(trendStore.availableTimeframes) { timeframe in
                Text(timeframe.title).tag(timeframe)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(maxWidth: .infinity)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(currentSymbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let currentPrice = trendStore.currentPrice {
                    Text(formatter.price(currentPrice))
                        .font(.system(size: 21, weight: .semibold, design: .monospaced))
                }

                if let measurement = currentMeasurement {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("区间")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(BinanceTheme.secondaryText)
                        Text("\(formatter.change(measurement.change))  \(formatter.percent(measurement.changePercent))")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(measurement.change >= 0 ? BinanceTheme.up : BinanceTheme.down)
                    }
                } else if let change = trendStore.priceChange,
                          let percent = trendStore.changePercent {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(trendStore.selectedTimeframe.title)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(BinanceTheme.secondaryText)
                        Text("\(formatter.change(change))  \(formatter.percent(percent))")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(trendColor)
                    }
                }
            }

        }
        .frame(minHeight: 28, alignment: .leading)
    }

    @ViewBuilder
    private var chartContent: some View {
        ZStack(alignment: .topTrailing) {
            if trendStore.candles.isEmpty {
                emptyChartState
            } else {
                trendChart
            }

            if trendStore.isLoading, !trendStore.candles.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(4)
            }

        }
        .frame(height: 142)
        .background(BinanceTheme.panel, in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(BinanceTheme.border, lineWidth: 0.75)
        }
        .contentShape(Rectangle())
    }

    /// 将悬停 K 线指标放在图表下方的独立区域，避免覆盖蜡烛和十字线。
    /// - Returns: 当前有悬停 K 线时显示指标卡片，否则显示等高的透明占位区域。
    @ViewBuilder
    private var hoverDetails: some View {
        HStack {
            if let hoveredCandle {
                hoverTooltip(for: hoveredCandle)
                    .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 86, maxHeight: 86, alignment: .topLeading)
    }

    @ViewBuilder
    private var trendChart: some View {
        Chart {
            ForEach(trendStore.candles, id: \.openTime) { candle in
                let color = candle.close >= candle.open
                    ? BinanceTheme.up
                    : BinanceTheme.down
                let body = candleBodyRange(for: candle)
                let bodyWidth = candleBodyWidth(for: candle)

                // 上下影线：从最低价连接到最高价，表现 Binance K 线的完整波动范围。
                RuleMark(
                    x: .value("时间", candle.openTime),
                    yStart: .value("最低", doubleValue(candle.low)),
                    yEnd: .value("最高", doubleValue(candle.high))
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .round))

                // 实体：开盘价和收盘价之间的矩形，绿色上涨、红色下跌。
                RectangleMark(
                    xStart: .value("实体开始", candle.openTime.addingTimeInterval(-bodyWidth / 2)),
                    xEnd: .value("实体结束", candle.openTime.addingTimeInterval(bodyWidth / 2)),
                    yStart: .value("实体低点", body.lowerBound),
                    yEnd: .value("实体高点", body.upperBound)
                )
                .foregroundStyle(color)
            }

            if let hoveredCandle {
                RuleMark(x: .value("悬停时间", hoveredCandle.openTime))
                    .foregroundStyle(BinanceTheme.crosshair)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                PointMark(
                    x: .value("悬停时间", hoveredCandle.openTime),
                    y: .value("悬停价格", doubleValue(hoveredCandle.close))
                )
                .foregroundStyle(trendColor)
                .symbolSize(52)
            }
        }
        .chartYScale(domain: chartYDomain)
        .chartPlotStyle { plotArea in
            plotArea
                .padding(.trailing, 32)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(BinanceTheme.grid.opacity(0.65))
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(axisLabel(for: date))
                            .font(.system(size: 9))
                            .foregroundStyle(BinanceTheme.secondaryText)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(BinanceTheme.grid.opacity(0.65))
                AxisValueLabel {
                    if let price = value.as(Double.self) {
                        Text(priceFormatter.axisString(from: price))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(BinanceTheme.secondaryText)
                            .offset(x: 10)
                    }
                }
            }
        }
        .chartXScale(domain: visibleChartDomain)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack {
                    measurementOverlay(proxy: proxy, geometry: geometry)
                    crosshairOverlay(proxy: proxy, geometry: geometry)

                    ChartInteractionView(
                        onHover: { location in
                            updateHoveredCandle(
                                at: location,
                                proxy: proxy,
                                geometry: geometry
                            )
                        },
                        onMouseDown: { location in
                            beginMeasurementPress(
                                at: location,
                                proxy: proxy,
                                geometry: geometry
                            )
                        },
                        onDrag: { deltaX, location in
                            handleChartDrag(
                                deltaX: deltaX,
                                at: location,
                                proxy: proxy,
                                geometry: geometry
                            )
                        },
                        onMouseUp: { _, didDrag in
                            if !didDrag, currentMeasurement != nil {
                                clearMeasurement()
                            }
                            measurementPressCandle = nil
                        },
                        onScroll: { deltaX in
                            shiftChart(by: deltaX, width: geometry.size.width)
                        },
                        onMagnify: { magnification, midpointRatio in
                            magnifyChart(by: magnification, aroundXRatio: midpointRatio)
                        }
                    )
                }
            }
        }
    }

    /// 绘制跟随鼠标高度的横向十字线，与图表内已有的竖向悬停线组成完整十字线。
    /// - Parameters:
    ///   - proxy: Swift Charts 提供的坐标转换代理。
    ///   - geometry: 图表交互层的几何信息。
    /// - Returns: 鼠标位于图表内时显示的横向虚线，否则为空视图。
    @ViewBuilder
    private func crosshairOverlay(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        if let hoverLocation {
            let plotRect = geometry[proxy.plotAreaFrame]
            let y = min(max(hoverLocation.y, plotRect.minY), plotRect.maxY)

            Path { path in
                path.move(to: CGPoint(x: plotRect.minX, y: y))
                path.addLine(to: CGPoint(x: plotRect.maxX, y: y))
            }
            .stroke(
                BinanceTheme.crosshair.opacity(0.85),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
            .allowsHitTesting(false)
        }
    }

    private var currentChartViewport: ChartViewport {
        if let chartViewport {
            return clampedViewport(start: chartViewport.start, end: chartViewport.end)
        }
        return defaultChartViewport
    }

    private var defaultChartViewport: ChartViewport {
        guard let dataDomain = chartDataDomain else {
            let end = Date.now
            return ChartViewport(start: end.addingTimeInterval(-3_600), end: end)
        }
        let duration = min(
            trendStore.selectedTimeframe.defaultVisibleDuration,
            max(dataDomain.upperBound.timeIntervalSince(dataDomain.lowerBound), 60)
        )
        return ChartViewport(
            start: dataDomain.upperBound.addingTimeInterval(-duration),
            end: dataDomain.upperBound
        )
    }

    private var chartDataDomain: ClosedRange<Date>? {
        guard let first = trendStore.candles.first?.openTime,
              let last = trendStore.candles.last?.openTime,
              first < last else {
            return nil
        }
        return first...last
    }

    private var visibleChartDomain: ClosedRange<Date> {
        currentChartViewport.start...currentChartViewport.end
    }

    /// 根据当前 K 线数据重置到最新时间窗口，保留缩放和拖动的明确入口。
    private func resetChartViewport() {
        chartViewport = nil
    }

    /// 按鼠标拖动或触控板横向滚动的增量平移时间窗口。
    /// - Parameters:
    ///   - deltaX: 本次事件在图表上的水平位移，单位为点。
    ///   - width: 图表交互区域的宽度，单位为点。
    /// - Returns: 无；通过状态更新当前可视时间窗口。
    private func shiftChart(by deltaX: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let viewport = currentChartViewport
        let secondsPerPoint = viewport.duration / width
        let shift = -Double(deltaX) * secondsPerPoint
        chartViewport = clampedViewport(
            start: viewport.start.addingTimeInterval(shift),
            end: viewport.end.addingTimeInterval(shift)
        )
    }

    /// 按触控板捏合增量缩放时间窗口，以双指中心点为时间锚点。
    /// - Parameters:
    ///   - magnification: AppKit 提供的本次捏合增量，正值表示放大。
    ///   - midpointRatio: 双指中心点在图表宽度中的比例，范围为 0 到 1。
    /// - Returns: 无；通过状态更新当前可视时间窗口。
    private func magnifyChart(by magnification: CGFloat, aroundXRatio midpointRatio: CGFloat? = nil) {
        let viewport = currentChartViewport
        let effectiveMagnification = magnification * 2.2
        let scale = min(max(exp(Double(effectiveMagnification)), 0.2), 5)
        let duration = viewport.duration / scale
        let ratio = min(max(midpointRatio ?? 0.5, 0), 1)
        let anchor = viewport.start.addingTimeInterval(viewport.duration * Double(ratio))
        let nextViewport = clampedViewport(
            start: anchor.addingTimeInterval(-duration * Double(ratio)),
            end: anchor.addingTimeInterval(duration * Double(1 - ratio))
        )
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            chartViewport = nextViewport
        }
    }

    /// 按中心点和目标时长生成新的可见时间窗口，并限制在已加载数据范围内。
    private func centeredViewport(around center: Date, duration: TimeInterval) -> ChartViewport {
        clampedViewport(
            start: center.addingTimeInterval(-duration / 2),
            end: center.addingTimeInterval(duration / 2)
        )
    }

    /// 将拖动或缩放后的时间窗口限制在当前已加载 K 线的首尾时间之间。
    private func clampedViewport(start: Date, end: Date) -> ChartViewport {
        guard let dataDomain = chartDataDomain else {
            return ChartViewport(start: start, end: end)
        }
        let totalDuration = max(dataDomain.upperBound.timeIntervalSince(dataDomain.lowerBound), 60)
        let requestedDuration = max(end.timeIntervalSince(start), 60)
        let duration = min(requestedDuration, totalDuration)
        var normalizedStart = start
        var normalizedEnd = start.addingTimeInterval(duration)

        if normalizedStart < dataDomain.lowerBound {
            normalizedStart = dataDomain.lowerBound
            normalizedEnd = normalizedStart.addingTimeInterval(duration)
        }
        if normalizedEnd > dataDomain.upperBound {
            normalizedEnd = dataDomain.upperBound
            normalizedStart = normalizedEnd.addingTimeInterval(-duration)
        }

        return ChartViewport(start: normalizedStart, end: normalizedEnd)
    }

    /// 根据图表坐标绘制拖动选中的半透明测量矩形。
    /// - Parameters:
    ///   - proxy: Swift Charts 提供的坐标转换代理。
    ///   - geometry: 图表交互层的几何信息。
    /// - Returns: 覆盖在 K 线绘图区上的测量视图，不拦截鼠标和触控板事件。
    @ViewBuilder
    private func measurementOverlay(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        let plotRect = geometry[proxy.plotAreaFrame]

        if let startCandle = measurementStartCandle,
           let startPosition = proxy.position(forX: startCandle.openTime) {
            let startX = plotRect.minX + startPosition

            if let endCandle = measurementEndCandle,
               let endPosition = proxy.position(forX: endCandle.openTime) {
                let endX = plotRect.minX + endPosition
                let left = min(startX, endX)
                let right = max(startX, endX)
                let width = max(right - left, 2)

                ZStack {
                    Rectangle()
                        .fill(BinanceTheme.selected.opacity(0.22))
                        .frame(width: width, height: plotRect.height)
                        .position(x: (left + right) / 2, y: plotRect.midY)

                    Rectangle()
                        .stroke(BinanceTheme.selected.opacity(0.8), lineWidth: 1)
                        .frame(width: width, height: plotRect.height)
                        .position(x: (left + right) / 2, y: plotRect.midY)

                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .allowsHitTesting(false)
            }
        }
    }

    private func hoverTooltip(for candle: PriceCandle) -> some View {
        let previousCandle = previousCandle(before: candle)
        let change = previousCandle.map { candle.close - $0.close }
        let percent: Decimal? = {
            guard let previousCandle,
                  let change,
                  previousCandle.close != 0 else {
                return nil
            }
            return change / previousCandle.close * 100
        }()

        return VStack(alignment: .leading, spacing: 3) {
            Text(hoverTimestamp(for: candle.openTime))
                .foregroundStyle(BinanceTheme.secondaryText)

            HStack(alignment: .top, spacing: 9) {
                VStack(alignment: .leading, spacing: 2) {
                    tooltipValue("开", candle.open)
                    tooltipValue("高", candle.high)
                    tooltipValue("低", candle.low)
                    tooltipValue("收", candle.close)
                }

                Divider()
                    .overlay(BinanceTheme.border)

                VStack(alignment: .leading, spacing: 2) {
                    Text("涨跌额")
                        .foregroundStyle(BinanceTheme.secondaryText)
                    if let change {
                        Text(formatter.change(change))
                            .foregroundStyle(candleChangeColor(change))
                    } else {
                        Text("暂无")
                            .foregroundStyle(BinanceTheme.secondaryText)
                    }

                    Text("涨跌%")
                        .foregroundStyle(BinanceTheme.secondaryText)
                    if let percent {
                        Text(formatter.percent(percent))
                            .foregroundStyle(candleChangeColor(change ?? 0))
                    } else {
                        Text("暂无")
                            .foregroundStyle(BinanceTheme.secondaryText)
                    }

                    tooltipAmountValue("额", candle.quoteVolume)
                }
            }
        }
        .font(.system(size: 9, design: .monospaced))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(BinanceTheme.tooltip.opacity(0.68), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(BinanceTheme.border, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
    }

    /// 生成悬停卡片中的 OHLC 单项数据。
    /// - Parameters:
    ///   - title: 指标名称，例如开、高、低、收。
    ///   - value: 指标对应的价格。
    /// - Returns: 带指标名称和价格的文本视图。
    private func tooltipValue(_ title: String, _ value: Decimal) -> some View {
        Text("\(title) \(formatter.price(value))")
            .foregroundStyle(BinanceTheme.primaryText)
    }

    /// 生成悬停卡片中的成交额数据，并使用万、亿等中文单位压缩显示。
    /// - Parameters:
    ///   - title: 指标名称，当前为“额”。
    ///   - value: 对应 K 线的成交额。
    /// - Returns: 带中文单位的成交额文本视图。
    private func tooltipAmountValue(_ title: String, _ value: Decimal) -> some View {
        Text("\(title) \(formatter.amount(value))")
            .foregroundStyle(BinanceTheme.primaryText)
    }

    /// 将顶部实时行情同步到趋势图，驱动最后一根未收盘 K 线实时波动。
    /// - Parameter prices: 顶部行情轮询得到的最新价格列表。
    /// - Returns: 无；没有当前合约行情时不做任何处理。
    private func syncLivePrice(from prices: [LatestPrice]) {
        guard let livePrice = prices.first(where: { $0.symbol == trendStore.selectedSymbol }) else {
            return
        }
        trendStore.updateLivePrice(
            livePrice.value,
            for: livePrice.symbol,
            at: livePrice.updatedAt
        )
    }

    /// 查找当前悬浮 K 线之前的上一根 K 线，用于逐点计算数值和百分比涨幅。
    private func previousCandle(before candle: PriceCandle) -> PriceCandle? {
        let sortedCandles = trendStore.candles.sorted { $0.openTime < $1.openTime }
        guard let index = sortedCandles.firstIndex(where: { $0.openTime == candle.openTime }),
              index > 0 else {
            return nil
        }
        return sortedCandles[index - 1]
    }

    private func candleChangeColor(_ change: Decimal) -> Color {
        change >= 0 ? BinanceTheme.up : BinanceTheme.down
    }

    @ViewBuilder
    private var emptyChartState: some View {
        if trendStore.isLoading {
            ProgressView()
                .controlSize(.small)
        } else if let errorText = trendStore.errorText {
            VStack(spacing: 8) {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button {
                    trendStore.refreshNow()
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }
        } else {
            Text("暂无趋势数据")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if !trendStore.candles.isEmpty {
                Text("\(trendStore.candles.count)根")
                    .foregroundStyle(.secondary)
            }

            if let errorText = trendStore.errorText, !trendStore.candles.isEmpty {
                Label("更新失败，显示缓存", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .help(errorText)
            } else if let updatedAt = trendStore.updatedAt {
                Text("更新 \(updatedAt.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                trendStore.refreshNow()
                Task {
                    await tickerStore.refreshNow()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("立即刷新")
        }
        .font(.system(size: 10))
        .frame(height: 18)
    }

    private var managementMenu: some View {
        Menu {
            Section("自选合约") {
                ForEach(tickerStore.selectedSymbols, id: \.self) { symbolID in
                    let symbol = menuSymbol(for: symbolID)
                    Toggle(menuTitle(for: symbol), isOn: selectionBinding(for: symbolID))
                        .disabled(tickerStore.selectedSymbols.count == 1)
                }
            }

            Section("顶部展示（\(tickerStore.menuBarSymbols.count)/\(TickerSelection.menuBarMaximumCount)）") {
                ForEach(tickerStore.selectedSymbols, id: \.self) { symbolID in
                    let symbol = menuSymbol(for: symbolID)
                    Toggle(menuTitle(for: symbol), isOn: menuBarSelectionBinding(for: symbolID))
                        .disabled(menuBarSelectionIsDisabled(symbolID))
                }
            }

            Section("常用合约") {
                ForEach(commonMenuSymbols) { symbol in
                    Toggle(menuTitle(for: symbol), isOn: selectionBinding(for: symbol.id))
                        .disabled(selectionIsDisabled(symbol.id))
                }
            }

            Divider()

            Section("刷新频率") {
                ForEach(PriceRefreshInterval.allCases) { interval in
                    Button {
                        tickerStore.updateRefreshInterval(interval)
                    } label: {
                        Label(
                            interval.title,
                            systemImage: tickerStore.refreshInterval == interval ? "checkmark" : ""
                        )
                    }
                }
            }

            Divider()

            Button {
                trendStore.refreshNow()
                Task {
                    await tickerStore.refreshNow()
                }
            } label: {
                Label("立即刷新", systemImage: "arrow.clockwise")
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("管理自选")
    }

    private var symbolBinding: Binding<String> {
        Binding(
            get: { trendStore.selectedSymbol },
            set: { trendStore.selectSymbol($0) }
        )
    }

    private var timeframeBinding: Binding<TrendTimeframe> {
        Binding(
            get: { trendStore.selectedTimeframe },
            set: { trendStore.selectTimeframe($0) }
        )
    }

    private func selectionBinding(for symbol: String) -> Binding<Bool> {
        Binding(
            get: { tickerStore.isSelected(symbol) },
            set: { isSelected in
                guard isSelected != tickerStore.isSelected(symbol) else { return }
                _ = tickerStore.toggleSymbol(symbol)
            }
        )
    }

    /// 创建顶部展示勾选项的双向绑定。
    /// - Parameter symbol: 顶部指标对应的合约 ID。
    /// - Returns: 读取当前展示状态并在用户点击时更新状态的 Binding。
    private func menuBarSelectionBinding(for symbol: String) -> Binding<Bool> {
        Binding(
            get: { tickerStore.menuBarSymbols.contains(symbol) },
            set: { isDisplayed in
                guard isDisplayed != tickerStore.menuBarSymbols.contains(symbol) else { return }
                _ = tickerStore.toggleMenuBarSymbol(symbol)
            }
        )
    }

    /// 判断顶部展示勾选项是否需要禁用。
    /// - Parameter symbol: 要判断的合约 ID。
    /// - Returns: 达到最多 8 个或只剩一个指标时返回 true。
    private func menuBarSelectionIsDisabled(_ symbol: String) -> Bool {
        if tickerStore.menuBarSymbols.contains(symbol) {
            return tickerStore.menuBarSymbols.count == 1
        }
        return tickerStore.menuBarSymbols.count >= TickerSelection.menuBarMaximumCount
    }

    private func selectionIsDisabled(_ symbol: String) -> Bool {
        if tickerStore.isSelected(symbol) {
            return tickerStore.selectedSymbols.count == 1
        }
        return tickerStore.selectedSymbols.count >= TickerSelection.maximumCount
    }

    private func addSearchResult(_ symbol: String) {
        guard !tickerStore.isSelected(symbol),
              tickerStore.selectedSymbols.count < TickerSelection.maximumCount else {
            return
        }
        _ = tickerStore.toggleSymbol(symbol)
        searchStore.query = ""
    }

    private func searchResultIsDisabled(_ symbol: String) -> Bool {
        tickerStore.isSelected(symbol) || tickerStore.selectedSymbols.count >= TickerSelection.maximumCount
    }

    private func searchResultHelp(for symbol: String) -> String {
        if tickerStore.isSelected(symbol) {
            return "已在自选"
        }
        if tickerStore.selectedSymbols.count >= TickerSelection.maximumCount {
            return "最多选择 \(TickerSelection.maximumCount) 个合约"
        }
        return "加入自选"
    }

    private func searchResultTitle(for symbol: TickerSymbol) -> String {
        if symbol.shortName == symbol.id {
            return symbol.id
        }
        return "\(symbol.shortName)  \(symbol.id)"
    }

    private var commonMenuSymbols: [TickerSymbol] {
        TickerSymbolCatalog.symbols.filter { !tickerStore.isSelected($0.id) }
    }

    private func menuSymbol(for symbolID: String) -> TickerSymbol {
        searchStore.symbol(for: symbolID) ?? TickerSymbolCatalog.symbol(for: symbolID) ?? TickerSymbol(
            id: symbolID,
            name: symbolID,
            shortName: symbolID
        )
    }

    private func menuTitle(for symbol: TickerSymbol) -> String {
        symbol.name == symbol.id ? symbol.id : "\(symbol.name)  \(symbol.id)"
    }

    private var currentSymbolName: String {
        TickerSymbolCatalog.symbol(for: trendStore.selectedSymbol)?.name ?? trendStore.selectedSymbol
    }

    private var trendColor: Color {
        guard let change = trendStore.priceChange else { return .secondary }
        return change >= 0 ? BinanceTheme.up : BinanceTheme.down
    }

    /// 读取当前拖动完成的区间测量结果，供右上角摘要显示涨跌额和涨跌百分比。
    /// - Returns: 已完成拖动时返回按时间排序的测量结果，否则返回 nil。
    private var currentMeasurement: ChartMeasurement? {
        guard let measurementStartCandle,
              let measurementEndCandle else {
            return nil
        }
        return ChartMeasurement(start: measurementStartCandle, end: measurementEndCandle)
    }

    private var chartYDomain: ClosedRange<Double> {
        let viewport = currentChartViewport
        let visibleCandles = trendStore.candles.filter {
            $0.openTime >= viewport.start && $0.openTime <= viewport.end
        }
        let sourceCandles = visibleCandles.isEmpty ? trendStore.candles : visibleCandles
        let values = sourceCandles.flatMap { candle in
            [doubleValue(candle.low), doubleValue(candle.high)]
        }
        return domainCalculator.domain(for: values)
    }

    /// 计算 K 线实体的价格范围，十字星也保留最小可见高度。
    /// - Parameter candle: 当前 K 线数据。
    /// - Returns: 由开盘价和收盘价组成的实体价格范围。
    private func candleBodyRange(for candle: PriceCandle) -> ClosedRange<Double> {
        let open = doubleValue(candle.open)
        let close = doubleValue(candle.close)
        let low = min(open, close)
        let high = max(open, close)
        guard low < high else {
            let padding = max(abs(low) * 0.0005, 0.00000001)
            return (low - padding) ... (high + padding)
        }
        return low ... high
    }

    /// 计算 K 线实体在时间轴上的宽度，按当前 K 线周期留出间隔。
    /// - Parameter candle: 当前 K 线数据。
    /// - Returns: 实体宽度对应的时间长度。
    private func candleBodyWidth(for candle: PriceCandle) -> TimeInterval {
        let interval = candle.closeTime.timeIntervalSince(candle.openTime)
        return max(interval > 0 ? interval * 0.62 : 60, 1)
    }

    private func doubleValue(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    /// 在鼠标按下时记录潜在的测量起点，但不立即显示测量结果。
    /// - Parameters:
    ///   - location: 鼠标在图表交互层中的位置。
    ///   - proxy: Swift Charts 坐标转换代理。
    ///   - geometry: 图表交互层的几何信息。
    /// - Returns: 无；仅保存按下位置对应的 K 线，等待实际拖动后生效。
    private func beginMeasurementPress(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        measurementPressCandle = candle(at: location, proxy: proxy, geometry: geometry)
    }

    /// 处理鼠标按住后的拖动；只有真正发生拖动才创建区间测量，否则保留普通悬停状态。
    /// - Parameters:
    ///   - deltaX: 本次拖动相对上一事件的横向位移。
    ///   - location: 鼠标在图表交互层中的当前位置。
    ///   - proxy: Swift Charts 坐标转换代理。
    ///   - geometry: 图表交互层的几何信息。
    /// - Returns: 无；测量模式下更新终点，普通模式下平移图表。
    private func handleChartDrag(
        deltaX: CGFloat,
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        guard let pressCandle = measurementPressCandle else {
            shiftChart(by: deltaX, width: geometry.size.width)
            return
        }

        // 测量状态下，拖到绘图区右侧留白也不能退回普通平移逻辑，避免整张图被带着向左移动。
        guard let candle = candle(at: location, proxy: proxy, geometry: geometry),
              candle.openTime != pressCandle.openTime else {
            return
        }

        measurementStartCandle = pressCandle
        measurementEndCandle = candle
        hoveredCandle = candle
        hoverLocation = location
    }

    private func updateHoveredCandle(
        at location: CGPoint?,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        guard let location else {
            hoveredCandle = nil
            hoverLocation = nil
            return
        }
        guard let candle = candle(at: location, proxy: proxy, geometry: geometry) else {
            hoveredCandle = nil
            hoverLocation = nil
            return
        }
        hoverLocation = location
        hoveredCandle = candle
    }

    /// 将图表上的一个位置转换为最近的 K 线，供悬停和区间测量共用。
    /// - Parameters:
    ///   - location: 鼠标在图表交互层中的位置。
    ///   - proxy: Swift Charts 坐标转换代理。
    ///   - geometry: 图表交互层的几何信息。
    /// - Returns: 最近的 K 线；位置不在绘图区内时返回 nil。
    private func candle(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) -> PriceCandle? {
        let plotRect = geometry[proxy.plotAreaFrame]
        guard plotRect.contains(location),
              let date: Date = proxy.value(atX: location.x - plotRect.minX) else {
            return nil
        }
        return hoverSelector.nearestCandle(to: date, in: trendStore.candles)
    }

    /// 清除当前区间测量状态。
    /// - Returns: 无；移除起点、终点和测量矩形。
    private func clearMeasurement() {
        measurementPressCandle = nil
        measurementStartCandle = nil
        measurementEndCandle = nil
    }

    private func hoverTimestamp(for date: Date) -> String {
        let duration = currentChartViewport.duration
        if duration <= 2 * 24 * 60 * 60 {
            return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
        }
        if duration <= 120 * 24 * 60 * 60 {
            return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour())
        }
        return date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
    }

    private func axisLabel(for date: Date) -> String {
        let duration = currentChartViewport.duration
        if duration <= 2 * 24 * 60 * 60 {
            return date.formatted(.dateTime.hour().minute())
        }
        if duration <= 120 * 24 * 60 * 60 {
            return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
        }
        return date.formatted(.dateTime.year().month(.twoDigits))
    }
}

/// 区间测量结果，按时间先后统一起点和终点。
private struct ChartMeasurement {
    let start: PriceCandle
    let end: PriceCandle

    /// 创建按时间先后排列的区间测量结果，便于统一计算涨跌额和涨跌百分比。
    /// - Parameters:
    ///   - start: 用户选择的第一个 K 线锚点。
    ///   - end: 用户选择的第二个 K 线锚点。
    /// - Returns: 起点时间不晚于终点时间的测量结果。
    init(start: PriceCandle, end: PriceCandle) {
        if start.openTime <= end.openTime {
            self.start = start
            self.end = end
        } else {
            self.start = end
            self.end = start
        }
    }

    var change: Decimal {
        end.close - start.close
    }

    var changePercent: Decimal {
        guard start.close != 0 else { return 0 }
        return change / start.close * 100
    }
}

private struct ChartViewport: Equatable {
    let start: Date
    let end: Date

    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }

    var center: Date {
        start.addingTimeInterval(duration / 2)
    }
}

/// Binance 夜间风格的趋势弹窗配色，统一背景、面板、文字和涨跌颜色。
private enum BinanceTheme {
    static let background = Color(red: 0.043, green: 0.051, blue: 0.063)
    static let panel = Color(red: 0.071, green: 0.082, blue: 0.102)
    static let surface = Color(red: 0.110, green: 0.125, blue: 0.153)
    static let input = Color(red: 0.094, green: 0.106, blue: 0.129)
    static let tooltip = Color(red: 0.145, green: 0.161, blue: 0.192)
    static let selected = Color(red: 0.118, green: 0.247, blue: 0.365)
    static let border = Color(red: 0.220, green: 0.247, blue: 0.290)
    static let grid = Color(red: 0.290, green: 0.325, blue: 0.380)
    static let crosshair = Color(red: 0.510, green: 0.553, blue: 0.620)
    static let primaryText = Color(red: 0.910, green: 0.925, blue: 0.950)
    static let secondaryText = Color(red: 0.580, green: 0.620, blue: 0.690)
    static let up = Color(red: 0.055, green: 0.796, blue: 0.506)
    static let down = Color(red: 0.965, green: 0.275, blue: 0.365)
}
