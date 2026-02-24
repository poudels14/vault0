import AppKit
import SwiftUI

class MainWindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_: NSWindow) -> Bool {
        MasterPasswordSession.shared.lock()
        return true
    }
}

class WindowManager: ObservableObject {
    static let shared = WindowManager()

    private var mainWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var loginWindow: NSWindow?
    private var lockScreenWindow: NSWindow?
    private var mainWindowDelegate: MainWindowDelegate?

    private init() {}

    func showOnboarding() {
        closeAllWindows()

        let contentView = OnboardingView()
            .environmentObject(MasterPasswordSession.shared)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false,
        )
        window.title = "Welcome to Vault0"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        onboardingWindow = window
    }

    func showLogin() {
        closeAllWindows()

        let contentView = LoginView()
            .environmentObject(MasterPasswordSession.shared)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false,
        )
        window.title = "Vault0 Login"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        loginWindow = window
    }

    func showLockScreen() {
        closeAllWindows()

        let contentView = LockScreenView()
            .environmentObject(MasterPasswordSession.shared)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false,
        )
        window.title = "Vault0 Locked"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        lockScreenWindow = window
    }

    func showMainWindow() {
        closeAllWindows()

        let contentView = MainWindowView()
            .environmentObject(MasterPasswordSession.shared)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false,
        )
        window.title = "Vault0"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("MainWindow")

        // Set up delegate to detect window close
        mainWindowDelegate = MainWindowDelegate()
        window.delegate = mainWindowDelegate

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        mainWindow = window
    }

    func closeAllWindows() {
        mainWindow?.close()
        onboardingWindow?.close()
        loginWindow?.close()
        lockScreenWindow?.close()

        mainWindow = nil
        onboardingWindow = nil
        loginWindow = nil
        lockScreenWindow = nil
    }
}
