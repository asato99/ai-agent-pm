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
    @State private var isLoading = false

    private let columns: [TaskStatus] = [.backlog, .todo, .inProgress, .inReview, .done]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(columns, id: \.self) { status in
                    TaskColumnView(
                        status: status,
                        tasks: tasks.filter { $0.status == status },
                        agents: agents
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Task Board")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.showSheet(.newTask(projectId))
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Task")
            }

            ToolbarItem {
                Button {
                    AsyncTask { await loadData() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            tasks = try container.getTasksUseCase.execute(projectId: projectId, status: nil)
            agents = try container.getAgentsUseCase.execute(projectId: projectId)
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
                Spacer()
                Text("\(tasks.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 8)

            // Tasks
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(tasks, id: \.id) { task in
                        TaskCardView(task: task, agents: agents)
                            .onTapGesture {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)

            if !task.description.isEmpty {
                Text(task.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                PriorityBadge(priority: task.priority)

                Spacer()

                if let name = assigneeName {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
    }
}

extension TaskStatus {
    var displayName: String {
        switch self {
        case .backlog: return "Backlog"
        case .todo: return "To Do"
        case .inProgress: return "In Progress"
        case .inReview: return "In Review"
        case .blocked: return "Blocked"
        case .done: return "Done"
        case .cancelled: return "Cancelled"
        }
    }
}
