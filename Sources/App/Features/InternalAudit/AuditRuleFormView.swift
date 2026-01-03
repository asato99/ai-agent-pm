// Sources/App/Features/InternalAudit/AuditRuleFormView.swift
// Audit Rule作成・編集フォーム
// 参照: docs/requirements/AUDIT.md

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
    @State private var selectedTemplateId: WorkflowTemplateID?
    @State private var templates: [WorkflowTemplate] = []
    @State private var templateTasks: [TemplateTask] = []
    @State private var agents: [Agent] = []
    @State private var taskAssignments: [TaskAssignmentInput] = []
    @State private var isSaving = false
    @State private var isLoading = false

    struct TaskAssignmentInput: Identifiable {
        let id = UUID()
        var templateTaskOrder: Int
        var templateTaskTitle: String
        var agentId: AgentID?
    }

    var auditId: InternalAuditID {
        switch mode {
        case .create(let id): return id
        case .edit(_, let id): return id
        }
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedTemplateId != nil
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
                        }

                        Section("Workflow Template") {
                            Picker("Template", selection: $selectedTemplateId) {
                                Text("Select Template").tag(nil as WorkflowTemplateID?)
                                ForEach(templates, id: \.id) { template in
                                    Text(template.name).tag(template.id as WorkflowTemplateID?)
                                }
                            }
                            .accessibilityIdentifier("WorkflowTemplatePicker")
                            .onChange(of: selectedTemplateId) { _, newValue in
                                if let templateId = newValue {
                                    loadTemplateTasks(templateId)
                                } else {
                                    templateTasks = []
                                    taskAssignments = []
                                }
                            }
                        }

                        if !taskAssignments.isEmpty {
                            // Note: Section-level accessibilityIdentifier interferes with child Picker identifiers on macOS
                            // Using header text "Task Assignments" for section identification instead
                            Section("Task Assignments") {
                                ForEach($taskAssignments) { $assignment in
                                    TaskAgentAssignmentRow(
                                        assignment: $assignment,
                                        agents: agents
                                    )
                                }
                            }
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

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            templates = try container.listTemplatesUseCase.execute(includeArchived: false)
            agents = try container.getAgentsUseCase.execute()

            if case .edit(let ruleId, _) = mode {
                // Load existing rule data
                let rules = try container.listAuditRulesUseCase.execute(auditId: auditId, enabledOnly: false)
                if let rule = rules.first(where: { $0.id == ruleId }) {
                    name = rule.name
                    triggerType = rule.triggerType
                    selectedTemplateId = rule.workflowTemplateId

                    // Load template tasks for assignments
                    if let result = try container.getTemplateWithTasksUseCase.execute(templateId: rule.workflowTemplateId) {
                        templateTasks = result.tasks
                        taskAssignments = result.tasks.map { task in
                            let existingAssignment = rule.taskAssignments.first { $0.templateTaskOrder == task.order }
                            return TaskAssignmentInput(
                                templateTaskOrder: task.order,
                                templateTaskTitle: task.title,
                                agentId: existingAssignment?.agentId
                            )
                        }
                    }
                }
            }
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }

    private func loadTemplateTasks(_ templateId: WorkflowTemplateID) {
        AsyncTask {
            do {
                if let result = try container.getTemplateWithTasksUseCase.execute(templateId: templateId) {
                    templateTasks = result.tasks
                    taskAssignments = result.tasks.map { task in
                        TaskAssignmentInput(
                            templateTaskOrder: task.order,
                            templateTaskTitle: task.title,
                            agentId: nil
                        )
                    }
                }
            } catch {
                router.showAlert(.error(message: error.localizedDescription))
            }
        }
    }

    private func save() {
        guard let templateId = selectedTemplateId else { return }
        isSaving = true

        let assignments = taskAssignments.compactMap { input -> TaskAssignment? in
            guard let agentId = input.agentId else { return nil }
            return TaskAssignment(templateTaskOrder: input.templateTaskOrder, agentId: agentId)
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
                        workflowTemplateId: templateId,
                        taskAssignments: assignments
                    )
                case .edit(let ruleId, _):
                    _ = try container.updateAuditRuleUseCase.execute(
                        ruleId: ruleId,
                        name: name,
                        triggerConfig: nil,
                        taskAssignments: assignments
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

// MARK: - Task Agent Assignment Row

/// タスク別エージェント割り当て行（アクセシビリティ対応）
/// Sectionの accessibilityIdentifier が子Pickerに干渉する問題を回避するため分離
private struct TaskAgentAssignmentRow: View {
    @Binding var assignment: AuditRuleFormView.TaskAssignmentInput
    let agents: [Agent]

    var body: some View {
        HStack {
            Text("#\(assignment.templateTaskOrder)")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.2))
                .cornerRadius(4)

            Text(assignment.templateTaskTitle)
                .lineLimit(1)

            Spacer()

            Picker("Agent", selection: $assignment.agentId) {
                Text("Unassigned").tag(nil as AgentID?)
                ForEach(agents, id: \.id) { agent in
                    Text(agent.name).tag(agent.id as AgentID?)
                }
            }
            .labelsHidden()
            .frame(width: 150)
            .accessibilityIdentifier("TaskAgentPicker_\(assignment.templateTaskOrder)")
        }
    }
}

