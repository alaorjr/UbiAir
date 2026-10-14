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
    @Published var problem: AppProblem?
    @Published private(set) var deviceProblems: [String: AppProblem] = [:]

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
    var canControl: Bool { isConnected && state != nil && !isBusy && problem?.blocksControls != true }
    var requiresReconnect: Bool { problem?.requiresReconnect == true }
    var automaticRefreshPaused: Bool { requiresReconnect || problem?.kind == .rateLimited }
    var selectedProblem: AppProblem? { selectedID.flatMap { deviceProblems[$0] } }
    func deviceProblem(for id: String) -> AppProblem? { deviceProblems[id] }

    func restoreSession() async {
        if CommandLine.arguments.contains("--demo") {
            let args = CommandLine.arguments
            if let index = args.firstIndex(of: "--demo-error"), args.indices.contains(index + 1),
               let scenario = DemoProblemScenario(rawValue: args[index + 1]) {
                await startDemo(service: DemoProblemService(scenario))
            } else {
                await startDemo()
            }
            return
        }
        do {
            if let token = try credentials.loadToken() {
                await connect(token: token, country: preferences.countryCode, remember: false, restoring: true)
            }
        } catch {
            problem = AppProblem(title: "Não foi possível acessar o Chaves", message: "Informe seu PAT para conectar. Confira a autorização do UbiAir no Chaves do macOS.")
        }
    }

    func connect(token: String, country: String, remember: Bool, restoring: Bool = false) async {
        guard !isBusy else { return }
        let cleanedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedToken.isEmpty else {
            problem = AppProblem(ThinQError.invalidToken)
            return
        }
        resetSession()
        let revision = sessionRevision
        isConnecting = true
        problem = nil
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
                catch { problem = AppProblem(title: "PAT não salvo", message: "A conexão funciona nesta sessão. Confira a autorização do Chaves antes de salvar o PAT novamente.") }
            } else if !restoring {
                do { try credentials.deleteToken() }
                catch { problem = AppProblem(title: "PAT anterior não removido", message: "A conexão funciona, mas o PAT anterior continua salvo no Chaves. Confira a autorização do UbiAir no macOS.") }
            }
            if let first = devices.first { await selectDevice(first.id, refreshOtherDevices: false) }
            schedulePowerRefresh()
        } catch {
            guard revision == sessionRevision else { return }
            isConnecting = false
            if !(error is CancellationError) { problem = AppProblem(error) }
        }
    }

    func startDemo(service demo: any ThinQService = DemoThinQService()) async {
        guard !isBusy else { return }
        resetSession()
        problem = nil
        service = demo
        isDemo = true
        isConnected = true
        do {
            devices = try await demo.devices()
            powerReadsAllowed = true
            if let first = devices.first { await selectDevice(first.id, refreshOtherDevices: false) }
            schedulePowerRefresh()
        } catch { if !(error is CancellationError) { problem = AppProblem(error) } }
    }

    func disconnect() {
        guard !isSending else {
            problem = AppProblem(title: "Comando em andamento", message: "Aguarde a verificação do comando antes de desconectar.")
            return
        }
        let wasDemo = isDemo
        resetSession()
        problem = nil
        if !wasDemo {
            do { try credentials.deleteToken() }
            catch { problem = AppProblem(title: "PAT não removido", message: "A sessão foi encerrada, mas o PAT continua salvo no Chaves. Confira a autorização do UbiAir no macOS.") }
        }
    }

    /// Returns to the PAT form without deleting a saved credential.
    func showConnectionForm() {
        guard !isSending else { return }
        resetSession()
    }

    private func resetSession() {
        powerRefreshTask?.cancel()
        powerRefreshTask = nil
        powerRefreshTaskID = nil
        powerBatchID = nil
        powerReadsAllowed = false
        powerRevisions.removeAll()
        powerStates.removeAll()
        deviceProblems.removeAll()
        problem = nil
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
        guard !isSending, !requiresReconnect, let service, devices.contains(where: { $0.id == id }) else { return }
        selectionRevision = UUID()
        let selection = selectionRevision, session = sessionRevision
        selectedID = id
        state = nil
        capabilities = nil
        isRefreshing = true
        let powerRevision = UUID()
        powerRevisions[id] = powerRevision
        commandMessage = nil
        do {
            let profile = try await service.capabilities(for: id)
            let snapshot = try await service.state(for: id)
            guard selection == selectionRevision, session == sessionRevision else { return }
            capabilities = profile
            state = snapshot
            if powerRevisions[id] == powerRevision {
                setPowerState(snapshot.isOn, for: id)
                deviceProblems.removeValue(forKey: id)
                if problem?.kind == .rateLimited { problem = nil }
            }
        } catch {
            guard selection == selectionRevision, session == sessionRevision else { return }
            if !(error is CancellationError), powerRevisions[id] == powerRevision {
                recordDeviceFailure(error, for: id)
            }
        }
        guard selection == selectionRevision, session == sessionRevision else { return }
        isRefreshing = false
        if refreshOtherDevices { scheduleOtherPowerReads() }
    }

    func refresh() async {
        guard !isBusy, !requiresReconnect, let service, let id = selectedID else { return }
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
            deviceProblems.removeValue(forKey: id)
            if problem?.kind == .rateLimited { problem = nil }
        } catch {
            guard selection == selectionRevision, session == sessionRevision else { return }
            if !(error is CancellationError) {
                recordDeviceFailure(error, for: id)
            }
        }
        guard selection == selectionRevision, session == sessionRevision else { return }
        isRefreshing = false
        schedulePowerRefresh()
    }

    func reloadDevices() async {
        guard !isBusy, !requiresReconnect, let service else { return }
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
            deviceProblems = deviceProblems.filter { retained.contains($0.key) }
            problem = nil
            isRefreshing = false
            if let preferred { await selectDevice(preferred.id, refreshOtherDevices: false) }
            else { selectedID = nil; state = nil; capabilities = nil }
            schedulePowerRefresh()
        } catch {
            guard revision == sessionRevision else { return }
            isRefreshing = false
            if !(error is CancellationError) { problem = AppProblem(error) }
        }
    }

    func send(_ command: ThinQCommand) async {
        guard canControl, let service, let id = selectedID, let capabilities else { return }
        let session = sessionRevision, selection = selectionRevision
        isSending = true
        problem = nil
        commandMessage = isDemo ? "Aplicando na demonstração…" : "Enviando comando…"
        var accepted = false
        do {
            try await service.send(command, to: id, capabilities: capabilities)
            guard session == sessionRevision, selection == selectionRevision else { return }
            accepted = true
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
                deviceProblems.removeValue(forKey: id)
                if command.isConfirmed(by: snapshot) { confirmed = true; break }
            }
            guard session == sessionRevision, selection == selectionRevision else { return }
            commandMessage = confirmed ? (isDemo ? "Atualizado na demonstração" : "Confirmado pela nuvem LG") : nil
            if !confirmed {
                state = nil
                powerStates.removeValue(forKey: id)
                deviceProblems[id] = AppProblem(title: "Comando ainda não confirmado", message: "O comando foi enviado. Atualize o estado antes de tentar novamente.")
            }
        } catch {
            guard session == sessionRevision, selection == selectionRevision else { return }
            commandMessage = nil
            if error is CancellationError {
                state = nil
                powerStates.removeValue(forKey: id)
                deviceProblems[id] = AppProblem(title: "Verificação interrompida", message: "Atualize o estado para conferir o aparelho antes de repetir o comando.")
            } else {
                let kind = (error as? ThinQError)?.kind ?? .unknown
                recordDeviceFailure(error, for: id, commandUncertain: accepted || [.connection, .timeout, .service, .unknown].contains(kind))
            }
        }
        guard session == sessionRevision, selection == selectionRevision else { return }
        isSending = false
    }

    /// Reads each connected non-selected appliance once, serially. Unknown or
    /// failed reads clear the cache so the UI can show an unknown status.
    func refreshDevicePowerStates() async {
        guard isConnected, !automaticRefreshPaused, powerReadsAllowed, let service, powerBatchID == nil else { return }
        let batchID = UUID()
        powerBatchID = batchID
        defer { if powerBatchID == batchID { powerBatchID = nil } }
        let session = sessionRevision
        for device in devices where device.id != selectedID {
            guard session == sessionRevision, !Task.isCancelled, !automaticRefreshPaused else { return }
            guard devices.contains(where: { $0.id == device.id }) else { continue }
            let revision = UUID()
            powerRevisions[device.id] = revision
            do {
                let snapshot = try await service.state(for: device.id)
                guard session == sessionRevision, batchID == powerBatchID, !Task.isCancelled else { return }
                guard powerRevisions[device.id] == revision else { continue }
                setPowerState(snapshot.isOn, for: device.id)
                deviceProblems.removeValue(forKey: device.id)
            } catch {
                guard session == sessionRevision, batchID == powerBatchID, !Task.isCancelled else { return }
                if !(error is CancellationError), powerRevisions[device.id] == revision {
                    recordDeviceFailure(error, for: device.id)
                }
            }
        }
    }

    private func recordDeviceFailure(_ error: Error, for id: String, commandUncertain: Bool = false) {
        let failure = AppProblem(error, commandUncertain: commandUncertain)
        deviceProblems[id] = failure
        powerStates.removeValue(forKey: id)
        if id == selectedID { state = nil }
        if failure.requiresReconnect || failure.kind == .rateLimited { problem = failure }
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
                if self?.automaticRefreshPaused == false { await self?.refresh() }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { break }
                    guard !Task.isCancelled else { break }
                    if self?.automaticRefreshPaused == false { await self?.refresh() }
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
