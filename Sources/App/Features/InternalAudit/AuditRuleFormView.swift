// Sources/App/Features/InternalAudit/AuditRuleFormView.swift
// Audit Rule作成・編集フォーム
// 参照: docs/requirements/AUDIT.md
// 設計変更: AuditRuleはauditTasksをインラインで保持（WorkflowTemplateはプロジェクトスコープのため）

import SwiftUI
import Domain

private typealias AsyncTask = _Concurrency.Task

struct AuditRuleFormView: View {
    enum Mode: Equatable {
        case create(InternalAuditID)
        case edit(AuditRuleID, InternalAuditID)
    }

    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var name: String = ""
    @State private var triggerType: TriggerType = .taskCompleted
    @State private var auditTaskInputs: [AuditTaskInput] = []
    @State private var agents: [Agent] = []
    @State private var isSaving = false
    @State private var isLoading = false

    // Trigger configuration state
    @State private var targetStatus: TaskStatus = .done
    @State private var graceMinutes: Int = 30

    // Workflow Template import state
    @State private var workflowTemplates: [WorkflowTemplate] = []
    @State private var selectedTemplateId: WorkflowTemplateID?

    /// Audit Task入力用の構造体
    struct AuditTaskInput: Identifiable {
        let id = UUID()
        var order: Int = 1
        var title: String = ""
        var description: String = ""
        var agentId: AgentID?
        var priority: TaskPriority = .medium
        var dependsOnOrders: [Int] = []
    }

