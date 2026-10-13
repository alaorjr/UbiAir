import Foundation
import Security

@MainActor
final class CredentialStore {
    private let service = "br.com.alaorjr.LGThinQ"
    private let account = "personal-access-token"

    func loadToken() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw CredentialStoreError.status(status: status, operation: "ler")
        }
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.invalidValue
        }
        return token
    }

    func saveToken(_ token: String) throws {
        guard !token.isEmpty, let data = token.data(using: .utf8) else {
            throw CredentialStoreError.emptyToken
        }

        // Update the existing item first. If that fails, the previous token remains intact.
        let status = SecItemUpdate(baseQuery as CFDictionary, [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ] as CFDictionary)

        if status == errSecSuccess {
            return
        }
        if status == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecSuccess {
                return
            }
            // A concurrent save may have inserted the item after our initial update.
            if addStatus == errSecDuplicateItem {
                try updateToken(data)
                return
            }
            throw CredentialStoreError.status(status: addStatus, operation: "salvar")
        }

        throw CredentialStoreError.status(status: status, operation: "atualizar")
    }

    func deleteToken() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.status(status: status, operation: "remover")
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }

    private func updateToken(_ data: Data) throws {
        let status = SecItemUpdate(baseQuery as CFDictionary, [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ] as CFDictionary)
        guard status == errSecSuccess else {
            throw CredentialStoreError.status(status: status, operation: "atualizar")
        }
    }
}

private enum CredentialStoreError: LocalizedError {
    case emptyToken
    case invalidValue
    case status(status: OSStatus, operation: String)

    var errorDescription: String? {
        switch self {
        case .emptyToken:
            return "O token de acesso está vazio. Informe um PAT antes de salvar."
        case .invalidValue:
            return "O Chaves retornou uma credencial inválida. Remova e salve o PAT novamente."
        case let .status(status, operation):
            let detail: String
            switch status {
            case errSecAuthFailed:
                detail = "O acesso foi recusado. Uma assinatura ad hoc diferente pode impedir o acesso a credenciais salvas; use a mesma identidade de assinatura entre builds ou salve o PAT novamente."
            case errSecInteractionNotAllowed:
                detail = "O Chaves não está disponível enquanto a sessão está bloqueada. Desbloqueie a sessão e tente novamente."
            case errSecNotAvailable:
                detail = "O serviço Chaves do macOS está indisponível. Tente novamente mais tarde."
            default:
                detail = "O Chaves do macOS retornou o erro \(status)."
            }
            return "Não foi possível \(operation) o PAT no Chaves. \(detail)"
        }
    }
}
