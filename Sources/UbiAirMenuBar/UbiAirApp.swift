import AppKit
import Darwin
import SwiftUI

@main
@MainActor
enum UbiAirApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.finishLaunching()
            delegate.prepareInterface()
            application.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = AppModel()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        prepareInterface()
    }

    func prepareInterface() {
        guard statusItem == nil else { return }
        installMainMenu()
        let controller = NSHostingController(rootView: MenuPanel(model: model))
        controller.sizingOptions = []
        controller.preferredContentSize = NSSize(width: 360, height: 650)
        controller.view.frame = NSRect(x: 0, y: 0, width: 360, height: 650)
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 360, height: 650)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            let image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "UbiAir")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "UbiAir"
            button.setAccessibilityLabel("UbiAir")
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        Task {
            if CommandLine.arguments.contains("--ui-smoke-test"), !CommandLine.arguments.contains("--demo") {
                reportFailure("O teste visual exige --demo.")
            }
            await model.restoreSession()
            // Local review opens the same anchored popover used by a menu-bar click.
            if CommandLine.arguments.contains("--ui-smoke-test") { await verifyPopover() }
            else if CommandLine.arguments.contains("--show-panel") { await showWhenReady() }
        }
    }

    private func verifyPopover() async {
        guard model.isDemo else { reportFailure("O teste visual exige --demo.") }
        // Keep the snapshot stable while the test runner owns desktop focus.
        // Ordinary use keeps the transient behavior configured above.
        popover.behavior = .applicationDefined
        popover.animates = false
        await showWhenReady()
        try? await Task.sleep(for: .milliseconds(250))
        guard popover.isShown, let window = popover.contentViewController?.view.window else {
            reportFailure("O popover não abriu ancorado à barra de menus.")
        }
        guard !window.styleMask.contains(.titled) else { reportFailure("O painel criou uma janela com barra de título.") }
        guard statusItem?.button?.window?.isVisible == true, window.isVisible else {
            reportFailure("O painel não está visível junto ao ícone.")
        }
        let previewPath = ProcessInfo.processInfo.environment["UBIAIR_UI_PREVIEW_PATH"]
            ?? ProcessInfo.processInfo.environment["LGTHINQ_UI_PREVIEW_PATH"]
        if let path = previewPath, let view = popover.contentViewController?.view {
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { reportFailure("Não foi possível renderizar a prévia.") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { reportFailure("Não foi possível criar a imagem PNG.") }
            do { try data.write(to: URL(fileURLWithPath: path)) }
            catch { reportFailure("Não foi possível salvar a prévia de demonstração.") }
        }
        popover.close()
        guard !popover.isShown else { reportFailure("O popover não fechou.") }
        togglePopover(nil)
        guard popover.isShown else { reportFailure("O popover não reabriu.") }
        FileHandle.standardError.write(Data("UbiAir UI smoke passou: painel ancorado, sem barra de título, fechamento e reabertura.\n".utf8))
        NSApplication.shared.terminate(nil)
    }

    private func reportFailure(_ message: String) -> Never {
        FileHandle.standardError.write(Data("UI smoke falhou: \(message)\n".utf8))
        exit(1)
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown { popover.performClose(sender) }
        else { showPopover() }
    }

    private func showWhenReady() async {
        // A visible status-item window can still be settling during application launch.
        // This delay is only for development flags; a normal icon click opens immediately.
        try? await Task.sleep(for: .seconds(1))
        for _ in 0..<30 {
            if statusItem?.button?.window?.isVisible == true {
                showPopover()
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.title = "UbiAir"
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool { false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func installMainMenu() {
        let menu = NSMenu()
        let applicationMenu = NSMenu(title: "UbiAir")
        applicationMenu.addItem(withTitle: "Encerrar UbiAir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let applicationItem = NSMenuItem()
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)

        let editMenu = NSMenu(title: "Editar")
        editMenu.addItem(withTitle: "Recortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Colar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Selecionar tudo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApplication.shared.mainMenu = menu
    }
}
