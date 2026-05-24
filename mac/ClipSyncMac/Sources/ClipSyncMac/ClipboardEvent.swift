import Foundation

struct ClipboardEvent: CustomStringConvertible {
    let id: UUID
    let timestamp: Date
    let text: String
    let normalizedText: String
    let hash: String

    var description: String {
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
