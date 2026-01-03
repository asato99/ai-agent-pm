// Sources/App/Features/WorkflowTemplate/InstantiateTemplateView.swift
// テンプレートインスタンス化ビュー
// 参照: docs/requirements/WORKFLOW_TEMPLATES.md

import SwiftUI
import Domain
import UseCase

private typealias AsyncTask = _Concurrency.Task

struct InstantiateTemplateView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss

    let templateId: WorkflowTemplateID
    let projectId: ProjectID

    @State private var template: WorkflowTemplate?
    @State private var templateTasks: [TemplateTask] = []
    @State private var variableValues: [String: String] = [:]
    @State private var selectedAgentId: AgentID?
    @State private var agents: [Agent] = []
    @State private var isLoading = false
    @State private var isApplying = false

    var isValid: Bool {
        guard let template = template else { return false }
        // すべての変数に値が入力されているか確認
        return template.variables.allSatisfy { variable in
            let value = variableValues[variable] ?? ""
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let template = template {
                    Section("Template") {
                        LabeledContent("Name", value: template.name)
                        if !template.description.isEmpty {
                            Text(template.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !template.variables.isEmpty {
                        Section("Variables") {
                            ForEach(template.variables, id: \.self) { variable in
                                TextField(variable, text: Binding(
                                    get: { variableValues[variable] ?? "" },
                                    set: { variableValues[variable] = $0 }
                                ))
                                .accessibilityIdentifier("Variable_\(variable)")
                            }
                        }
                    }

                    Section("Assignment") {
                        Picker("Assign To", selection: $selectedAgentId) {
                            Text("Unassigned").tag(nil as AgentID?)
                            ForEach(agents, id: \.id) { agent in
                                Text(agent.name).tag(agent.id as AgentID?)
                            }
                        }
                        .accessibilityIdentifier("AssigneeSelector")
                    }

                    Section {
                        Text("\(templateTasks.count) tasks will be created")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(templateTasks, id: \.id) { task in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("#\(task.order)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(previewTitle(task))
                                        .font(.subheadline)
                                }

                                if !task.dependsOnOrders.isEmpty {
                                    Text("Depends on: #\(task.dependsOnOrders.map { String($0) }.joined(separator: ", #"))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Tasks Preview")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Apply Template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("CancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applyTemplate()
                    }
                    .disabled(!isValid || isApplying)
                    .accessibilityIdentifier("ApplyButton")
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .accessibilityIdentifier("LoadingIndicator")
                }
            }
            .task {
                await loadData()
            }
        }
        .frame(minWidth: 450, minHeight: 400)
    }

    private func previewTitle(_ task: TemplateTask) -> String {
        task.resolveTitle(with: variableValues)
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if let result = try container.getTemplateWithTasksUseCase.execute(templateId: templateId) {
                template = result.template
                templateTasks = result.tasks

                // 変数の初期値を空文字列に設定
                for variable in result.template.variables {
                    variableValues[variable] = ""
                }
            }

            agents = try container.getAgentsUseCase.execute()
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }

    private func applyTemplate() {
        isApplying = true

        AsyncTask {
            do {
                let input = InstantiateTemplateUseCase.Input(
                    templateId: templateId,
                    projectId: projectId,
                    variableValues: variableValues,
                    assigneeId: selectedAgentId
                )
                let result = try container.instantiateTemplateUseCase.execute(input: input)

                await MainActor.run {
                    router.showAlert(.info(
                        title: "Template Applied",
                        message: "\(result.createdTasks.count) tasks have been created."
                    ))
                    dismiss()
                }
            } catch {
                isApplying = false
                router.showAlert(.error(message: error.localizedDescription))
            }
        }
    }
}
