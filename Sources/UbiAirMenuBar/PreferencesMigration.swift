import Foundation

/// Imports only the two supported preferences from the original app, without
/// overwriting a UbiAir choice or copying credentials and unrelated defaults.
enum PreferencesMigration {
    static let legacyDomain = "br.com.alaorjr.LGThinQ"

    static func copyLegacyValues(from legacy: [String: Any]?, to defaults: UserDefaults) {
        guard let legacy else { return }

        if defaults.object(forKey: "countryCode") == nil,
           let rawCountry = legacy["countryCode"] as? String {
            let country = rawCountry.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if country.utf8.count == 2, country.utf8.allSatisfy({ (65...90).contains($0) }) {
                defaults.set(country, forKey: "countryCode")
            }
        }

        if defaults.object(forKey: "clientID") == nil,
           let clientID = legacy["clientID"] as? String,
           UUID(uuidString: clientID) != nil {
            defaults.set(clientID, forKey: "clientID")
        }
    }
}
