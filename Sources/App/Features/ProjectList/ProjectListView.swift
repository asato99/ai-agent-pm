// Sources/App/Features/ProjectList/ProjectListView.swift
// サイドバービュー - プロジェクト一覧とエージェント一覧

import SwiftUI
import Domain

private typealias AsyncTask = _Concurrency.Task

struct ProjectListView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router

    @State private var projects: [Project] = []
    @State private var agents: [Agent] = []
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
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .accessibilityIdentifier("AddButton")
                .help("Add Project or Agent")
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
                    .accessibilityIdentifier("LoadingIndicator")
            } else if projects.isEmpty && agents.isEmpty {
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
            _Concurrency.Task {
                await loadData()
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
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(.headline)

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
        }
    }
}
