import Foundation
import XCTest
@testable import UbiAirMenuBar

final class PreferencesMigrationTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "ai.ubiquu.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    func testImportsValidSettingsAndKeepsClientIdentity() {
        withDefaults { defaults in
            let clientID = UUID().uuidString
            PreferencesMigration.copyLegacyValues(from: ["countryCode": " br ", "clientID": clientID, "unrelated": "ignored"], to: defaults)
            XCTAssertEqual(defaults.string(forKey: "countryCode"), "BR")
            XCTAssertEqual(defaults.string(forKey: "clientID"), clientID)
            XCTAssertNil(defaults.object(forKey: "unrelated"))
        }
    }

    func testExistingUbiAirChoicesTakePrecedencePerField() {
        withDefaults { defaults in
            let clientID = UUID().uuidString
            defaults.set("US", forKey: "countryCode")
            PreferencesMigration.copyLegacyValues(from: ["countryCode": "BR", "clientID": clientID], to: defaults)
            XCTAssertEqual(defaults.string(forKey: "countryCode"), "US")
            XCTAssertEqual(defaults.string(forKey: "clientID"), clientID)

            PreferencesMigration.copyLegacyValues(from: ["countryCode": "CA", "clientID": UUID().uuidString], to: defaults)
            XCTAssertEqual(defaults.string(forKey: "countryCode"), "US")
            XCTAssertEqual(defaults.string(forKey: "clientID"), clientID)
        }
    }

    func testMalformedLegacyValuesAreNotImported() {
        withDefaults { defaults in
            for legacy in [["countryCode": "B1", "clientID": "invalid"], ["countryCode": "BRA", "clientID": ""], ["countryCode": 42, "clientID": 10]] as [[String: Any]] {
                PreferencesMigration.copyLegacyValues(from: legacy, to: defaults)
            }
            XCTAssertNil(defaults.object(forKey: "countryCode"))
            XCTAssertNil(defaults.object(forKey: "clientID"))
        }
    }

    func testAbsentLegacyDomainLeavesNewPreferencesIntact() {
        withDefaults { defaults in
            let clientID = UUID().uuidString
            defaults.set("BR", forKey: "countryCode")
            defaults.set(clientID, forKey: "clientID")
            PreferencesMigration.copyLegacyValues(from: nil, to: defaults)
            XCTAssertEqual(defaults.string(forKey: "countryCode"), "BR")
            XCTAssertEqual(defaults.string(forKey: "clientID"), clientID)
        }
    }
}
