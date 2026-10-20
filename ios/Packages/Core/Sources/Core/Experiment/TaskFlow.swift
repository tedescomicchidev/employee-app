import Foundation

/// docs/experiment/metrics.md. Content-free by construction: there is no field that could hold text.
public struct ExperimentEvent: Sendable, Equatable, Encodable {
    public enum Name: String, Sendable, Encodable {
        case taskStarted = "task_started", taskCompleted = "task_completed"
        case taskAbandoned = "task_abandoned", taskError = "task_error"
        case confirmShown = "confirm_shown", confirmAccepted = "confirm_accepted"
        case confirmRejected = "confirm_rejected", agentTurn = "agent_turn"
    }
    public enum Action: String, Sendable, Encodable { case publish, request, cancel, decide, optIn = "opt_in" }

    public var event: Name
    public var participantId: UUID
    public var sessionId: UUID
    public var taskRunId: UUID
    public var taskId: String
    public var feature: String
    public var mode: String
    public var orderIndex: Int
    public var appVersion: String
    public var osVersion: String
    public var locale: String
    public var ts: Date
    public var elapsedMs: Int?
    public var tapCount: Int?
    public var outcomeValid: Bool?
    public var lastState: String?
    public var code: String?
    public var recovered: Bool?
    public var action: Action?
    public var latencyMs: Int?
    /// AGENT mode: user messages sent in the task (`task_completed`), and per-turn timings (`agent_turn`).
    public var messageCount: Int?
    public var latencyFirstTokenMs: Int?
    public var latencyTotalMs: Int?
    public var toolCalls: Int?

    enum CodingKeys: String, CodingKey {
        case event, ts, feature, mode, locale, code, recovered, action
        case participantId = "participant_id", sessionId = "session_id", taskRunId = "task_run_id"
        case taskId = "task_id", orderIndex = "order_index", appVersion = "app_version"
        case osVersion = "os_version", elapsedMs = "elapsed_ms", tapCount = "tap_count"
        case outcomeValid = "outcome_valid", lastState = "last_state", latencyMs = "latency_ms"
        case messageCount = "message_count", latencyFirstTokenMs = "latency_first_token_ms"
        case latencyTotalMs = "latency_total_ms", toolCalls = "tool_calls"
    }
}

public protocol EventSink: Sendable {
    func record(_ event: ExperimentEvent) async
}

public struct TaskContext: Sendable {
    public var participantId: UUID
    public var sessionId: UUID
    public var orderIndex: Int
    public var appVersion: String
    public var osVersion: String
    public var locale: String

    public init(
        participantId: UUID, sessionId: UUID = UUID(), orderIndex: Int = 0,
        appVersion: String = "dev", osVersion: String = "", locale: String = "en"
    ) {
        self.participantId = participantId
        self.sessionId = sessionId
        self.orderIndex = orderIndex
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.locale = locale
    }
}

/// Shared task-flow wrapper (ADR-009): `task_started`, then exactly one of completed/abandoned.
/// Late events after the terminal one are dropped, so a flow can never double-report.
@MainActor
public final class TaskFlow {
    public let taskId: String
    public let feature: String
    public let mode: AppMode
    /// What `confirm_*` events report: the write this flow asks the user to confirm.
    private let confirmAction: ExperimentEvent.Action
    private let context: TaskContext
    private let sink: any EventSink
    private let now: @Sendable () -> Date
    private let runId: UUID
    private var startedAt: Date?
    private var shownAt: Date?
    private var taps = 0
    private var finished = false

    public init(
        taskId: String, feature: String, mode: AppMode, context: TaskContext, sink: any EventSink,
        confirmAction: ExperimentEvent.Action = .publish,
        runId: UUID = UUID(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.runId = runId
        self.taskId = taskId
        self.feature = feature
        self.mode = mode
        self.confirmAction = confirmAction
        self.context = context
        self.sink = sink
        self.now = now
    }

    public var taskRunId: UUID { runId }
    /// The run id REST calls are tagged with (EXP-005): nil once the flow finished, so later background
    /// calls (badge refresh, pull-to-refresh) are not attributed to a completed task.
    public var activeRunId: UUID? { finished ? nil : runId }
    public var tapCount: Int { taps }
    public var isFinished: Bool { finished }

    /// `date` back-dates the start: an AGENT chat only learns which task it is (from the tools the agent
    /// used) after the first reply, but the task began with the first message.
    public func start(at date: Date? = nil) {
        guard startedAt == nil else { return }
        startedAt = date ?? now()
        emit(.taskStarted, at: startedAt)
    }

    public func tap() { if !finished { taps += 1 } }

    public func confirmShown() {
        shownAt = now()
        emit(.confirmShown) { [confirmAction] in $0.action = confirmAction }
    }

    public func confirmAccepted() { confirmResolved(.confirmAccepted) }
    public func confirmRejected() { confirmResolved(.confirmRejected) }

    public func error(code: String, recovered: Bool) {
        emit(.taskError) { $0.code = code; $0.recovered = recovered }
    }

    public func complete(outcomeValid: Bool, messageCount: Int? = nil) {
        finish(.taskCompleted) { $0.outcomeValid = outcomeValid; $0.messageCount = messageCount }
    }

    /// One completed agent response (EXP-002/005): timings and a tool-call count, never names or text.
    public func agentTurn(firstTokenMs: Int?, totalMs: Int, toolCalls: Int) {
        emit(.agentTurn) {
            $0.latencyFirstTokenMs = firstTokenMs
            $0.latencyTotalMs = totalMs
            $0.toolCalls = toolCalls
        }
    }

    public func abandon(lastState: String) {
        guard startedAt != nil else { return }
        finish(.taskAbandoned) { $0.lastState = lastState }
    }

    private func confirmResolved(_ name: ExperimentEvent.Name) {
        let latency = shownAt.map { Int(now().timeIntervalSince($0) * 1000) }
        emit(name) { [confirmAction] in $0.action = confirmAction; $0.latencyMs = latency }
    }

    private func finish(_ name: ExperimentEvent.Name, _ configure: (inout ExperimentEvent) -> Void) {
        guard startedAt != nil, !finished else { return }
        let elapsed = startedAt.map { Int(now().timeIntervalSince($0) * 1000) }
        let taps = taps
        emit(name) { event in
            event.elapsedMs = elapsed
            event.tapCount = taps
            configure(&event)
        }
        finished = true
    }

    private func emit(
        _ name: ExperimentEvent.Name, at date: Date? = nil, _ configure: (inout ExperimentEvent) -> Void = { _ in }
    ) {
        guard startedAt != nil, !finished else { return }
        var event = ExperimentEvent(
            event: name, participantId: context.participantId, sessionId: context.sessionId,
            taskRunId: runId, taskId: taskId, feature: feature, mode: mode.rawValue,
            orderIndex: context.orderIndex, appVersion: context.appVersion, osVersion: context.osVersion,
            locale: context.locale, ts: date ?? now())
        configure(&event)
        let sink = sink
        Task { await sink.record(event) }
    }
}

/// EXP-005: ties the REST calls a task makes to its `task_run_id` (the `X-Task-Run-Id` header), so the
/// server can count calls and latency per task. Task-local: a concurrent call of another flow is never
/// attributed to this one.
public enum TaskRun {
    @TaskLocal public static var current: UUID?
    public static let header = "X-Task-Run-Id"

    public static func tag(_ request: inout URLRequest) {
        if let id = current { request.setValue(id.uuidString, forHTTPHeaderField: header) }
    }
}
