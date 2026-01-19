// Sources/App/Features/ProjectList/ProjectListView.swift
// サイドバービュー - プロジェクト一覧とエージェント一覧

import SwiftUI
import Domain
import UseCase

private typealias AsyncTask = _Concurrency.Task

struct ProjectListView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router

    @State private var projects: [Project] = []
    @State private var agents: [Agent] = []
    @State private var internalAudits: [InternalAudit] = []
    @State private var isLoading = false
    @State private var searchText = ""

    var filteredProjects: [Project] {
        if searchText.isEmpty {
            return projects
        }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var filteredAgents: [Agent] {
        if searchText.isEmpty {
            return agents
        }
        return agents.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var filteredInternalAudits: [InternalAudit] {
        if searchText.isEmpty {
            return internalAudits
        }
        return internalAudits.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List(selection: Binding(
            get: { router.selectedProject },
            set: { router.selectProject($0) }
        )) {
            // Projects Section
            Section {
                ForEach(filteredProjects, id: \.id) { project in
                    ProjectRow(project: project)
                        .tag(project.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            router.selectProject(project.id)
                        }
                        .accessibilityIdentifier("ProjectRow_\(project.id.value)")
                }
            } header: {
                HStack {
                    Label("Projects", systemImage: "folder")
                    Spacer()
                    Button {
                        router.showSheet(.newProject)
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("NewProjectButton")
                    .accessibilityLabel("New Project")
                    .help("New Project (⇧⌘N)")
                }
            }
            .accessibilityIdentifier("ProjectsSection")

            // Agents Section
            Section {
                ForEach(filteredAgents, id: \.id) { agent in
                    AgentRow(agent: agent, identifier: "AgentRow_\(agent.id.value)")
                        .contentShape(Rectangle())
                        .onTapGesture {
                            router.selectAgent(agent.id)
                        }
                }
            } header: {
                HStack {
                    Label("Agents", systemImage: "person.2")
                    Spacer()
                    Button {
                        router.showSheet(.newAgent)
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("NewAgentButton")
                    .accessibilityLabel("New Agent")
                    .help("New Agent (⇧⌘A)")
                }
            }
            .accessibilityIdentifier("AgentsSection")

            // Internal Audits Section
            Section {
                ForEach(filteredInternalAudits, id: \.id) { audit in
                    InternalAuditRowView(audit: audit)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            router.selectInternalAudit(audit.id)
                            router.showSheet(.internalAuditDetail(audit.id))
                        }
                }
            } header: {
                HStack {
                    Text("Internal Audits")
                        .contentShape(Rectangle())
                        .onTapGesture {
                            router.showInternalAudits()
                        }
                    Image(systemName: "checkmark.shield")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        router.showSheet(.newInternalAudit)
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("SidebarNewInternalAuditButton")
                    .accessibilityLabel("New Internal Audit")
                    .help("New Internal Audit")
                }
            }
            .accessibilityIdentifier("InternalAuditsSection")

            // System Section (MCP Server & Web Server)
            Section {
                MCPServerRowView(daemonManager: container.mcpDaemonManager)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        router.showMCPServer()
                    }

                WebServerRowView(serverManager: container.webServerManager)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        router.showWebServer()
                    }
            } header: {
                Label("System", systemImage: "gearshape.2")
            }
            .accessibilityIdentifier("SystemSection")
        }
        .accessibilityIdentifier("ProjectList")
        .searchable(text: $searchText, prompt: "Search")
        .navigationTitle("Workspace")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        router.showSheet(.newProject)
                    } label: {
                        Label("New Project", systemImage: "folder.badge.plus")
                    }
                    .keyboardShortcut("n", modifiers: [.command, .shift])

                    Button {
                        router.showSheet(.newAgent)
                    } label: {
                        Label("New Agent", systemImage: "person.badge.plus")
                    }
                    .keyboardShortcut("a", modifiers: [.command, .shift])

                    Button {
                        router.showSheet(.newInternalAudit)
                    } label: {
                        Label("New Internal Audit", systemImage: "checkmark.shield")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .accessibilityIdentifier("AddButton")
                .help("Add Project, Agent, or Internal Audit")
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
                    .accessibilityIdentifier("LoadingIndicator")
            } else if projects.isEmpty && agents.isEmpty && internalAudits.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("プロジェクトがありません")
                        .font(.headline)
                    Text("最初のプロジェクトを作成してAIエージェントとの協働を始めましょう")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("新規プロジェクト作成") {
                        router.showSheet(.newProject)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("CreateFirstProjectButton")
                    .accessibilityLabel("新規プロジェクト作成")
                    .accessibilityAddTraits(.isButton)
                }
                .padding()
                .accessibilityIdentifier("EmptyState")
            }
        }
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .testDataSeeded)) { _ in
            // UIテストデータシード完了後に再読み込み
            #if DEBUG
            try? "ProjectListView received testDataSeeded at \(Date())".appendToFile("/tmp/uitest_workflow_debug.txt")
            #endif
            _Concurrency.Task {
                await loadData()
                #if DEBUG
                try? "ProjectListView loadData completed, projects count: \(projects.count)".appendToFile("/tmp/uitest_workflow_debug.txt")
                #endif
            }
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
            projects = try container.getProjectsUseCase.execute()
            agents = try container.getAgentsUseCase.execute()
            internalAudits = try container.listInternalAuditsUseCase.execute(includeInactive: false)
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }
}

