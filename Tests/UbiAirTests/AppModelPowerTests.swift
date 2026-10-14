import Foundation
import XCTest
import ThinQCore
@testable import UbiAirMenuBar

@MainActor
final class AppModelPowerTests: XCTestCase {
    func testDemoCachesBothPowerStatesBeforeSelectingSecondDevice() async {
        let model = makeModel()
        await model.startDemo()
        let batchFinished = await awaitPowerRefresh(model)
        XCTAssertTrue(batchFinished)

        XCTAssertEqual(model.powerState(for: DemoThinQService.livingRoomID), true)
        XCTAssertEqual(model.powerState(for: DemoThinQService.bedroomID), false)
    }

    func testSelectionAndCommandUpdateOnlyTheirOwnDevice() async {
        let model = makeModel()
        await model.startDemo()
        let batchFinished = await awaitPowerRefresh(model)
        XCTAssertTrue(batchFinished)

        await model.selectDevice(DemoThinQService.bedroomID)
        XCTAssertEqual(model.powerState(for: DemoThinQService.livingRoomID), true)
        XCTAssertEqual(model.powerState(for: DemoThinQService.bedroomID), false)

        await model.send(.power(true))
        XCTAssertEqual(model.powerState(for: DemoThinQService.livingRoomID), true)
        XCTAssertEqual(model.powerState(for: DemoThinQService.bedroomID), true)
    }

    func testNewDemoSessionAndLogoutClearCachedStatuses() async {
        let model = makeModel()
        await model.startDemo()
        let firstBatchFinished = await awaitPowerRefresh(model)
        XCTAssertTrue(firstBatchFinished)
        XCTAssertNotNil(model.powerState(for: DemoThinQService.bedroomID))

        await model.startDemo()
        let secondBatchFinished = await awaitPowerRefresh(model)
        XCTAssertTrue(secondBatchFinished)
        XCTAssertEqual(model.powerState(for: DemoThinQService.bedroomID), false)

        model.disconnect()
        XCTAssertNil(model.powerState(for: DemoThinQService.livingRoomID))
        XCTAssertNil(model.powerState(for: DemoThinQService.bedroomID))
    }

    func testUnknownAndFailedReadsRemainNeutral() async {
        let unknown = ThinQDevice(id: "unknown", name: "Unknown")
        let failed = ThinQDevice(id: "failed", name: "Failed")
        let first = ThinQDevice(id: "selected", name: "Selected")
        let service = PowerTestService(devices: [first, unknown, failed], states: [
            first.id: ACState(isOn: true), unknown.id: ACState(isOn: nil), failed.id: ACState(isOn: false)
        ])
        let model = makeModel()
        await model.startDemo(service: service)
        let batchFinished = await awaitPowerRefresh(model)
        XCTAssertTrue(batchFinished)

        XCTAssertEqual(model.powerState(for: first.id), true)
        XCTAssertNil(model.powerState(for: unknown.id))
        XCTAssertEqual(model.powerState(for: failed.id), false)

        await service.setFailure(for: failed.id, enabled: true)
        await model.refreshDevicePowerStates()
        XCTAssertNil(model.powerState(for: failed.id))
    }

    func testSessionAndManualRefreshReadEachDeviceExactlyOnce() async {
        let first = ThinQDevice(id: "first", name: "First")
        let second = ThinQDevice(id: "second", name: "Second")
        let service = PowerTestService(devices: [first, second], states: [
            first.id: ACState(isOn: true), second.id: ACState(isOn: false)
        ])
        let model = makeModel()

        await model.startDemo(service: service)
        let sessionBatchFinished = await awaitPowerRefresh(model)
        XCTAssertTrue(sessionBatchFinished)
        let firstSessionReads = await service.readCount(for: first.id)
        let secondSessionReads = await service.readCount(for: second.id)
        XCTAssertEqual(firstSessionReads, 1)
        XCTAssertEqual(secondSessionReads, 1)

        await model.refresh()
        let refreshBatchFinished = await awaitPowerRefresh(model)
        XCTAssertTrue(refreshBatchFinished)
        let firstRefreshReads = await service.readCount(for: first.id)
        let secondRefreshReads = await service.readCount(for: second.id)
        XCTAssertEqual(firstRefreshReads, 2)
        XCTAssertEqual(secondRefreshReads, 2)
    }

