// Sources/App/Features/AgentManagement/AgentFormView.swift
// エージェント作成・編集フォーム

import SwiftUI
import Domain

private typealias AsyncTask = _Concurrency.Task

struct AgentFormView: View {
    enum Mode {
        case create(projectId: ProjectID)
        case edit(AgentID)
    }

    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var name: String = ""
    @State private var role: String = ""
    @State private var roleType: AgentRoleType = .developer
    @State private var type: AgentType = .ai
    @State private var systemPrompt: String = ""
    @State private var isSaving = false

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var formTitle: String {
        switch mode {
        case .create: return "New Agent"
        case .edit: return "Edit Agent"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Name", text: $name)
                    TextField("Role Description", text: $role)
                }

                Section("Type") {
                    Picker("Role Type", selection: $roleType) {
                        ForEach(AgentRoleType.allCases, id: \.self) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }

                    Picker("Agent Type", selection: $type) {
                        Text("AI Agent").tag(AgentType.ai)
                        Text("Human").tag(AgentType.human)
                    }
                }

                if type == .ai {
                    Section("AI Configuration") {
                        TextField("System Prompt", text: $systemPrompt, axis: .vertical)
                            .lineLimit(5...10)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(formTitle)
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
                if case .edit(let agentId) = mode {
                    await loadAgent(agentId)
                }
            }
        }
        .frame(minWidth: 450, minHeight: 400)
    }

    private func loadAgent(_ agentId: AgentID) async {
        do {
            if let agent = try container.agentRepository.findById(agentId) {
                name = agent.name
                role = agent.role
                roleType = agent.roleType
                type = agent.type
                systemPrompt = agent.systemPrompt ?? ""
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
                case .create(let projectId):
                    _ = try container.createAgentUseCase.execute(
                        projectId: projectId,
                        name: name,
                        role: role,
                        roleType: roleType,
                        type: type,
                        systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt
                    )
                case .edit(let agentId):
                    if var agent = try container.agentRepository.findById(agentId) {
                        agent.name = name
                        agent.role = role
                        agent.roleType = roleType
                        agent.type = type
                        agent.systemPrompt = systemPrompt.isEmpty ? nil : systemPrompt
                        try container.agentRepository.save(agent)
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
