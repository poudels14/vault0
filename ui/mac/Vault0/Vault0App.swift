import SwiftUI

@main
struct Vault0App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var sessionManager: SessionManager!
    var masterPasswordSession: MasterPasswordSession!

    private var statusItem: NSStatusItem?
    private var activityMonitors: [Any] = []

    func applicationDidFinishLaunching(_: Notification) {
        _ = Vault0Library.shared
        sessionManager = SessionManager.shared
        masterPasswordSession = MasterPasswordSession.shared
        setupMenuBar()
        setupActivityMonitoring()

        let authState = sessionManager.getAuthenticationState()
        switch authState {
        case .needsOnboarding:
            WindowManager.shared.showOnboarding()
        case .needsLogin:
            WindowManager.shared.showLogin()
        }

        NSLog("Vault0 started successfully")
    }

    func applicationWillTerminate(_: Notification) {
        for monitor in activityMonitors {
            NSEvent.removeMonitor(monitor)
        }
        activityMonitors.removeAll()

        masterPasswordSession.clearSession()
        Vault0Library.shared.stopServer()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let statusItem else { return }

        if let button = statusItem.button {
            if let lockImage = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Vault0") {
                button.image = lockImage
                button.image?.isTemplate = true
            }
        }

        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Vault0", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let openItem = NSMenuItem(title: "Open Vault0", action: #selector(openMainWindow), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let lockItem = NSMenuItem(title: "Lock", action: #selector(lockApp), keyEquivalent: "l")
        lockItem.target = self
        menu.addItem(lockItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Vault0", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func setupActivityMonitoring() {
        let eventMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown]

        let monitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] _ in
            self?.masterPasswordSession.resetInactivityTimer()
        }

        if let monitor {
            activityMonitors.append(monitor)
        }

        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            self?.masterPasswordSession.resetInactivityTimer()
            return event
        }

        if let localMonitor {
            activityMonitors.append(localMonitor)
        }
    }

    @objc func openMainWindow() {
        if masterPasswordSession.needsAuthentication {
            WindowManager.shared.showLogin()
        } else {
            WindowManager.shared.showMainWindow()
        }
    }

    @objc func lockApp() {
        masterPasswordSession.lock()
        WindowManager.shared.showLogin()
    }

    @objc func quitApp() {
        masterPasswordSession.clearSession()
        WindowManager.shared.closeAllWindows()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.terminate(nil)
        }
    }
}
