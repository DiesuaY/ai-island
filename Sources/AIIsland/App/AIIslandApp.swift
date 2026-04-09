import AppKit

// AI Island - macOS Dynamic Island for AI Coding Agents
// Uses NSApplicationMain pattern for NSPanel support (no SwiftUI App protocol)

// Hold delegate as a global to prevent deallocation (NSApplication.delegate is weak)
private let appDelegate = AppDelegate()

@main
struct AIIslandMain {
    static func main() {
        let app = NSApplication.shared

        // Configure as agent app (no dock icon)
        app.setActivationPolicy(.accessory)

        app.delegate = appDelegate
        app.run()
    }
}
