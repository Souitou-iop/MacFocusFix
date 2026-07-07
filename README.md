<p align="center">
  <img src="macOS-Windows-FIX%20Exports/macOS-Windows-FIX.icon/Assets/icon%E5%BE%85%E5%AE%9A.png" width="160" alt="MacFocusFix icon">
</p>

<h1 align="center">MacFocusFix</h1>

<p align="center">
  A lightweight macOS menu bar app that keeps remote-control clicks from leaving keyboard focus behind.
</p>

<p align="center">
  <strong>English</strong> | <a href="docs/README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/Souitou-iop/MacFocusFix/releases">Download</a> ·
  <a href="https://github.com/Souitou-iop/MacFocusFix/actions/workflows/release.yml">Builds</a> ·
  <a href="https://github.com/Souitou-iop/MacFocusFix/issues">Feedback</a>
</p>

## Demo

**Before — focus stays on the old app**

https://github.com/user-attachments/assets/7d204367-d2a1-47b9-989d-c1f29b16fc22

**After — focus follows the click**

https://github.com/user-attachments/assets/f0de3a6b-1230-42c9-a297-02f72a61b3ed

## Why I Built This

After updating to macOS 27, I started seeing a strange remote-control focus bug with tools such as UU Remote. A remote click could still reach the right window control, so buttons and fields looked like they were being clicked. But macOS did not always switch the real foreground app: the app name next to the Apple menu stayed on the previous app, and keyboard input kept going there.

The clearest workaround was to click the target window's title bar first. That forced macOS to activate the window, but it broke the natural remote-control flow: every time I wanted to type into another app, I had to remember to click the frame instead of the content.

The first round of debugging pointed away from a normal app setting issue. Accessibility permissions, UI restarts, and remote-control settings were useful things to check, but the symptom looked deeper: the mouse event arrived, while the WindowServer / Accessibility foreground-app activation step did not. Apple's own remote-control stack also appeared to be changing around newer macOS input and Accessibility behavior, which made this feel like a third-party remote-input compatibility gap rather than a single text-field bug.

MacFocusFix is the small local workaround that came out of that investigation. It does not replace the remote-control app. It simply runs on the Mac being controlled, listens for mouse clicks, finds the app under the pointer, and explicitly activates it so keyboard focus follows the click again.

## Features

- Menu bar only: no Dock icon.
- Enable or disable the focus fix from the menu bar.
- Always On by default, with an optional Remote Apps Only mode for common remote-control tools such as UU Remote, ToDesk, Sunlogin, RustDesk, AnyDesk, and Chrome Remote Desktop.
- Handles left-click activation only, so right-click menus and middle-click actions are left alone.
- Optional Launch at Login toggle from the menu bar.
- Ignores the macOS menu bar and known system UI processes, so Control Center, Wi-Fi, input method controls, Notification Center, Spotlight, Siri, and Screenshot keep working normally.
- Uses the bundled app icon from the Icon Composer export and a separate template-style menu bar icon.

## Installation

1. Download the latest zip from [Releases](https://github.com/Souitou-iop/MacFocusFix/releases).
2. Unzip it.
3. Move `MacFocusFix.app` to `/Applications`.
4. Launch the app.
5. Grant Accessibility permission in System Settings when macOS asks for it.

Official tagged releases are currently built with ad hoc signing. If you build the app locally, the local build also uses ad hoc signing unless you provide your own signing identity.

## Menu Bar

- Status: shows whether the helper is on, off, or waiting for Accessibility permission.
- Enable / Disable Focus Fix: installs or removes the mouse event listener.
- Mode: switches between Always On and Remote Apps Only.
- Language: switches between System, English, and Simplified Chinese. Use the Restart prompt after changing this setting.
- Open Accessibility Settings
- Launch at Login
- Open GitHub
- Version: useful when reporting bugs.
- Quit MacFocusFix

## Build Locally

```zsh
./script/build_app.sh
./script/build_and_run.sh
```

`build_app.sh` creates `dist/MacFocusFix.app` and signs it ad hoc for local use.
`build_and_run.sh` builds the app and opens it.

## Troubleshooting

- If macOS says the app cannot be opened, open System Settings > Privacy & Security and choose Open Anyway for MacFocusFix. This can happen because current public releases are ad hoc signed.
- If you cannot find the app after launching it, look for the MacFocusFix icon in the menu bar. The app intentionally has no Dock icon.
- If the focus fix does not work, open the menu bar item and choose Open Accessibility Settings, then make sure MacFocusFix is enabled under Accessibility. Quit and relaunch the app after changing permission.
- If the app opens in the wrong language, use the menu bar Language items to choose English or Simplified Chinese, then restart MacFocusFix.
- If an update asks for Accessibility permission again, it is usually because ad hoc signing does not provide a stable Developer ID identity. A Developer ID signed and notarized build is needed to make updates smoother.
- Public releases provide an `arm64` download for Apple Silicon Macs. Intel Macs can build from source if needed, but release assets are no longer produced for `x86_64`.

## Troubleshooting Logs

For click compatibility bugs, run MacFocusFix with click diagnostics enabled:

```zsh
./script/build_and_run.sh --debug-clicks
```

Then reproduce the bad click once. The log includes the clicked app, bundle identifier, process id, Accessibility role/subrole/title/description, window title, current mode, and whether MacFocusFix skipped or activated the target.

## Releases

GitHub Actions builds release artifacts on macOS. Pushing a tag such as `v0.1.0` publishes a zipped `.app` bundle as a GitHub Release asset. When Developer ID signing secrets are available, the workflow can sign and notarize the app; otherwise it falls back to ad hoc signing.

This matters for Accessibility permission. macOS tracks trusted apps by code identity, not just by app name. Ad hoc builds can look like a different app after every rebuild, which may require granting Accessibility permission again. A stable Developer ID signature keeps the identity consistent across updates.

Release and CI workflows pin third-party GitHub Actions to commit SHAs instead of floating major-version tags. This keeps the build pipeline from changing unexpectedly when an upstream action tag moves or receives new code.

The release workflow expects these repository secrets:

- `DEVELOPER_ID_CERTIFICATE_BASE64`: base64-encoded `.p12` Developer ID Application certificate.
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`: password for the `.p12` file.
- `DEVELOPER_ID_SIGNING_IDENTITY`: full signing identity, for example `Developer ID Application: Name (TEAMID)`.
- `APPLE_ID`: Apple ID used for notarization.
- `APPLE_TEAM_ID`: Apple Developer Team ID.
- `APPLE_APP_PASSWORD`: app-specific password for notarization.

Local development can still use:

```zsh
./script/build_app.sh
```

To test with a local signing identity:

```zsh
SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ./script/build_app.sh
```

## Uninstall

Quit MacFocusFix, then move `MacFocusFix.app` to the Trash. If you granted Accessibility permission, you can also remove it from System Settings.

## Compatibility

MacFocusFix is built with SwiftPM and targets macOS 14 or later. Public releases are built for Apple Silicon (`arm64`).
