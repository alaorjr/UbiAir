import AppKit
import SwiftUI

@main
struct LGThinQApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: AppModel

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        AppDelegate.model = model
    }

    var body: some Scene {
        MenuBarExtra("LGThinQ", systemImage: "snowflake") { MenuPanel(model: model) }
            .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var model: AppModel?
    private var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let model = Self.model else { return }
        Task { await model.restoreSession() }
        if CommandLine.arguments.contains("--preview") {
            let controller = NSHostingController(rootView: MenuPanel(model: model))
            let window = NSWindow(contentViewController: controller)
            window.title = "LGThinQ — demonstração"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 380, height: 620))
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            previewWindow = window
        }
    }
}
