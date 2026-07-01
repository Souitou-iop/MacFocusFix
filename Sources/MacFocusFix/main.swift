import AppKit
import ApplicationServices
import Foundation
import os
import ServiceManagement

private let bundleID = "win.ebato.MacFocusFix"
private let logger = Logger(subsystem: bundleID, category: "focus")
private let ignoredSystemUIBundleIdentifiers: Set<String> = [
    "com.apple.systemuiserver",
    "com.apple.controlcenter",
    "com.apple.dock",
    "com.apple.TextInputMenuAgent",
    "com.apple.notificationcenterui",
    "com.apple.Spotlight",
    "com.apple.Siri",
    "com.apple.siri.launcher",
    "com.apple.screenshot.launcher"
]
private let userDefaultsModeKey = "focusMode"
private let userDefaultsWelcomeKey = "hasShownWelcome"
private let projectURL = URL(string: "https://github.com/Souitou-iop/macOS-Windows-FIX")!

private enum FocusMode: String {
    case alwaysOn
    case remoteAppsOnly

    var title: String {
        switch self {
        case .alwaysOn:
            return L10n.tr("mode.alwaysOn")
        case .remoteAppsOnly:
            return L10n.tr("mode.remoteAppsOnly")
        }
    }

    static func stored() -> FocusMode {
        guard let rawValue = UserDefaults.standard.string(forKey: userDefaultsModeKey),
              let mode = FocusMode(rawValue: rawValue) else {
            return .alwaysOn
        }
        return mode
    }

    func store() {
        UserDefaults.standard.set(rawValue, forKey: userDefaultsModeKey)
    }
}

private enum AppResources {
    private static let bundleName = "MacFocusFix_MacFocusFix.bundle"

    static let bundle: Bundle = {
        let candidates = resourceBundleCandidates()

        for candidate in candidates {
            let bundleURL = candidate.appendingPathComponent(bundleName)
            if let bundle = Bundle(url: bundleURL) {
                return bundle
            }
        }

        return .main
    }()

    private static func resourceBundleCandidates() -> [URL] {
        var candidates: [URL] = []

        if let override = ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_PATH"]
            ?? ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_URL"] {
            candidates.append(URL(fileURLWithPath: override))
        }

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL)
        }

        if let executableURL = Bundle.main.executableURL {
            let contentsURL = executableURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            candidates.append(contentsURL.appendingPathComponent("Resources"))
        }

        candidates.append(Bundle.main.bundleURL)
        return candidates
    }
}

private enum L10n {
    private static let bundle: Bundle = {
        let localization = preferredLocalization()

        guard let path = AppResources.bundle.path(forResource: localization, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return AppResources.bundle
        }

        return bundle
    }()

    private static func preferredLocalization() -> String {
        for language in preferredLanguages() {
            let normalized = language.lowercased()
            if normalized.hasPrefix("en") {
                return "en"
            }
            if normalized.hasPrefix("zh") {
                return "zh-Hans"
            }
        }

        return "en"
    }

    private static func preferredLanguages() -> [String] {
        if let rawLanguages = ProcessInfo.processInfo.environment["AppleLanguages"] {
            let languages = rawLanguages
                .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'"))) }
                .filter { !$0.isEmpty }

            if !languages.isEmpty {
                return languages
            }
        }

        return (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String]) ?? Locale.preferredLanguages
    }

    static func tr(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, value: key, comment: "")
    }
}

private struct Options {
    var focusMode = FocusMode.stored()
    var activationDelay: TimeInterval = 0.06
    var debugClicks = false
}

private enum FocusState {
    case disabled
    case waitingForPermission
    case active

    var title: String {
        switch self {
        case .disabled:
            return L10n.tr("status.disabled")
        case .waitingForPermission:
            return L10n.tr("status.waitingForPermission")
        case .active:
            return L10n.tr("status.active")
        }
    }
}

private final class FocusController {
    private var options: Options
    private let systemElement = AXUIElementCreateSystemWide()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var lastActivation = Date.distantPast
    private var suppressedUntil = Date.distantPast
    private let minimumActivationInterval: TimeInterval = 0.08
    private(set) var state = FocusState.disabled
    var onStateChanged: (() -> Void)?

    init(options: Options) {
        self.options = options
    }

    var focusMode: FocusMode {
        options.focusMode
    }

    var isEnabled: Bool {
        state != .disabled
    }

