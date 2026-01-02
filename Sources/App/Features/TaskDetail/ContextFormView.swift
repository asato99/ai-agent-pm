// Sources/App/Features/TaskDetail/ContextFormView.swift
// コンテキスト追加フォーム

import SwiftUI
import Domain

private typealias AsyncTask = _Concurrency.Task

struct ContextFormView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss

    let taskId: TaskID

    @State private var task: Task?
    @State private var progress: String = ""
    @State private var findings: String = ""
    @State private var blockers: String = ""
    @State private var nextSteps: String = ""
    @State private var isLoading = false
    @State private var isSaving = false

    var isValid: Bool {
        !progress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !findings.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !blockers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !nextSteps.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if let task = task {
                    Section("Task") {
                        LabeledContent("Title") {
                            Text(task.title)
                        }
                        LabeledContent("Status") {
                            StatusBadge(status: task.status)
                        }
                    }
                }

                Section("Context Details") {
                    TextField("Progress", text: $progress, axis: .vertical)
                        .lineLimit(3...5)
                        .accessibilityIdentifier("ContextProgressField")

                    TextField("Findings", text: $findings, axis: .vertical)
                        .lineLimit(3...5)
                        .accessibilityIdentifier("ContextFindingsField")

                    TextField("Blockers", text: $blockers, axis: .vertical)
                        .lineLimit(3...5)
                        .accessibilityIdentifier("ContextBlockersField")

                    TextField("Next Steps", text: $nextSteps, axis: .vertical)
                        .lineLimit(3...5)
                        .accessibilityIdentifier("ContextNextStepsField")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Context")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveContext()
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
            .task {
                await loadData()
            }
        }
        .frame(minWidth: 500, minHeight: 450)
        .accessibilityIdentifier("ContextFormView")
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            task = try container.taskRepository.findById(taskId)
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }

    private func saveContext() {
        isSaving = true

        AsyncTask {
            do {
                // 簡略化された実装: 直接コンテキストを保存
                // 本番環境では適切なセッション管理が必要
                let context = Context(
                    id: ContextID.generate(),
                    taskId: taskId,
                    sessionId: SessionID.generate(), // プレースホルダー
                    agentId: AgentID.generate(), // プレースホルダー
                    progress: progress.isEmpty ? nil : progress,
                    findings: findings.isEmpty ? nil : findings,
                    blockers: blockers.isEmpty ? nil : blockers,
                    nextSteps: nextSteps.isEmpty ? nil : nextSteps
                )
                try container.contextRepository.save(context)
                dismiss()
            } catch {
                isSaving = false
                router.showAlert(.error(message: error.localizedDescription))
            }
        }
    }
}