    var auditId: InternalAuditID {
        switch mode {
        case .create(let id): return id
        case .edit(_, let id): return id
        }
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var title: String {
        switch mode {
        case .create: return "New Audit Rule"
        case .edit: return "Edit Audit Rule"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .accessibilityIdentifier("LoadingIndicator")
                } else {
                    Form {
                        Section("Rule Info") {
                            TextField("Rule Name", text: $name)
                                .accessibilityIdentifier("AuditRuleNameField")

                            Picker("Trigger Type", selection: $triggerType) {
                                ForEach(TriggerType.allCases, id: \.self) { type in
                                    Text(type.displayName).tag(type)
                                }
                            }
                            .accessibilityIdentifier("TriggerTypePicker")

                            Picker("Import from Template", selection: $selectedTemplateId) {
                                Text("None").tag(nil as WorkflowTemplateID?)
                                ForEach(workflowTemplates) { template in
                                    Text(template.name).tag(template.id as WorkflowTemplateID?)
                                }
                            }
                            .accessibilityIdentifier("WorkflowTemplatePicker")
                            .onChange(of: selectedTemplateId) { _, newValue in
                                if let templateId = newValue {
                                    loadTemplateTasks(templateId: templateId)
                                }
                            }
                        }

                        // Trigger-specific configuration
                        if triggerType == .statusChanged {
                            Section("Trigger Configuration") {
                                Picker("Target Status", selection: $targetStatus) {
                                    ForEach(TaskStatus.allCases, id: \.self) { status in
                                        Text(status.displayName).tag(status)
                                    }
                                }
                                .accessibilityIdentifier("TriggerStatusPicker")
                            }
                        }

                        if triggerType == .deadlineExceeded {
                            Section("Trigger Configuration") {
                                HStack {
                                    Text("Grace Period (minutes)")
                                    TextField("Minutes", value: $graceMinutes, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                        .accessibilityIdentifier("TriggerGraceMinutesField")
                                }
                            }
                        }

                        Section {
                            ForEach($auditTaskInputs) { $taskInput in
                                AuditTaskInputRow(
                                    taskInput: $taskInput,
                                    allTasks: auditTaskInputs,
                                    agents: agents,
                                    onDelete: { deleteTask(taskInput) }
                                )
                            }

                            Button {
                                addTask()
                            } label: {
                                Label("Add Audit Task", systemImage: "plus.circle")
                            }
                            .accessibilityIdentifier("AddAuditTaskButton")
                        } header: {
                            Text("Audit Tasks")
                        } footer: {
                            Text("Define tasks that will be created when this rule is triggered")
                                .font(.caption)
                        }
                    }
                    .formStyle(.grouped)
                }
            }
            .accessibilityIdentifier("AuditRuleEditView")
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("CancelButton")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!isValid || isSaving)
                    .accessibilityIdentifier("SaveAuditRuleButton")
                }
            }
            .task {
                await loadData()
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private func addTask() {
        let newOrder = (auditTaskInputs.map { $0.order }.max() ?? 0) + 1
        auditTaskInputs.append(AuditTaskInput(order: newOrder))
    }

    private func deleteTask(_ task: AuditTaskInput) {
        auditTaskInputs.removeAll { $0.id == task.id }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            agents = try container.getAgentsUseCase.execute()
            workflowTemplates = try container.listAllTemplatesUseCase.execute()

            if case .edit(let ruleId, _) = mode {
                // Load existing rule data
                let rules = try container.listAuditRulesUseCase.execute(auditId: auditId, enabledOnly: false)
                if let rule = rules.first(where: { $0.id == ruleId }) {
                    name = rule.name
                    triggerType = rule.triggerType

                    // Convert AuditTask to AuditTaskInput
                    auditTaskInputs = rule.auditTasks.map { task in
                        AuditTaskInput(
                            order: task.order,
                            title: task.title,
                            description: task.description,
                            agentId: task.assigneeId,
                            priority: task.priority,
                            dependsOnOrders: task.dependsOnOrders
                        )
                    }
                }
            }
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }

    /// テンプレートからタスクをインポート
    private func loadTemplateTasks(templateId: WorkflowTemplateID) {
        do {
            guard let result = try container.getTemplateWithTasksUseCase.execute(templateId: templateId) else {
                return
            }

            // Convert TemplateTask to AuditTaskInput
            auditTaskInputs = result.tasks.map { task in
                AuditTaskInput(
                    order: task.order,
                    title: task.title,
                    description: task.description,
                    agentId: nil,  // エージェントは手動で割り当て
                    priority: task.defaultPriority,
                    dependsOnOrders: task.dependsOnOrders
                )
            }
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }

    private func save() {
        isSaving = true

        // Convert inputs to AuditTask
        // Note: assigneeId is optional, only title is required
        let auditTasks = auditTaskInputs.compactMap { input -> AuditTask? in
            guard !input.title.isEmpty else { return nil }
            return AuditTask(
                order: input.order,
                title: input.title,
                description: input.description,
                assigneeId: input.agentId,
                priority: input.priority,
                dependsOnOrders: input.dependsOnOrders
            )
        }

        AsyncTask {
            do {
                switch mode {
                case .create(let auditId):
                    _ = try container.createAuditRuleUseCase.execute(
                        auditId: auditId,
                        name: name,
                        triggerType: triggerType,
                        triggerConfig: nil,
                        auditTasks: auditTasks
                    )
                case .edit(let ruleId, _):
                    _ = try container.updateAuditRuleUseCase.execute(
                        ruleId: ruleId,
                        name: name,
                        triggerConfig: nil,
                        auditTasks: auditTasks
                    )
                }
                dismiss()
            } catch {
                isSaving = false
                router.showAlert(.error(message: error.localizedDescription))
            }
        }
    }
}

// MARK: - Audit Task Input Row

/// Audit Task入力行
private struct AuditTaskInputRow: View {
    @Binding var taskInput: AuditRuleFormView.AuditTaskInput
    let allTasks: [AuditRuleFormView.AuditTaskInput]
    let agents: [Agent]
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Task #\(taskInput.order)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            TextField("Task Title", text: $taskInput.title)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("AuditTaskTitle_\(taskInput.order)")

            TextField("Description", text: $taskInput.description, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...3)

            HStack {
                Picker("Agent", selection: $taskInput.agentId) {
                    Text("Select Agent").tag(nil as AgentID?)
                    ForEach(agents, id: \.id) { agent in
                        Text(agent.name).tag(agent.id as AgentID?)
                    }
                }
                .frame(width: 150)
                .accessibilityIdentifier("TaskAgentPicker_\(taskInput.order)")

                Picker("Priority", selection: $taskInput.priority) {
                    Text("Low").tag(TaskPriority.low)
                    Text("Medium").tag(TaskPriority.medium)
                    Text("High").tag(TaskPriority.high)
                    Text("Urgent").tag(TaskPriority.urgent)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("TaskPriorityPicker_\(taskInput.order)")
            }
        }
        .padding(.vertical, 8)
    }
}
