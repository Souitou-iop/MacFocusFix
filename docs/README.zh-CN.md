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
  <a href="https://github.com/Souitou-iop/macOS-Windows-FIX/releases">下载</a> ·
  <a href="https://github.com/Souitou-iop/macOS-Windows-FIX/actions/workflows/release.yml">构建</a> ·
  <a href="https://github.com/Souitou-iop/macOS-Windows-FIX/issues">反馈</a>
</p>

## 为什么需要它

有些远程控制工具能把鼠标点击送到正确的 macOS 窗口，但不会把那个 App 变成真正的前台 App。结果就是：鼠标点到了输入框，但键盘输入仍然进了上一个 App。

MacFocusFix 会监听鼠标点击，找到指针下方的 App，并主动激活它，让键盘输入跟随点击目标。

## 功能

- 只驻留菜单栏，不显示 Dock 图标。
- 可以从菜单栏开启或关闭焦点修复。
- 提供“激活后二次点击”兜底模式。
- 会忽略 macOS 顶部菜单栏和已知系统 UI 进程，因此不会干扰控制中心、Wi-Fi、输入法等系统控件。
- App 图标来自 Icon Composer 导出资源，菜单栏图标使用单独的模板风格图标。

## 安装

1. 到 [Releases](https://github.com/Souitou-iop/macOS-Windows-FIX/releases) 下载最新 zip。
2. 解压。
3. 把 `MacFocusFix.app` 拖到 `/Applications`。
4. 启动应用。
5. 如果 macOS 提示权限，在系统设置里允许“辅助功能”。

如果 macOS 因为未 notarize 而阻止打开，请在 Finder 里按住 Control 点按应用，选择“打开”，然后确认。当前构建使用 ad hoc 签名，不是 Developer ID notarization。

## 菜单栏

- 状态：显示已开启、已关闭或等待辅助功能授权。
- 开启 / 关闭焦点修复：安装或移除鼠标事件监听。
- 激活后二次点击：给“已激活但仍不能输入”的 App 做兜底。
- 打开辅助功能设置
- 退出 MacFocusFix

## 本地构建

```zsh
./script/build_app.sh
./script/build_and_run.sh
```

`build_app.sh` 会生成 `dist/MacFocusFix.app`，并使用 ad hoc 签名。
`build_and_run.sh` 会构建并打开应用。

## 发布

GitHub Actions 会在 macOS runner 上构建发布产物。推送 `v0.1.0` 这类标签时，会生成 zip 格式的 `.app` 包并发布到 GitHub Release。

## 卸载

退出 MacFocusFix，然后把 `MacFocusFix.app` 移到废纸篓。如果之前授予过辅助功能权限，也可以在系统设置里移除它。

## 兼容性

MacFocusFix 使用 SwiftPM 构建，目标系统为 macOS 14 或更新版本。
