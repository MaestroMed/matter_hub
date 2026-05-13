import Foundation

public struct ChatMessage: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let role: Role
    public let content: String
    public let createdAt: Date

    public enum Role: String, Sendable {
        case user
        case assistant
    }

    public init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = .now) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}
