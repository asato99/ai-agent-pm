// Sources/App/Features/WorkflowTemplate/TemplateFormView.swift
// テンプレート作成・編集フォーム
// 参照: docs/requirements/WORKFLOW_TEMPLATES.md

import SwiftUI
import Domain
import UseCase

private typealias AsyncTask = _Concurrency.Task

struct TemplateFormView: View {
    enum Mode: Equatable {
        case create
        case edit(WorkflowTemplateID)
    }

    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var variablesText: String = ""
    @State private var templateTasks: [TemplateTaskInput] = []
    @State private var isSaving = false

    struct TemplateTaskInput: Identifiable {
        let id = UUID()
        var title: String = ""
        var description: String = ""
        var order: Int = 1
        var dependsOnOrders: [Int] = []
        var defaultPriority: TaskPriority = .medium
        var estimatedMinutes: Int?
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var title: String {
        switch mode {
        case .create: return "New Template"
        case .edit: return "Edit Template"
        }
    }

    var parsedVariables: [String] {
        variablesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Template Info") {
                    TextField("Template Name", text: $name)
                        .accessibilityIdentifier("TemplateNameField")

                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("TemplateDescriptionField")
                }

                Section {
                    TextField("Variable names (comma-separated)", text: $variablesText)
                        .accessibilityIdentifier("TemplateVariablesField")

                    if !parsedVariables.isEmpty {
                        HStack {
                            ForEach(parsedVariables, id: \.self) { variable in
                                Text("{{" + variable + "}}")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                    }
                } header: {
                    Text("Variables")
                } footer: {
                    Text("Use {{variable_name}} in task titles and descriptions")
                        .font(.caption)
                }

                Section {
                    ForEach($templateTasks) { $task in
                        TemplateTaskInputRow(
                            task: $task,
                            allTasks: templateTasks,
                            onDelete: { deleteTask(task) }
                        )
                    }

                    Button {
                        addTask()
                    } label: {
                        Label("Add Task", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("AddTemplateTaskButton")
                } header: {
                    Text("Template Tasks")
                } footer: {
                    Text("Define tasks that will be created when this template is applied")
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            .accessibilityElement(children: .contain)
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
                    .accessibilityIdentifier("SaveButton")
                }
            }
            .task {
                if case .edit(let templateId) = mode {
                    await loadTemplate(templateId)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private func addTask() {
        let newOrder = (templateTasks.map { $0.order }.max() ?? 0) + 1
        templateTasks.append(TemplateTaskInput(order: newOrder))
    }

    private func deleteTask(_ task: TemplateTaskInput) {
        templateTasks.removeAll { $0.id == task.id }
    }

    private func loadTemplate(_ templateId: WorkflowTemplateID) async {
        do {
            if let result = try container.getTemplateWithTasksUseCase.execute(templateId: templateId) {
                name = result.template.name
                description = result.template.description
                variablesText = result.template.variables.joined(separator: ", ")

                templateTasks = result.tasks.map { task in
                    TemplateTaskInput(
                        title: task.title,
                        description: task.description,
                        order: task.order,
                        dependsOnOrders: task.dependsOnOrders,
                        defaultPriority: task.defaultPriority,
                        estimatedMinutes: task.estimatedMinutes
                    )
                }
            }
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }

    private func save() {
        guard let projectId = router.selectedProject else {
            router.showAlert(.error(message: "No project selected"))
            return
        }

        isSaving = true

        AsyncTask {
            do {
                switch mode {
                case .create:
                    let input = CreateTemplateUseCase.Input(
                        projectId: projectId,
                        name: name,
                        description: description,
                        variables: parsedVariables,
                        tasks: templateTasks.map { task in
                            CreateTemplateUseCase.Input.TaskInput(
                                title: task.title,
                                description: task.description,
                                order: task.order,
                                dependsOnOrders: task.dependsOnOrders,
                                defaultPriority: task.defaultPriority,
                                estimatedMinutes: task.estimatedMinutes
                            )
                        }
                    )
                    _ = try container.createTemplateUseCase.execute(input: input)

                case .edit(let templateId):
                    _ = try container.updateTemplateUseCase.execute(
                        templateId: templateId,
                        name: name,
                        description: description,
                        variables: parsedVariables
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

struct TemplateTaskInputRow: View {
    @Binding var task: TemplateFormView.TemplateTaskInput
    let allTasks: [TemplateFormView.TemplateTaskInput]
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Task #\(task.order)")
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

            TextField("Task Title", text: $task.title)
                .textFieldStyle(.roundedBorder)

            TextField("Description", text: $task.description, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...3)

            HStack {
                Picker("Priority", selection: $task.defaultPriority) {
                    Text("Low").tag(TaskPriority.low)
                    Text("Medium").tag(TaskPriority.medium)
                    Text("High").tag(TaskPriority.high)
                    Text("Urgent").tag(TaskPriority.urgent)
                }
                .pickerStyle(.menu)

                Spacer()

                HStack {
                    Text("Est:")
                        .font(.caption)
                    TextField("min", value: $task.estimatedMinutes, format: .number)
                        .frame(width: 50)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
