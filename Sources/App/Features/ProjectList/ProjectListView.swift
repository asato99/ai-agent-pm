// Sources/App/Features/ProjectList/ProjectListView.swift
// プロジェクト一覧サイドバービュー

import SwiftUI
import Domain

private typealias AsyncTask = _Concurrency.Task

struct ProjectListView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router

    @State private var projects: [Project] = []
    @State private var isLoading = false
    @State private var searchText = ""

    var filteredProjects: [Project] {
        if searchText.isEmpty {
            return projects
        }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List(selection: Binding(
            get: { router.selectedProject },
            set: { router.selectProject($0) }
        )) {
            ForEach(filteredProjects, id: \.id) { project in
                ProjectRow(project: project)
                    .tag(project.id)
                    .accessibilityIdentifier("ProjectRow_\(project.id.value)")
            }
        }
        .accessibilityIdentifier("ProjectList")
        .searchable(text: $searchText, prompt: "Search projects")
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.showSheet(.newProject)
                } label: {
                    Label("New Project", systemImage: "plus")
                }
                .accessibilityIdentifier("NewProjectButton")
                .accessibilityLabel("New Project")
                .accessibilityAddTraits(.isButton)
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("New Project (⇧⌘N)")
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
                    .accessibilityIdentifier("LoadingIndicator")
            } else if projects.isEmpty {
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
            await loadProjects()
        }
        .refreshable {
            await loadProjects()
        }
        .onReceive(NotificationCenter.default.publisher(for: .testDataSeeded)) { _ in
            // UIテストデータシード完了後に再読み込み
            _Concurrency.Task {
                await loadProjects()
            }
        }
    }

    private func loadProjects() async {
        isLoading = true
        defer { isLoading = false }

        do {
            projects = try container.getProjectsUseCase.execute()
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }
}

struct ProjectRow: View {
    let project: Project

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
    }
}
