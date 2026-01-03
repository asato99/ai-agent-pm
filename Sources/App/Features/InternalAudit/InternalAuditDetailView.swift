// Sources/App/Features/InternalAudit/InternalAuditDetailView.swift
// Internal Audit詳細ビュー
// 参照: docs/requirements/AUDIT.md

import SwiftUI
import Domain

private typealias AsyncTask = _Concurrency.Task

struct InternalAuditDetailView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss

    let auditId: InternalAuditID

    @State private var audit: InternalAudit?
    @State private var rules: [AuditRule] = []
    @State private var lockedTasks: [Task] = []
    @State private var lockedAgents: [Agent] = []
    @State private var isLoading = false
    @State private var showLockSheet = false
    @State private var lockTargetType: LockTargetType = .task

    var body: some View {
        NavigationStack {
            mainContent
            .accessibilityIdentifier("InternalAuditDetailView")
            .navigationTitle(audit?.name ?? "Internal Audit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .accessibilityIdentifier("CloseButton")
                }

                if audit != nil {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            router.showSheet(.newAuditRule(auditId))
                        } label: {
                            Label("New Rule", systemImage: "plus.circle")
                        }
                        .accessibilityIdentifier("NewAuditRuleButton")
                    }

                    ToolbarItem(placement: .automatic) {
                        Button {
                            router.showSheet(.editInternalAudit(auditId))
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .accessibilityIdentifier("EditInternalAuditButton")
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            if audit?.status == .active {
                                Button {
                                    suspendAudit()
                                } label: {
                                    Label("Suspend", systemImage: "pause.circle")
                                }
                                .accessibilityIdentifier("SuspendAuditButton")
                            } else {
                                Button {
                                    activateAudit()
                                } label: {
                                    Label("Activate", systemImage: "play.circle")
                                }
                                .accessibilityIdentifier("ActivateAuditButton")
                            }

                            Divider()

                            Button(role: .destructive) {
                                router.showAlert(.deleteConfirmation(title: "Internal Audit") {
                                    deleteAudit()
                                })
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .accessibilityIdentifier("DeleteAuditButton")
                        } label: {
                            Label("Actions", systemImage: "ellipsis.circle")
                        }
                        .accessibilityIdentifier("ActionsMenu")
                    }
                }
            }
            .task {
                await loadAudit()
            }
            .onChange(of: router.currentSheet) { oldValue, newValue in
                if oldValue != nil && newValue == nil {
                    AsyncTask { await loadAudit() }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if let audit = audit {
            auditFormContent(audit)
                .sheet(isPresented: $showLockSheet) {
                    LockResourceSheet(
                        auditId: auditId,
                        targetType: lockTargetType,
                        container: container
                    ) {
                        AsyncTask { await loadAudit() }
                    }
                }
        } else if isLoading {
            ProgressView()
                .accessibilityIdentifier("LoadingIndicator")
        } else {
            ContentUnavailableView(
                "Audit Not Found",
                systemImage: "shield.slash",
                description: Text("The internal audit could not be loaded.")
            )
        }
    }

    @ViewBuilder
    private func auditFormContent(_ audit: InternalAudit) -> some View {
        Form {
            auditInfoSection(audit)
            auditRulesSection
            lockedResourcesSection(audit)
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func auditInfoSection(_ audit: InternalAudit) -> some View {
        Section("Audit Info") {
            LabeledContent("Name", value: audit.name)
                .accessibilityIdentifier("AuditName")

            if let description = audit.description, !description.isEmpty {
                LabeledContent("Description") {
                    Text(description)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("Status") {
                AuditStatusBadge(status: audit.status)
            }

            LabeledContent("Created", value: audit.createdAt, format: .dateTime)
            LabeledContent("Updated", value: audit.updatedAt, format: .dateTime)
        }
        .accessibilityIdentifier("AuditInfoSection")
    }

    @ViewBuilder
    private var auditRulesSection: some View {
        Section {
            ForEach(rules, id: \.id) { rule in
                AuditRuleRow(rule: rule, onEdit: {
                    router.showSheet(.editAuditRule(rule.id, auditId))
                }, onToggle: {
                    toggleRule(rule)
                }, onDelete: {
                    deleteRule(rule)
                })
            }

            if rules.isEmpty {
                Text("No rules defined")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("NoRulesMessage")
            }
        } header: {
            Text("Audit Rules (\(rules.count))")
        }
        .accessibilityIdentifier("AuditRulesSection")
    }

    @ViewBuilder
    private func lockedResourcesSection(_ audit: InternalAudit) -> some View {
        Section {
            if lockedTasks.isEmpty && lockedAgents.isEmpty {
                Text("No resources locked by this audit")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("NoLockedResourcesMessage")
            }

            ForEach(lockedTasks, id: \.id) { task in
                LockedTaskRow(task: task) { unlockTask(task) }
            }

            ForEach(lockedAgents, id: \.id) { agent in
                LockedAgentRow(agent: agent) { unlockAgent(agent) }
            }
        } header: {
            lockedResourcesHeader(audit)
        }
        .accessibilityIdentifier("LockedResourcesSection")
    }

    @ViewBuilder
    private func lockedResourcesHeader(_ audit: InternalAudit) -> some View {
        HStack {
            Text("Locked Resources (\(lockedTasks.count + lockedAgents.count))")
            Spacer()
            if audit.status == .active {
                lockMenu
            }
        }
    }

    private var lockMenu: some View {
        Menu {
            Button {
                lockTargetType = .task
                showLockSheet = true
            } label: {
                Label("Lock Task", systemImage: "doc.badge.lock")
            }
            .accessibilityIdentifier("LockTaskMenuItem")

            Button {
                lockTargetType = .agent
                showLockSheet = true
            } label: {
                Label("Lock Agent", systemImage: "person.badge.lock")
            }
            .accessibilityIdentifier("LockAgentMenuItem")
        } label: {
            Image(systemName: "plus.circle")
                .foregroundStyle(Color.accentColor)
        }
        .accessibilityIdentifier("AddLockMenu")
    }

    // MARK: - Data Loading

    private func loadAudit() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if let result = try container.getAuditWithRulesUseCase.execute(auditId: auditId) {
                audit = result.audit
                rules = result.rules
            }
            // ロック済みリソースを取得
            lockedTasks = try container.getLockedTasksUseCase.execute(auditId: auditId)
            lockedAgents = try container.getLockedAgentsUseCase.execute(auditId: auditId)
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }

    private func suspendAudit() {
        AsyncTask {
            do {
                _ = try container.suspendInternalAuditUseCase.execute(auditId: auditId)
                await loadAudit()
            } catch {
                router.showAlert(.error(message: error.localizedDescription))
            }
        }
    }

    private func activateAudit() {
        AsyncTask {
            do {
                _ = try container.activateInternalAuditUseCase.execute(auditId: auditId)
                await loadAudit()
            } catch {
                router.showAlert(.error(message: error.localizedDescription))
            }
        }
    }

    private func deleteAudit() {
        AsyncTask {
            do {
                try container.deleteInternalAuditUseCase.execute(auditId: auditId)
                dismiss()
            } catch {
                router.showAlert(.error(message: error.localizedDescription))
            }
        }
    }

    private func toggleRule(_ rule: AuditRule) {
        AsyncTask {
            do {
                _ = try container.enableDisableAuditRuleUseCase.execute(ruleId: rule.id, isEnabled: !rule.isEnabled)
                await loadAudit()
            } catch {
                router.showAlert(.error(message: error.localizedDescription))
            }
        }
    }

    private func deleteRule(_ rule: AuditRule) {
        AsyncTask {
            do {
                try container.deleteAuditRuleUseCase.execute(ruleId: rule.id)
                await loadAudit()
            } catch {
                router.showAlert(.error(message: error.localizedDescription))
            }
        }
    }

    private func unlockTask(_ task: Task) {
        AsyncTask {
            do {
                _ = try container.unlockTaskUseCase.execute(taskId: task.id, auditId: auditId)
                await loadAudit()
            } catch {
                router.showAlert(.error(message: error.localizedDescription))
            }
        }
    }

    private func unlockAgent(_ agent: Agent) {
        AsyncTask {
            do {
                _ = try container.unlockAgentUseCase.execute(agentId: agent.id, auditId: auditId)
                await loadAudit()
            } catch {
                router.showAlert(.error(message: error.localizedDescription))
            }
        }
    }
}

// MARK: - Lock Target Type

enum LockTargetType {
    case task
    case agent
}

struct AuditRuleRow: View {
    let rule: AuditRule
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    private var triggerIcon: String {
        switch rule.triggerType {
        case .taskCompleted: return "checkmark.circle"
        case .statusChanged: return "arrow.left.arrow.right"
        case .handoffCompleted: return "hand.wave"
        case .deadlineExceeded: return "clock.badge.exclamationmark"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: triggerIcon)
                .foregroundStyle(rule.isEnabled ? Color.accentColor : Color.secondary)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(rule.name)
                        .font(.headline)
                        .accessibilityIdentifier("RuleName_\(rule.id.value)")

                    if !rule.isEnabled {
                        Text("Disabled")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(3)
                    }
                }

                HStack(spacing: 8) {
                    Text("Trigger: \(rule.triggerType.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !rule.taskAssignments.isEmpty {
                        Text("\(rule.taskAssignments.count) assignments")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .accessibilityIdentifier("RuleToggle_\(rule.id.value)")
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("AuditRuleRow_\(rule.id.value)")
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .accessibilityIdentifier("EditRuleMenuItem")

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityIdentifier("DeleteRuleMenuItem")
        }
    }
}

// MARK: - Audit Status Badge

/// Internal Auditステータスバッジ（アクセシビリティ対応）
struct AuditStatusBadge: View {
    let status: AuditStatus

    private var statusColor: Color {
        switch status {
        case .active: return .green
        case .suspended: return .orange
        case .inactive: return .gray
        }
    }

    private var statusDisplayName: String {
        switch status {
        case .active: return "Active"
        case .suspended: return "Suspended"
        case .inactive: return "Inactive"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusDisplayName)
                .accessibilityIdentifier("AuditStatusText")
        }
    }
}

// MARK: - Locked Task Row

struct LockedTaskRow: View {
    let task: Task
    let onUnlock: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    Text(task.title)
                        .font(.headline)
                }

                if let lockedAt = task.lockedAt {
                    Text("Locked at \(lockedAt, format: .dateTime)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                onUnlock()
            } label: {
                Label("Unlock", systemImage: "lock.open")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("UnlockTaskButton_\(task.id.value)")
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("LockedTaskRow_\(task.id.value)")
    }
}

// MARK: - Locked Agent Row

struct LockedAgentRow: View {
    let agent: Agent
    let onUnlock: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                    Text(agent.name)
                        .font(.headline)
                }

                if let lockedAt = agent.lockedAt {
                    Text("Locked at \(lockedAt, format: .dateTime)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                onUnlock()
            } label: {
                Label("Unlock", systemImage: "lock.open")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("UnlockAgentButton_\(agent.id.value)")
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("LockedAgentRow_\(agent.id.value)")
    }
}

// MARK: - Lock Resource Sheet

struct LockResourceSheet: View {
    @Environment(\.dismiss) private var dismiss

    let auditId: InternalAuditID
    let targetType: LockTargetType
    let container: DependencyContainer
    let onLock: () -> Void

    @State private var tasks: [Task] = []
    @State private var agents: [Agent] = []
    @State private var selectedTaskId: TaskID?
    @State private var selectedAgentId: AgentID?
    @State private var projects: [Project] = []
    @State private var selectedProjectId: ProjectID?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            formContent
                .formStyle(.grouped)
                .navigationTitle(targetType == .task ? "Lock Task" : "Lock Agent")
                .toolbar { toolbarContent }
                .task { await loadResources() }
                .onChange(of: selectedProjectId) { _, newValue in
                    handleProjectChange(newValue)
                }
        }
        .frame(minWidth: 400, minHeight: 300)
        .accessibilityIdentifier("LockResourceSheet")
    }

    @ViewBuilder
    private var formContent: some View {
        Form {
            if targetType == .task {
                taskSelectionContent
            } else {
                agentSelectionContent
            }

            if let error = errorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private var taskSelectionContent: some View {
        Section("Select Project") {
            Picker("Project", selection: $selectedProjectId) {
                Text("Select a project").tag(nil as ProjectID?)
                ForEach(projects, id: \.id) { project in
                    Text(project.name).tag(project.id as ProjectID?)
                }
            }
            .accessibilityIdentifier("ProjectPicker")
        }

        Section("Select Task") {
            let unlockedTasks = tasks.filter { !$0.isLocked }
            if unlockedTasks.isEmpty {
                Text("No unlocked tasks available")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(unlockedTasks, id: \.id) { task in
                    TaskOptionRow(task: task, isSelected: selectedTaskId == task.id) {
                        selectedTaskId = task.id
                    }
                }
            }
        }
        .accessibilityIdentifier("TaskSelectionSection")
    }

    @ViewBuilder
    private var agentSelectionContent: some View {
        Section("Select Agent") {
            let unlockedAgents = agents.filter { !$0.isLocked }
            if unlockedAgents.isEmpty {
                Text("No unlocked agents available")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(unlockedAgents, id: \.id) { agent in
                    AgentOptionRow(agent: agent, isSelected: selectedAgentId == agent.id) {
                        selectedAgentId = agent.id
                    }
                }
            }
        }
        .accessibilityIdentifier("AgentSelectionSection")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityIdentifier("CancelLockButton")
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("Lock") { performLock() }
                .disabled(targetType == .task ? selectedTaskId == nil : selectedAgentId == nil)
                .accessibilityIdentifier("ConfirmLockButton")
        }
    }

    private func handleProjectChange(_ newValue: ProjectID?) {
        if let projectId = newValue {
            loadTasks(for: projectId)
        } else {
            tasks = []
        }
    }

    private func loadResources() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if targetType == .task {
                projects = try container.getProjectsUseCase.execute()
            } else {
                agents = try container.getAgentsUseCase.execute()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadTasks(for projectId: ProjectID) {
        do {
            tasks = try container.getTasksUseCase.execute(projectId: projectId, status: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performLock() {
        do {
            if targetType == .task, let taskId = selectedTaskId {
                _ = try container.lockTaskUseCase.execute(taskId: taskId, auditId: auditId)
            } else if targetType == .agent, let agentId = selectedAgentId {
                _ = try container.lockAgentUseCase.execute(agentId: agentId, auditId: auditId)
            }
            onLock()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Option Rows for Lock Sheet

private struct TaskOptionRow: View {
    let task: Task
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(task.title).font(.headline)
                Text(task.status.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .accessibilityIdentifier("TaskOption_\(task.id.value)")
    }
}

private struct AgentOptionRow: View {
    let agent: Agent
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(agent.name).font(.headline)
                Text(agent.role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .accessibilityIdentifier("AgentOption_\(agent.id.value)")
    }
}