struct InternalAuditRowView: View {
    let audit: InternalAudit
    @Environment(Router.self) var router

    private var statusIcon: String {
        audit.status == .active ? "checkmark.shield" : "pause.circle"
    }

    private var statusColor: Color {
        audit.status == .active ? Color.accentColor : Color.secondary
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(audit.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .accessibilityIdentifier("InternalAuditName_\(audit.id.value)")

                if let description = audit.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if audit.status == .suspended {
                Text("Suspended")
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("InternalAuditRow_\(audit.id.value)")
        .contextMenu {
            Button {
                router.showSheet(.editInternalAudit(audit.id))
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .accessibilityIdentifier("EditAuditMenuItem")
        }
    }
}

struct TemplateRowView: View {
    let template: WorkflowTemplate
    @Environment(Router.self) var router

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.doc")
                .foregroundStyle(Color.accentColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .accessibilityIdentifier("TemplateName_\(template.id.value)")

                if !template.description.isEmpty {
                    Text(template.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !template.variables.isEmpty {
                Text("\(template.variables.count)")
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("TemplateRow_\(template.id.value)")
        .contextMenu {
            Button {
                router.showSheet(.editTemplate(template.id))
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .accessibilityIdentifier("EditTemplateMenuItem")

            if let projectId = router.selectedProject {
                Button {
                    router.showSheet(.instantiateTemplate(template.id, projectId))
                } label: {
                    Label("Apply to Project", systemImage: "arrow.right.doc.on.clipboard")
                }
                .accessibilityIdentifier("InstantiateTemplateMenuItem")
            }
        }
    }
}

struct AgentRow: View {
    let agent: Agent
    var identifier: String? = nil

    var statusIcon: String {
        switch agent.status {
        case .active: return "🟢"
        case .inactive: return "🟡"
        case .suspended: return "🟠"
        case .archived: return "⚫"
        }
    }

    var typeIcon: String {
        agent.type == .ai ? "🤖" : "👤"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(typeIcon)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .accessibilityIdentifier("AgentName_\(agent.id.value)")

                Text(agent.role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(statusIcon)
                .font(.caption)
                .accessibilityIdentifier("AgentStatus_\(agent.id.value)")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier ?? "AgentRow_\(agent.id.value)")
    }
}

struct ProjectRow: View {
    let project: Project
    @Environment(Router.self) var router
    @EnvironmentObject var container: DependencyContainer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(project.name)
                    .font(.headline)

                Spacer()

                // プロジェクトステータス表示
                if project.status == .paused {
                    Text("Paused")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(4)
                } else {
                    Text("Active")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(4)
                }
            }

            if !project.description.isEmpty {
                Text(project.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                router.showSheet(.editProject(project.id))
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .accessibilityIdentifier("EditProjectMenuItem")

            Divider()

            // 一時停止/再開ボタン
            if project.status == .active {
                Button {
                    pauseProject()
                } label: {
                    Label("Pause", systemImage: "pause.circle")
                }
                .accessibilityIdentifier("PauseProjectMenuItem")
            } else if project.status == .paused {
                Button {
                    resumeProject()
                } label: {
                    Label("Resume", systemImage: "play.circle")
                }
                .accessibilityIdentifier("ResumeProjectMenuItem")
            }
        }
    }

    private func pauseProject() {
        AsyncTask {
            do {
                let useCase = PauseProjectUseCase(
                    projectRepository: container.projectRepository,
                    agentSessionRepository: container.agentSessionRepository
                )
                try await useCase.execute(projectId: project.id)
                // UI更新は@Published経由で自動的に行われることを期待
                // 必要であればNotificationCenterで通知
                NotificationCenter.default.post(name: .testDataSeeded, object: nil)
            } catch {
                print("Failed to pause project: \(error)")
            }
        }
    }

    private func resumeProject() {
        AsyncTask {
            do {
                let useCase = ResumeProjectUseCase(
                    projectRepository: container.projectRepository
                )
                try await useCase.execute(projectId: project.id)
                // UI更新
                NotificationCenter.default.post(name: .testDataSeeded, object: nil)
            } catch {
                print("Failed to resume project: \(error)")
            }
        }
    }
}
