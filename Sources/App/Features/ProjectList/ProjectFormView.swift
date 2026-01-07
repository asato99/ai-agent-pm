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
    @State private var allAgents: [Agent] = []
    @State private var assignedAgentIds: Set<AgentID> = []

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

                Section("Assigned Agents") {
                    if allAgents.isEmpty {
                        Text("No agents available")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(allAgents, id: \.id) { agent in
                            Toggle(isOn: Binding(
                                get: { assignedAgentIds.contains(agent.id) },
                                set: { isOn in
                                    if isOn {
                                        assignedAgentIds.insert(agent.id)
                                    } else {
                                        assignedAgentIds.remove(agent.id)
                                    }
                                }
                            )) {
                                HStack {
                                    Text(agent.name)
                                    Spacer()
                                    Text(agent.type.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityIdentifier("AgentToggle_\(agent.id.value)")
                        }
                    }

                    Text("Only assigned agents can be assigned to tasks in this project")
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
                await loadAgents()
                if case .edit(let projectId) = mode {
                    await loadProject(projectId)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 200)
    }

    private func loadAgents() async {
        do {
            allAgents = try container.agentRepository.findAll()
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }

    private func loadProject(_ projectId: ProjectID) async {
        do {
            if let project = try container.projectRepository.findById(projectId) {
                name = project.name
                description = project.description
                workingDirectory = project.workingDirectory ?? ""

                // Load assigned agents
                let assignedAgents = try container.projectAgentAssignmentRepository.findAgentsByProject(projectId)
                assignedAgentIds = Set(assignedAgents.map { $0.id })
            }
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }

    private func save() {
        isSaving = true

        AsyncTask {
            do {
                let projectId: ProjectID
                switch mode {
                case .create:
                    let newProject = try container.createProjectUseCase.execute(
                        name: name,
                        description: description.isEmpty ? nil : description,
                        workingDirectory: workingDirectory.isEmpty ? nil : workingDirectory
                    )
                    projectId = newProject.id
                case .edit(let editProjectId):
                    if var project = try container.projectRepository.findById(editProjectId) {
                        project.name = name
                        project.description = description
                        project.workingDirectory = workingDirectory.isEmpty ? nil : workingDirectory
                        try container.projectRepository.save(project)
                    }
                    projectId = editProjectId
                }

                // Update agent assignments
                try await updateAgentAssignments(for: projectId)

                dismiss()
            } catch {
                isSaving = false
                router.showAlert(.error(message: error.localizedDescription))
            }
        }
    }

    private func updateAgentAssignments(for projectId: ProjectID) async throws {
        // Get current assignments
        let currentAssignments = try container.projectAgentAssignmentRepository.findAgentsByProject(projectId)
        let currentAssignedIds = Set(currentAssignments.map { $0.id })

        // Remove agents that are no longer assigned
        for agentId in currentAssignedIds {
            if !assignedAgentIds.contains(agentId) {
                try container.projectAgentAssignmentRepository.remove(projectId: projectId, agentId: agentId)
            }
        }

        // Add newly assigned agents
        for agentId in assignedAgentIds {
            if !currentAssignedIds.contains(agentId) {
                _ = try container.projectAgentAssignmentRepository.assign(projectId: projectId, agentId: agentId)
            }
        }
    }
}
