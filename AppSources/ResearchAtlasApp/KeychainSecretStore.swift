import Foundation
import LocalAuthentication
import ResearchAtlasCore
import Security

enum KeychainSecretError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData
    case interactionRefused

    var errorDescription: String? {
        switch self {
        case .interactionRefused:
            return "Research Atlas refused to display a macOS Keychain password dialog. Paste the API key once in Integrations to replace the credential saved by an older local build."
        case .unexpectedStatus(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "The credential could not be accessed securely: \(detail)"
        case .invalidData: return "The stored credential could not be decoded."
        }
    }
}
enum KeychainSecretStore {
    // This is intentionally a fresh service name. Older items were created by development
    // builds with changing code identities, so reading them can make macOS ask for the login
    // keychain password. They remain untouched and are never queried.
    private static let service = "app.researchatlas.desktop.ai-provider.v3"
    private static let presenceMarkerPrefix = "aiCredentialStored.v3."

    static func save(_ secret: String, for provider: AIProviderKind) throws {
        guard provider.requiresCredential else { return }
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { try delete(for: provider); return }
        let data = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider),
            kSecUseAuthenticationContext as String: nonInteractiveContext()
        ]
        let protectedValue: [String: Any] = [
            kSecValueData as String: data
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, protectedValue as CFDictionary)
        if updateStatus == errSecSuccess {
            rememberPresence(true, for: provider)
            return
        }
        if updateStatus == errSecInteractionNotAllowed { throw KeychainSecretError.interactionRefused }
        guard updateStatus == errSecItemNotFound else { throw KeychainSecretError.unexpectedStatus(updateStatus) }
        var insertion = query
        insertion.removeValue(forKey: kSecUseAuthenticationContext as String)
        insertion[kSecValueData as String] = data
        insertion[kSecAttrAccess as String] = try applicationOnlyAccess()
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainSecretError.unexpectedStatus(addStatus) }
        rememberPresence(true, for: provider)
    }

    static func read(for provider: AIProviderKind) throws -> String? {
        guard provider.requiresCredential else { return provider.isLocal ? "" : nil }
        if let current = try read(account: account(for: provider)) {
            rememberPresence(true, for: provider)
            return current
        }
        rememberPresence(false, for: provider)
        return nil
    }

    /// Returns a non-secret UI hint recorded after an explicit save, read, or deletion. It never
    /// contacts Keychain, so launching the app or browsing provider settings cannot display a
    /// macOS credential prompt. The authoritative check remains the approved send-time read.
    static func rememberedPresence(for provider: AIProviderKind) -> Bool {
        guard provider != .disabled else { return false }
        guard provider.requiresCredential else { return true }
        return UserDefaults.standard.bool(forKey: presenceMarkerKey(for: provider))
    }

    static func delete(for provider: AIProviderKind) throws {
        guard provider.requiresCredential else { return }
        try delete(account: account(for: provider))
        rememberPresence(false, for: provider)
    }

    private static func read(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: nonInteractiveContext()
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        if status == errSecInteractionNotAllowed { throw KeychainSecretError.interactionRefused }
        guard status == errSecSuccess else { throw KeychainSecretError.unexpectedStatus(status) }
        guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw KeychainSecretError.invalidData
        }
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationContext as String: nonInteractiveContext()
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecInteractionNotAllowed { throw KeychainSecretError.interactionRefused }
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretError.unexpectedStatus(status)
        }
    }

    private static func account(for provider: AIProviderKind) -> String {
        switch provider {
        case .disabled: "disabled"
        case .openAI: "openai-api-key"
        case .anthropic: "anthropic-api-key"
        case .googleGemini: "google-gemini-api-key"
        case .ollamaLocal: "ollama-local-no-credential"
        case .lmStudioLocal: "lm-studio-local-no-credential"
        case .compatibleEndpoint: "compatible-responses-api-key"
        }
    }

    private static func presenceMarkerKey(for provider: AIProviderKind) -> String {
        presenceMarkerPrefix + provider.rawValue
    }

    private static func nonInteractiveContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }

    private static func applicationOnlyAccess() throws -> SecAccess {
        var trustedApplication: SecTrustedApplication?
        let trustedStatus = SecTrustedApplicationCreateFromPath(nil, &trustedApplication)
        guard trustedStatus == errSecSuccess, let trustedApplication else {
            throw KeychainSecretError.unexpectedStatus(trustedStatus)
        }
        var access: SecAccess?
        let accessStatus = SecAccessCreate(
            "Research Atlas AI provider credential" as CFString,
            [trustedApplication] as CFArray,
            &access
        )
        guard accessStatus == errSecSuccess, let access else {
            throw KeychainSecretError.unexpectedStatus(accessStatus)
        }
        return access
    }

    private static func rememberPresence(_ present: Bool, for provider: AIProviderKind) {
        guard provider.requiresCredential else { return }
        UserDefaults.standard.set(present, forKey: presenceMarkerKey(for: provider))
    }
}

/// Removes only obsolete local preferences from the retired Zotero integration. The former
/// Keychain item is deliberately left untouched so app launch can never trigger authentication.
enum RetiredIntegrationCleanup {
    static func run() {
        // Zotero is retired. Do not touch its former Keychain item during launch: even a cleanup
        // query can trigger a system prompt on a locked or separately protected login keychain.
        UserDefaults.standard.removeObject(forKey: "zoteroWebUserID")
        UserDefaults.standard.removeObject(forKey: "zoteroWebLastDiagnostic")
    }
}
