// Sources/App/Features/TaskBoard/TaskFormView.swift
// タスク作成・編集フォーム

import SwiftUI
import Domain

private typealias AsyncTask = _Concurrency.Task

struct TaskFormView: View {
    enum Mode {
        case create(projectId: ProjectID)
        case edit(TaskID)
    }

    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var priority: TaskPriority = .medium
    @State private var assigneeId: AgentID?
    @State private var estimatedMinutes: Int?
    @State private var agents: [Agent] = []
    @State private var isSaving = false

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var formTitle: String {
        switch mode {
        case .create: return "New Task"
        case .edit: return "Edit Task"
        }
    }

    var projectId: ProjectID {
        switch mode {
        case .create(let id): return id
        case .edit: return ProjectID(value: "") // Will be loaded
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task Information") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Details") {
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { priority in
                            Text(priority.rawValue.capitalized).tag(priority)
                        }
                    }

                    Picker("Assignee", selection: $assigneeId) {
                        Text("Unassigned").tag(nil as AgentID?)
                        ForEach(agents, id: \.id) { agent in
                            Text(agent.name).tag(agent.id as AgentID?)
                        }
                    }

                    TextField("Estimated Minutes", value: $estimatedMinutes, format: .number)
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
                await loadData()
            }
        }
        .frame(minWidth: 450, minHeight: 350)
    }

    private func loadData() async {
        do {
            // エージェントはプロジェクト非依存なので全件取得
            agents = try container.getAgentsUseCase.execute()

            switch mode {
            case .create:
                break // エージェントリストは既に読み込み済み
            case .edit(let taskId):
                if let task = try container.taskRepository.findById(taskId) {
                    title = task.title
                    description = task.description
                    priority = task.priority
                    assigneeId = task.assigneeId
                    estimatedMinutes = task.estimatedMinutes
                }
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
                    _ = try container.createTaskUseCase.execute(
                        projectId: projectId,
                        title: title,
                        description: description,
                        priority: priority,
                        assigneeId: assigneeId,
                        actorAgentId: nil,
                        sessionId: nil
                    )
                case .edit(let taskId):
                    _ = try container.updateTaskUseCase.execute(
                        taskId: taskId,
                        title: title,
                        description: description.isEmpty ? nil : description,
                        priority: priority,
                        estimatedMinutes: estimatedMinutes
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
