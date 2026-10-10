<p align="center"><img src="Resources/AppIcon-source.png" width="120" alt="SnapStack 连截图标"></p>

# SnapStack / 连截 · macOS 连续截图与批量粘贴

**macOS 连续截图工具：先收集、调整顺序，再一键粘贴。每张图片可选填文字备注，也可直接添加图片标记。**

A native macOS screenshot queue built with SwiftUI and AppKit. Capture multiple regions, reorder screenshots, add optional per-image notes and image markup, and paste them into another app in sequence. No account or cloud service required.

[简体中文](README.md) · [English](README.en.md)

## 版本与下载

当前源码版本：**0.2.0**。此轮更新源码，**尚未发布 0.2.0 安装包**。

[已有安装包与历史版本](https://github.com/lumignfei/SnapStack/releases) · [0.2.0 更新说明](docs/releases/v0.2.0.md) · [问题反馈](https://github.com/lumignfei/SnapStack/issues)

已发布的 v0.1.2 是旧版，不包含本页介绍的新界面与备注功能，快捷键也不同。体验当前版本请从源码构建。

## 能做什么

- 连续截取多个屏幕区域，暂存在悬浮栏中。
- 打开图片面板，拖动排序、删除图片；无需备注的图片保持原样。
- 点击缩略图放大查看，给指定图片添加备注；备注跟随图片排序，作为独立文字粘贴。
- 在图片上添加矩形、圆圈、箭头、画笔、文字和马赛克；支持颜色、粗细、撤销和重做。原图在当前会话内保留，粘贴使用标记后的图片。
- 通过按钮或快捷键逐张粘贴图片和备注；不自动按 Enter 发送消息。
- 紧凑长条可收起为悬浮按钮；提供权限引导和悬停反馈。

适合收集多个页面中的问题截图、给界面反馈配说明，以及向支持图片粘贴的应用整理材料。它不提供录屏、OCR 或长期剪贴板历史功能。

## 使用场景

| 你要整理的内容 | 使用方式 |
| --- | --- |
| 软件问题反馈 | 连截几个复现画面，给其中一张补充“点击保存后没有反应” |
| 界面参考 | 收集不同页面的按钮或布局，排序后给需要解释的图片加备注 |
| 多图说明材料 | 先收集完整图片，再一次按顺序粘贴到支持图片的输入框 |

## 使用

| 操作 | 方式 |
| --- | --- |
| 区域截图 | **Control + Shift + A**，或点击“截图” |
| 粘贴全部 | **Control + Shift + S**，或点击“粘贴” |
| 调整顺序 | 点击图片区打开面板，拖动缩略图 |
| 放大与备注 | 点击缩略图打开大图，按需写备注，Return 完成返回托盘 |
| 图片标记 | 在大图右侧选择工具，再在图片上点击或拖动；文字工具点击图片后输入文字 |
| 备注换行 | Shift + Return；中文输入法选字时 Return 不会误收起 |
| 清空或收起 | 长条右侧“更多操作” |

1. 启动连截，连续拖选需要的截图区域。
2. 按需排序、标记和添加备注。备注框随内容增高，到上限后内部滚动；空备注不会输出文字。
3. 点击目标应用的输入位置；悬停“粘贴”按钮可确认目标。
4. 粘贴后检查接收内容。队列会保留，便于再次使用或手动清空。

每张图之后，仅在有备注时粘贴“图片 N：备注”；编号按当前排序生成。目标应用可能把图片显示为附件，并将文字另行排列，不能保证所有应用都显示为图片旁边的文字。

快捷键仅在应用运行时生效；目前没有开机自启。长条和悬浮按钮支持拖动，位置只保留在本次运行中。

## 安装与权限

要求 **macOS 13.5+**。源码构建需要 **Swift 6 / Xcode 或 Command Line Tools**，无第三方 Swift 包依赖。

```sh
git clone https://github.com/lumignfei/SnapStack.git
cd SnapStack
bash scripts/setup-local-signing.sh
bash scripts/build-app.sh release
open dist/SnapStack.app
```

- **屏幕录制**：截取你选中的屏幕区域。授权后可先开始截图。
- **辅助功能**：向你选择的目标应用模拟 Command-V，用于自动粘贴。

首次使用按权限引导打开对应系统设置，授权后返回应用；部分系统要求退出并重开。可通过“更多操作 → 权限与使用引导”再次查看。

历史下载版采用 **ad-hoc 临时签名，尚未进行 Developer ID 签名和公证**。下载版本可能触发 Gatekeeper；只在信任来源时按系统提示允许打开，不需要关闭系统安全保护。参见 [Apple 说明](https://support.apple.com/en-us/102445)。

### 已开启权限，为什么仍提示授权？

升级或重新构建可能改变签名，使旧授权记录失效。退出连截，在对应权限列表移除旧记录，再添加当前安装的 `SnapStack.app`，并按系统提示重新打开。避免同时运行不同位置的旧版本。

本机构建现在要求固定签名身份。首次执行 `scripts/setup-local-signing.sh`，私钥保存在登录钥匙串，配置在 `~/Library/Application Support/SnapStack/Signing/`；后续更新保留该身份。不会修改全局信任，首次签名可能需钥匙串确认。切换身份后需重新授权，本机已验证连续两次代码更新后屏幕录制与辅助功能授权保留；其他设备仍需验证。可用 `SNAPSTACK_SIGNING_IDENTITY` 指定已有证书，仅临时测试可显式设置为 `-`。本机自签名不是 Developer ID 签名或公证。

## 隐私与数据

- 无联网、上传、账号、云同步或历史记录功能。
- 原图 PNG 存在系统临时目录，缩略图、标记、撤销历史和备注用于当前运行会话；标记不会覆盖原图。
- 删除、清空和正常退出会删除对应临时原图；退出后队列及备注不会恢复。崩溃或强制退出可能留下临时文件。
- 粘贴会覆盖系统剪贴板，最后保留本次最后写入的图片或备注文字。
- 内容只通过粘贴交给选定应用；之后的数据处理取决于该接收应用。

## 验证范围与限制

当前版本已通过 release 构建、备注绑定与重排测试、原生独立剪贴板图文接收测试、快捷键注册测试和 7 项权限启动策略检查。已检查正式应用权限引导、收起展开及退出重开。图片标记导出、撤销重做、原图保留、排序绑定和长备注原生布局检查已通过。详见 [本次检查记录](docs/markup-checks.md)。

**尚未完成当前版本在 ChatGPT、微信等应用中的完整“真实截图 → 入队 → 图文批量粘贴”专项验收。** 原生剪贴板测试不代表这些应用的兼容性已验证。

粘贴使用固定等待，无法确认接收应用已完成上传或处理；弹窗、焦点变化或处理缓慢可能影响结果。请等待粘贴结束再操作，并核对实际图片数量。Intel、macOS 13.5、多屏、Space 和全屏场景尚未专项实机验证；动画未进行帧率测量。

## 开发与打包

```sh
bash scripts/test-permission-launch.sh
bash scripts/test-notes.sh
# 需在桌面会话中退出连截后运行，避免占用同一组快捷键：
bash scripts/test-hotkeys.sh
# 构建 Apple Silicon + Intel 通用安装包，不替换本机 dist/SnapStack.app：
bash scripts/package-release.sh
```

构建产物位于 `.build/` 和 `dist/`，不提交到源码仓库。`Resources/AppIcon-source.png` 是图标源图，`AppIcon.icns` 是正式图标资源。`docs/` 中早期设计与检查文档属于历史记录，以本页和当前版本说明为准。

## FAQ

**和普通截图有什么不同？** 连截主要增加当前会话的多图队列、拖动排序、可选备注和一次触发的顺序粘贴，不必每截一张就切换到目标应用。

**支持 Windows 吗？** 当前仅支持 macOS，没有 Windows 或 Linux 版本。

**是免费开源的吗？** 源码采用 MIT 许可，可以按许可条款使用和修改；无需账号或订阅。

**支持 ChatGPT、微信吗？** 连截通过系统剪贴板和 Command-V 粘贴；这些应用当前版本的完整图文流程尚未专项验收，图片和文字的排列由接收应用决定。


**可以只给一张图写备注吗？** 可以，备注是可选的；重排后仍属于原图。

**会把备注画进图片吗？** 不会，原图和文字分别粘贴。

**会自动发送聊天消息吗？** 不会，只模拟粘贴，不模拟 Enter。

**退出后还能恢复截图吗？** 不能，目前仅保留当前会话。

## 反馈与许可

在 [Issues](https://github.com/lumignfei/SnapStack/issues) 提供系统版本、芯片类型、目标应用和复现步骤；请勿上传私人截图。

[MIT License](LICENSE)。系统调用思路参考 [Clippy](https://github.com/yarasaa/Clippy)，界面交互参考 [DogSC](https://github.com/laogou717/dogsc)；本项目独立实现。图标由 AI 辅助生成，采用蓝灰叠片与截图取景角标。
