import Foundation
import Testing
@testable import Core

/// Captures requests instead of sending them.
private final class Recorder: URLProtocol, @unchecked Sendable {
    // Test-only global; the suite is serialised.
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var status = 202

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var copy = request
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            copy.httpBody = data
        }
        Self.requests.append(copy)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func session() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [Recorder.self]
    Recorder.requests = []
    Recorder.status = 202
    return URLSession(configuration: config)
}

private func event(_ name: ExperimentEvent.Name) -> ExperimentEvent {
    ExperimentEvent(
        event: name, participantId: UUID(), sessionId: UUID(), taskRunId: UUID(), taskId: "T-ANN-PUB",
        feature: "ann", mode: "classic", orderIndex: 0, appVersion: "1", osVersion: "17", locale: "en", ts: Date())
}

@Suite("EXP transport", .serialized)
struct ExperimentTransportTests {
    @Test("EXP-005: requests made inside a task run carry its id; others carry none")
    func header() {
        let id = UUID()
        var tagged = URLRequest(url: URL(string: "https://x.test")!)
        TaskRun.$current.withValue(id) { TaskRun.tag(&tagged) }
        #expect(tagged.value(forHTTPHeaderField: "X-Task-Run-Id") == id.uuidString)
        var plain = URLRequest(url: URL(string: "https://x.test")!)
        TaskRun.tag(&plain)
        #expect(plain.value(forHTTPHeaderField: "X-Task-Run-Id") == nil)
    }

    @Test("EXP-001: events are batched, flushed on the terminal event, and carry no content fields")
    func batching() async throws {
        let sink = URLSessionEventSink(
            baseURL: URL(string: "https://x.test")!, session: session(), batchSize: 5, token: { "t" })
        await sink.record(event(.taskStarted))
        await sink.record(event(.taskError))
        #expect(Recorder.requests.isEmpty)
        await sink.record(event(.taskCompleted))
        #expect(Recorder.requests.count == 1)
        let body = try #require(Recorder.requests.first?.httpBody)
        let events = try #require((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["events"] as? [[String: Any]])
        #expect(events.count == 3)
        #expect(Set(events.flatMap(\.keys)).isDisjoint(with: ["title", "body", "reason", "text"]))
    }

    @Test("EXP-001: a failed upload keeps the events queued; sign-out clears the queue")
    func retryAndClear() async {
        let sink = URLSessionEventSink(
            baseURL: URL(string: "https://x.test")!, session: session(), batchSize: 5, token: { "t" })
        Recorder.status = 503
        await sink.record(event(.taskStarted))
        await sink.record(event(.taskAbandoned))
        #expect(Recorder.requests.count == 1)
        Recorder.status = 202
        await sink.flush()
        #expect(Recorder.requests.count == 2)  // same two events again
        await sink.flush()
        #expect(Recorder.requests.count == 2)  // nothing left
        await sink.record(event(.taskStarted))
        await sink.clear()
        await sink.flush()
        #expect(Recorder.requests.count == 2)
    }
}
