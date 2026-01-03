// Sources/App/Features/InternalAudit/InternalAuditListView.swift
// Internal Audit一覧ビュー
// 参照: docs/requirements/AUDIT.md

import SwiftUI
import Domain

private typealias AsyncTask = _Concurrency.Task

struct InternalAuditListView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router

    @State private var audits: [InternalAudit] = []
    @State private var isLoading = false
    @State private var includeInactive = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .accessibilityIdentifier("LoadingIndicator")
            } else if audits.isEmpty {
                emptyStateView
            } else {
                auditListView
            }
        }
        .accessibilityIdentifier("InternalAuditListView")
        .navigationTitle("Internal Audits")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                newAuditButton
            }
            ToolbarItem(placement: .automatic) {
                inactiveToggle
            }
        }
        .task {
            await loadAudits()
        }
        .onChange(of: includeInactive) { _, _ in
            AsyncTask { await loadAudits() }
        }
        .onChange(of: router.currentSheet) { oldValue, newValue in
            if oldValue != nil && newValue == nil {
                AsyncTask { await loadAudits() }
            }
        }
    }

    private var auditListView: some View {
        List {
            ForEach(audits, id: \.id) { audit in
                auditRow(audit)
            }
        }
    }

    private func auditRow(_ audit: InternalAudit) -> some View {
        InternalAuditRow(audit: audit)
            .contentShape(Rectangle())
            .onTapGesture {
                router.selectInternalAudit(audit.id)
                router.showSheet(.internalAuditDetail(audit.id))
            }
            .accessibilityIdentifier("InternalAuditRow_\(audit.id.value)")
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Internal Audits",
            systemImage: "checkmark.shield",
            description: Text("Create internal audits to automate process compliance monitoring.")
        )
        .accessibilityIdentifier("EmptyState")
    }

    private var newAuditButton: some View {
        Button {
            router.showSheet(.newInternalAudit)
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("New Internal Audit")
        .accessibilityIdentifier("NewInternalAuditButton")
        .help("New Internal Audit")
    }

    private var inactiveToggle: some View {
        Toggle("Show Inactive", isOn: $includeInactive)
            .accessibilityIdentifier("ShowInactiveToggle")
    }

    private func loadAudits() async {
        isLoading = true
        defer { isLoading = false }

        do {
            audits = try container.listInternalAuditsUseCase.execute(includeInactive: includeInactive)
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }
}

struct InternalAuditRow: View {
    let audit: InternalAudit
    @Environment(Router.self) var router

    private var statusIcon: String {
        switch audit.status {
        case .active: return "checkmark.shield"
        case .inactive: return "xmark.circle"
        case .suspended: return "pause.circle"
        }
    }

    private var statusColor: Color {
        switch audit.status {
        case .active: return Color.accentColor
        case .inactive: return Color.gray
        case .suspended: return Color.secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            iconView
            contentView
            Spacer()
            statusBadge
        }
        .padding(.vertical, 4)
        .contextMenu {
            contextMenuItems
        }
    }

    private var iconView: some View {
        Image(systemName: statusIcon)
            .foregroundStyle(statusColor)
            .font(.title2)
    }

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(audit.name)
                .font(.headline)
                .accessibilityIdentifier("InternalAuditName_\(audit.id.value)")

            if let description = audit.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if audit.status == .suspended {
            Text("Suspended")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            router.showSheet(.editInternalAudit(audit.id))
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .accessibilityIdentifier("EditAuditMenuItem")

        Divider()

        if audit.status == .active {
            Button {
                router.showSheet(.newAuditRule(audit.id))
            } label: {
                Label("Add Rule", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("AddRuleMenuItem")
        }
    }
}
