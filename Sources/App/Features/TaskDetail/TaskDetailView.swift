// Sources/App/Features/TaskDetail/TaskDetailView.swift
// タスク詳細ビュー
// 要件: サブタスク概念は削除（タスク間の関係は依存関係のみで表現）

import SwiftUI
import Domain

// Domain.Task と Swift.Task の名前衝突を解決
private typealias AsyncTask = _Concurrency.Task

struct TaskDetailView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router

    let taskId: TaskID

    @State private var task: Task?
    @State private var contexts: [Context] = []
    @State private var dependentTasks: [Task] = []
    @State private var handoffs: [Handoff] = []
    @State private var historyEvents: [StateChangeEvent] = []
    @State private var assignee: Agent?
    @State private var isLoading = false

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

                        // Output (成果物情報)
                        if task.outputFileName != nil || task.outputDescription != nil {
                            outputSection(task)
                        }

                        // Status & Assignment
                        statusSection(task)

                        Divider()

                        // Dependencies
                        dependenciesSection

                        Divider()

                        // Handoffs
                        handoffsSection

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
    private func outputSection(_ task: Task) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Output")
                .font(.headline)

            if let fileName = task.outputFileName {
                LabeledContent("File Name") {
                    Text(fileName)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("OutputFileName")
            }

            if let description = task.outputDescription {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(description)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("OutputDescription")
            }
        }
        .accessibilityIdentifier("OutputSection")
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

                // in_progressへの遷移時はエージェントをキック
                if newStatus == .inProgress && updatedTask.assigneeId != nil {
                    do {
                        _ = try await container.kickAgentUseCase.execute(taskId: taskId)
                    } catch {
                        // キック失敗時はエラーを表示（ステータス変更は成功している）
                        router.showAlert(.error(message: error.localizedDescription))
                    }
                }

                await loadData()
            } catch {
                router.showAlert(.error(message: error.localizedDescription))
            }
        }
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
