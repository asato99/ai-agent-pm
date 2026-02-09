// Sources/App/Features/AgentManagement/AgentDetailView.swift
// エージェント詳細ビュー
// コンポーネント: AgentDetailComponents.swift
// ログビューア: LogViewer.swift

import SwiftUI
import Domain

private typealias AsyncTask = _Concurrency.Task

/// タブの種類
private enum AgentDetailTab: String, CaseIterable {
    case profile = "プロファイル"
    case executionHistory = "実行履歴"
}

struct AgentDetailView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router

    let agentId: AgentID

    @State private var agent: Agent?
    @State private var tasks: [Task] = []
    @State private var sessions: [Session] = []
    @State private var executionLogs: [ExecutionLog] = []
    @State private var taskCache: [TaskID: Task] = [:]
    @State private var projectCache: [ProjectID: Project] = [:]
    @State private var isLoading = false
    @State private var isPasskeyVisible = false
    @State private var showRegenerateConfirmation = false
    @State private var selectedTab: AgentDetailTab = .profile
    @State private var selectedLogForViewer: ExecutionLog?
    @State private var assignedSkills: [SkillDefinition] = []
    @State private var showSkillAssignment = false

    var body: some View {
        Group {
            if let agent = agent {
                VStack(spacing: 0) {
                    // Header (always visible)
                    agentHeader(agent)
                        .padding()

                    Divider()

                    // Tab Picker
                    Picker("Tab", selection: $selectedTab) {
                        ForEach(AgentDetailTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("AgentDetailTabPicker")

                    Divider()

                    // Tab Content
                    TabView(selection: $selectedTab) {
                        profileTabContent(agent)
                            .tag(AgentDetailTab.profile)

                        executionHistoryTabContent
                            .tag(AgentDetailTab.executionHistory)
                    }
                    .tabViewStyle(.automatic)
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
        .sheet(item: $selectedLogForViewer) { log in
            LogViewerSheet(
                log: log,
                task: taskCache[log.taskId],
                project: taskCache[log.taskId].flatMap { projectCache[$0.projectId] },
                agent: agent
            )
        }
        .sheet(isPresented: $showSkillAssignment) {
            if let agent = agent {
                AgentSkillAssignmentView(
                    agent: agent,
                    onSave: { skillIds in
                        showSkillAssignment = false
                        saveSkillAssignment(skillIds)
                    },
                    onCancel: {
                        showSkillAssignment = false
                    }
                )
                .environmentObject(container)
            }
        }
    }

    // MARK: - Profile Tab Content

    @ViewBuilder
    private func profileTabContent(_ agent: Agent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Stats
                statsSection

                Divider()

                // Passkey (Phase 3-4)
                passkeySection(agent)

                Divider()

                // Skills
                AgentSkillsSection(
                    assignedSkills: assignedSkills,
                    onManageSkills: {
                        showSkillAssignment = true
                    }
                )

                Divider()

                // Assigned Tasks
                tasksSection

                Divider()

                // Session History
                sessionsSection
            }
            .padding()
        }
        .accessibilityIdentifier("ProfileTabContent")
    }

    // MARK: - Execution History Tab Content

    private var executionHistoryTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if executionLogs.isEmpty {
                    ContentUnavailableView(
                        "No Execution History",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("This agent has not executed any tasks yet.")
                    )
                    .accessibilityIdentifier("NoExecutionHistoryMessage")
                } else {
                    ForEach(executionLogs, id: \.id) { log in
                        ExecutionLogDetailRow(
                            log: log,
                            task: taskCache[log.taskId],
                            project: taskCache[log.taskId].flatMap { projectCache[$0.projectId] },
                            onOpenLog: {
                                selectedLogForViewer = log
                            }
                        )
                        .accessibilityIdentifier("ExecutionLog_\(log.id.value)")
                    }
                }
            }
            .padding()
        }
        .accessibilityIdentifier("ExecutionHistoryTabContent")
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

    private func saveSkillAssignment(_ skillIds: [SkillID]) {
        AsyncTask {
            do {
                try container.agentSkillUseCases.assignSkills(agentId: agentId, skillIds: skillIds)
                // スキルを再読み込み
                assignedSkills = try container.agentSkillUseCases.getAgentSkills(agentId)
            } catch {
                router.showAlert(.error(message: error.localizedDescription))
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
            executionLogs = try container.getExecutionLogsUseCase.executeByAgentId(agentId)
            assignedSkills = try container.agentSkillUseCases.getAgentSkills(agentId)

            // 実行ログに関連するタスクとプロジェクトをキャッシュに読み込む
            var newTaskCache: [TaskID: Task] = [:]
            var newProjectCache: [ProjectID: Project] = [:]

            for log in executionLogs {
                if newTaskCache[log.taskId] == nil {
                    if let task = try container.taskRepository.findById(log.taskId) {
                        newTaskCache[log.taskId] = task
                        if newProjectCache[task.projectId] == nil {
                            if let project = try container.projectRepository.findById(task.projectId) {
                                newProjectCache[task.projectId] = project
                            }
                        }
                    }
                }
            }

            taskCache = newTaskCache
            projectCache = newProjectCache
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }
}
