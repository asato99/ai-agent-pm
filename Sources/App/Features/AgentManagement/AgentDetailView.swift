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
    @State private var executionLogs: [ExecutionLog] = []
    @State private var isLoading = false
    @State private var isPasskeyVisible = false
    @State private var showRegenerateConfirmation = false

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

                        // Passkey (Phase 3-4)
                        passkeySection(agent)

                        Divider()

                        // Assigned Tasks
                        tasksSection

                        Divider()

                        // Execution Logs (Phase 3-4)
                        executionLogsSection

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

                Text("ID: \(agent.id.value)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("AgentIdDisplay")

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

    // MARK: - Passkey Section (Phase 3-4)

    @ViewBuilder
    private func passkeySection(_ agent: Agent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Passkey")
                .font(.headline)
                .accessibilityIdentifier("PasskeyHeader")

            if agent.authLevel == .level0 {
                Text("This agent uses Level 0 authentication (no passkey required)")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .accessibilityIdentifier("PasskeyNotRequired")
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auth Level: \(agent.authLevel.displayName)")
                            .font(.subheadline)
                            .accessibilityIdentifier("AuthLevelDisplay")

                        if let passkey = agent.passkey {
                            HStack {
                                if isPasskeyVisible {
                                    Text(passkey)
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)
                                } else {
                                    Text(String(repeating: "•", count: min(passkey.count, 16)))
                                        .font(.system(.body, design: .monospaced))
                                }
                            }
                            .accessibilityIdentifier("PasskeyDisplay")
                        } else {
                            Text("No passkey set")
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("NoPasskeyMessage")
                        }
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button {
                            isPasskeyVisible.toggle()
                        } label: {
                            Image(systemName: isPasskeyVisible ? "eye.slash" : "eye")
                        }
                        .accessibilityIdentifier("ShowPasskeyButton")
                        .help(isPasskeyVisible ? "Hide Passkey" : "Show Passkey")

                        Button {
                            showRegenerateConfirmation = true
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityIdentifier("RegeneratePasskeyButton")
                        .help("Regenerate Passkey")
                    }
                }
            }
        }
        .accessibilityIdentifier("PasskeySection")
        .alert("Regenerate Passkey?", isPresented: $showRegenerateConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Regenerate", role: .destructive) {
                regeneratePasskey()
            }
            .accessibilityIdentifier("ConfirmButton")
        } message: {
            Text("This will invalidate the current passkey. Any existing Runner configurations will need to be updated.")
        }
    }

    private func regeneratePasskey() {
        AsyncTask {
            do {
                // パスキーを再生成
                let newPasskey = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(32))
                var updatedAgent = agent!
                updatedAgent.passkey = newPasskey
                updatedAgent.updatedAt = Date()

                try container.agentRepository.save(updatedAgent)

                // AgentCredentialも作成/更新（認証とエクスポートに必要）
                // 既存のcredentialがあれば削除
                if let existing = try container.agentCredentialRepository.findByAgentId(updatedAgent.id) {
                    try container.agentCredentialRepository.delete(existing.id)
                }
                let credential = AgentCredential(
                    agentId: updatedAgent.id,
                    rawPasskey: newPasskey
                )
                try container.agentCredentialRepository.save(credential)

                agent = updatedAgent

                router.showAlert(.info(title: "Success", message: "Passkey updated"))
            } catch {
                router.showAlert(.error(message: error.localizedDescription))
            }
        }
    }

    // MARK: - Execution Logs Section (Phase 3-4)

    private var executionLogsSection: some View {
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
                ForEach(executionLogs.prefix(10), id: \.id) { log in
                    ExecutionLogRow(log: log)
                        .accessibilityIdentifier("ExecutionLog_\(log.id.value)")
                }
            }
        }
        .accessibilityIdentifier("ExecutionLogsSection")
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            agent = try container.getAgentProfileUseCase.execute(agentId: agentId)
            tasks = try container.getTasksByAssigneeUseCase.execute(assigneeId: agentId)
            sessions = try container.getAgentSessionsUseCase.execute(agentId: agentId)
            executionLogs = try container.getExecutionLogsUseCase.executeByAgentId(agentId)
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }
}

// MARK: - ExecutionLogRow (Phase 3-4)

struct ExecutionLogRow: View {
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
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Task: \(log.taskId.value)")
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

                if let duration = log.durationSeconds {
                    Text("Duration: \(String(format: "%.1f", duration))s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = log.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
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
