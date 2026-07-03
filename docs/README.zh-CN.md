<p align="center">
  <img src="../macOS-Windows-FIX%20Exports/macOS-Windows-FIX.icon/Assets/icon%E5%BE%85%E5%AE%9A.png" width="160" alt="MacFocusFix 图标">
</p>

<h1 align="center">MacFocusFix</h1>

<p align="center">
  一个轻量 macOS 菜单栏工具，用来修复远程点击后键盘焦点仍留在旧 App 的问题。
</p>

<p align="center">
  <a href="../README.md">English</a> | <strong>简体中文</strong>
</p>

<p align="center">
  <a href="https://github.com/Souitou-iop/MacFocusFix/releases">下载</a> ·
  <a href="https://github.com/Souitou-iop/MacFocusFix/actions/workflows/release.yml">构建</a> ·
  <a href="https://github.com/Souitou-iop/MacFocusFix/issues">反馈</a>
</p>

## 为什么写这个软件

升级到 macOS 27 之后，我在使用 UU 远程这类远程控制工具时遇到了一个很奇怪的焦点问题：远程鼠标点击确实能到达目标窗口，按钮会响应，输入框也像是被点到了；但 macOS 没有把这个窗口所属的 App 变成真正的前台 App。Apple 菜单右侧显示的 App 名称仍然停在旧 App，后续键盘输入也继续进入旧 App。

当时最稳定的手动 workaround 是先点目标窗口的标题栏。标题栏点击能触发真正的窗口激活，但这会打断正常远控体验：每次想在另一个 App 里打字，都要先记得点窗口边框，而不是直接点内容区域。

前期排查后，这个问题不像普通应用设置能解决。辅助功能权限、重启 UI 组件、远控设置都值得检查，但症状更像是系统层的输入路由变化：鼠标事件到了，WindowServer / Accessibility 负责切换真正前台 App 的那一步没有发生。Apple 自家的远控链路也在新系统上围绕输入和辅助功能做过适配，这进一步说明第三方远控可能需要跟进新的事件注入行为。

MacFocusFix 就是这次排查后做出来的一个小型本机补偿器。它不替代远控软件，而是运行在被控制的 Mac 上，监听鼠标点击，找到指针下方窗口所属的 App，并显式激活它，让键盘焦点重新跟随鼠标点击。

## 功能

- 只驻留菜单栏，不显示 Dock 图标。
- 可以从菜单栏开启或关闭焦点修复。
- 默认始终生效，也可以切换到“仅远控软件运行时”模式，识别 UU 远程、ToDesk、向日葵、RustDesk、AnyDesk、Chrome Remote Desktop 等常见远控工具。
- 默认只处理左键激活，避免干扰右键菜单和中键操作。
- 可以从菜单栏开启或关闭开机启动。
- 会忽略 macOS 顶部菜单栏和已知系统 UI 进程，因此不会干扰控制中心、Wi-Fi、输入法、通知中心、Spotlight、Siri、截图工具等系统控件。
- App 图标来自 Icon Composer 导出资源，菜单栏图标使用单独的模板风格图标。

## 安装

