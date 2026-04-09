import Foundation

/// Persisted app settings, saved to ~/Library/Preferences/com.aiisland.settings.json
@Observable
final class IslandSettings {

    // MARK: - Persisted Properties

    var soundEnabled: Bool = true { didSet { save() } }
    var autoHideEnabled: Bool = false { didSet { save() } }
    var autoHideSeconds: Int = 10 { didSet { save() } }

    // MARK: - Init

    static let shared = IslandSettings()

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Preferences")
        return dir.appendingPathComponent("com.aiisland.settings.json")
    }()

    private init() {
        load()
    }

    // MARK: - Persistence

    private struct SettingsData: Codable {
        var soundEnabled: Bool = true
        var autoHideEnabled: Bool = false
        var autoHideSeconds: Int = 10
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(SettingsData.self, from: data) else {
            return
        }
        soundEnabled = decoded.soundEnabled
        autoHideEnabled = decoded.autoHideEnabled
        autoHideSeconds = decoded.autoHideSeconds
    }

    private func save() {
        let data = SettingsData(
            soundEnabled: soundEnabled,
            autoHideEnabled: autoHideEnabled,
            autoHideSeconds: autoHideSeconds
        )
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: fileURL, options: .atomic)
    }
}
