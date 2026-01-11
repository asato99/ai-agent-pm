// Sources/App/Features/TaskBoard/TaskBoardView.swift
// カンバンスタイルのタスクボードビュー
// リアクティブ要件: TaskStoreを使用してUIの自動更新を実現

import SwiftUI
import Domain
import UseCase
import UniformTypeIdentifiers

private typealias AsyncTask = _Concurrency.Task

// MARK: - Debug Logging (ファイル出力でXCUITest環境でもログ確認可能)
enum DebugLog {
    static let logFile = "/tmp/aiagentpm_debug.log"

    static func write(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)\n"

        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile) {
                if let handle = FileHandle(forWritingAtPath: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logFile, contents: data, attributes: nil)
            }
        }

        // NSLogも出力（コンソール確認用）
        NSLog("%@", message)
    }
}

// MARK: - Drag & Drop Support

/// UTType for TaskID transfer during drag and drop
extension UTType {
    static let taskID = UTType(exportedAs: "com.aiagentpm.taskid")
}

/// Wrapper for TaskID to support drag and drop via Transferable
struct DraggableTaskID: Codable, Transferable {
    let taskIdValue: String

    init(taskId: TaskID) {
        self.taskIdValue = taskId.value
    }

    var taskId: TaskID {
        TaskID(value: taskIdValue)
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .taskID)
    }
}

