import Foundation

struct Vault: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let description: String?
    let createdAt: Int64
    let updatedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt))
    }

    var updatedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(updatedAt))
    }
}

struct Secret: Codable, Identifiable {
    let id: String
    let vaultId: String
    let environment: String
    let key: String
    let value: String
    let createdAt: Int64
    let updatedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id, environment, key, value
        case vaultId = "vault_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt))
    }

    var updatedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(updatedAt))
    }
}

struct EnvironmentItem: Codable, Identifiable {
    let id: String
    let name: String
    let createdAt: Int64
    let displayOrder: Int64

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
        case displayOrder = "display_order"
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt))
    }
}

struct ApiKey: Codable, Identifiable {
    let id: String
    let name: String
    let vaultId: String
    let environment: String
    let expiresAt: Int64?
    let createdAt: Int64
    let lastUsedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case vaultId = "vault_id"
        case environment
        case expiresAt = "expires_at"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
    }

    var expirationDate: Date? {
        guard let expiresAt else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(expiresAt))
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt))
    }

    var lastUsedDate: Date? {
        guard let lastUsedAt else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(lastUsedAt))
    }

    var isExpired: Bool {
        guard let expirationDate else {
            return false
        }
        return expirationDate < Date()
    }
}

struct ApiKeyResponse: Codable {
    let apiKey: ApiKey
    let jwtToken: String
    let apiSecret: String

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case jwtToken = "jwt_token"
        case apiSecret = "api_secret"
    }
}

enum ApiKeyExpiration: Int32, CaseIterable, Identifiable {
    case oneDay = 1
    case oneWeek = 7
    case oneMonth = 30
    case ninetyDays = 90
    case noExpiry = -1

    var id: Int32 {
        rawValue
    }

    var displayName: String {
        switch self {
        case .oneDay: "1 Day"
        case .oneWeek: "1 Week"
        case .oneMonth: "1 Month"
        case .ninetyDays: "90 Days"
        case .noExpiry: "No Expiry"
        }
    }
}
