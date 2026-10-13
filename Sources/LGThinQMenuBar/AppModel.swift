import Foundation
import SwiftUI
import ThinQCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var devices: [ThinQDevice] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var capabilities: ACCapabilities?
    @Published private(set) var state: ACState?
    @Published private(set) var isConnected = false
    @Published private(set) var isDemo = false
    @Published private(set) var isConnecting = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSending = false
    @Published private(set) var commandMessage: String?
    @Published var errorMessage: String?

    let preferences = AppPreferences()
    private let credentials = CredentialStore()
    private var service: (any ThinQService)?
    private var sessionRevision = UUID()
    private var selectionRevision = UUID()
    private var visiblePanels: Set<UUID> = []
    private var pollingTask: Task<Void, Never>?

    var selectedDevice: ThinQDevice? { devices.first { $0.id == selectedID } }
    var isBusy: Bool { isConnecting || isRefreshing || isSending }
    var canControl: Bool { isConnected && state != nil && !isBusy }

    func restoreSession() async {
        if CommandLine.arguments.contains("--demo") || CommandLine.arguments.contains("--preview") {
            await startDemo()
            return
        }
        do {
            if let token = try credentials.loadToken() {
                await connect(token: token, country: preferences.countryCode, remember: false, restoring: true)
            }
        } catch {
            errorMessage = "Não foi possível ler o token no Chaves. \(error.localizedDescription)"
        }
    }

    func connect(token: String, country: String, remember: Bool, restoring: Bool = false) async {
        guard !isBusy else { return }
        let cleanedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedToken.isEmpty else {
            errorMessage = "Informe seu token pessoal ThinQ."
            return
        }
        resetSession()
        let revision = sessionRevision
        isConnecting = true
        errorMessage = nil
        do {
            let countryCode = country.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let client = try ThinQClient(token: cleanedToken, countryCode: countryCode, clientID: preferences.clientID)
            let discovered = try await client.devices()
            guard revision == sessionRevision else { return }
            service = client
            devices = discovered
            preferences.countryCode = countryCode
            isConnected = true
            isConnecting = false
            if remember {
                do { try credentials.saveToken(cleanedToken) }
                catch { errorMessage = "Conectado, mas o token não foi salvo no Chaves. \(error.localizedDescription)" }
            } else if !restoring {
                do { try credentials.deleteToken() }
                catch { errorMessage = "Conectado, mas o token anteriormente salvo não foi removido do Chaves. \(error.localizedDescription)" }
            }
            if let first = devices.first { await selectDevice(first.id) }
        } catch {
            guard revision == sessionRevision else { return }
            isConnecting = false
            errorMessage = error.localizedDescription
        }
    }

    func startDemo() async {
        guard !isBusy else { return }
        resetSession()
        errorMessage = nil
        let demo = DemoThinQService()
        service = demo
        isDemo = true
        isConnected = true
        do {
            devices = try await demo.devices()
            if let first = devices.first { await selectDevice(first.id) }
        } catch { errorMessage = error.localizedDescription }
    }

    func disconnect() {
        guard !isSending else {
            errorMessage = "Aguarde a verificação do comando antes de desconectar."
            return
        }
        let wasDemo = isDemo
        resetSession()
        errorMessage = nil
        if !wasDemo {
            do { try credentials.deleteToken() }
            catch { errorMessage = "Sessão encerrada, mas não foi possível remover o token do Chaves. \(error.localizedDescription)" }
        }
    }

    private func resetSession() {
        sessionRevision = UUID()
        selectionRevision = UUID()
        service = nil
        devices = []
        selectedID = nil
        capabilities = nil
        state = nil
        isConnected = false
        isDemo = false
        isConnecting = false
        isRefreshing = false
        isSending = false
        commandMessage = nil
    }

    func selectDevice(_ id: String) async {
        guard !isSending, let service, devices.contains(where: { $0.id == id }) else { return }
        selectionRevision = UUID()
        let selection = selectionRevision, session = sessionRevision
        selectedID = id
        state = nil
        capabilities = nil
        isRefreshing = true
        commandMessage = nil
        do {
            let profile = try await service.capabilities(for: id)
            let snapshot = try await service.state(for: id)
            guard selection == selectionRevision, session == sessionRevision else { return }
            capabilities = profile
            state = snapshot
        } catch {
            guard selection == selectionRevision, session == sessionRevision else { return }
            errorMessage = error.localizedDescription
        }
        guard selection == selectionRevision, session == sessionRevision else { return }
        isRefreshing = false
    }

    func refresh() async {
        guard !isBusy, let service, let id = selectedID else { return }
        if capabilities == nil { await selectDevice(id); return }
        let selection = selectionRevision, session = sessionRevision
        isRefreshing = true
        do {
            let snapshot = try await service.state(for: id)
            guard selection == selectionRevision, session == sessionRevision else { return }
            state = snapshot
            errorMessage = nil
        } catch {
            guard selection == selectionRevision, session == sessionRevision else { return }
            if !(error is CancellationError) {
                state = nil
                errorMessage = error.localizedDescription
            }
        }
        guard selection == selectionRevision, session == sessionRevision else { return }
        isRefreshing = false
    }

    func reloadDevices() async {
        guard !isBusy, let service else { return }
        let revision = sessionRevision
        isRefreshing = true
        do {
            let discovered = try await service.devices()
            guard revision == sessionRevision else { return }
            let preferred = discovered.first { $0.id == selectedID } ?? discovered.first
            devices = discovered
            isRefreshing = false
            if let preferred { await selectDevice(preferred.id) }
            else { selectedID = nil; state = nil; capabilities = nil }
        } catch {
            guard revision == sessionRevision else { return }
            isRefreshing = false
            errorMessage = error.localizedDescription
        }
    }

    func send(_ command: ThinQCommand) async {
        guard canControl, let service, let id = selectedID, let capabilities else { return }
        let session = sessionRevision, selection = selectionRevision
        isSending = true
        errorMessage = nil
        commandMessage = isDemo ? "Aplicando na demonstração…" : "Enviando comando…"
        do {
            try await service.send(command, to: id, capabilities: capabilities)
            guard session == sessionRevision, selection == selectionRevision else { return }
            commandMessage = "Aguardando confirmação…"
            var confirmed = false
            for attempt in 0..<4 {
                if attempt > 0 { try await Task.sleep(for: .seconds(2)) }
                try Task.checkCancellation()
                let snapshot = try await service.state(for: id)
                guard session == sessionRevision, selection == selectionRevision else { return }
                state = snapshot
                if command.isConfirmed(by: snapshot) { confirmed = true; break }
            }
            guard session == sessionRevision, selection == selectionRevision else { return }
            commandMessage = confirmed ? (isDemo ? "Atualizado na demonstração" : "Confirmado pela nuvem LG") : nil
            if !confirmed { errorMessage = "O comando foi enviado, mas ainda não foi confirmado pela nuvem. Atualize o estado antes de tentar novamente." }
        } catch {
            guard session == sessionRevision, selection == selectionRevision else { return }
            commandMessage = nil
            errorMessage = error is CancellationError ? "Verificação cancelada. Atualize o estado para conferir o aparelho." : error.localizedDescription
        }
        guard session == sessionRevision, selection == selectionRevision else { return }
        isSending = false
    }

    func panelVisibilityChanged(id: UUID, visible: Bool) {
        if visible { visiblePanels.insert(id) } else { visiblePanels.remove(id) }
        if visiblePanels.isEmpty {
            pollingTask?.cancel()
            pollingTask = nil
        } else if pollingTask == nil {
            pollingTask = Task { [weak self] in
                await self?.refresh()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { break }
                    guard !Task.isCancelled else { break }
                    await self?.refresh()
                }
            }
        }
    }
}
