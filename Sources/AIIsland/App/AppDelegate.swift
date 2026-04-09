import AppKit
import AIIslandProtocol

final class AppDelegate: NSObject, NSApplicationDelegate {

    let appState = AppState()
    private var socketServer: SocketServer?
    private var panelController: IslandPanelController?
    private var statusItem: NSStatusItem?
    private var localEventMonitor: Any?

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupKeyboardShortcuts()
        setupIslandPanel()
        startSocketServer()
        runHookInstallerIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        socketServer?.stop()
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Status Item (Menu Bar)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            if let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI Island") {
                image.isTemplate = true
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                button.image = image.withSymbolConfiguration(config)
            } else {
                // Fallback: text label if SF Symbols unavailable
                button.title = "🏝"
            }
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Island", action: #selector(toggleIsland), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Install Hooks...", action: #selector(installHooks), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let soundItem = NSMenuItem(title: "Sound Effects", action: #selector(toggleSound), keyEquivalent: "")
        soundItem.state = appState.soundEnabled ? .on : .off
        menu.addItem(soundItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit AI Island", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func toggleIsland() {
        panelController?.toggleVisibility()
    }

    // MARK: - Island Panel

    private func setupIslandPanel() {
        panelController = IslandPanelController(appState: appState)
        panelController?.showPanel()
    }

    @objc private func installHooks() {
        HookInstaller.installAll(force: true)
    }

    @objc private func toggleSound(_ sender: NSMenuItem) {
        appState.soundEnabled.toggle()
        sender.state = appState.soundEnabled ? .on : .off
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Keyboard Shortcuts

    private func setupKeyboardShortcuts() {
        // Global shortcuts for permission approve/deny
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            // Cmd+Y = Allow
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "y" {
                if self.appState.pendingPermission != nil {
                    self.appState.handlePermissionResponse(allow: true)
                    return nil // consume event
                }
            }

            // Cmd+N = Deny
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "n" {
                if self.appState.pendingPermission != nil {
                    self.appState.handlePermissionResponse(allow: false)
                    return nil // consume event
                }
            }

            // Cmd+1 through Cmd+9 = select ask option
            if event.modifierFlags.contains(.command),
               let chars = event.charactersIgnoringModifiers,
               let digit = chars.first?.wholeNumberValue,
               digit >= 1 && digit <= 9 {
                if self.appState.pendingQuestion != nil {
                    self.appState.handleAskResponse(optionIndex: digit - 1)
                    return nil
                }
            }

            return event
        }
    }

    // MARK: - Socket Server

    private func startSocketServer() {
        socketServer = SocketServer(appState: appState)
        socketServer?.start()
    }

    // MARK: - Hook Installer

    private func runHookInstallerIfNeeded() {
        HookInstaller.installAll()
    }
}
