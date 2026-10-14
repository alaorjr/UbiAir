import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppPreferences: ObservableObject {
    private enum Key {
        static let countryCode = "countryCode"
        static let clientID = "clientID"
    }

    private let defaults: UserDefaults

    @Published var countryCode: String {
        didSet { defaults.set(countryCode, forKey: Key.countryCode) }
    }

    let clientID: String

    @Published private(set) var launchAtLogin = false
    @Published private(set) var requiresApproval = false
    @Published var loginMessage: String?

    init(defaults: UserDefaults = .standard, previousDomain: String? = PreferencesMigration.previousPreferencesDomain) {
        self.defaults = defaults
        if let previousDomain {
            PreferencesMigration.copyPreviousValues(
                from: defaults.persistentDomain(forName: previousDomain),
                to: defaults
            )
        }

        let savedCountry = defaults.string(forKey: Key.countryCode)
        self.countryCode = savedCountry.flatMap { $0.isEmpty ? nil : $0 } ?? "BR"

        if let savedClientID = defaults.string(forKey: Key.clientID),
           UUID(uuidString: savedClientID) != nil {
            self.clientID = savedClientID
        } else {
            let newClientID = UUID().uuidString
            defaults.set(newClientID, forKey: Key.clientID)
            self.clientID = newClientID
        }

        refreshLaunchAtLogin()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLogin()
            if requiresApproval {
                loginMessage = "O macOS precisa da sua aprovação. Ative o UbiAir em Ajustes do Sistema > Geral > Itens de Início de Sessão."
            }
        } catch {
            refreshLaunchAtLogin()
            loginMessage = "Não foi possível atualizar o início automático. Verifique se o app está instalado em Aplicativos e tente novamente."
        }
    }

    func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        requiresApproval = status == .requiresApproval

        if requiresApproval, loginMessage == nil {
            loginMessage = "O macOS precisa da sua aprovação. Ative o UbiAir em Ajustes do Sistema > Geral > Itens de Início de Sessão."
        } else if !requiresApproval, loginMessage?.hasPrefix("O macOS precisa da sua aprovação") == true {
            loginMessage = nil
        }

        if status == .notFound {
            loginMessage = "O macOS não encontrou este app no caminho atual. Mova UbiAir.app para Aplicativos e tente novamente."
        }
    }
}
