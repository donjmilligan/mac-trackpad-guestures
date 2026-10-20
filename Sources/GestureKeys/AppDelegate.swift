import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = ConfigStore()
    lazy var controller = GestureController(store: store)

    private var statusItem: NSStatusItem!
    private var enabledItem: NSMenuItem!
    private var profileMenu = NSMenu()
    private var settingsWindow: NSWindow?
    private var enabledObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        setUpStatusItem()
        controller.start()
        if !controller.accessibilityTrusted { controller.requestAccessibility() }
        if store.isFirstLaunch { showSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings() // launching the app again (e.g. from Finder) opens settings
        return false
    }

    // MARK: Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Template image bundled by scripts/build-app.sh; the SF Symbol covers unbundled runs.
        let icon = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "hand.draw", accessibilityDescription: nil)
        icon?.isTemplate = true
        icon?.accessibilityDescription = "GestureKeys"
        statusItem.button?.image = icon

        let menu = NSMenu()
        menu.delegate = self
        enabledItem = NSMenuItem(title: "Gestures Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        menu.addItem(enabledItem)
        menu.addItem(withTitle: "Profile", action: nil, keyEquivalent: "").submenu = profileMenu
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Restart Touch Listener", action: #selector(restartListener), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit GestureKeys", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        enabledObserver = store.$config.map(\.enabled).removeDuplicates().sink { [weak self] enabled in
            self?.statusItem.button?.appearsDisabled = !enabled
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        enabledItem.state = store.config.enabled ? .on : .off
        profileMenu.removeAllItems()
        for profile in store.config.profiles {
            let item = NSMenuItem(title: profile.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id
            item.state = profile.id == store.config.activeProfileID ? .on : .off
            profileMenu.addItem(item)
        }
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { store.config.activeProfileID = id }
    }

    @objc private func toggleEnabled() {
        store.config.enabled.toggle()
    }

    @objc private func restartListener() {
        controller.restartListener()
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let root = SettingsView()
                .environmentObject(store)
                .environmentObject(controller)
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "GestureKeys"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("SettingsWindow")
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Main menu

    /// An accessory app has no visible menu bar, but its main menu still provides ⌘C/⌘V/⌘W in the settings window.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit GestureKeys", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "GestureKeys", action: nil, keyEquivalent: "").submenu = appMenu

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = window

        return main
    }
}
