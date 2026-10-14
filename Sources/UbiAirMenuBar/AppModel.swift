import Foundation
import SwiftUI
import ThinQCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var devices: [ThinQDevice] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var capabilities: ACCapabilities?
    @Published private(set) var state: ACState?
    @Published private(set) var powerStates: [String: Bool] = [:]
    @Published private(set) var isConnected = false
    @Published private(set) var isDemo = false
    @Published private(set) var isConnecting = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSending = false
    @Published private(set) var commandMessage: String?
    @Published var errorMessage: String?

    let preferences: AppPreferences
    private let credentials = CredentialStore()
    private var service: (any ThinQService)?
    private var sessionRevision = UUID()
    private var selectionRevision = UUID()
    private var visiblePanels: Set<UUID> = []
    private var pollingTask: Task<Void, Never>?
    private var powerRefreshTask: Task<Void, Never>?
    private var powerRevisions: [String: UUID] = [:]
    private var powerBatchID: UUID?
    private var powerRefreshTaskID: UUID?
    private var powerReadsAllowed = false

    init(preferences: AppPreferences? = nil) {
        self.preferences = preferences ?? AppPreferences()
    }

    var selectedDevice: ThinQDevice? { devices.first { $0.id == selectedID } }
    func powerState(for id: String) -> Bool? { powerStates[id] }
    var isBusy: Bool { isConnecting || isRefreshing || isSending }
    var canControl: Bool { isConnected && state != nil && !isBusy }

    func restoreSession() async {
        if CommandLine.arguments.contains("--demo") {
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
            powerReadsAllowed = true
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
            if let first = devices.first { await selectDevice(first.id, refreshOtherDevices: false) }
            schedulePowerRefresh()
        } catch {
            guard revision == sessionRevision else { return }
            isConnecting = false
            errorMessage = error.localizedDescription
        }
    }

    func startDemo(service demo: any ThinQService = DemoThinQService()) async {
        guard !isBusy else { return }
        resetSession()
        errorMessage = nil
        service = demo
        isDemo = true
        isConnected = true
        do {
            devices = try await demo.devices()
            powerReadsAllowed = true
            if let first = devices.first { await selectDevice(first.id, refreshOtherDevices: false) }
            schedulePowerRefresh()
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
        powerRefreshTask?.cancel()
        powerRefreshTask = nil
        powerRefreshTaskID = nil
        powerBatchID = nil
        powerReadsAllowed = false
        powerRevisions.removeAll()
        powerStates.removeAll()
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

    func selectDevice(_ id: String, refreshOtherDevices: Bool = true) async {
        guard !isSending, let service, devices.contains(where: { $0.id == id }) else { return }
        selectionRevision = UUID()
        let selection = selectionRevision, session = sessionRevision
        selectedID = id
        state = nil
        capabilities = nil
        isRefreshing = true
        let powerRevision = UUID()
        powerRevisions[id] = powerRevision
        commandMessage = nil
        var attemptedStateRead = false
        do {
            let profile = try await service.capabilities(for: id)
            attemptedStateRead = true
            let snapshot = try await service.state(for: id)
            guard selection == selectionRevision, session == sessionRevision else { return }
            capabilities = profile
            state = snapshot
            if powerRevisions[id] == powerRevision { setPowerState(snapshot.isOn, for: id) }
        } catch {
            guard selection == selectionRevision, session == sessionRevision else { return }
            errorMessage = error.localizedDescription
            if attemptedStateRead, !(error is CancellationError), powerRevisions[id] == powerRevision {
                powerStates.removeValue(forKey: id)
            }
        }
        guard selection == selectionRevision, session == sessionRevision else { return }
        isRefreshing = false
        if refreshOtherDevices { scheduleOtherPowerReads() }
    }

    func refresh() async {
        guard !isBusy, let service, let id = selectedID else { return }
        if capabilities == nil {
            await selectDevice(id, refreshOtherDevices: false)
            schedulePowerRefresh()
            return
        }
        let selection = selectionRevision, session = sessionRevision
        isRefreshing = true
        do {
            let powerRevision = UUID()
            powerRevisions[id] = powerRevision
            let snapshot = try await service.state(for: id)
            guard selection == selectionRevision, session == sessionRevision else { return }
            guard powerRevisions[id] == powerRevision else { return }
            state = snapshot
            setPowerState(snapshot.isOn, for: id)
            errorMessage = nil
        } catch {
            guard selection == selectionRevision, session == sessionRevision else { return }
            if !(error is CancellationError) {
                state = nil
                powerStates.removeValue(forKey: id)
                errorMessage = error.localizedDescription
            }
        }
        guard selection == selectionRevision, session == sessionRevision else { return }
        isRefreshing = false
        schedulePowerRefresh()
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
            let retained = Set(discovered.map(\.id))
            powerStates = powerStates.filter { retained.contains($0.key) }
            powerRevisions = powerRevisions.filter { retained.contains($0.key) }
            isRefreshing = false
            if let preferred { await selectDevice(preferred.id, refreshOtherDevices: false) }
            else { selectedID = nil; state = nil; capabilities = nil }
            schedulePowerRefresh()
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
                let powerRevision = UUID()
                powerRevisions[id] = powerRevision
                let snapshot = try await service.state(for: id)
                guard session == sessionRevision, selection == selectionRevision else { return }
                guard powerRevisions[id] == powerRevision else { continue }
                state = snapshot
                setPowerState(snapshot.isOn, for: id)
                if command.isConfirmed(by: snapshot) { confirmed = true; break }
            }
            guard session == sessionRevision, selection == selectionRevision else { return }
            commandMessage = confirmed ? (isDemo ? "Atualizado na demonstração" : "Confirmado pela nuvem LG") : nil
            if !confirmed { errorMessage = "O comando foi enviado, mas ainda não foi confirmado pela nuvem. Atualize o estado antes de tentar novamente." }
        } catch {
            guard session == sessionRevision, selection == selectionRevision else { return }
            if !(error is CancellationError) { powerStates.removeValue(forKey: id) }
            commandMessage = nil
            errorMessage = error is CancellationError ? "Verificação cancelada. Atualize o estado para conferir o aparelho." : error.localizedDescription
        }
        guard session == sessionRevision, selection == selectionRevision else { return }
        isSending = false
    }

    /// Reads each connected non-selected appliance once, serially. Unknown or
    /// failed reads clear the cache so the UI can show an unknown status.
    func refreshDevicePowerStates() async {
        guard isConnected, powerReadsAllowed, let service, powerBatchID == nil else { return }
        let batchID = UUID()
        powerBatchID = batchID
        defer { if powerBatchID == batchID { powerBatchID = nil } }
        let session = sessionRevision
        for device in devices where device.id != selectedID {
            guard session == sessionRevision, !Task.isCancelled else { return }
            guard devices.contains(where: { $0.id == device.id }) else { continue }
            let revision = UUID()
            powerRevisions[device.id] = revision
            do {
                let snapshot = try await service.state(for: device.id)
                guard session == sessionRevision, batchID == powerBatchID, !Task.isCancelled else { return }
                guard powerRevisions[device.id] == revision else { continue }
                setPowerState(snapshot.isOn, for: device.id)
            } catch {
                guard session == sessionRevision, batchID == powerBatchID, !Task.isCancelled else { return }
                if !(error is CancellationError), powerRevisions[device.id] == revision {
                    powerStates.removeValue(forKey: device.id)
                }
            }
        }
    }

    private func setPowerState(_ value: Bool?, for id: String) {
        if let value { powerStates[id] = value }
        else { powerStates.removeValue(forKey: id) }
    }

    private func scheduleOtherPowerReads() {
        guard powerReadsAllowed, powerRefreshTaskID == nil, !visiblePanels.isEmpty else { return }
        schedulePowerRefresh()
    }

    /// Capture the current batch before yielding, so a caller can await even a
    /// batch that is invalidated by a later session change.
    func waitForPowerRefresh(timeout: Duration = .seconds(5)) -> Task<Bool, Never> {
        let task = powerRefreshTask
        return Task {
            guard let task else { return true }
            return await withCheckedContinuation { continuation in
                let waiter = PowerRefreshWaiter(continuation)
                Task {
                    await task.value
                    await waiter.finish(true)
                }
                Task {
                    try? await Task.sleep(for: timeout)
                    await waiter.finish(false)
                }
            }
        }
    }

    private func schedulePowerRefresh() {
        guard powerReadsAllowed, powerRefreshTaskID == nil else { return }
        let taskID = UUID()
        powerRefreshTaskID = taskID
        powerRefreshTask = Task { [weak self] in
            await self?.refreshDevicePowerStates()
            if self?.powerRefreshTaskID == taskID { self?.powerRefreshTaskID = nil; self?.powerRefreshTask = nil }
        }
    }

    func panelVisibilityChanged(id: UUID, visible: Bool) {
        if visible { visiblePanels.insert(id) } else { visiblePanels.remove(id) }
        if visiblePanels.isEmpty {
            pollingTask?.cancel()
            pollingTask = nil
            powerReadsAllowed = false
            powerRefreshTask?.cancel()
            powerRefreshTask = nil
            powerRefreshTaskID = nil
            powerBatchID = nil
        } else if pollingTask == nil {
            powerReadsAllowed = true
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

private actor PowerRefreshWaiter {
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func finish(_ result: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: result)
    }
}