    func start(prompt: Bool = true) {
        if installEventTapWhenTrusted(prompt: prompt) {
            printStatus()
            return
        }

        setState(.waitingForPermission)
        schedulePermissionTimer()
        printPermissionStatus()
    }

    func stop() {
        permissionTimer?.invalidate()
        permissionTimer = nil

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        setState(.disabled)
        logger.info("MacFocusFix event tap is disabled")
    }

    func suppressBriefly(for interval: TimeInterval = 0.35) {
        suppressedUntil = Date().addingTimeInterval(interval)
    }

    func setFocusMode(_ mode: FocusMode) {
        guard options.focusMode != mode else { return }
        options.focusMode = mode
        mode.store()
        if state == .active {
            printStatus()
        }
        onStateChanged?()
    }

    private func schedulePermissionTimer() {
        guard permissionTimer == nil else { return }

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.installEventTapWhenTrusted(prompt: false) {
                self.printStatus()
            }
        }
    }

    private func installEventTapWhenTrusted(prompt: Bool) -> Bool {
        guard requestAccessibilityTrust(prompt: prompt) else { return false }
        guard eventTap == nil else {
            setState(.active)
            return true
        }

        let mask = 1 << CGEventType.leftMouseDown.rawValue

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<FocusController>.fromOpaque(refcon).takeUnretainedValue()
            controller.handleMouseDown(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            print(L10n.tr("error.eventTapCreateFailed"))
            return false
        }

        permissionTimer?.invalidate()
        permissionTimer = nil
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        setState(.active)
        return true
    }

    private func printStatus() {
        print(L10n.tr("console.running"))
        print(String(format: L10n.tr("console.mode"), options.focusMode.title))
        logger.info("MacFocusFix event tap is active")
    }

    private func printPermissionStatus() {
        print(L10n.tr("console.waitingForPermission"))
        print(L10n.tr("console.permissionInstructions"))
    }

    private func setState(_ newState: FocusState) {
        guard state != newState else { return }
        state = newState
        onStateChanged?()
    }

    private func requestAccessibilityTrust(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func handleMouseDown(type: CGEventType, event: CGEvent) {
        let location = event.location
        guard Date() >= suppressedUntil else {
            logClick(at: location, skipReason: "suppressed")
            return
        }
        guard Date().timeIntervalSince(lastActivation) >= minimumActivationInterval else {
            logClick(at: location, skipReason: "minimumActivationInterval")
            return
        }
        guard options.focusMode == .alwaysOn || RemoteAppDetector.isRunning() else {
            logClick(at: location, skipReason: "noRemoteAppRunning")
            return
        }

        guard !isMenuBarLocation(location) else {
            logClick(at: location, skipReason: "menuBarLocation")
            return
        }
        guard !isIgnoredSystemUI(at: location) else {
            logClick(at: location, skipReason: "systemUI")
            return
        }

        logClick(at: location, skipReason: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + options.activationDelay) { [weak self] in
            self?.activateElement(at: location)
        }
    }

    private func isMenuBarLocation(_ location: CGPoint) -> Bool {
        let menuBarHeight = max(NSStatusBar.system.thickness, 24) + 8
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return location.y <= menuBarHeight
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success else {
            return location.y <= menuBarHeight
        }

        return displays.prefix(Int(displayCount)).contains { display in
            let bounds = CGDisplayBounds(display)
            return location.x >= bounds.minX &&
                location.x <= bounds.maxX &&
                location.y >= bounds.minY &&
                location.y <= bounds.minY + menuBarHeight
        }
    }

    private func activateElement(at location: CGPoint) {
        guard Date() >= suppressedUntil else {
            logClick(at: location, skipReason: "suppressedBeforeActivation")
            return
        }
        guard !isMenuBarLocation(location) else {
            logClick(at: location, skipReason: "menuBarBeforeActivation")
            return
        }
        guard let (element, pid) = elementAndProcessIdentifier(at: location), pid != getpid() else {
            logClick(at: location, skipReason: "missingElementOrSelf")
            return
        }
        guard !isSystemUIProcess(pid: pid) else {
            logClick(at: location, element: element, pid: pid, skipReason: "systemUIBeforeActivation")
            return
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != pid else {
            logClick(at: location, element: element, pid: pid, skipReason: "frontmostApp")
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        let window = focusedWindowCandidate(from: element)

        if let window {
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window)
        }

        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate()
        lastActivation = Date()
        logClick(at: location, element: element, pid: pid, skipReason: nil, didActivate: true)
        logger.info("Activated pid \(pid, privacy: .public) at x=\(location.x, privacy: .public) y=\(location.y, privacy: .public)")

    }

    private func logClick(
        at location: CGPoint,
        element providedElement: AXUIElement? = nil,
        pid providedPid: pid_t? = nil,
        skipReason: String?,
        didActivate: Bool = false
    ) {
        guard options.debugClicks else { return }

        let elementAndPid: (element: AXUIElement, pid: pid_t)?
        if let providedElement, let providedPid {
            elementAndPid = (providedElement, providedPid)
        } else {
            elementAndPid = elementAndProcessIdentifier(at: location)
        }

        guard let elementAndPid else {
            let reason = skipReason ?? "missingElement"
            logger.info("click debug x=\(location.x, privacy: .public) y=\(location.y, privacy: .public) target=none mode=\(self.options.focusMode.title, privacy: .public) willActivate=false didActivate=false skipReason=\(reason, privacy: .public)")
            return
        }

        let element = elementAndPid.element
        let pid = elementAndPid.pid
        let app = NSRunningApplication(processIdentifier: pid)
        let bundleIdentifier = app?.bundleIdentifier ?? "unknown"
        let appName = app?.localizedName ?? "unknown"
        let window = focusedWindowCandidate(from: element)
        let willActivate = skipReason == nil && !didActivate
        let role = axString(element, kAXRoleAttribute)
        let subrole = axString(element, kAXSubroleAttribute)
        let title = axString(element, kAXTitleAttribute)
        let description = axString(element, kAXDescriptionAttribute)
        let windowRole = axString(window, kAXRoleAttribute)
        let windowTitle = axString(window, kAXTitleAttribute)
        let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        let reason = skipReason ?? "none"

        logger.info("click debug x=\(location.x, privacy: .public) y=\(location.y, privacy: .public) pid=\(pid, privacy: .public) app=\(appName, privacy: .public) bundle=\(bundleIdentifier, privacy: .public) role=\(role, privacy: .public) subrole=\(subrole, privacy: .public) title=\(title, privacy: .public) description=\(description, privacy: .public) windowRole=\(windowRole, privacy: .public) windowTitle=\(windowTitle, privacy: .public) frontmost=\(isFrontmost, privacy: .public) mode=\(self.options.focusMode.title, privacy: .public) willActivate=\(willActivate, privacy: .public) didActivate=\(didActivate, privacy: .public) skipReason=\(reason, privacy: .public)")
    }

    private func axString(_ element: AXUIElement?, _ attribute: String) -> String {
        guard let element else { return "none" }
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue) == .success else {
            return "none"
        }
        return (rawValue as? String) ?? String(describing: rawValue)
    }

    private func isIgnoredSystemUI(at location: CGPoint) -> Bool {
        guard let (_, pid) = elementAndProcessIdentifier(at: location) else { return false }
        return pid == getpid() || isSystemUIProcess(pid: pid)
    }

    private func elementAndProcessIdentifier(at location: CGPoint) -> (element: AXUIElement, pid: pid_t)? {
        var rawElement: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemElement,
            Float(location.x),
            Float(location.y),
            &rawElement
        )

        guard result == .success, let element = rawElement else { return nil }

        var pid = pid_t(0)
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else { return nil }
        return (element, pid)
    }

    private func focusedWindowCandidate(from element: AXUIElement) -> AXUIElement? {
        if role(of: element) == kAXWindowRole {
            return element
        }

        var rawWindow: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &rawWindow) == .success,
           CFGetTypeID(rawWindow) == AXUIElementGetTypeID() {
            return (rawWindow as! AXUIElement)
        }

        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let item = current else { break }

            var rawParent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXParentAttribute as CFString, &rawParent) == .success,
                  CFGetTypeID(rawParent) == AXUIElementGetTypeID() else {
                break
            }

            let parent = rawParent as! AXUIElement
            if role(of: parent) == kAXWindowRole {
                return parent
            }
            current = parent
        }

        return nil
    }

    private func role(of element: AXUIElement) -> String? {
        var rawRole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &rawRole) == .success else {
            return nil
        }
        return rawRole as? String
    }

    private func isSystemUIProcess(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleIdentifier = app.bundleIdentifier else {
            return false
        }

        return ignoredSystemUIBundleIdentifiers.contains(bundleIdentifier)
    }

}

