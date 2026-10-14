import Foundation
import XCTest
import ThinQCore
@testable import UbiAirMenuBar

@MainActor
final class AppModelFailureTests: XCTestCase {
    func testSelectedDeviceOfflineClearsStateAndRefreshRecovers() async {
        let device = ThinQDevice(id: "selected", name: "Selected")
        let service = FailureTestService(devices: [device], states: [device.id: ACState(isOn: true)])
        let model = makeModel()
        await model.startDemo(service: service)

        await service.failNextRead(for: device.id, with: ThinQError.api(code: "1222", message: "offline"))
        await model.refresh()

        XCTAssertNil(model.state)
        XCTAssertEqual(model.selectedProblem?.kind, .offline)
        XCTAssertFalse(model.canControl)

        await model.refresh()
        XCTAssertEqual(model.state?.isOn, true)
        XCTAssertNil(model.selectedProblem)
        XCTAssertTrue(model.canControl)
    }

    func testTimeoutAndUnknownReadFailuresKeepTheirOwnKinds() async {
        let failures: [(any Error, ThinQFailureKind)] = [
            (ThinQError.timeout, .timeout), (ThinQError.noInternet, .connection),
            (FailureTestError(), .unknown)
        ]
        for (error, expectedKind) in failures {
            let device = ThinQDevice(id: UUID().uuidString, name: "Selected")
            let service = FailureTestService(devices: [device], states: [device.id: ACState(isOn: true)])
            let model = makeModel()
            await model.startDemo(service: service)
            await service.failNextRead(for: device.id, with: error)

            await model.refresh()

            XCTAssertEqual(model.selectedProblem?.kind, expectedKind)
            XCTAssertNil(model.state)
            XCTAssertFalse(model.canControl)
        }
    }

    func testOfflineAuxiliaryReadDoesNotContaminateSelectedControls() async {
        let selected = ThinQDevice(id: "selected", name: "Selected")
        let auxiliary = ThinQDevice(id: "auxiliary", name: "Auxiliary")
        let service = FailureTestService(devices: [selected, auxiliary], states: [
            selected.id: ACState(isOn: true), auxiliary.id: ACState(isOn: false)
        ])
        let model = makeModel()
        await model.startDemo(service: service)
        _ = await model.waitForPowerRefresh().value

        await service.failNextRead(for: auxiliary.id, with: ThinQError.api(code: "1222", message: "offline"))
        await model.refreshDevicePowerStates()

        XCTAssertEqual(model.deviceProblem(for: auxiliary.id)?.kind, .offline)
        XCTAssertEqual(model.state?.isOn, true)
        XCTAssertNil(model.selectedProblem)
        XCTAssertNil(model.problem)
        XCTAssertTrue(model.canControl)
    }

    func testAcceptedCommandWithFailedVerificationRequiresManualRefreshBeforeRetry() async {
        let device = ThinQDevice(id: "selected", name: "Selected")
        let service = FailureTestService(devices: [device], states: [device.id: ACState(isOn: false)])
        let model = makeModel()
        await model.startDemo(service: service)
        await service.failNextRead(for: device.id, with: ThinQError.timeout)

        await model.send(.power(true))

        let sendsAfterFailure = await service.sendCount()
        XCTAssertEqual(sendsAfterFailure, 1)
        XCTAssertNil(model.state)
        XCTAssertFalse(model.canControl)
        XCTAssertTrue(model.selectedProblem?.message.contains("Atualize o estado antes de repetir") == true)
        let readsAfterFailure = await service.readCount(for: device.id)
        XCTAssertEqual(readsAfterFailure, 2)

        await model.send(.power(true))
        let sendsAfterBlockedRetry = await service.sendCount()
        let readsAfterBlockedRetry = await service.readCount(for: device.id)
        XCTAssertEqual(sendsAfterBlockedRetry, 1)
        XCTAssertEqual(readsAfterBlockedRetry, 2)
    }

    func testAuthenticationFailureRequiresReconnectAndReturnsToFormWithoutCredentialAccess() async {
        let service = FailureTestService(devices: [], states: [:], deviceFailure: ThinQError.invalidToken)
        let model = makeModel()
        await model.startDemo(service: service)

        XCTAssertTrue(model.requiresReconnect)
        XCTAssertEqual(model.problem?.kind, .authentication)

        model.showConnectionForm()

        XCTAssertFalse(model.isConnected)
        XCTAssertFalse(model.requiresReconnect)
        XCTAssertNil(model.problem)
        XCTAssertTrue(model.devices.isEmpty)
    }

    func testAuthenticationFailureDuringSelectedReadRequiresReconnect() async {
        let device = ThinQDevice(id: "selected-auth", name: "Selected")
        let service = FailureTestService(devices: [device], states: [device.id: ACState(isOn: true)])
        let model = makeModel()
        await model.startDemo(service: service)
        await service.failNextRead(for: device.id, with: ThinQError.api(code: "1103", message: "auth"))

        await model.refresh()

        XCTAssertNil(model.state)
        XCTAssertEqual(model.selectedProblem?.kind, .authentication)
        XCTAssertEqual(model.problem?.kind, .authentication)
        XCTAssertTrue(model.requiresReconnect)
        XCTAssertFalse(model.canControl)
    }

