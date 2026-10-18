import Foundation

/// Batches content-free events to `POST /v1/events`. Failures keep events queued in memory only
/// (ADR-009 allows offline queueing of content-free events); sign-out clears the queue.
public actor URLSessionEventSink: EventSink {
    private let baseURL: URL
    private let session: URLSession
    private let token: @Sendable () async throws -> String
    private let batchSize: Int
    private var queue: [ExperimentEvent] = []

    public init(
        baseURL: URL, session: URLSession = .shared, batchSize: Int = 5,
        token: @escaping @Sendable () async throws -> String
    ) {
        self.baseURL = baseURL
        self.session = session
        self.batchSize = batchSize
        self.token = token
    }

    public func record(_ event: ExperimentEvent) async {
        queue.append(event)
        let terminal = event.event == .taskCompleted || event.event == .taskAbandoned
        if terminal || queue.count >= batchSize { await flush() }
    }

    public func clear() { queue.removeAll() }

    public func flush() async {
        guard !queue.isEmpty, let bearer = try? await token() else { return }
        let batch = queue
        var request = URLRequest(url: baseURL.appending(path: "v1/events"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        struct Body: Encodable { let events: [ExperimentEvent] }
        guard let body = try? encoder.encode(Body(events: batch)) else { return }
        request.httpBody = body
        if let (_, response) = try? await session.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 202 {
            queue.removeFirst(min(batch.count, queue.count))
        }
    }
}

/// Collects events in memory; used by tests and when no API is configured.
public actor MemoryEventSink: EventSink {
    public private(set) var events: [ExperimentEvent] = []
    public init() {}
    public func record(_ event: ExperimentEvent) { events.append(event) }
}
