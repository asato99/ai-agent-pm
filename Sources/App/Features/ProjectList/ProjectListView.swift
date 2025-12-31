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
            }
        }
        .searchable(text: $searchText, prompt: "Search projects")
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.showSheet(.newProject)
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Project")
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            } else if projects.isEmpty {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "folder.badge.plus",
                    description: Text("Create a new project to get started.")
                )
            }
        }
        .task {
            await loadProjects()
        }
        .refreshable {
            await loadProjects()
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
