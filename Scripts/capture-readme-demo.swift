import AppKit
import Foundation
import SwiftUI
import ThinQCore

@main
@MainActor
enum CaptureReadmeDemo {
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            fputs("Uso: capture-readme-demo <diretorio-de-frames>\n", stderr)
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
                fputs("Falha ao capturar demonstração: \(error)\n", stderr)
                exit(1)
            }
        }
        app.run()
    }

    private static func capture(to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Use a fresh preferences domain and the in-memory demo service only.
        let suiteName = "ai.ubiquu.UbiAir.ReadmeCapture.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw CaptureError.preferencesUnavailable
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(preferences: AppPreferences(defaults: defaults, previousDomain: nil))
        let window = makeWindow(model: model)
        defer { window.close() }

        await model.startDemo()
        try await settleLayout(window)
        try render(window, to: directory.appendingPathComponent("frame-01.png"))

        await model.send(.temperature(21))
        try await capture(window, to: directory, name: "frame-02.png")
        await model.send(.temperature(26))
        try await capture(window, to: directory, name: "frame-03.png")

        await model.selectDevice(DemoThinQService.bedroomID)
        try await capture(window, to: directory, name: "frame-04.png")
        await model.send(.power(true))
        try await capture(window, to: directory, name: "frame-05.png")
        await model.send(.verticalSwing(true))
        try await capture(window, to: directory, name: "frame-06.png")

        print("Exportados 6 frames nativos: 720 × 1480 px")
    }

    private static func capture(_ window: NSWindow, to directory: URL, name: String) async throws {
        try await settleLayout(window)
        try render(window, to: directory.appendingPathComponent(name))
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
        window.contentView = NSHostingView(rootView: MenuPanel(model: model).preferredColorScheme(.light))
        window.setContentSize(NSSize(width: PanelLayout.width, height: PanelLayout.height))
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private static func settleLayout(_ window: NSWindow) async throws {
        window.contentView?.setFrameSize(NSSize(width: PanelLayout.width, height: PanelLayout.height))
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
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
