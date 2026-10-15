import Foundation

/// Imports only supported preferences from the previous UbiAir domain, without
/// overwriting current choices or copying credentials and unrelated defaults.
enum PreferencesMigration {
    #if UBIAIR_SANDBOX
    // The sandboxed app reads only its own preferences container.
    static let previousPreferencesDomain: String? = nil
    #else
    static let previousPreferencesDomain = AppIdentity.previousPreferencesDomain
    #endif

    static func copyPreviousValues(from previous: [String: Any]?, to defaults: UserDefaults) {
        guard let previous else { return }

        if defaults.object(forKey: "countryCode") == nil,
           let rawCountry = previous["countryCode"] as? String {
            let country = rawCountry.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if country.utf8.count == 2, country.utf8.allSatisfy({ (65...90).contains($0) }) {
                defaults.set(country, forKey: "countryCode")
            }
        }

        if defaults.object(forKey: "clientID") == nil,
           let clientID = previous["clientID"] as? String,
           UUID(uuidString: clientID) != nil {
            defaults.set(clientID, forKey: "clientID")
        }
    }
}