private enum RemoteAppDetector {
    private static let bundleIdentifierPrefixes = [
        "com.netease.uuremote",
        "com.todesk",
        "com.youqu.sunlogin",
        "com.oray.sunlogin",
        "com.rustdesk",
        "com.philandro.anydesk",
        "com.google.chrome.remote"
    ]

    private static let processNameFragments = [
        "uuremote",
        "todesk",
        "sunlogin",
        "rustdesk",
        "anydesk",
        "chrome remote desktop"
    ]

    static func isRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            if let bundleIdentifier = app.bundleIdentifier?.lowercased(),
               bundleIdentifierPrefixes.contains(where: { bundleIdentifier.hasPrefix($0) }) {
                return true
            }

            let processName = app.localizedName?.lowercased() ?? ""
            return processNameFragments.contains { processName.contains($0) }
        }
    }
}

private final class MenuBarController: NSObject, NSMenuDelegate {
    private let focusController: FocusController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem()
    private let toggleMenuItem = NSMenuItem()
    private let modeMenuItem = NSMenuItem()
    private let alwaysOnMenuItem = NSMenuItem()
    private let remoteAppsOnlyMenuItem = NSMenuItem()
    private let versionMenuItem = NSMenuItem()
    private let launchAtLoginMenuItem = NSMenuItem()

