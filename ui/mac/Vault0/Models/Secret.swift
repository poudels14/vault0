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
    let parentId: String?
    let opVault: String?
    let opItem: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
        case displayOrder = "display_order"
        case parentId = "parent_id"
        case opVault = "op_vault"
        case opItem = "op_item"
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt))
    }

    var isOnePassword: Bool {
        opItem != nil
    }
}

struct OpEntry: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}
