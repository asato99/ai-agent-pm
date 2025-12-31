// Sources/App/Features/Handoff/HandoffView.swift
// ハンドオフ作成・管理ビュー

import SwiftUI
import Domain

private typealias AsyncTask = _Concurrency.Task

struct HandoffView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss

    let taskId: TaskID

    @State private var task: Task?
    @State private var agents: [Agent] = []
    @State private var toAgentId: AgentID?
    @State private var summary: String = ""
    @State private var context: String = ""
    @State private var recommendations: String = ""
    @State private var isLoading = false
    @State private var isSaving = false

    var isValid: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

                Section("Handoff Details") {
                    Picker("Hand off to", selection: $toAgentId) {
                        Text("Anyone").tag(nil as AgentID?)
                        ForEach(agents, id: \.id) { agent in
                            Text(agent.name).tag(agent.id as AgentID?)
                        }
                    }

                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(3...5)
                }

                Section("Additional Information") {
                    TextField("Context (Optional)", text: $context, axis: .vertical)
                        .lineLimit(3...5)

                    TextField("Recommendations (Optional)", text: $recommendations, axis: .vertical)
                        .lineLimit(3...5)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Create Handoff")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Handoff") {
                        createHandoff()
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
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            task = try container.taskRepository.findById(taskId)
            if let task = task {
                agents = try container.getAgentsUseCase.execute(projectId: task.projectId)
            }
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }

    private func createHandoff() {
        isSaving = true

        AsyncTask {
            do {
                // Note: In a real app, fromAgentId would come from the current user/session
                let fromAgentId = AgentID.generate()

                _ = try container.createHandoffUseCase.execute(
                    taskId: taskId,
                    fromAgentId: fromAgentId,
                    toAgentId: toAgentId,
                    summary: summary,
                    context: context.isEmpty ? nil : context,
                    recommendations: recommendations.isEmpty ? nil : recommendations
                )
                dismiss()
            } catch {
                isSaving = false
                router.showAlert(.error(message: error.localizedDescription))
            }
        }
    }
}

// MARK: - Pending Handoffs View

struct PendingHandoffsView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router

    let agentId: AgentID?

    @State private var handoffs: [Handoff] = []
    @State private var isLoading = false

    var body: some View {
        List {
            ForEach(handoffs, id: \.id) { handoff in
                HandoffRow(handoff: handoff) {
                    acceptHandoff(handoff)
                }
            }
        }
        .navigationTitle("Pending Handoffs")
        .overlay {
            if isLoading {
                ProgressView()
            } else if handoffs.isEmpty {
                ContentUnavailableView(
                    "No Pending Handoffs",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("No handoffs waiting for acceptance.")
                )
            }
        }
        .task {
            await loadHandoffs()
        }
        .refreshable {
            await loadHandoffs()
        }
    }

    private func loadHandoffs() async {
        isLoading = true
        defer { isLoading = false }

        do {
            handoffs = try container.getPendingHandoffsUseCase.execute(agentId: agentId)
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }

    private func acceptHandoff(_ handoff: Handoff) {
        AsyncTask {
            do {
                guard let acceptingAgentId = agentId else { return }
                _ = try container.acceptHandoffUseCase.execute(
                    handoffId: handoff.id,
                    acceptingAgentId: acceptingAgentId
                )
                await loadHandoffs()
            } catch {
                router.showAlert(.error(message: error.localizedDescription))
            }
        }
    }
}

struct HandoffRow: View {
    let handoff: Handoff
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(handoff.summary)
                .font(.headline)

            if let context = handoff.context {
                Text(context)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Text(handoff.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Accept") {
                    onAccept()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
