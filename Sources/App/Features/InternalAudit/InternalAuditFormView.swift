// Sources/App/Features/InternalAudit/InternalAuditFormView.swift
// Internal Audit作成・編集フォーム
// 参照: docs/requirements/AUDIT.md

import SwiftUI
import Domain

private typealias AsyncTask = _Concurrency.Task

struct InternalAuditFormView: View {
    enum Mode: Equatable {
        case create
        case edit(InternalAuditID)
    }

    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var status: AuditStatus = .active
    @State private var isSaving = false

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var title: String {
        switch mode {
        case .create: return "New Internal Audit"
        case .edit: return "Edit Internal Audit"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Audit Info") {
                    TextField("Audit Name", text: $name)
                        .accessibilityIdentifier("AuditNameField")

                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("AuditDescriptionField")

                    Picker("Status", selection: $status) {
                        Text("Active").tag(AuditStatus.active)
                        Text("Suspended").tag(AuditStatus.suspended)
                        Text("Inactive").tag(AuditStatus.inactive)
                    }
                    .accessibilityIdentifier("AuditStatusPicker")
                }
            }
            .formStyle(.grouped)
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
                    .accessibilityIdentifier("SaveAuditButton")
                }
            }
            .task {
                await loadExistingData()
            }
        }
        .frame(minWidth: 400, minHeight: 200)
    }

    private func loadExistingData() async {
        guard case .edit(let auditId) = mode else { return }

        do {
            let audit = try container.getInternalAuditUseCase.execute(auditId: auditId)
            name = audit.name
            description = audit.description ?? ""
            status = audit.status
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
                    _ = try container.createInternalAuditUseCase.execute(
                        name: name,
                        description: description.isEmpty ? nil : description
                    )
                case .edit(let auditId):
                    _ = try container.updateInternalAuditUseCase.execute(
                        auditId: auditId,
                        name: name,
                        description: description.isEmpty ? nil : description
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
