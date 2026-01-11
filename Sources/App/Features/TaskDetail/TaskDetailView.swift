// Sources/App/Features/TaskDetail/TaskDetailView.swift
// タスク詳細ビュー
// 要件: サブタスク概念は削除（タスク間の関係は依存関係のみで表現）
// リアクティブ要件: TaskStoreを使用してUIの自動更新を実現

import SwiftUI
import Domain

// Domain.Task と Swift.Task の名前衝突を解決
private typealias AsyncTask = _Concurrency.Task

/// TaskStoreの変更を監視するためのObservableObjectラッパー
/// TaskStoreがnilの場合でも安全に動作する
@MainActor
private final class TaskStoreObserver: ObservableObject {
    @Published var tasks: [Task] = []
    private var taskStore: TaskStore?
    private var cancellable: AnyCancellable?

    init(taskStore: TaskStore?) {
        self.taskStore = taskStore
        if let store = taskStore {
            // TaskStoreのtasksをサブスクライブ
            cancellable = store.$tasks.sink { [weak self] newTasks in
                self?.tasks = newTasks
            }
            tasks = store.tasks
        }
    }
}

import Combine

struct TaskDetailView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router

    let taskId: TaskID

    /// 共有タスクストア（ContentViewから渡される）
    /// ステータス変更時にこのストアを更新することで、TaskBoardViewも自動更新される
    var taskStore: TaskStore?

    /// TaskStoreの変更を監視するためのラッパー
    /// taskStoreがnilでない場合のみリアクティブ更新が有効
    @ObservedObject private var storeObserver: TaskStoreObserver

    @State private var task: Task?
    @State private var contexts: [Context] = []
    @State private var dependentTasks: [Task] = []
    @State private var handoffs: [Handoff] = []
    @State private var historyEvents: [StateChangeEvent] = []
    @State private var executionLogs: [ExecutionLog] = []
    @State private var assignee: Agent?
    @State private var isLoading = false

    /// イニシャライザ: taskStoreを監視するためのobserverを初期化
    init(taskId: TaskID, taskStore: TaskStore? = nil) {
        self.taskId = taskId
        self.taskStore = taskStore
        self._storeObserver = ObservedObject(wrappedValue: TaskStoreObserver(taskStore: taskStore))
    }

    var body: some View {
        Group {
            if let task = task {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header
                        taskHeader(task)

                        Divider()

                        // Description
                        if !task.description.isEmpty {
                            descriptionSection(task.description)
                        }

                        // Status & Assignment
                        statusSection(task)

                        // Kick Status
                        kickStatusSection(task)

                        // Notification Status
                        notificationSection(task)

                        Divider()

                        // Dependencies
                        dependenciesSection

                        Divider()

                        // Handoffs
                        handoffsSection

                        Divider()

                        // Execution History (Phase 3-4)
                        executionHistorySection

                        Divider()

                        // History (StateChangeEvents)
                        historySection

                        Divider()

                        // Context History
                        contextSection
                    }
                    .padding()
                }
                .accessibilityIdentifier("TaskDetailView")
            } else if isLoading {
                ProgressView()
                    .accessibilityIdentifier("LoadingIndicator")
            } else {
                ContentUnavailableView(
                    "Task Not Found",
                    systemImage: "doc.questionmark"
                )
                .accessibilityIdentifier("TaskNotFound")
            }
        }
        .navigationTitle(task?.title ?? "Task")
        .toolbar {
            if task != nil {
                ToolbarItem {
                    Button {
                        router.showSheet(.editTask(taskId))
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("EditTaskButton")
                    .keyboardShortcut("e", modifiers: [.command])
                    .help("Edit Task (⌘E)")
                }

                ToolbarItem {
                    Button {
                        router.showSheet(.handoff(taskId))
                    } label: {
                        Label("Handoff", systemImage: "arrow.right.arrow.left")
                    }
                    .accessibilityIdentifier("HandoffButton")
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                    .help("Create Handoff (⇧⌘H)")
                }
            }
        }
        .task {
            await loadData()
        }
        .onChange(of: router.currentSheet) { oldValue, newValue in
            // シートが閉じられた場合（editTask または addContext）、データを再読み込み
            if newValue == nil {
                if case .editTask(let editedTaskId) = oldValue, editedTaskId == taskId {
                    AsyncTask {
                        await loadData()
                    }
                } else if case .addContext(let contextTaskId) = oldValue, contextTaskId == taskId {
                    AsyncTask {
                        await loadData()
                    }
                } else if case .handoff(let handoffTaskId) = oldValue, handoffTaskId == taskId {
                    AsyncTask {
                        await loadData()
                    }
                }
            }
        }
        // リアクティブ更新: TaskStoreのタスク配列が変更されたらローカル状態を更新
        // ドラッグ&ドロップでステータスが変更された場合にTaskDetailViewも自動更新される
        .onChange(of: storeObserver.tasks) { _, newTasks in
            if let updatedTask = newTasks.first(where: { $0.id == taskId }) {
                task = updatedTask
            }
        }
    }

    @ViewBuilder
    private func taskHeader(_ task: Task) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PriorityBadge(priority: task.priority)
                    .accessibilityIdentifier("TaskPriority")
                StatusBadge(status: task.status)
                    .accessibilityIdentifier("TaskStatus")
            }

            Text(task.title)
                .font(.title)
                .fontWeight(.bold)
                .accessibilityIdentifier("TaskTitle")
        }
        .accessibilityIdentifier("TaskHeader")
    }

    @ViewBuilder
    private func descriptionSection(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.headline)
            Text(description)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func statusSection(_ task: Task) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)

            LabeledContent("Status") {
                Picker("Status", selection: Binding(
                    get: { task.status },
                    set: { updateStatus($0) }
                )) {
                    ForEach(TaskStatus.allCases, id: \.self) { status in
                        Text(status.displayName).tag(status)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("StatusPicker")
            }

            if let assignee = assignee {
                LabeledContent("Assignee") {
                    Text(assignee.name)
                }
            }

            if let estimated = task.estimatedMinutes {
                LabeledContent("Estimated") {
                    Text("\(estimated) min")
                }
            }

            if let actual = task.actualMinutes {
                LabeledContent("Actual") {
                    Text("\(actual) min")
                }
            }
        }
    }

    /// キック状態を履歴イベントとタスク状態から取得
    private func getKickStatus(for task: Task) -> String {
        // in_progressでない場合
        guard task.status == .inProgress else {
            return "N/A"
        }

        // アサインされていない場合
        guard task.assigneeId != nil else {
            return "No Assignee"
        }

        // 最新のkickedイベントを探す
        if let kickedEvent = historyEvents.first(where: { $0.eventType == .kicked }) {
            // newStateにキック結果が記録されている想定
            if let newState = kickedEvent.newState {
                return newState.capitalized
            }
            return "Success"
        }

        // in_progressだがキックイベントがない場合
        return "Pending"
    }

    @ViewBuilder
    private func kickStatusSection(_ task: Task) -> some View {
        let status = getKickStatus(for: task)

        VStack(alignment: .leading, spacing: 12) {
            Text("Kick Status")
                .font(.headline)
                .accessibilityIdentifier("KickStatusHeader")

            HStack {
                Image(systemName: kickStatusIcon(status))
                    .foregroundStyle(kickStatusColor(status))
                    .font(.title2)

                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(kickStatusColor(status))
            }
            .accessibilityIdentifier("KickStatusIndicator")
        }
        .accessibilityIdentifier("KickStatusSection")
    }

    private func kickStatusIcon(_ status: String) -> String {
        switch status.lowercased() {
        case "success": return "checkmark.circle.fill"
        case "failed": return "xmark.circle.fill"
        case "running": return "arrow.triangle.2.circlepath.circle.fill"
        case "pending": return "clock.circle.fill"
        default: return "minus.circle"
        }
    }

    private func kickStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "success": return .green
        case "failed": return .red
        case "running": return .orange
        case "pending": return .blue
        default: return .secondary
        }
    }

    // MARK: - Notification Section

    /// 親（上位エージェント/ユーザー）への通知状態を表示
    @ViewBuilder
    private func notificationSection(_ task: Task) -> some View {
        let notificationEvent = historyEvents.first { $0.eventType == .notified }
        let wasNotified = notificationEvent != nil

        VStack(alignment: .leading, spacing: 12) {
            Text("Parent Notification")
                .font(.headline)
                .accessibilityIdentifier("NotificationHeader")

            HStack {
                if task.status == .done {
                    if wasNotified {
                        Image(systemName: "bell.badge.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("Parent notified")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                            if let event = notificationEvent {
                                Text(event.timestamp.formatted())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Image(systemName: "bell.slash")
                            .foregroundStyle(.orange)
                            .font(.title2)
                        Text("Notification pending")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                } else {
                    Image(systemName: "bell")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                    Text("Will notify on completion")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("NotificationIndicator")
        }
        .accessibilityIdentifier("NotificationSection")
    }

    private var dependenciesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dependencies")
                .font(.headline)
                .accessibilityIdentifier("DependenciesHeader")

            if dependentTasks.isEmpty {
                Text("No dependencies")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .accessibilityIdentifier("NoDependenciesMessage")
            } else {
                ForEach(dependentTasks, id: \.id) { depTask in
                    HStack {
                        Image(systemName: depTask.status == .done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(depTask.status == .done ? .green : .secondary)

                        VStack(alignment: .leading) {
                            Text(depTask.title)
                                .font(.subheadline)
                            Text(depTask.status.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onTapGesture {
                        router.selectTask(depTask.id)
                    }
                    .accessibilityIdentifier("Dependency_\(depTask.id.value)")
                }
            }
        }
        .accessibilityIdentifier("DependenciesSection")
    }

    private var handoffsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Handoffs")
                .font(.headline)
                .accessibilityIdentifier("HandoffsHeader")

            if handoffs.isEmpty {
                Text("No handoffs yet")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .accessibilityIdentifier("NoHandoffsMessage")
            } else {
                ForEach(handoffs, id: \.id) { handoff in
                    HandoffCard(handoff: handoff)
                        .accessibilityIdentifier("Handoff_\(handoff.id.value)")
                }
            }
        }
        .accessibilityIdentifier("HandoffsSection")
    }

    // MARK: - Execution History Section (Phase 3-4)

    private var executionHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Execution History")
                .font(.headline)
                .accessibilityIdentifier("ExecutionHistoryHeader")

            if executionLogs.isEmpty {
                Text("No execution logs yet")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .accessibilityIdentifier("NoExecutionLogsMessage")
            } else {
                ForEach(executionLogs, id: \.id) { log in
                    TaskExecutionLogRow(log: log)
                        .accessibilityIdentifier("ExecutionLog_\(log.id.value)")
                }
            }
        }
        .accessibilityIdentifier("ExecutionHistorySection")
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.headline)
                .accessibilityIdentifier("HistoryHeader")

            if historyEvents.isEmpty {
                Text("No history events")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .accessibilityIdentifier("NoHistoryMessage")
            } else {
                ForEach(historyEvents, id: \.id) { event in
                    HistoryEventRow(event: event)
                        .accessibilityIdentifier("HistoryEvent_\(event.id.value)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("HistorySection")
    }

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Context History")
                    .font(.headline)
                    .accessibilityIdentifier("ContextHeader")

                Spacer()

                Button("Add Context") {
                    if let task = task {
                        router.showSheet(.addContext(task.id))
                    }
                }
                .accessibilityIdentifier("AddContextButton")
                .help("Add Context")
            }

            if contexts.isEmpty {
                Text("No context saved yet")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .accessibilityIdentifier("NoContextMessage")
            } else {
                ForEach(contexts, id: \.id) { context in
                    ContextCard(context: context)
                        .accessibilityIdentifier("Context_\(context.id.value)")
                }
            }
        }
        .accessibilityIdentifier("ContextSection")
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let detail = try container.getTaskDetailUseCase.execute(taskId: taskId)
            task = detail.task
            contexts = detail.contexts
            dependentTasks = detail.dependentTasks

            if let assigneeId = detail.task.assigneeId {
                assignee = try container.agentRepository.findById(assigneeId)
            }

            // Load handoffs for this task
            handoffs = try container.handoffRepository.findByTask(taskId)

            // Load history events for this task
            historyEvents = try container.eventRepository.findByEntity(
                type: .task,
                id: taskId.value
            )

            // Load execution logs for this task (Phase 3-4)
            executionLogs = try container.getExecutionLogsUseCase.executeByTaskId(taskId)
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }

    private func updateStatus(_ newStatus: TaskStatus) {
        AsyncTask {
            do {
                let updatedTask = try container.updateTaskStatusUseCase.execute(
                    taskId: taskId,
                    newStatus: newStatus,
                    agentId: nil,
                    sessionId: nil,
                    reason: nil
                )

                // 🔄 リアクティブ更新: TaskStoreを即座に更新してTaskBoardViewに反映
                taskStore?.updateTask(updatedTask)

                // done への遷移時は親に完了通知イベントを記録
                if newStatus == .done {
                    try await notifyParent(task: updatedTask)
                }

                await loadData()
            } catch {
                router.showAlert(.error(message: error.localizedDescription))
            }
        }
    }

    /// 親（上位エージェント/ユーザー）に完了通知を送る
    private func notifyParent(task: Task) async throws {
        let event = StateChangeEvent(
            id: .generate(),
            projectId: task.projectId,
            entityType: .task,
            entityId: task.id.value,
            eventType: .notified,
            agentId: task.assigneeId,
            previousState: nil,
            newState: "Parent notified of completion",
            reason: "Task completed",
            timestamp: Date()
        )
        try container.eventRepository.save(event)
    }
}

