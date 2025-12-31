// Sources/App/Features/TaskDetail/TaskDetailView.swift
// タスク詳細ビュー

import SwiftUI
import Domain

// Domain.Task と Swift.Task の名前衝突を解決
private typealias AsyncTask = _Concurrency.Task

struct TaskDetailView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router

    let taskId: TaskID

    @State private var task: Task?
    @State private var subtasks: [Subtask] = []
    @State private var contexts: [Context] = []
    @State private var assignee: Agent?
    @State private var isLoading = false
    @State private var newSubtaskTitle = ""

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

                        Divider()

                        // Subtasks
                        subtasksSection

                        Divider()

                        // Context History
                        contextSection
                    }
                    .padding()
                }
            } else if isLoading {
                ProgressView()
            } else {
                ContentUnavailableView(
                    "Task Not Found",
                    systemImage: "doc.questionmark"
                )
            }
        }
        .navigationTitle(task?.title ?? "Task")
        .toolbar {
            if task != nil {
                ToolbarItem {
                    Button {
                        router.showSheet(.editTask(taskId))
                    } label: {
                        Image(systemName: "pencil")
                    }
                }

                ToolbarItem {
                    Button {
                        router.showSheet(.handoff(taskId))
                    } label: {
                        Image(systemName: "arrow.right.arrow.left")
                    }
                    .help("Create Handoff")
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
                StatusBadge(status: task.status)
            }

            Text(task.title)
                .font(.title)
                .fontWeight(.bold)
        }
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

    private var subtasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subtasks")
                .font(.headline)

            ForEach(subtasks, id: \.id) { subtask in
                HStack {
                    Button {
                        toggleSubtask(subtask)
                    } label: {
                        Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(subtask.isCompleted ? .green : .secondary)
                    }
                    .buttonStyle(.plain)

                    Text(subtask.title)
                        .strikethrough(subtask.isCompleted)
                        .foregroundStyle(subtask.isCompleted ? .secondary : .primary)
                }
            }

            HStack {
                TextField("Add subtask...", text: $newSubtaskTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addSubtask()
                    }

                Button("Add") {
                    addSubtask()
                }
                .disabled(newSubtaskTitle.isEmpty)
            }
        }
    }

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Context History")
                .font(.headline)

            if contexts.isEmpty {
                Text("No context saved yet")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(contexts, id: \.id) { context in
                    ContextCard(context: context)
                }
            }
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let detail = try container.getTaskDetailUseCase.execute(taskId: taskId)
            task = detail.task
            subtasks = detail.subtasks
            contexts = detail.contexts

            if let assigneeId = detail.task.assigneeId {
                assignee = try container.agentRepository.findById(assigneeId)
            }
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }

    private func updateStatus(_ newStatus: TaskStatus) {
        AsyncTask {
            do {
                _ = try container.updateTaskStatusUseCase.execute(
                    taskId: taskId,
                    newStatus: newStatus,
                    agentId: nil,
                    sessionId: nil,
                    reason: nil
                )
                await loadData()
            } catch {
                router.showAlert(.error(message: error.localizedDescription))
            }
        }
    }

    private func toggleSubtask(_ subtask: Subtask) {
        AsyncTask {
            do {
                if subtask.isCompleted {
                    _ = try container.completeSubtaskUseCase.uncomplete(subtaskId: subtask.id)
                } else {
                    _ = try container.completeSubtaskUseCase.execute(subtaskId: subtask.id)
                }
                await loadData()
            } catch {
                router.showAlert(.error(message: error.localizedDescription))
            }
        }
    }

    private func addSubtask() {
        guard !newSubtaskTitle.isEmpty else { return }

        AsyncTask {
            do {
                _ = try container.addSubtaskUseCase.execute(
                    taskId: taskId,
                    title: newSubtaskTitle
                )
                newSubtaskTitle = ""
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
        case .inReview: return .purple
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
