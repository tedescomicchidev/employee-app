import Foundation
import Testing
@testable import Core

@MainActor
@Suite("TaskFlow")
struct TaskFlowTests {
    private func flow(_ sink: MemoryEventSink) -> TaskFlow {
        TaskFlow(taskId: "T-ANN-PUB", feature: "ann", mode: .classic,
                 context: TaskContext(participantId: UUID()), sink: sink)
    }

    @Test("EXP-005: calls are tagged with the run only while the flow is running")
    func activeRunId() {
        let flow = flow(MemoryEventSink())
        #expect(flow.activeRunId == flow.taskRunId)
        flow.start()
        flow.complete(outcomeValid: true)
        #expect(flow.activeRunId == nil)
    }

    @Test("EXP-001: exactly one terminal event; later events are dropped")
    func oneTerminal() async throws {
        let sink = MemoryEventSink()
        let flow = flow(sink)
        flow.start()
        flow.complete(outcomeValid: true)
        flow.abandon(lastState: "review")
        flow.complete(outcomeValid: false)
        flow.error(code: "X", recovered: false)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await sink.events.map(\.event) == [.taskStarted, .taskCompleted])
    }

    @Test("EXP-001: nothing is emitted before start, and abandon without start is a no-op")
    func needsStart() async throws {
        let sink = MemoryEventSink()
        let flow = flow(sink)
        flow.abandon(lastState: "compose")
        flow.error(code: "X", recovered: false)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await sink.events.isEmpty)
    }

    @Test("EXP-002: the terminal event carries taps and elapsed time")
    func tapsAndElapsed() async throws {
        let sink = MemoryEventSink()
        let flow = flow(sink)
        flow.start()
        flow.tap(); flow.tap()
        flow.complete(outcomeValid: true)
        try await Task.sleep(for: .milliseconds(50))
        let done = try #require(await sink.events.last)
        #expect(done.tapCount == 2 && done.elapsedMs != nil)
    }
}