    func testCancelledRefreshPreservesStateAndDoesNotInventProblem() async {
        let device = ThinQDevice(id: "selected", name: "Selected")
        let service = FailureTestService(devices: [device], states: [device.id: ACState(isOn: true)])
        let model = makeModel()
        await model.startDemo(service: service)
        await service.failNextRead(for: device.id, with: CancellationError())

        await model.refresh()

        XCTAssertEqual(model.state?.isOn, true)
        XCTAssertNil(model.selectedProblem)
        XCTAssertNil(model.problem)
        XCTAssertTrue(model.canControl)
    }

    func testEmptyDeviceListRemainsConnectedAndReloadCanRecover() async {
        let device = ThinQDevice(id: "later", name: "Later")
        let service = FailureTestService(devices: [], states: [device.id: ACState(isOn: true)])
        let model = makeModel()
        await model.startDemo(service: service)

        XCTAssertTrue(model.isConnected)
        XCTAssertTrue(model.devices.isEmpty)
        XCTAssertNil(model.problem)

        await service.setDevices([device])
        await model.reloadDevices()

        XCTAssertTrue(model.isConnected)
        XCTAssertEqual(model.selectedID, device.id)
        XCTAssertEqual(model.state?.isOn, true)
    }

    func testRateLimitPausesAutomaticReadsUntilManualRefreshSucceeds() async {
        let selected = ThinQDevice(id: "selected-rate", name: "Selected")
        let auxiliary = ThinQDevice(id: "aux-rate", name: "Auxiliary")
        let service = FailureTestService(devices: [selected, auxiliary], states: [
            selected.id: ACState(isOn: true), auxiliary.id: ACState(isOn: false)
        ])
        let model = makeModel()
        await model.startDemo(service: service)
        _ = await model.waitForPowerRefresh().value

        await service.failNextRead(for: selected.id, with: ThinQError.httpStatus(429))
        await model.refresh()

        XCTAssertTrue(model.automaticRefreshPaused)
        XCTAssertFalse(model.canControl)
        let readsBeforePausedBatch = await service.readCount(for: auxiliary.id)
        await model.refreshDevicePowerStates()
        let readsDuringPausedBatch = await service.readCount(for: auxiliary.id)
        XCTAssertEqual(readsDuringPausedBatch, readsBeforePausedBatch)

        await model.refresh()
        XCTAssertFalse(model.automaticRefreshPaused)
        XCTAssertNil(model.selectedProblem)
        XCTAssertTrue(model.canControl)

        await model.refreshDevicePowerStates()
        let readsAfterRecoveryBatch = await service.readCount(for: auxiliary.id)
        XCTAssertEqual(readsAfterRecoveryBatch, readsBeforePausedBatch + 1)
    }

    func testDeviceReloadServerFailureBlocksControlsUntilReloadRecovers() async {
        let device = ThinQDevice(id: "reload", name: "Reload")
        let service = FailureTestService(devices: [device], states: [device.id: ACState(isOn: true)])
        let model = makeModel()
        await model.startDemo(service: service)

        await service.failNextDevices(with: ThinQError.httpStatus(503))
        await model.reloadDevices()

        XCTAssertEqual(model.problem?.kind, .service)
        XCTAssertFalse(model.canControl)

        await model.reloadDevices()

        XCTAssertNil(model.problem)
        XCTAssertTrue(model.canControl)
        XCTAssertEqual(model.selectedID, device.id)
        XCTAssertEqual(model.state?.isOn, true)
    }

    private func makeModel() -> AppModel {
        let suite = "\(AppIdentity.bundleIdentifier).failure-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(preferences: AppPreferences(defaults: defaults, previousDomain: nil))
        return model
    }
}

private actor FailureTestService: ThinQService {
    private var sampleDevices: [ThinQDevice]
    private var states: [String: ACState]
    private var readFailures: [String: [Error]] = [:]
    private var deviceFailures: [Error] = []
    private let deviceFailure: Error?
    private var sends = 0
    private var reads: [String: Int] = [:]
    private let sampleCapabilities = ACCapabilities(canControlPower: true)

    init(devices: [ThinQDevice], states: [String: ACState], deviceFailure: Error? = nil) {
        sampleDevices = devices
        self.states = states
        self.deviceFailure = deviceFailure
    }

    func devices() async throws -> [ThinQDevice] {
        if !deviceFailures.isEmpty { throw deviceFailures.removeFirst() }
        if let deviceFailure { throw deviceFailure }
        return sampleDevices
    }

    func setDevices(_ devices: [ThinQDevice]) { sampleDevices = devices }

    func failNextDevices(with error: Error) { deviceFailures.append(error) }

    func failNextRead(for id: String, with error: Error) {
        readFailures[id, default: []].append(error)
    }

    func readCount(for id: String) -> Int { reads[id, default: 0] }
    func sendCount() -> Int { sends }

    func capabilities(for id: String) async throws -> ACCapabilities { sampleCapabilities }

    func state(for id: String) async throws -> ACState {
        reads[id, default: 0] += 1
        if var failures = readFailures[id], !failures.isEmpty {
            let error = failures.removeFirst()
            readFailures[id] = failures
            throw error
        }
        guard let state = states[id] else { throw FailureTestError() }
        return state
    }

    func send(_ command: ThinQCommand, to id: String, capabilities: ACCapabilities) async throws {
        sends += 1
        // The test intentionally leaves the reported state unchanged so the
        // post-acceptance verification path is exercised without a physical device.
    }
}

private struct FailureTestError: Error {}
