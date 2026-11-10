import Foundation

enum ClipVaultError: LocalizedError {
    case storage(String)
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .storage(let message), .invalidPayload(let message):
            return message
        }
    }
}