    init(focusController: FocusController) {
        self.focusController = focusController
        super.init()
        configureStatusItem()
        configureMenu()
        focusController.onStateChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.updateMenu()
            }
        }
        updateMenu()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = statusImage(active: true, appearance: button.effectiveAppearance)
        button.imagePosition = .imageOnly
        button.title = button.image == nil ? "FF" : ""

        button.toolTip = L10n.tr("menuBar.tooltip")
    }

    private func configureMenu() {
        menu.delegate = self

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        toggleMenuItem.target = self
        toggleMenuItem.action = #selector(toggleFocusFix)
        menu.addItem(toggleMenuItem)

        modeMenuItem.isEnabled = false
        menu.addItem(modeMenuItem)

        alwaysOnMenuItem.target = self
        alwaysOnMenuItem.action = #selector(selectAlwaysOnMode)
        menu.addItem(alwaysOnMenuItem)

        remoteAppsOnlyMenuItem.target = self
        remoteAppsOnlyMenuItem.action = #selector(selectRemoteAppsOnlyMode)
        menu.addItem(remoteAppsOnlyMenuItem)

        let accessibilityItem = NSMenuItem(title: L10n.tr("menu.openAccessibilitySettings"), action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        launchAtLoginMenuItem.target = self
        launchAtLoginMenuItem.action = #selector(toggleLaunchAtLogin)
        menu.addItem(launchAtLoginMenuItem)

        menu.addItem(.separator())

        let helpItem = NSMenuItem(title: L10n.tr("menu.openGitHub"), action: #selector(openGitHub), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)

        versionMenuItem.isEnabled = false
        menu.addItem(versionMenuItem)

        let quitItem = NSMenuItem(title: L10n.tr("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        focusController.suppressBriefly()
        updateMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        focusController.suppressBriefly()
    }

    private func updateMenu() {
        statusMenuItem.title = String(format: L10n.tr("menu.statusFormat"), focusController.state.title)
        toggleMenuItem.title = focusController.isEnabled ? L10n.tr("menu.disableFocusFix") : L10n.tr("menu.enableFocusFix")
        updateFocusModeMenuItems()
        updateLaunchAtLoginMenuItem()
        versionMenuItem.title = String(format: L10n.tr("menu.versionFormat"), appVersion())

        guard let button = statusItem.button else { return }
        button.image = statusImage(active: focusController.state == .active, appearance: button.effectiveAppearance)
        button.title = button.image == nil ? "FF" : ""
        button.contentTintColor = nil
        button.needsDisplay = true
    }

    private func updateFocusModeMenuItems() {
        modeMenuItem.title = String(format: L10n.tr("menu.modeFormat"), focusController.focusMode.title)
        alwaysOnMenuItem.title = L10n.tr("menu.modeAlwaysOn")
        alwaysOnMenuItem.state = focusController.focusMode == .alwaysOn ? .on : .off
        remoteAppsOnlyMenuItem.title = L10n.tr("menu.modeRemoteAppsOnly")
        remoteAppsOnlyMenuItem.state = focusController.focusMode == .remoteAppsOnly ? .on : .off
    }

    private func appVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0-dev"
    }

    private func statusImage(active: Bool, appearance: NSAppearance) -> NSImage? {
        guard let baseImage = statusIconImage() else { return nil }

        let mode = appearance.bestMatch(from: [.darkAqua, .aqua])
        let color: NSColor
        if active {
            color = mode == .darkAqua ? .white : .black
        } else {
            color = mode == .darkAqua
                ? NSColor(calibratedWhite: 0.45, alpha: 1.0)
                : NSColor(calibratedWhite: 0.66, alpha: 1.0)
        }
        let size = NSSize(width: 18, height: 18)
        let rect = NSRect(origin: .zero, size: size)
        let image = NSImage(size: size)

        image.lockFocus()
        baseImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        color.setFill()
        rect.fill(using: .sourceAtop)
        image.unlockFocus()

        image.isTemplate = false
        return image
    }

    private func statusIconImage() -> NSImage? {
        guard let url = AppResources.bundle.url(forResource: "MenuBarIcon", withExtension: "svg") else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    private func updateLaunchAtLoginMenuItem() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLoginMenuItem.title = L10n.tr("menu.launchAtLogin")
            launchAtLoginMenuItem.state = .on
            launchAtLoginMenuItem.isEnabled = true
        case .requiresApproval:
            launchAtLoginMenuItem.title = L10n.tr("menu.launchAtLoginRequiresApproval")
            launchAtLoginMenuItem.state = .mixed
            launchAtLoginMenuItem.isEnabled = true
        case .notRegistered, .notFound:
            launchAtLoginMenuItem.title = L10n.tr("menu.launchAtLogin")
            launchAtLoginMenuItem.state = .off
            launchAtLoginMenuItem.isEnabled = true
        @unknown default:
            launchAtLoginMenuItem.title = L10n.tr("menu.launchAtLogin")
            launchAtLoginMenuItem.state = .off
            launchAtLoginMenuItem.isEnabled = true
        }
    }

    @objc private func toggleFocusFix() {
        if focusController.isEnabled {
            focusController.stop()
        } else {
            focusController.start(prompt: true)
        }
    }

    @objc private func selectAlwaysOnMode() {
        focusController.setFocusMode(.alwaysOn)
        updateMenu()
    }

    @objc private func selectRemoteAppsOnlyMode() {
        focusController.setFocusMode(.remoteAppsOnly)
        updateMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            switch SMAppService.mainApp.status {
            case .enabled, .requiresApproval:
                try SMAppService.mainApp.unregister()
            case .notRegistered, .notFound:
                try SMAppService.mainApp.register()
            @unknown default:
                try SMAppService.mainApp.register()
            }
        } catch {
            logger.error("Could not update Launch at Login: \(error.localizedDescription, privacy: .public)")
            showLaunchAtLoginError(error)
        }

        updateMenu()
    }

    private func showLaunchAtLoginError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.tr("error.launchAtLoginUpdateFailed")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("alert.ok"))
        alert.runModal()
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(projectURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let focusController: FocusController
    private var menuBarController: MenuBarController?

    init(options: Options) {
        focusController = FocusController(options: options)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(focusController: focusController)
        showWelcomeIfNeeded()
        focusController.start(prompt: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        focusController.stop()
    }

    private func showWelcomeIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: userDefaultsWelcomeKey) else { return }
        UserDefaults.standard.set(true, forKey: userDefaultsWelcomeKey)

        let alert = NSAlert()
        alert.messageText = L10n.tr("welcome.title")
        alert.informativeText = L10n.tr("welcome.message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("welcome.openAccessibilitySettings"))
        alert.addButton(withTitle: L10n.tr("welcome.later"))

        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

private func parseOptions() -> Options {
    var options = Options()

    for argument in CommandLine.arguments.dropFirst() {
        switch argument {
        case "--always":
            options.focusMode = .alwaysOn
        case "--remote-apps-only":
            options.focusMode = .remoteAppsOnly
        case "--debug-clicks":
            options.debugClicks = true
        case "--help", "-h":
            print(L10n.tr("help.usage"))
            exit(0)
        default:
            print(String(format: L10n.tr("error.unknownArgument"), argument))
            exit(2)
        }
    }

    return options
}

private let options = parseOptions()
private let app = NSApplication.shared
app.setActivationPolicy(.accessory)

private let appDelegate = AppDelegate(options: options)
app.delegate = appDelegate
app.run()
