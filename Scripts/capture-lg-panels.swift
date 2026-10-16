import AppKit
import Foundation
import SwiftUI
import ThinQCore

@main
@MainActor
enum CaptureLGPanels {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        Task { @MainActor in
            do {
                try await capture()
                app.terminate(nil)
            } catch {
                fputs("Falha ao exportar painéis: \(error)\n", stderr)
                exit(1)
            }
        }
        app.run()
    }

    private static func capture() async throws {
        guard CommandLine.arguments.count == 3,
              ["connection", "controls"].contains(CommandLine.arguments[2]) else {
            fputs("Uso: capture-lg-panels <diretorio-de-saida> <connection|controls>\n", stderr)
            exit(2)
        }

        let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let suiteName = "ai.ubiquu.UbiAir.LGPanelCapture.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw CaptureError.preferencesUnavailable
        }
        let preferences = AppPreferences(defaults: defaults, previousDomain: nil)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        // Keep each fixture session isolated; never restore a saved user session.
        let model = AppModel(preferences: preferences)
        let filename: String
        switch CommandLine.arguments[2] {
        case "controls":
            await model.startDemo()
            filename = "02-controls-demo.png"
        default:
            filename = "01-connection.png"
        }
        try await renderPanel(model, to: outputDirectory.appendingPathComponent(filename))
        print("Exportado \(filename): 720 × 1480 px")
    }

    private static func renderPanel(_ model: AppModel, to url: URL) async throws {
        let window = makeWindow(model: model)
        defer { window.close() }
        await settleLayout(window)
        try render(window, to: url)
    }

    private static func makeWindow(model: AppModel) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: PanelLayout.width, height: PanelLayout.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.contentView = NSHostingView(
            rootView: MenuPanel(model: model)
                .preferredColorScheme(.light)
        )
        window.setContentSize(NSSize(width: PanelLayout.width, height: PanelLayout.height))
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private static func settleLayout(_ window: NSWindow) async {
        window.contentView?.setFrameSize(NSSize(width: PanelLayout.width, height: PanelLayout.height))
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        // Let SwiftUI process onAppear and publish the demo state before bitmap export.
        try? await Task.sleep(for: .milliseconds(300))
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    private static func render(_ window: NSWindow, to url: URL) throws {
        guard let view = window.contentView,
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(PanelLayout.width * 2),
                pixelsHigh: Int(PanelLayout.height * 2),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ) else { throw CaptureError.bitmapUnavailable }

        view.layoutSubtreeIfNeeded()
        view.needsDisplay = true
        view.displayIfNeeded()
        // SwiftUI's cached AppKit draw pass can omit unchanged Text elements.
        // Export the complete native layer tree instead, mapping its flipped
        // coordinates directly into the 2x bitmap.
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap), let layer = view.layer else {
            throw CaptureError.bitmapUnavailable
        }
        context.cgContext.translateBy(x: 0, y: CGFloat(bitmap.pixelsHigh))
        context.cgContext.scaleBy(x: 2, y: -2)
        layer.render(in: context.cgContext)

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CaptureError.pngEncodingFailed
        }
        try data.write(to: url, options: .atomic)

    }
}

private enum CaptureError: Error {
    case preferencesUnavailable
    case bitmapUnavailable
    case pngEncodingFailed
}
