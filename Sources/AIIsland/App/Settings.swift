import AppKit
import Foundation
import ServiceManagement

/// Persisted app settings, saved to ~/Library/Preferences/com.aiisland.settings.json
@Observable
final class IslandSettings {

    // MARK: - Persisted Properties

    /// Guards against side effects during init/load.
    private var isInitialized = false
    /// Guards against infinite re-entry when reverting a failed login item change.
    private var isRevertingLoginItem = false

    var soundEnabled: Bool = true { didSet { if isInitialized { save() } } }
    var autoHideEnabled: Bool = false { didSet { if isInitialized { save() } } }
    var autoHideSeconds: Int = 10 { didSet { if isInitialized { save() } } }

    /// Preferred screen for the overlay panel. Empty string = auto (notch screen or main screen).
    var preferredScreenID: String = "" { didSet { if isInitialized { save() } } }
    var showDockIcon: Bool = false {
        didSet {
            guard isInitialized, showDockIcon != oldValue else { return }
            save()
            NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
            if !showDockIcon {
                // macOS doesn't immediately refresh the Dock when switching to .accessory.
                // Briefly hiding forces the Dock to drop the icon.
                NSApp.hide(nil)
                DispatchQueue.main.async { NSApp.unhide(nil) }
            }
        }
    }
    var launchAtLogin: Bool = false {
        didSet {
            guard isInitialized, launchAtLogin != oldValue else { return }
            save()
            updateLoginItem()
        }
    }

    // MARK: - Init

    static let shared = IslandSettings()

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Preferences")
        return dir.appendingPathComponent("com.aiisland.settings.json")
    }()

    private init() {
        load()
        // System is the source of truth — the user may have toggled login items
        // in System Settings while the app was not running, so override the persisted value.
        launchAtLogin = SMAppService.mainApp.status == .enabled
        isInitialized = true
    }

    // MARK: - Login Item

    private func updateLoginItem() {
        guard !isRevertingLoginItem else { return }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // If registration fails, revert the setting without re-triggering updateLoginItem
            let current = SMAppService.mainApp.status == .enabled
            if current != launchAtLogin {
                isRevertingLoginItem = true
                launchAtLogin = current
                isRevertingLoginItem = false
            }
        }
    }

    // MARK: - Persistence

    private struct SettingsData: Codable {
        var soundEnabled: Bool = true
        var autoHideEnabled: Bool = false
        var autoHideSeconds: Int = 10
        var showDockIcon: Bool = false
        var launchAtLogin: Bool = false
        var preferredScreenID: String = ""
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(SettingsData.self, from: data) else {
            return
        }
        soundEnabled = decoded.soundEnabled
        autoHideEnabled = decoded.autoHideEnabled
        autoHideSeconds = decoded.autoHideSeconds
        showDockIcon = decoded.showDockIcon
        launchAtLogin = decoded.launchAtLogin
        preferredScreenID = decoded.preferredScreenID
    }

    private func save() {
        let data = SettingsData(
            soundEnabled: soundEnabled,
            autoHideEnabled: autoHideEnabled,
            autoHideSeconds: autoHideSeconds,
            showDockIcon: showDockIcon,
            launchAtLogin: launchAtLogin,
            preferredScreenID: preferredScreenID
        )
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: fileURL, options: .atomic)
    }
}
