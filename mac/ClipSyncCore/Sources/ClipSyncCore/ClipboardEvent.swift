import Foundation

public struct ClipboardEvent: CustomStringConvertible {
    public let id: UUID
    public let timestamp: Date
    public let text: String
    public let normalizedText: String
    public let hash: String

    public init(
        id: UUID,
        timestamp: Date,
        text: String,
        normalizedText: String,
        hash: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.normalizedText = normalizedText
        self.hash = hash
    }

    public var description: String {
        """
        ClipboardEvent(
          id: \(id.uuidString),
          timestamp: \(timestamp.ISO8601Format()),
          hash: \(hash),
          preview: \(normalizedText.debugDescription)
        )
        """
    }
}
