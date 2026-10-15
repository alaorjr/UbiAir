import Foundation
import XCTest
import ThinQCore
@testable import UbiAirMenuBar

@MainActor
final class TemperatureControlTests: XCTestCase {
    func testWholeDegreeControlsMoveOneStepInEitherDirection() throws {
        let range = TemperatureCapability(minimum: 16, maximum: 30, step: 1)

        XCTAssertEqual(MenuPanel.nextTemperature(-1, state: ACState(targetTemperature: 23), range: range), 22)
        XCTAssertEqual(MenuPanel.nextTemperature(-1, state: ACState(targetTemperature: 22), range: range), 21)
        XCTAssertEqual(MenuPanel.nextTemperature(1, state: ACState(targetTemperature: 21), range: range), 22)
    }

    func testControlsStopAtMinimumAndMaximum() throws {
        let range = TemperatureCapability(minimum: 16, maximum: 30, step: 1)

        XCTAssertNil(MenuPanel.nextTemperature(-1, state: ACState(targetTemperature: 16), range: range))
        XCTAssertNil(MenuPanel.nextTemperature(1, state: ACState(targetTemperature: 30), range: range))
    }

    func testFractionalStepsSkipExceptionsAndRoundOffGridStateByDirection() throws {
        let range = TemperatureCapability(minimum: 19, maximum: 22, step: 0.5, except: [20])

        XCTAssertEqual(MenuPanel.nextTemperature(-0.5, state: ACState(targetTemperature: 20.5), range: range), 19.5)
        XCTAssertEqual(MenuPanel.nextTemperature(0.5, state: ACState(targetTemperature: 19.5), range: range), 20.5)
        XCTAssertEqual(MenuPanel.nextTemperature(-0.5, state: ACState(targetTemperature: 21.25), range: range), 21)
        XCTAssertEqual(MenuPanel.nextTemperature(0.5, state: ACState(targetTemperature: 21.25), range: range), 21.5)
    }

    func testMissingTemperatureOrInvalidStepHasNoNextValue() throws {
        let range = TemperatureCapability(minimum: 16, maximum: 30, step: 1)
        let invalidStep = TemperatureCapability(minimum: 16, maximum: 30, step: 0)

        XCTAssertNil(MenuPanel.nextTemperature(-1, state: ACState(), range: range))
        XCTAssertNil(MenuPanel.nextTemperature(1, state: ACState(targetTemperature: 23), range: invalidStep))
    }

    func testPanelHandlerAppliesTwoDecreasesAndOneIncreaseToDemoService() async throws {
        let suite = "\(AppIdentity.bundleIdentifier).temperature-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = AppModel(preferences: AppPreferences(defaults: defaults, previousDomain: nil))
        await model.startDemo()

        let initialState = try XCTUnwrap(model.state)
        let range = try XCTUnwrap(model.capabilities?.temperature)
        XCTAssertEqual(initialState.targetTemperature, 23)

        let panel = MenuPanel(model: model)
        let firstDecrease = try XCTUnwrap(panel.changeTemperature(-range.step, state: initialState, range: range))
        await firstDecrease.value
        XCTAssertEqual(model.state?.targetTemperature, 22)

        let secondState = try XCTUnwrap(model.state)
        let secondDecrease = try XCTUnwrap(panel.changeTemperature(-range.step, state: secondState, range: range))
        await secondDecrease.value
        XCTAssertEqual(model.state?.targetTemperature, 21)

        let thirdState = try XCTUnwrap(model.state)
        let increase = try XCTUnwrap(panel.changeTemperature(range.step, state: thirdState, range: range))
        await increase.value
        XCTAssertEqual(model.state?.targetTemperature, 22)
    }
}
