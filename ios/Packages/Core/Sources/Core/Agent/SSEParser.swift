import Foundation

/// One server-sent event of the agent stream: its name and the JSON text of its `data:` line.
public struct SSEEvent: Sendable, Equatable {
    public let name: String
    public let data: String

    public init(name: String, data: String) {
        self.name = name
        self.data = data
    }
}

/// Reads `event:` / `data:` lines. The api sends exactly one `data:` line per event, so a `data:` line
/// completes the event. `URLSession.AsyncBytes.lines` drops empty lines, so the blank separator is
/// neither required nor relied on; a blank line only resets the pending name.
public struct SSEParser: Sendable {
    private var name: String?

    public init() {}

    public mutating func feed(line: String) -> SSEEvent? {
        if line.isEmpty {
            name = nil
            return nil
        }
        if line.hasPrefix(":") { return nil }  // comment / keep-alive
        if line.hasPrefix("event:") {
            name = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return nil
        }
        if line.hasPrefix("data:") {
            var data = String(line.dropFirst(5))
            if data.hasPrefix(" ") { data.removeFirst() }
            defer { name = nil }
            return SSEEvent(name: name ?? "message", data: data)
        }
        return nil
    }
}
