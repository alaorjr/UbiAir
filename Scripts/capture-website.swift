import AppKit
import Foundation
import SwiftUI
import ThinQCore

@main
@MainActor
enum CaptureWebsite {
    static var airflowExpanded = false

    static func main() {
        guard CommandLine.arguments.count == 2 else {
            fputs("Uso: capture-website <diretorio-de-saida>\n", stderr)
            exit(2)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        Task { @MainActor in
            do {
                try await capture(to: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
                app.terminate(nil)
            } catch {
                fputs("Falha ao exportar screenshots: \(error)\n", stderr)
                exit(1)
            }
        }
        app.run()
    }

    private static func capture(to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "ai.ubiquu.UbiAir.WebsiteCapture.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CaptureError.preferencesUnavailable }
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(preferences: AppPreferences(defaults: defaults, previousDomain: nil))
        let window = makeWindow(model: model)
        defer { window.close() }

        for (kind, demo) in [("connection", false), ("controls", true), ("airflow", true)] {
            if demo { await model.startDemo() }
            airflowExpanded = kind == "airflow"
            for theme in ["light", "dark"] {
                setTheme(theme, window: window, model: model)
                try await settle(window)
                let filename = "\(kind)-\(theme).png"
                try render(window, to: directory.appendingPathComponent(filename))
                print("Exportado \(filename): 720 × 1480 px")
            }
        }
    }

    private static func makeWindow(model: AppModel) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: PanelLayout.width, height: PanelLayout.height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.contentView = NSHostingView(rootView: MenuPanel(model: model).preferredColorScheme(.light))
        window.setContentSize(NSSize(width: PanelLayout.width, height: PanelLayout.height))
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private static func setTheme(_ theme: String, window: NSWindow, model: AppModel) {
        let scheme: ColorScheme = theme == "dark" ? .dark : .light
        window.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: MenuPanel(model: model).preferredColorScheme(scheme))
        window.backgroundColor = .windowBackgroundColor
    }

    private static func settle(_ window: NSWindow) async throws {
        window.contentView?.setFrameSize(NSSize(width: PanelLayout.width, height: PanelLayout.height))
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    private static func render(_ window: NSWindow, to url: URL) throws {
        guard let view = window.contentView,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(PanelLayout.width * 2), pixelsHigh: Int(PanelLayout.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap), let layer = view.layer else { throw CaptureError.bitmapUnavailable }
        view.layoutSubtreeIfNeeded()
        view.needsDisplay = true
        view.displayIfNeeded()
        context.cgContext.translateBy(x: 0, y: CGFloat(bitmap.pixelsHigh))
        context.cgContext.scaleBy(x: 2, y: -2)
        layer.render(in: context.cgContext)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CaptureError.pngEncodingFailed }
        try data.write(to: url, options: .atomic)
    }
}

private enum CaptureError: Error { case preferencesUnavailable, bitmapUnavailable, pngEncodingFailed }