struct StatusBadge: View {
    let status: TaskStatus

    var color: Color {
        switch status {
        case .backlog: return .gray
        case .todo: return .blue
        case .inProgress: return .orange
        case .blocked: return .red
        case .done: return .green
        case .cancelled: return .gray
        }
    }

    var body: some View {
        Text(status.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct ContextCard: View {
    let context: Context

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(context.createdAt, style: .date)
                Text(context.createdAt, style: .time)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let progress = context.progress {
                Label(progress, systemImage: "arrow.right")
                    .font(.subheadline)
            }

            if let findings = context.findings {
                Label(findings, systemImage: "lightbulb")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let blockers = context.blockers {
                Label(blockers, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct HandoffCard: View {
    let handoff: Handoff

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(handoff.createdAt, style: .date)
                Text(handoff.createdAt, style: .time)
                Spacer()
                if handoff.isAccepted {
                    Text("Accepted")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                } else {
                    Text("Pending")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(handoff.summary)
                .font(.subheadline)

            if let context = handoff.context {
                Text(context)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let recommendations = handoff.recommendations {
                Label(recommendations, systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct HistoryEventRow: View {
    let event: StateChangeEvent

    var eventIcon: String {
        switch event.eventType {
        case .created: return "plus.circle"
        case .updated: return "pencil.circle"
        case .deleted: return "trash.circle"
        case .statusChanged: return "arrow.triangle.2.circlepath"
        case .assigned: return "person.badge.plus"
        case .unassigned: return "person.badge.minus"
        case .started: return "play.circle"
        case .completed: return "checkmark.circle"
        case .kicked: return "bolt.circle"
        case .notified: return "bell.badge"
        }
    }

    var eventColor: Color {
        switch event.eventType {
        case .created: return .green
        case .deleted: return .red
        case .completed: return .green
        case .statusChanged: return .blue
        case .assigned, .unassigned: return .purple
        case .kicked: return .orange
        case .notified: return .green
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: eventIcon)
                .foregroundStyle(eventColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.eventType.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let previousState = event.previousState, let newState = event.newState {
                    Text("\(previousState) → \(newState)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let reason = event.reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(event.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - TaskExecutionLogRow (Phase 3-4)

struct TaskExecutionLogRow: View {
    let log: ExecutionLog

    var statusColor: Color {
        switch log.status {
        case .running: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }

    var statusIcon: String {
        switch log.status {
        case .running: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Agent: \(log.agentId.value)")
                            .font(.subheadline)
                            .lineLimit(1)

                        Spacer()

                        Text(log.status.rawValue.capitalized)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.15))
                            .foregroundStyle(statusColor)
                            .clipShape(Capsule())
                    }

                    HStack {
                        Text(log.startedAt, style: .date)
                        Text(log.startedAt, style: .time)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let duration = log.durationSeconds {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text("Duration: \(String(format: "%.1f", duration))s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let exitCode = log.exitCode {
                HStack {
                    Image(systemName: exitCode == 0 ? "checkmark.seal" : "xmark.seal")
                        .foregroundStyle(exitCode == 0 ? .green : .red)
                    Text("Exit Code: \(exitCode)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let logPath = log.logFilePath {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    Text(logPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityIdentifier("LogFilePath_\(log.id.value)")
            }

            if let error = log.errorMessage {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
