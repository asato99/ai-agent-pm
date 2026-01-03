// Sources/App/Features/WorkflowTemplate/TemplateDetailView.swift
// テンプレート詳細ビュー
// 参照: docs/requirements/WORKFLOW_TEMPLATES.md

import SwiftUI
import Domain

private typealias AsyncTask = _Concurrency.Task

struct TemplateDetailView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss

    let templateId: WorkflowTemplateID

    @State private var template: WorkflowTemplate?
    @State private var templateTasks: [TemplateTask] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if let template = template {
                    Form {
                        Section("Template Info") {
                            LabeledContent("Name", value: template.name)

                            if !template.description.isEmpty {
                                LabeledContent("Description") {
                                    Text(template.description)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            LabeledContent("Status") {
                                HStack {
                                    Circle()
                                        .fill(template.isActive ? Color.green : Color.gray)
                                        .frame(width: 8, height: 8)
                                    Text(template.isActive ? "Active" : "Archived")
                                }
                            }

                            LabeledContent("Created", value: template.createdAt, format: .dateTime)
                            LabeledContent("Updated", value: template.updatedAt, format: .dateTime)
                        }

                        if !template.variables.isEmpty {
                            Section("Variables") {
                                ForEach(template.variables, id: \.self) { variable in
                                    HStack {
                                        Image(systemName: "curlybraces")
                                            .foregroundStyle(.secondary)
                                        Text(variable)
                                            .font(.system(.body, design: .monospaced))
                                    }
                                }
                            }
                        }

                        Section("Template Tasks (\(templateTasks.count))") {
                            ForEach(templateTasks, id: \.id) { task in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("#\(task.order)")
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.2))
                                            .cornerRadius(4)

                                        Text(task.title)
                                            .font(.headline)
                                    }

                                    if !task.description.isEmpty {
                                        Text(task.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    HStack(spacing: 12) {
                                        Label(task.defaultPriority.rawValue.capitalized, systemImage: priorityIcon(task.defaultPriority))
                                            .font(.caption)

                                        if let minutes = task.estimatedMinutes {
                                            Label("\(minutes)min", systemImage: "clock")
                                                .font(.caption)
                                        }

                                        if !task.dependsOnOrders.isEmpty {
                                            Label("→ #\(task.dependsOnOrders.map { String($0) }.joined(separator: ", #"))", systemImage: "arrow.turn.down.right")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .formStyle(.grouped)
                } else if isLoading {
                    ProgressView()
                        .accessibilityIdentifier("LoadingIndicator")
                } else {
                    ContentUnavailableView(
                        "Template Not Found",
                        systemImage: "doc.questionmark",
                        description: Text("The template could not be loaded.")
                    )
                }
            }
            .navigationTitle(template?.name ?? "Template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .accessibilityIdentifier("CloseButton")
                }

                if template != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                router.showSheet(.editTemplate(templateId))
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .accessibilityIdentifier("EditTemplateButton")

                            if let projectId = router.selectedProject {
                                Button {
                                    dismiss()
                                    router.showSheet(.instantiateTemplate(templateId, projectId))
                                } label: {
                                    Label("Apply to Project", systemImage: "arrow.right.doc.on.clipboard")
                                }
                                .accessibilityIdentifier("ApplyTemplateButton")
                            }

                            Divider()

                            if template?.isActive == true {
                                Button(role: .destructive) {
                                    archiveTemplate()
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .accessibilityIdentifier("ArchiveTemplateButton")
                            }
                        } label: {
                            Label("Actions", systemImage: "ellipsis.circle")
                        }
                        .accessibilityIdentifier("ActionsMenu")
                    }
                }
            }
            .task {
                await loadTemplate()
            }
        }
        .frame(minWidth: 450, minHeight: 400)
    }

    private func priorityIcon(_ priority: TaskPriority) -> String {
        switch priority {
        case .low: return "arrow.down"
        case .medium: return "minus"
        case .high: return "arrow.up"
        case .urgent: return "exclamationmark.2"
        }
    }

    private func loadTemplate() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if let result = try container.getTemplateWithTasksUseCase.execute(templateId: templateId) {
                template = result.template
                templateTasks = result.tasks
            }
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }

    private func archiveTemplate() {
        AsyncTask {
            do {
                _ = try container.archiveTemplateUseCase.execute(templateId: templateId)
                await loadTemplate()
            } catch {
                router.showAlert(.error(message: error.localizedDescription))
            }
        }
    }
}
