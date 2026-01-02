// Sources/App/Features/ProjectList/ProjectFormView.swift
// プロジェクト作成・編集フォーム

import SwiftUI
import Domain

private typealias AsyncTask = _Concurrency.Task

struct ProjectFormView: View {
    enum Mode {
        case create
        case edit(ProjectID)
    }

    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var workingDirectory: String = ""
    @State private var isSaving = false

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var title: String {
        switch mode {
        case .create: return "New Project"
        case .edit: return "Edit Project"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project Name", text: $name)
                        .accessibilityIdentifier("ProjectNameField")
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("ProjectDescriptionField")
                }

                Section("Execution Settings") {
                    TextField("Working Directory", text: $workingDirectory)
                        .accessibilityIdentifier("ProjectWorkingDirectoryField")

                    Text("Claude Code agent will execute tasks in this directory")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .task {
                if case .edit(let projectId) = mode {
                    await loadProject(projectId)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 200)
    }

    private func loadProject(_ projectId: ProjectID) async {
        do {
            if let project = try container.projectRepository.findById(projectId) {
                name = project.name
                description = project.description
                workingDirectory = project.workingDirectory ?? ""
            }
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }

    private func save() {
        isSaving = true

        AsyncTask {
            do {
                switch mode {
                case .create:
                    _ = try container.createProjectUseCase.execute(
                        name: name,
                        description: description.isEmpty ? nil : description,
                        workingDirectory: workingDirectory.isEmpty ? nil : workingDirectory
                    )
                case .edit(let projectId):
                    if var project = try container.projectRepository.findById(projectId) {
                        project.name = name
                        project.description = description
                        project.workingDirectory = workingDirectory.isEmpty ? nil : workingDirectory
                        try container.projectRepository.save(project)
                    }
                }
                dismiss()
            } catch {
                isSaving = false
                router.showAlert(.error(message: error.localizedDescription))
            }
        }
    }
}
