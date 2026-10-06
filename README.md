# SnapStack / 连截

连续截图，先收集，最后一键按顺序粘贴。

SnapStack 是一个原生 macOS 小工具，用 SwiftUI + AppKit 实现。截图暂存在悬浮栏里，整理好后点击一次“全部粘贴”，逐张送到你正在使用的应用。

## 下载与安装

**[下载最新版本](https://github.com/lumignfei/SnapStack/releases/latest)**

1. 在 Release 的 **Assets** 中下载 `SnapStack-0.1.0-macOS-universal.zip`。`Source code` 是源码压缩包，不是安装包。
2. 解压，将 `SnapStack.app` 放进“应用程序”文件夹，然后双击打开。
3. 首次截图时，在“系统设置 → 隐私与安全性 → 屏幕录制”（部分系统显示为“录屏与系统录音”）允许 SnapStack。
4. 首次粘贴时，允许“辅助功能”权限（部分系统显示为“设备控制和数据访问”）。按系统提示退出并重新打开应用。

要求 **macOS 13.5 或更新版本**。下载包包含 Apple Silicon（M 系列）和 Intel 两种架构；实际运行验证使用 Apple Silicon Mac，Intel 与 macOS 13.5 尚未实机验证。

当前版本采用 ad-hoc 签名，**尚未进行 Apple Developer ID 签名和公证**。首次打开可能被 Gatekeeper 阻止；仅当你信任本项目时，在“系统设置 → 隐私与安全性”查看此次拦截并选择“仍要打开”，详见 [Apple 官方说明](https://support.apple.com/en-us/102445)。不需要关闭系统安全保护。

## 使用

1. **先打开 SnapStack**，然后按 **⌃⌥⌘S**（Control + Option + Command + S），拖选截图区域；重复操作可连续收集多张。
2. 悬浮栏横向显示缩略图。点击右上角叉号删除单张；从图片中部拖到另一张图的位置调整顺序。
3. 点击目标应用中需要粘贴的位置，确认悬浮栏底部“目标”显示正确应用。
4. 点击一次 **全部粘贴**。每张图片依次写入系统剪贴板、激活固定目标并发送 Command-V；每张发送后等待 **400ms**。
5. 粘贴后队列保留，可再次粘贴；点击 **清空** 删除当前队列。

左侧“连截”标题可以拖动悬浮栏。菜单栏文字“连截”提供截图、显示截图栏和退出；悬浮栏右上角也有“退出”。当前版本启动后会显示悬浮栏，清空后仍然显示。

快捷键只在应用运行时有效，**不能用它启动已退出的应用**。可将应用固定到 Dock 方便启动；目前不包含开机自启。

## 权限与数据

- 屏幕录制：读取你拖选的屏幕区域。
- 辅助功能：仅在点击“全部粘贴”后，向目标应用发送 Command-V。
- 原图 PNG 保存于系统临时目录，缩略图留在内存中。队列只用于当前运行会话；删除、清空和正常退出会移除对应临时原图。强制终止或崩溃可能留下临时文件。
- 应用没有联网、上传、登录、云同步和历史记录功能。正常退出后的队列不会恢复。
- 粘贴会覆盖系统剪贴板，完成后保留最后一张图片。

## 当前版本与限制

首个预览版本已实际验证：区域截图、连续收集、悬浮缩略图、单张删除、拖动排序、一次点击逐张粘贴，以及清空队列。接收应用使用本地“文本编辑”RTFD 文档，实测确认了排序后的图片接收顺序。

飞书等其他应用尚未专项验证。固定 400ms 等待不能确认接收应用已经处理完毕；网络上传、应用弹窗和焦点变化可能影响结果。请等待粘贴完成后再操作目标应用，留意实际收到的图片数量。本工具不会自动按 Enter 发送聊天消息。

文本编辑首次接收图片时，可能要求将 RTF 文档转换成 RTFD。快捷键冲突时可使用悬浮栏“截图”按钮。多屏、Space、全屏专项适配不在本版范围内。

升级或重新构建后，ad-hoc 签名可能改变，旧授权记录可能失效。若权限开关已开但功能仍不可用，请退出应用，在对应权限列表移除 SnapStack，再添加当前安装的版本，并按系统提示重新打开。

## 从源码构建

需要 macOS 和 Swift 6.0 或更新版本（Xcode 或 Command Line Tools）。本机已使用 Swift 6.4 构建，无第三方包依赖。

```sh
git clone https://github.com/lumignfei/SnapStack.git
cd SnapStack
bash scripts/build-app.sh
open dist/SnapStack.app
```

`build-app.sh [debug|release]` 编译本机架构，生成标准 `.app` Bundle、检查 Info.plist 并进行 ad-hoc 签名。固定 Bundle Identifier 为 `com.yangyaoming.snapstack`。

生成用于分发的 Universal 下载包和 SHA-256 校验文件：

```sh
bash scripts/package-release.sh
```

输出到 `dist/release/`，不替换本机开发用的 `dist/SnapStack.app`。构建产物、临时验证材料均不提交到源码仓库。

## 源码结构

| 文件 | 职责 |
| --- | --- |
| `App.swift` | 应用生命周期、菜单栏和模块连接 |
| `CaptureHotKey.swift` | Carbon 全局快捷键 |
| `CaptureState.swift` | 系统区域截图、临时 PNG、缩略图、队列和粘贴流程 |
| `PasteManager.swift` | 目标应用、辅助功能权限、剪贴板和 Command-V |
| `FloatingBar.swift` | NSPanel、SwiftUI 悬浮栏、删除与 AppKit 拖动排序 |
| `Resources/Info.plist` | 应用元数据与权限用途说明 |
| `scripts/build-app.sh` | 本机编译与 Bundle 打包 |
| `scripts/package-release.sh` | 双架构构建、Universal 合并、签名和 ZIP 打包 |

## 反馈与许可

遇到问题可在 [Issues](https://github.com/lumignfei/SnapStack/issues) 提供 macOS 版本、Mac 芯片类型、目标应用和复现步骤。请不要上传包含隐私信息的截图。

MIT License，见 [LICENSE](LICENSE)。系统调用思路参考 [yarasaa/Clippy](https://github.com/yarasaa/Clippy)，本项目独立实现，未复制其源码。