    func testDelayedOldSessionReadCannotRestoreCacheAfterDisconnect() async {
        let first = ThinQDevice(id: "selected", name: "Selected")
        let other = ThinQDevice(id: "other", name: "Other")
        let oldService = PowerTestService(devices: [first, other], states: [
            first.id: ACState(isOn: true), other.id: ACState(isOn: true)
        ])
        await oldService.holdNextRead(for: other.id)
        let model = makeModel()

        await model.startDemo(service: oldService)
        await oldService.waitUntilReadStarted(for: other.id)
        let oldBatchCompletion = model.waitForPowerRefresh(timeout: .seconds(5))
        model.disconnect()
        XCTAssertNil(model.powerState(for: first.id))
        XCTAssertNil(model.powerState(for: other.id))

        let newService = PowerTestService(devices: [first, other], states: [
            first.id: ACState(isOn: true), other.id: ACState(isOn: false)
        ])
        await model.startDemo(service: newService)
        let newBatchFinished = await awaitPowerRefresh(model)
        XCTAssertTrue(newBatchFinished)
        XCTAssertEqual(model.powerState(for: other.id), false)

        await oldService.releaseHeldRead(for: other.id)
        let oldBatchFinished = await oldBatchCompletion.value
        XCTAssertTrue(oldBatchFinished)
        XCTAssertEqual(model.powerState(for: other.id), false)
    }

    private func makeModel() -> AppModel {
        let suite = "\(AppIdentity.bundleIdentifier).power-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        return AppModel(preferences: AppPreferences(defaults: defaults, previousDomain: nil))
    }

    private func awaitPowerRefresh(_ model: AppModel) async -> Bool {
        await model.waitForPowerRefresh(timeout: .seconds(5)).value
    }
}

private actor PowerTestService: ThinQService {
    private let sampleDevices: [ThinQDevice]
    private var states: [String: ACState]
    private var failingIDs: Set<String>
    private var readCounts: [String: Int] = [:]
    private var heldReadIDs: Set<String> = []
    private var heldReadContinuations: [String: CheckedContinuation<ACState, Error>] = [:]
    private var startedReadIDs: Set<String> = []
    private var readStartWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private let sampleCapabilities = ACCapabilities(
        canControlPower: true,
        modes: [],
        fanSpeeds: [],
        temperature: nil,
        canControlVerticalSwing: false,
        canControlHorizontalSwing: false
    )

    init(devices: [ThinQDevice], states: [String: ACState], failingIDs: Set<String> = []) {
        self.sampleDevices = devices
        self.states = states
        self.failingIDs = failingIDs
    }

    func devices() async throws -> [ThinQDevice] { sampleDevices }

    func setFailure(for id: String, enabled: Bool) {
        if enabled { failingIDs.insert(id) } else { failingIDs.remove(id) }
    }

    func readCount(for id: String) -> Int { readCounts[id, default: 0] }

    func holdNextRead(for id: String) { heldReadIDs.insert(id) }

    func waitUntilReadStarted(for id: String) async {
        if startedReadIDs.contains(id) { return }
        await withCheckedContinuation { continuation in
            readStartWaiters[id, default: []].append(continuation)
        }
    }

    func releaseHeldRead(for id: String) {
        guard let continuation = heldReadContinuations.removeValue(forKey: id),
              let state = states[id] else { return }
        continuation.resume(returning: state)
    }

    func capabilities(for id: String) async throws -> ACCapabilities {
        sampleCapabilities
    }

    func state(for id: String) async throws -> ACState {
        readCounts[id, default: 0] += 1
        if startedReadIDs.insert(id).inserted {
            let waiters = readStartWaiters.removeValue(forKey: id) ?? []
            for waiter in waiters { waiter.resume() }
        }
        if heldReadIDs.remove(id) != nil {
            return try await withCheckedThrowingContinuation { heldReadContinuations[id] = $0 }
        }
        if failingIDs.contains(id) { throw PowerTestError.readFailed }
        guard let state = states[id] else { throw PowerTestError.readFailed }
        return state
    }

    func send(_ command: ThinQCommand, to id: String, capabilities: ACCapabilities) async throws {
        guard case .power(let enabled) = command, var state = states[id] else { return }
        state.isOn = enabled
        states[id] = state
    }
}

private enum PowerTestError: Error {
    case readFailed
}