struct TaskBoardView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router

    let projectId: ProjectID

    /// 共有タスクストア（ContentViewから渡される）
    /// nilの場合はローカルで作成
    @ObservedObject var taskStore: TaskStore

    @State private var agents: [Agent] = []
    @State private var templates: [WorkflowTemplate] = []
    @State private var project: Project?
    @State private var isLoading = false
    @State private var showingTemplates = false
    @State private var pollingTimer: Timer?

    private let columns: [TaskStatus] = [.backlog, .todo, .inProgress, .blocked, .done]

    init(projectId: ProjectID, taskStore: TaskStore?) {
        self.projectId = projectId
        // taskStoreがnilの場合は一時的なダミーを作成（すぐにContentViewから正しいものが渡される）
        self._taskStore = ObservedObject(wrappedValue: taskStore ?? TaskStore(projectId: projectId, container: DependencyContainer.shared))
    }

    @ViewBuilder
    private var templatesButton: some View {
        Button {
            showingTemplates.toggle()
        } label: {
            Label("Templates", systemImage: "doc.on.doc")
        }
        .help("Templates (⇧⌘M)")
        .popover(isPresented: $showingTemplates) {
            TemplatesPopoverView(
                projectId: projectId,
                templates: templates,
                onTemplateSelected: { templateId in
                    showingTemplates = false
                    router.showSheet(.templateDetail(templateId))
                },
                onNewTemplate: {
                    showingTemplates = false
                    router.showSheet(.newTemplate)
                },
                onRefresh: {
                    AsyncTask { await loadTemplates() }
                }
            )
            .accessibilityIdentifier("TemplatesPopover")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Project Info Header
            if let project = project {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Working Directory:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(project.workingDirectory ?? "Not set")
                            .font(.caption)
                            .foregroundStyle(project.workingDirectory != nil ? .primary : .tertiary)
                            .accessibilityIdentifier("WorkingDirectoryValue")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("ProjectWorkingDirectory")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.background.secondary)
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(columns, id: \.self) { status in
                        TaskColumnView(
                            status: status,
                            tasks: taskStore.tasks(for: status),
                            agents: agents,
                            onTaskDropped: { taskId, newStatus in
                                handleTaskDrop(taskId: taskId, newStatus: newStatus)
                            }
                        )
                    }
                }
                .padding()
            }
            .accessibilityIdentifier("TaskBoardScrollView")
        }
        .accessibilityIdentifier("TaskBoard")
        .navigationTitle("Task Board")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.showSheet(.newTask(projectId))
                } label: {
                    Label("New Task", systemImage: "plus")
                }
                .accessibilityIdentifier("NewTaskButton")
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .help("New Task (⇧⌘T)")
            }

            ToolbarItem {
                templatesButton
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Templates")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("TemplatesButton")
            }

            ToolbarItem {
                Button {
                    AsyncTask { await loadData() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("RefreshButton")
                .keyboardShortcut("r", modifiers: [.command])
                .help("Refresh (⌘R)")
            }
        }
        .overlay {
            if isLoading || taskStore.isLoading {
                ProgressView()
                    .accessibilityIdentifier("LoadingIndicator")
            }
        }
        .task {
            await loadData()
        }
        .onChange(of: router.currentSheet) { oldValue, newValue in
            // シートが閉じられた時にデータを再読み込み
            if oldValue != nil && newValue == nil {
                AsyncTask { await loadData() }
            }
        }
        .onAppear {
            // UIテスト時は外部DB更新を検出するためにポーリング
            if AIAgentPMApp.isUITesting {
                pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                    DebugLog.write("[TaskBoardView] Polling timer fired, calling loadTasks")
                    AsyncTask { @MainActor in
                        await taskStore.loadTasks()
                        let statuses = taskStore.tasks.map { "\($0.id.value):\($0.status.rawValue)" }.joined(separator: ", ")
                        DebugLog.write("[TaskBoardView] loadTasks completed: \(statuses)")
                    }
                }
                DebugLog.write("[TaskBoardView] UITesting polling started")
            }
        }
        .onDisappear {
            pollingTimer?.invalidate()
            pollingTimer = nil
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            project = try container.projectRepository.findById(projectId)
            // タスクはTaskStore経由で読み込み
            await taskStore.loadTasks()
            agents = try container.getAgentsUseCase.execute()
            templates = try container.listTemplatesUseCase.execute(
                projectId: projectId,
                includeArchived: false
            )
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }

    private func loadTemplates() async {
        do {
            templates = try container.listTemplatesUseCase.execute(
                projectId: projectId,
                includeArchived: false
            )
        } catch {
            router.showAlert(.error(message: error.localizedDescription))
        }
    }

    /// ドラッグ&ドロップによるタスクのステータス変更
    private func handleTaskDrop(taskId: TaskID, newStatus: TaskStatus) {
        NSLog("🟣 [DragDrop] handleTaskDrop called: taskId=\(taskId.value), newStatus=\(newStatus.rawValue)")

        // 現在のタスクの状態を確認
        guard let currentTask = taskStore.tasks.first(where: { $0.id == taskId }) else {
            NSLog("🔴 [DragDrop] Task not found in taskStore: \(taskId.value)")
            return
        }

        NSLog("🟣 [DragDrop] Current task status: \(currentTask.status.rawValue)")

        // 同じステータスへのドロップは無視
        guard currentTask.status != newStatus else {
            NSLog("🟡 [DragDrop] Same status, ignoring drop")
            return
        }

        // ステータス遷移が有効か確認
        guard UpdateTaskStatusUseCase.canTransition(from: currentTask.status, to: newStatus) else {
            NSLog("🔴 [DragDrop] Invalid transition: \(currentTask.status.rawValue) -> \(newStatus.rawValue)")
            router.showAlert(.error(message: "Cannot change status from \(currentTask.status.displayName) to \(newStatus.displayName)"))
            return
        }

        NSLog("🟣 [DragDrop] Executing status update...")

        // ステータス更新を実行
        AsyncTask {
            do {
                _ = try container.updateTaskStatusUseCase.execute(
                    taskId: taskId,
                    newStatus: newStatus,
                    agentId: nil,
                    sessionId: nil,
                    reason: "Status changed via drag and drop"
                )
                NSLog("🟢 [DragDrop] Status update successful")
                // TaskStoreを再読み込みしてUIを更新
                await taskStore.loadTasks()
            } catch {
                NSLog("🔴 [DragDrop] Status update failed: \(error.localizedDescription)")
                await MainActor.run {
                    router.showAlert(.error(message: error.localizedDescription))
                }
            }
        }
    }
}

// MARK: - Templates Popover View

/// テンプレート一覧ポップオーバー
struct TemplatesPopoverView: View {
    let projectId: ProjectID
    let templates: [WorkflowTemplate]
    let onTemplateSelected: (WorkflowTemplateID) -> Void
    let onNewTemplate: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Templates")
                    .font(.headline)
                Spacer()
                Button {
                    onNewTemplate()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("NewTemplateButton")
            }
            .padding()

            Divider()

