import Foundation
import ThinQCore

struct AppProblem: Equatable {
    let title: String
    let message: String
    let kind: ThinQFailureKind
    let blocksControls: Bool

    init(_ error: Error, commandUncertain: Bool = false) {
        let failure = error as? ThinQError
        kind = failure?.kind ?? .unknown
        blocksControls = true
        switch kind {
        case .authentication: title = "Conecte sua conta novamente"
        case .permission: title = "Sem permissão para este aparelho"
        case .offline: title = "Aparelho offline no ThinQ"
        case .rateLimited: title = "Aguarde antes de atualizar"
        case .connection: title = "Não foi possível conectar"
        case .timeout: title = "A LG demorou para responder"
        case .service: title = "ThinQ indisponível no momento"
        case .request: title = "Solicitação não aceita"
        case .unknown: title = "Não foi possível concluir"
        }
        if commandUncertain {
            message = "Não foi possível confirmar o resultado. Atualize o estado antes de repetir o comando."
        } else {
            message = failure?.errorDescription ?? "Tente atualizar novamente. Se continuar, confira o aparelho no app LG ThinQ."
        }
    }

    init(title: String, message: String) {
        self.title = title
        self.message = message
        kind = .unknown
        blocksControls = false
    }

    var requiresReconnect: Bool { kind == .authentication }
}
