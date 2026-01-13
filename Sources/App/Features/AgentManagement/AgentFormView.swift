// Sources/App/Features/AgentManagement/AgentFormView.swift
// エージェント作成・編集フォーム

import SwiftUI
import Domain

private typealias AsyncTask = _Concurrency.Task

struct AgentFormView: View {
    enum Mode {
        case create
        case edit(AgentID)
    }

    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var name: String = ""
    @State private var role: String = ""
    @State private var hierarchyType: AgentHierarchyType = .worker
    @State private var roleType: AgentRoleType = .developer
    @State private var type: AgentType = .ai
    @State private var aiType: AIType? = nil
    @State private var parentAgentId: AgentID? = nil
    @State private var maxParallelTasks: Int = 1
    @State private var systemPrompt: String = ""
    @State private var authLevel: AuthLevel = .level0
    @State private var passkey: String = ""
    @State private var isSaving = false
    @State private var availableAgents: [Agent] = []

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
                        .accessibilityIdentifier("AgentNameField")
                    TextField("Role Description", text: $role)
                        .accessibilityIdentifier("AgentRoleField")
                }

                Section("Type") {
                    Picker("Hierarchy Type", selection: $hierarchyType) {
                        ForEach(AgentHierarchyType.allCases, id: \.self) { hType in
                            Text(hType.displayName).tag(hType)
                        }
                    }
                    .accessibilityIdentifier("HierarchyTypePicker")

                    Picker("Role Type", selection: $roleType) {
                        ForEach(AgentRoleType.allCases, id: \.self) { rType in
                            Text(rType.rawValue.capitalized).tag(rType)
                        }
                    }

                    Picker("Agent Type", selection: $type) {
                        Text("AI Agent").tag(AgentType.ai)
                        Text("Human").tag(AgentType.human)
                    }
                }

                Section("Hierarchy & Resources") {
                    Picker("Parent Agent", selection: $parentAgentId) {
                        Text("None (Top Level)").tag(nil as AgentID?)
                        ForEach(availableAgents, id: \.id) { agent in
                            Text(agent.name).tag(agent.id as AgentID?)
                        }
                    }
                    .accessibilityIdentifier("ParentAgentPicker")

                    Stepper(value: $maxParallelTasks, in: 1...10) {
                        HStack {
                            Text("Max Parallel Tasks")
                            Spacer()
                            Text("\(maxParallelTasks)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("MaxParallelTasksStepper")
                }

                Section("Authentication") {
                    Picker("Auth Level", selection: $authLevel) {
                        ForEach(AuthLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .accessibilityIdentifier("AuthLevelPicker")

                    SecureField("Passkey", text: $passkey)
                        .accessibilityIdentifier("PasskeyField")
                }

                if type == .ai {
                    Section("AI Configuration") {
                        Picker("AI Model", selection: $aiType) {
                            Text("Not Specified").tag(nil as AIType?)
                            ForEach(AIType.allCases, id: \.self) { model in
                                Text(model.displayName).tag(model as AIType?)
                            }
                        }
                        .accessibilityIdentifier("AITypePicker")

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
                await loadAvailableAgents()
                if case .edit(let agentId) = mode {
                    await loadAgent(agentId)
                }
            }
        }
        .frame(minWidth: 450, minHeight: 400)
    }

    private func loadAvailableAgents() async {
        do {
            var agents = try container.agentRepository.findAll()
            // 編集モードの場合、自分自身を除外（自己参照防止）
            if case .edit(let agentId) = mode {
                agents = agents.filter { $0.id != agentId }
            }
            availableAgents = agents
        } catch {
            // エラーは無視（空リストで続行）
        }
    }

    private func loadAgent(_ agentId: AgentID) async {
        do {
            if let agent = try container.agentRepository.findById(agentId) {
                name = agent.name
                role = agent.role
                hierarchyType = agent.hierarchyType
                roleType = agent.roleType
                type = agent.type
                aiType = agent.aiType
                parentAgentId = agent.parentAgentId
                maxParallelTasks = agent.maxParallelTasks
                systemPrompt = agent.systemPrompt ?? ""
                authLevel = agent.authLevel
                passkey = agent.passkey ?? ""
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
                    _ = try container.createAgentUseCase.execute(
                        name: name,
                        role: role,
                        hierarchyType: hierarchyType,
                        roleType: roleType,
                        type: type,
                        aiType: aiType,
                        parentAgentId: parentAgentId,
                        maxParallelTasks: maxParallelTasks,
                        systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt,
                        authLevel: authLevel,
                        passkey: passkey.isEmpty ? nil : passkey
                    )
                case .edit(let agentId):
                    if var agent = try container.agentRepository.findById(agentId) {
                        agent.name = name
                        agent.role = role
                        agent.hierarchyType = hierarchyType
                        agent.roleType = roleType
                        agent.type = type
                        agent.aiType = aiType
                        agent.parentAgentId = parentAgentId
                        agent.maxParallelTasks = maxParallelTasks
                        agent.systemPrompt = systemPrompt.isEmpty ? nil : systemPrompt
                        agent.authLevel = authLevel
                        agent.passkey = passkey.isEmpty ? nil : passkey
                        try container.agentRepository.save(agent)

                        // パスキーが設定されている場合はAgentCredentialも作成/更新
                        if !passkey.isEmpty {
                            let credential = AgentCredential(agentId: agentId, rawPasskey: passkey)
                            try container.agentCredentialRepository.save(credential)
                        }
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