1. 到 [Releases](https://github.com/Souitou-iop/MacFocusFix/releases) 下载最新 zip。
2. 解压。
3. 把 `MacFocusFix.app` 拖到 `/Applications`。
4. 启动应用。
5. 如果 macOS 提示权限，在系统设置里允许“辅助功能”。

官方 tag release 目前默认使用 ad hoc 签名。如果你在本地自己构建，默认也会使用 ad hoc 签名，除非手动提供自己的签名身份。

## 菜单栏

- 状态：显示已开启、已关闭或等待辅助功能授权。
- 开启 / 关闭焦点修复：安装或移除鼠标事件监听。
- 模式：在“始终生效”和“仅远控软件运行时”之间切换。
- 语言：可以在“跟随系统”、English、简体中文之间切换。切换后需要重启 MacFocusFix 生效。
- 打开辅助功能设置
- 开机启动
- 打开 GitHub
- 版本号：反馈问题时可以直接提供。
- 退出 MacFocusFix

## 本地构建

```zsh
./script/build_app.sh
./script/build_and_run.sh
```

`build_app.sh` 会生成 `dist/MacFocusFix.app`，并使用 ad hoc 签名。
`build_and_run.sh` 会构建并打开应用。

## 故障排查

- 如果 macOS 提示无法打开 App，请到“系统设置 > 隐私与安全性”里选择仍要打开 MacFocusFix。当前公开 release 使用 ad hoc 签名，可能触发这个提示。
- 如果启动后找不到 App，请看菜单栏里的 MacFocusFix 图标。这个 App 有意不显示 Dock 图标。
- 如果焦点修复没有生效，点击菜单栏图标并选择“打开辅助功能设置”，确认 MacFocusFix 已在辅助功能里启用。改完权限后建议退出并重新启动 App。
- 如果 App 打开后语言不对，可以在菜单栏的语言选项里选择 English 或简体中文，然后重启 MacFocusFix。
- 如果更新后又要求辅助功能权限，通常是因为 ad hoc 签名没有稳定的 Developer ID 身份。要让更新体验更顺滑，需要 Developer ID 签名和 Apple 公证。
- Apple Silicon Mac 下载 `arm64`，Intel Mac 下载 `x86_64`。release 故意按架构拆分，避免安装包变大。

## 排查日志

如果遇到某个按钮或窗口点击兼容问题，可以开启点击诊断日志：

```zsh
./script/build_and_run.sh --debug-clicks
```

然后复现一次异常点击。日志会包含被点击 App、bundle identifier、进程 id、辅助功能 role/subrole/title/description、窗口标题、当前模式，以及 MacFocusFix 是跳过还是激活目标。

## 发布

GitHub Actions 会在 macOS runner 上构建发布产物。推送 `v0.1.0` 这类标签时，会发布 zip 格式的 `.app` 包到 GitHub Release；如果仓库里配置了 Developer ID 签名相关 secrets，workflow 也可以走正式签名和 notarization，否则会回退到 ad hoc 签名。

这对辅助功能权限很重要。macOS 信任一个 App 时看的不只是 App 名称，还包括代码签名身份。ad hoc 构建每次重建后都可能被系统当成新的 App，因此可能需要重新授予辅助功能权限。稳定的 Developer ID 签名可以让后续更新保持同一个代码身份。

Release 和 CI workflow 会把第三方 GitHub Actions 固定到具体 commit SHA，而不是浮动的大版本标签。这样可以避免上游 action tag 移动或更新代码后，让构建流程在没有明确变更的情况下发生变化。

发布 workflow 需要配置这些仓库 secrets：

- `DEVELOPER_ID_CERTIFICATE_BASE64`：base64 编码后的 `.p12` Developer ID Application 证书。
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`：`.p12` 文件密码。
- `DEVELOPER_ID_SIGNING_IDENTITY`：完整签名身份，例如 `Developer ID Application: Name (TEAMID)`。
- `APPLE_ID`：用于 notarization 的 Apple ID。
- `APPLE_TEAM_ID`：Apple Developer Team ID。
- `APPLE_APP_PASSWORD`：用于 notarization 的 App 专用密码。

本地开发仍然可以直接运行：

```zsh
./script/build_app.sh
```

如果要在本地测试正式签名：

```zsh
SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ./script/build_app.sh
```

## 卸载

退出 MacFocusFix，然后把 `MacFocusFix.app` 移到废纸篓。如果之前授予过辅助功能权限，也可以在系统设置里移除它。

## 兼容性

MacFocusFix 使用 SwiftPM 构建，目标系统为 macOS 14 或更新版本。Release 会分别提供 Apple Silicon（`arm64`）和 Intel Mac（`x86_64`）下载包。