            // Template List
            if templates.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.doc")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("No templates")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Create Template") {
                        onNewTemplate()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(templates, id: \.id) { template in
                            Button {
                                onTemplateSelected(template.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        if !template.description.isEmpty {
                                            Text(template.description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if !template.variables.isEmpty {
                                        Text("\(template.variables.count)")
                                            .font(.caption2)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.2))
                                            .cornerRadius(4)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("TemplateRow_\(template.id.value)")

                            if template.id != templates.last?.id {
                                Divider()
                                    .padding(.leading)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 220)
    }
}

struct TaskColumnView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router

    let status: TaskStatus
    let tasks: [Task]
    let agents: [Agent]
    let onTaskDropped: (TaskID, TaskStatus) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(status.displayName)
                    .font(.headline)
                    .accessibilityLabel(status.displayName)  // 明示的にラベルを設定
                    .accessibilityIdentifier("ColumnHeader_\(status.rawValue)")
                Spacer()
                Text("\(tasks.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(tasks.count)")
                    .accessibilityIdentifier("ColumnCount_\(status.rawValue)")
            }
            .padding(.horizontal, 8)

            // Tasks
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(tasks, id: \.id) { task in
                        DraggableTaskCard(
                            task: task,
                            agents: agents,
                            onTap: {
                                DebugLog.write("🟠 [Click] TaskCard clicked: \(task.id.value)")
                                router.selectTask(task.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(width: 220)
        .background(isDropTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .dropDestination(for: DraggableTaskID.self) { droppedItems, _ in
            DebugLog.write("🟢 [dropDestination] drop called for column: \(status.rawValue), items count: \(droppedItems.count)")
            guard let droppedItem = droppedItems.first else {
                DebugLog.write("🔴 [dropDestination] No items")
                return false
            }
            DebugLog.write("🟢 [dropDestination] Dropped taskId: \(droppedItem.taskId.value)")
            onTaskDropped(droppedItem.taskId, status)
            return true
        } isTargeted: { isTargeted in
            DebugLog.write("🟡 [dropDestination] isTargeted changed to: \(isTargeted) for column: \(status.rawValue)")
            isDropTargeted = isTargeted
        }
        .accessibilityIdentifier("TaskColumn_\(status.rawValue)")
    }
}

struct TaskCardView: View {
    let task: Task
    let agents: [Agent]

    var assigneeName: String? {
        guard let assigneeId = task.assigneeId else { return nil }
        return agents.first { $0.id == assigneeId }?.name
    }

    var assigneeIcon: String {
        guard let assigneeId = task.assigneeId,
              let agent = agents.first(where: { $0.id == assigneeId }) else {
            return "👻"
        }
        return agent.type == .ai ? "🤖" : "👤"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .accessibilityLabel(task.title)  // 明示的にラベルを設定
                .accessibilityIdentifier("TaskTitle_\(task.id.value)")

            if !task.description.isEmpty {
                Text(task.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityLabel(task.description)  // 明示的にラベルを設定
                    .accessibilityIdentifier("TaskDescription")
            }

            HStack {
                PriorityBadge(priority: task.priority)
                    .accessibilityIdentifier("PriorityBadge_\(task.priority.rawValue)")

                Spacer()

                if let name = assigneeName {
                    Text("\(assigneeIcon) \(name)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("TaskAssignee")
                }
            }
        }
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))  // タップ領域を明確に定義
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct PriorityBadge: View {
    let priority: TaskPriority

    var color: Color {
        switch priority {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .blue
        case .low: return .gray
        }
    }

    var body: some View {
        Text(priority.rawValue.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .accessibilityLabel("Priority")
            .accessibilityValue(priority.rawValue.capitalized)
    }
}

/// ドラッグ可能なタスクカード
/// ButtonではなくonTapGestureを使用し、draggableと競合しないようにする
struct DraggableTaskCard: View {
    let task: Task
    let agents: [Agent]
    let onTap: () -> Void

    @FocusState private var isFocused: Bool

    /// アサイニー名を取得
    private var assigneeName: String? {
        guard let assigneeId = task.assigneeId else { return nil }
        return agents.first { $0.id == assigneeId }?.name
    }

    /// アクセシビリティラベル（タイトル + アサイニー名）
    private var accessibilityLabelText: String {
        if let name = assigneeName {
            return "\(task.title), assigned to \(name)"
        }
        return task.title
    }

    var body: some View {
        TaskCardView(task: task, agents: agents)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture {
                onTap()
            }
            .draggable(DraggableTaskID(taskId: task.id)) {
                TaskCardView(task: task, agents: agents)
                    .frame(width: 200)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onAppear {
                        DebugLog.write("🔵 [draggable] preview shown for task: \(task.id.value)")
                    }
            }
            .focusable()
            .focused($isFocused)
            // アクセシビリティ設定
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabelText)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("TaskCard_\(task.id.value)")
    }
}

// displayName is already defined in Domain/Entities/Task.swift
