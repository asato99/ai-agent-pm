// Sources/App/Features/AgentManagement/AgentDetailView.swift
// エージェント詳細ビュー

import SwiftUI
import Domain

private typealias AsyncTask = _Concurrency.Task

struct AgentDetailView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router

    let agentId: AgentID

    @State private var agent: Agent?
    @State private var tasks: [Task] = []
    @State private var sessions: [Session] = []
    @State private var isLoading = false

    var body: some View {
        Group {
            if let agent = agent {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header
                        agentHeader(agent)

                        Divider()

                        // Stats
                        statsSection

                        Divider()

                        // Assigned Tasks
                        tasksSection

                        Divider()

                        // Session History
                        sessionsSection
                    }
                    .padding()
                }
                .accessibilityIdentifier("AgentDetailView")
            } else if isLoading {
                ProgressView()
                    .accessibilityIdentifier("LoadingIndicator")
            } else {
                ContentUnavailableView(
                    "Agent Not Found",
                    systemImage: "person.crop.circle.badge.questionmark"
                )
                .accessibilityIdentifier("AgentNotFound")
            }
        }
        .navigationTitle(agent?.name ?? "Agent")
        .toolbar {
            if agent != nil {
                ToolbarItem {
                    Button {
                        router.showSheet(.editAgent(agentId))
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("EditAgentButton")
                }
            }
        }
        .task {
            await loadData()
        }
    }

    @ViewBuilder
    private func agentHeader(_ agent: Agent) -> some View {
        HStack(spacing: 16) {
            Image(systemName: agent.type == .human ? "person.circle.fill" : "cpu.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(agent.name)
                    .font(.title)
                    .fontWeight(.bold)

                Text(agent.role)
                    .foregroundStyle(.secondary)

                HStack {
                    RoleTypeBadge(roleType: agent.roleType)
                    AgentTypeBadge(type: agent.type)
                    AgentStatusBadge(status: agent.status)
                }
            }
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)

            HStack(spacing: 32) {
                StatItem(title: "Assigned Tasks", value: "\(tasks.count)")
                StatItem(title: "In Progress", value: "\(tasks.filter { $0.status == .inProgress }.count)")
                StatItem(title: "Completed", value: "\(tasks.filter { $0.status == .done }.count)")
                StatItem(title: "Sessions", value: "\(sessions.count)")
            }
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Assigned Tasks")
                .font(.headline)

            if tasks.isEmpty {
                Text("No tasks assigned")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(tasks, id: \.id) { task in
                    TaskRow(task: task)
                        .onTapGesture {
                            router.selectTask(task.id)
                        }
                }
            }
        }
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Sessions")
                .font(.headline)

            if sessions.isEmpty {
                Text("No sessions yet")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(sessions.prefix(5), id: \.id) { session in
                    SessionRow(session: session)
                }
            }
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            agent = try container.getAgentProfileUseCase.execute(agentId: agentId)
            tasks = try container.getTasksByAssigneeUseCase.execute(assigneeId: agentId)
            sessions = try container.getAgentSessionsUseCase.execute(agentId: agentId)
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }
}

struct StatItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct TaskRow: View {
    let task: Task

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(task.title)
                    .font(.subheadline)
                Text(task.status.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            PriorityBadge(priority: task.priority)
        }
        .padding(.vertical, 4)
    }
}

struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(session.startedAt, style: .date)
                    .font(.subheadline)
                Text(session.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let endedAt = session.endedAt {
                Text(endedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct RoleTypeBadge: View {
    let roleType: AgentRoleType

    var body: some View {
        Text(roleType.rawValue.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.blue.opacity(0.15))
            .foregroundStyle(.blue)
            .clipShape(Capsule())
    }
}

struct AgentTypeBadge: View {
    let type: AgentType

    var body: some View {
        Text(type == .human ? "Human" : "AI")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.purple.opacity(0.15))
            .foregroundStyle(.purple)
            .clipShape(Capsule())
    }
}

struct AgentStatusBadge: View {
    let status: AgentStatus

    var color: Color {
        switch status {
        case .active: return .green
        case .inactive: return .gray
        case .suspended: return .orange
        case .archived: return .red
        }
    }

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
