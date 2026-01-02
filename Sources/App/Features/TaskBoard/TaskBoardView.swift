// Sources/App/Features/TaskBoard/TaskBoardView.swift
// カンバンスタイルのタスクボードビュー

import SwiftUI
import Domain

private typealias AsyncTask = _Concurrency.Task

struct TaskBoardView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router

    let projectId: ProjectID

    @State private var tasks: [Task] = []
    @State private var agents: [Agent] = []
    @State private var project: Project?
    @State private var isLoading = false

    private let columns: [TaskStatus] = [.backlog, .todo, .inProgress, .blocked, .done]

    var body: some View {
        VStack(spacing: 0) {
            // Project Info Header
            if let project = project {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Working Directory:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(project.workingDirectory ?? "Not set")
                            .font(.caption)
                            .foregroundStyle(project.workingDirectory != nil ? .primary : .tertiary)
                            .accessibilityIdentifier("WorkingDirectoryValue")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("ProjectWorkingDirectory")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.background.secondary)
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(columns, id: \.self) { status in
                        TaskColumnView(
                            status: status,
                            tasks: tasks.filter { $0.status == status },
                            agents: agents
                        )
                        .accessibilityIdentifier("TaskColumn_\(status.rawValue)")
                    }
                }
                .padding()
            }
        }
        .accessibilityIdentifier("TaskBoard")
        .navigationTitle("Task Board")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.showSheet(.newTask(projectId))
                } label: {
                    Label("New Task", systemImage: "plus")
                }
                .accessibilityIdentifier("NewTaskButton")
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .help("New Task (⇧⌘T)")
            }

            ToolbarItem {
                Button {
                    AsyncTask { await loadData() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("RefreshButton")
                .keyboardShortcut("r", modifiers: [.command])
                .help("Refresh (⌘R)")
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
                    .accessibilityIdentifier("LoadingIndicator")
            }
        }
        .task {
            await loadData()
        }
        .onChange(of: router.currentSheet) { oldValue, newValue in
            // シートが閉じられた時にデータを再読み込み
            if oldValue != nil && newValue == nil {
                AsyncTask { await loadData() }
            }
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            project = try container.projectRepository.findById(projectId)
            tasks = try container.getTasksUseCase.execute(projectId: projectId, status: nil)
            agents = try container.getAgentsUseCase.execute()
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }
}

struct TaskColumnView: View {
    @Environment(Router.self) var router

    let status: TaskStatus
    let tasks: [Task]
    let agents: [Agent]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(status.displayName)
                    .font(.headline)
                    .accessibilityLabel(status.displayName)  // 明示的にラベルを設定
                    .accessibilityIdentifier("ColumnHeader_\(status.rawValue)")
                Spacer()
                Text("\(tasks.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
                    .accessibilityIdentifier("ColumnCount_\(status.rawValue)")
            }
            .padding(.horizontal, 8)

            // Tasks
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(tasks, id: \.id) { task in
                        TaskCardButton(task: task, agents: agents) {
                            router.selectTask(task.id)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(width: 280)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct TaskCardView: View {
    let task: Task
    let agents: [Agent]

    var assigneeName: String? {
        guard let assigneeId = task.assigneeId else { return nil }
        return agents.first { $0.id == assigneeId }?.name
    }

    var assigneeIcon: String {
        guard let assigneeId = task.assigneeId,
              let agent = agents.first(where: { $0.id == assigneeId }) else {
            return "👻"
        }
        return agent.type == .ai ? "🤖" : "👤"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .accessibilityLabel(task.title)  // 明示的にラベルを設定
                .accessibilityIdentifier("TaskTitle_\(task.id.value)")

            if !task.description.isEmpty {
                Text(task.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityLabel(task.description)  // 明示的にラベルを設定
                    .accessibilityIdentifier("TaskDescription")
            }

            HStack {
                PriorityBadge(priority: task.priority)
                    .accessibilityIdentifier("PriorityBadge_\(task.priority.rawValue)")

                Spacer()

                if let name = assigneeName {
                    Text("\(assigneeIcon) \(name)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("TaskAssignee")
                }
            }
        }
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))  // タップ領域を明確に定義
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct PriorityBadge: View {
    let priority: TaskPriority

    var color: Color {
        switch priority {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .blue
        case .low: return .gray
        }
    }

    var body: some View {
        Text(priority.rawValue.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .accessibilityLabel("Priority")
            .accessibilityValue(priority.rawValue.capitalized)
    }
}

/// タスクカードボタン
/// XCUITestでタイトルが認識できるよう、キーボードアクセシブルなButtonを使用
struct TaskCardButton: View {
    let task: Task
    let agents: [Agent]
    let action: () -> Void

    @FocusState private var isFocused: Bool

    /// アサイニー名を取得
    private var assigneeName: String? {
        guard let assigneeId = task.assigneeId else { return nil }
        return agents.first { $0.id == assigneeId }?.name
    }

    /// アクセシビリティラベル（タイトル + アサイニー名）
    private var accessibilityLabelText: String {
        if let name = assigneeName {
            return "\(task.title), assigned to \(name)"
        }
        return task.title
    }

    var body: some View {
        Button(action: action) {
            TaskCardView(task: task, agents: agents)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($isFocused)
        // アクセシビリティ設定
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("TaskCard_\(task.id.value)")
    }
}

// displayName is already defined in Domain/Entities/Task.swift
