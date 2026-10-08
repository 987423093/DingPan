# SKHynixMenuBar

一个运行在 macOS 菜单栏中的行情小工具，支持自选合约、实时价格刷新和 K 线趋势图。

## 环境要求

- macOS 13.0 或更高版本
- Xcode 15+（Swift 6）
- 可访问行情数据接口的网络环境

## 直接运行已构建版本

仓库中的 `ReleaseApp/SKHynixMenuBar.app` 是一个可直接运行的 macOS 应用：

```bash
open ReleaseApp/SKHynixMenuBar.app
```

如果 macOS 阻止首次打开，可以在 Finder 中右键应用，选择“打开”。

## 从源码构建

### 使用 XcodeGen 生成工程

如果本地安装了 XcodeGen：

```bash
xcodegen generate
```

### 构建并运行

```bash
xcodebuild build \
  -project SKHynixMenuBar.xcodeproj \
  -scheme SKHynixMenuBar \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath .releasebuild

open .releasebuild/Build/Products/Release/SKHynixMenuBar.app
```

### 运行测试

```bash
xcodebuild test \
  -project SKHynixMenuBar.xcodeproj \
  -scheme SKHynixMenuBar \
  -destination 'platform=macOS' \
  -derivedDataPath .testbuild
```

## 使用说明

应用启动后会显示在 macOS 菜单栏附近：

- 点击行情条可展开趋势图和自选合约管理。
- 行情条整体可以拖动到桌面任意位置，位置会自动保存。
- 在管理菜单中选择自选合约，以及需要展示在顶部的指标，最多展示 8 个。
- 支持 1 秒刷新频率，以及 15 分钟、1 小时、4 小时、1 天等 K 线周期。

### 全局快捷键

快捷键不要求当前应用处于前台：

- `⌘G`：隐藏/显示顶部行情条。
- `⌘T`：展开/收起趋势图。

### 趋势图交互

- 鼠标移动到 K 线上，会显示开、高、低、收、成交额、逐根涨跌额和涨跌百分比，并显示横向/纵向十字线。
- 按住鼠标在图表中拖动，可框选一个时间区间，右上角显示区间涨跌额和涨跌百分比。
- 框选完成后，单击图表任意位置可以取消框选。
- 触控板双指左右滑动可以浏览历史时间；双指捏合可以放大或缩小时间范围。
- 最近一根未收盘 K 线会随实时行情更新。

## 项目结构

```text
Sources/
  Core/       基础模型与格式化
  Feature/    菜单栏、趋势图和交互逻辑
  Infra/      行情接口、偏好设置和持久化
Tests/        单元测试
```

## 说明

- 应用是菜单栏常驻程序，不会在 Dock 中显示普通窗口图标。
- 行情数据依赖运行时网络请求；网络不可用时会显示缓存或错误状态。
- 当前发布版本为本地构建版本，未配置 Apple Developer Team 签名。
