// Sources/App/Features/AgentManagement/AgentDetailView.swift
// エージェント詳細ビュー

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

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            agent = try container.getAgentProfileUseCase.execute(agentId: agentId)
            tasks = try container.getTasksByAssigneeUseCase.execute(assigneeId: agentId)
            sessions = try container.getAgentSessionsUseCase.execute(agentId: agentId)
            executionLogs = try container.getExecutionLogsUseCase.executeByAgentId(agentId)

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

// MARK: - ExecutionLogDetailRow (Enhanced)

/// 実行履歴タブ用の詳細行（プロジェクト名、タスクタイトル、ログを開くボタン付き）
struct ExecutionLogDetailRow: View {
    let log: ExecutionLog
    let task: Task?
    let project: Project?
    let onOpenLog: () -> Void

    private var statusColor: Color {
        switch log.status {
        case .running: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }

    private var statusIcon: String {
        switch log.status {
        case .running: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private var durationText: String {
        guard let duration = log.durationSeconds else { return "" }
        if duration < 60 {
            return String(format: "%.0f秒", duration)
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)分\(seconds)秒"
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)時間\(minutes)分"
        }
    }

    private var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var text = formatter.string(from: log.startedAt)
        if let completedAt = log.completedAt {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm:ss"
            text += " - " + timeFormatter.string(from: completedAt)
        }
        if !durationText.isEmpty {
            text += " (\(durationText))"
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with time range
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.title3)

                Text(timeRangeText)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text(log.status.rawValue.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }

            // Project info
            if let project = project {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("プロジェクト: \(project.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Task info
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let task = task {
                    Text("タスク: \(log.taskId.value.prefix(12))... \(task.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("タスク: \(log.taskId.value)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Error message if any
            if let error = log.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            // Open Log button
            if log.logFilePath != nil {
                Button(action: onOpenLog) {
                    Label("ログを開く", systemImage: "doc.text")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("OpenLogButton_\(log.id.value)")
            } else {
                Text("ログファイルなし")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - LogViewerSheet

/// ログファイルの内容を表示するシート
struct LogViewerSheet: View {
    let log: ExecutionLog
    let task: Task?
    let project: Project?
    let agent: Agent?

    @Environment(\.dismiss) private var dismiss
    @State private var logContent: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var isWordWrapEnabled = true

    private var filteredContent: String {
        guard !searchText.isEmpty else { return logContent }
        // 簡易的なハイライト（実際の検索）
        return logContent
    }

    private var durationText: String {
        guard let duration = log.durationSeconds else { return "-" }
        if duration < 60 {
            return String(format: "%.1f秒", duration)
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)分\(seconds)秒"
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)時間\(minutes)分"
        }
    }

    private var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var text = formatter.string(from: log.startedAt)
        if let completedAt = log.completedAt {
            text += " - " + formatter.string(from: completedAt)
        }
        return text
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("実行ログ")
                    .font(.headline)
                Spacer()
                Button("閉じる") {
                    dismiss()
                }
                .accessibilityIdentifier("CloseLogViewerButton")
            }
            .padding()

            Divider()

            // Metadata
            VStack(alignment: .leading, spacing: 4) {
                if let agent = agent {
                    HStack {
                        Text("エージェント:")
                            .foregroundStyle(.secondary)
                        Text(agent.name)
                    }
                    .font(.caption)
                }

                if let task = task {
                    HStack {
                        Text("タスク:")
                            .foregroundStyle(.secondary)
                        Text("\(log.taskId.value.prefix(12))... \(task.title)")
                            .lineLimit(1)
                    }
                    .font(.caption)
                }

                if let project = project {
                    HStack {
                        Text("プロジェクト:")
                            .foregroundStyle(.secondary)
                        Text(project.name)
                    }
                    .font(.caption)
                }

                HStack {
                    Text("実行期間:")
                        .foregroundStyle(.secondary)
                    Text("\(timeRangeText) (\(durationText))")
                }
                .font(.caption)

                HStack {
                    Text("結果:")
                        .foregroundStyle(.secondary)
                    Text(log.status.rawValue)
                        .foregroundStyle(log.status == .completed ? .green : (log.status == .failed ? .red : .orange))
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.controlBackgroundColor))

            Divider()

            // Search and options
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("検索...", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("LogSearchField")

                Spacer()

                Toggle(isOn: $isWordWrapEnabled) {
                    Text("折り返し")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("WordWrapToggle")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Log content
            Group {
                if isLoading {
                    ProgressView("ログを読み込み中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    ContentUnavailableView(
                        "ログを読み込めません",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else {
                    ScrollView([.vertical, .horizontal]) {
                        Text(filteredContent)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: isWordWrapEnabled ? .infinity : nil, alignment: .topLeading)
                            .textSelection(.enabled)
                            .padding()
                    }
                    .accessibilityIdentifier("LogContentScrollView")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, minHeight: 500)
        .task {
            await loadLogContent()
        }
    }

    private func loadLogContent() async {
        guard let path = log.logFilePath else {
            errorMessage = "ログファイルパスが設定されていません"
            isLoading = false
            return
        }

        do {
            let url = URL(fileURLWithPath: path)
            let content = try String(contentsOf: url, encoding: .utf8)
            logContent = content
            isLoading = false
        } catch {
            errorMessage = "ファイルを読み込めませんでした: \(error.localizedDescription)"
            isLoading = false
        }
    }
}
