// Sources/App/Features/WorkflowTemplate/TemplateListView.swift
// テンプレート一覧ビュー
// 参照: docs/requirements/WORKFLOW_TEMPLATES.md

import SwiftUI
import Domain

private typealias AsyncTask = _Concurrency.Task

struct TemplateListView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router

    @State private var templates: [WorkflowTemplate] = []
    @State private var isLoading = false
    @State private var includeArchived = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .accessibilityIdentifier("LoadingIndicator")
            } else if templates.isEmpty {
                emptyStateView
            } else {
                templateListView
            }
        }
        .accessibilityIdentifier("TemplateList")
        .navigationTitle("Templates")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                newTemplateButton
            }
            ToolbarItem(placement: .automatic) {
                archivedToggle
            }
        }
        .task {
            await loadTemplates()
        }
        .onChange(of: includeArchived) { _, _ in
            AsyncTask { await loadTemplates() }
        }
        .onChange(of: router.currentSheet) { oldValue, newValue in
            if oldValue != nil && newValue == nil {
                AsyncTask { await loadTemplates() }
            }
        }
    }

    private var templateListView: some View {
        List {
            ForEach(templates, id: \.id) { template in
                templateRow(template)
            }
        }
    }

    private func templateRow(_ template: WorkflowTemplate) -> some View {
        TemplateRow(template: template)
            .contentShape(Rectangle())
            .onTapGesture {
                router.selectTemplate(template.id)
                router.showSheet(.templateDetail(template.id))
            }
            .accessibilityIdentifier("TemplateRow_\(template.id.value)")
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Templates",
            systemImage: "doc.on.doc",
            description: Text("Create workflow templates to reuse task patterns across projects.")
        )
        .accessibilityIdentifier("EmptyState")
    }

    private var newTemplateButton: some View {
        Button {
            router.showSheet(.newTemplate)
        } label: {
            Label("New Template", systemImage: "plus")
        }
        .accessibilityIdentifier("NewTemplateButton")
        .help("New Template (⇧⌘T)")
    }

    private var archivedToggle: some View {
        Toggle("Show Archived", isOn: $includeArchived)
            .accessibilityIdentifier("ShowArchivedToggle")
    }

    private func loadTemplates() async {
        isLoading = true
        defer { isLoading = false }

        do {
            templates = try container.listTemplatesUseCase.execute(includeArchived: includeArchived)
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }
}

struct TemplateRow: View {
    let template: WorkflowTemplate
    @Environment(Router.self) var router

    private var statusIcon: String {
        template.isActive ? "doc.on.doc" : "archivebox"
    }

    private var statusColor: Color {
        template.isActive ? Color.accentColor : Color.secondary
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
            Text(template.name)
                .font(.headline)
                .accessibilityIdentifier("TemplateName_\(template.id.value)")

            if !template.description.isEmpty {
                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !template.variables.isEmpty {
                variablesRow
            }
        }
    }

    private var variablesRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "curlybraces")
                .font(.caption2)
            Text(template.variables.joined(separator: ", "))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if !template.isActive {
            Text("Archived")
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
            router.showSheet(.editTemplate(template.id))
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .accessibilityIdentifier("EditTemplateMenuItem")

        if let projectId = router.selectedProject {
            Button {
                router.showSheet(.instantiateTemplate(template.id, projectId))
            } label: {
                Label("Apply to Project", systemImage: "arrow.right.doc.on.clipboard")
            }
            .accessibilityIdentifier("InstantiateTemplateMenuItem")
        }
    }
}
