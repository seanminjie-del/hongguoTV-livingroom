import Foundation
public enum HongguoError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
public struct Series: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var cover: String = ""
    public var description: String = ""
    public var badge: String = ""
    public var tags: String = ""
    public init(id: String, title: String, cover: String = "", description: String = "", badge: String = "", tags: String = "") {
        self.id=id; self.title=title; self.cover=cover; self.description=description; self.badge=badge; self.tags=tags
    }
}
