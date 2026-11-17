import AppKit
import IOKit.pwr_mgt
import SwiftUI
import UniformTypeIdentifiers

/// Keeps one borderless window filling the iPad (Sidecar) screen. When the iPad
/// disconnects the window hides; when it comes back the window returns.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private let store = DashboardStore()
    private let calendar = CalendarFeed()
    private let background = BackgroundStore()
    private var widgetItems: [Widget: NSMenuItem] = [:]
    private var photoItem: NSMenuItem!
    private var awakeAssertion: IOPMAssertionID = 0
    private var keepAwakeItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: DashboardView()
            .environmentObject(store)
            .environmentObject(calendar)
            .environmentObject(background))
        window.backgroundColor = .black
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        // Above the menu bar so the dashboard owns the whole iPad screen.
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.placeWindow() }
        }
        // Sidecar can reconnect without a screen-change notice reaching us; re-check now and then.
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.placeWindow() }
        }

        setupStatusItem()
        if UserDefaults.standard.bool(forKey: "keepAwake") { setKeepAwake(true) }
        placeWindow()
        if Demo.isOn {
            Demo.load(store: store, calendar: calendar)
            return
        }
        store.start()
        calendar.promptShowing = { [weak self] showing in
            self?.window.level = showing ? .normal : .statusBar
            if showing { NSApp.activate(ignoringOtherApps: true) }
        }
        calendar.start()
        background.start()
    }

    private func targetScreen() -> NSScreen? {
        let override = UserDefaults.standard.string(forKey: "screenName")?.lowercased()
        return NSScreen.screens.first { screen in
            let name = screen.localizedName.lowercased()
            if let override, !override.isEmpty { return name.contains(override) }
            return name.contains("sidecar") || name.contains("ipad")
        }
    }

    private func placeWindow() {
        guard let screen = targetScreen() else {
            if window.isVisible { window.orderOut(nil) }
            return
        }
        if window.frame != screen.frame { window.setFrame(screen.frame, display: true) }
        if !window.isVisible { window.orderFrontRegardless() }
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent",
                                           accessibilityDescription: "Sidecar Dash")
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r").target = self
        keepAwakeItem = menu.addItem(withTitle: "Keep Screens Awake", action: #selector(toggleKeepAwake),
                                     keyEquivalent: "")
        keepAwakeItem.target = self
        menu.addItem(.separator())

        let widgetsMenu = NSMenu()
        for widget in Widget.allCases {
            let item = widgetsMenu.addItem(withTitle: widget.title, action: #selector(toggleWidget(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = widget.rawValue
            widgetItems[widget] = item
        }
        menu.addItem(withTitle: "Widgets", action: nil, keyEquivalent: "").submenu = widgetsMenu

        let bgMenu = NSMenu()
        bgMenu.addItem(withTitle: "Add Images…", action: #selector(addBackgroundImages), keyEquivalent: "").target = self
        bgMenu.addItem(withTitle: "Next Image", action: #selector(nextBackground), keyEquivalent: "").target = self
        bgMenu.addItem(withTitle: "Show Images Folder", action: #selector(showBackgroundFolder), keyEquivalent: "").target = self
        bgMenu.addItem(.separator())
        photoItem = bgMenu.addItem(withTitle: "Use Photo Background", action: #selector(togglePhoto), keyEquivalent: "")
        photoItem.target = self
        menu.addItem(withTitle: "Background", action: nil, keyEquivalent: "").submenu = bgMenu
        menu.addItem(withTitle: "Billing…", action: #selector(editBilling), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Calendar Access…", action: #selector(openCalendarPrivacy), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sidecar Dash", action: #selector(quit), keyEquivalent: "q").target = self
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for (widget, item) in widgetItems { item.state = widget.isOn ? .on : .off }
        photoItem.state = background.isEnabled ? .on : .off
    }

    @objc private func refreshNow() {
        store.refreshAll()
        calendar.reload()
    }

    @objc private func toggleWidget(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let widget = Widget(rawValue: raw) else { return }
        widget.isOn.toggle()
        if widget == .calendar, widget.isOn { calendar.requestAccess() }
    }

    @objc private func addBackgroundImages() {
        let panel = NSOpenPanel()
        panel.title = "Choose background images for the iPad dashboard"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { background.add(panel.urls) }
    }

    @objc private func openCalendarPrivacy() {
        calendar.requestAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func editBilling() {
        func field(_ value: String, placeholder: String) -> NSTextField {
            let f = NSTextField(string: value)
            f.placeholderString = placeholder
            f.frame.size.width = 120
            return f
        }
        let price = { (v: Double) in v == v.rounded() ? String(Int(v)) : String(v) }
        let claudePrice = field(price(Billing.claudePrice), placeholder: "100")
        let claudeDay = field(Billing.claudeDay > 0 ? String(Billing.claudeDay) : "", placeholder: "1–31")
        let opencodePrice = field(price(Billing.opencodePrice), placeholder: "10")
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Claude price (USD / month)"), claudePrice],
            [NSTextField(labelWithString: "Claude charge day of month"), claudeDay],
            [NSTextField(labelWithString: "OpenCode Go price (USD / month)"), opencodePrice],
        ])
        grid.rowSpacing = 8
        grid.frame.size = grid.fittingSize

        let alert = NSAlert()
        alert.messageText = "Subscription billing"
        alert.informativeText = "Shown on the Claude and OpenCode cards. OpenCode's renewal date is read automatically; "
            + "Claude's charge day is on your receipt or at claude.ai → Settings → Billing."
        alert.accessoryView = grid
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = claudeDay
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let number = { (f: NSTextField) in Double(f.stringValue.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) }
        if let v = number(claudePrice), v >= 0 { Billing.claudePrice = v }
        if let v = number(opencodePrice), v >= 0 { Billing.opencodePrice = v }
        let day = Int(claudeDay.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
        Billing.claudeDay = (1...31).contains(day) ? day : 0
    }

    @objc private func nextBackground() { background.next() }

    @objc private func showBackgroundFolder() { NSWorkspace.shared.open(background.folder) }

    @objc private func togglePhoto() { background.isEnabled.toggle() }

    @objc private func toggleKeepAwake() {
        let on = awakeAssertion == 0
        setKeepAwake(on)
        UserDefaults.standard.set(on, forKey: "keepAwake")
    }

    private func setKeepAwake(_ on: Bool) {
        if on, awakeAssertion == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Sidecar Dash keeps the dashboard visible" as CFString,
                                        &awakeAssertion)
        } else if !on, awakeAssertion != 0 {
            IOPMAssertionRelease(awakeAssertion)
            awakeAssertion = 0
        }
        keepAwakeItem?.state = awakeAssertion != 0 ? .on : .off
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
