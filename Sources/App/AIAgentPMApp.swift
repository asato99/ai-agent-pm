// Sources/App/AIAgentPMApp.swift
// SwiftUI Mac App エントリーポイント

import SwiftUI
import AppKit
import Domain
import Infrastructure

/// AppDelegate for proper window management in macOS
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure app is active and windows are visible
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Force window to front for UI testing
        if CommandLine.arguments.contains("-UITesting") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct AIAgentPMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var container: DependencyContainer
    @State private var router = Router()

    // MARK: - UIテスト用フラグ

    /// UIテストモードかどうか（-UITesting引数で判定）
    static var isUITesting: Bool {
        CommandLine.arguments.contains("-UITesting")
    }

    /// テストシナリオ（-UITestScenario:XXX で指定）
    static var testScenario: TestScenario {
        for arg in CommandLine.arguments {
            if arg.hasPrefix("-UITestScenario:") {
                let scenario = String(arg.dropFirst("-UITestScenario:".count))
                return TestScenario(rawValue: scenario) ?? .basic
            }
        }
        return .basic
    }

    /// テストシナリオの種類
    enum TestScenario: String {
        case empty = "Empty"           // 空状態（プロジェクトなし）
        case basic = "Basic"           // 基本データ（プロジェクト+エージェント+タスク）
        case multiProject = "MultiProject"  // 複数プロジェクト
        case uc001 = "UC001"           // UC001: エージェントキック用（workingDirectory設定済み）
        case noWD = "NoWD"             // NoWD: workingDirectory未設定エラーテスト用
        case internalAudit = "InternalAudit" // Internal Audit機能テスト用
        case workflowTemplate = "WorkflowTemplate" // ワークフローテンプレート機能テスト用
    }

    init() {
        // Initialize container - any error here is fatal
        let newContainer: DependencyContainer
        do {
            if Self.isUITesting {
                // UIテスト用: 一時ディレクトリに専用DBを作成
                let testDBPath = NSTemporaryDirectory() + "AIAgentPM_UITest.db"
                // 前回のテストDBとジャーナルファイルを削除してクリーンな状態で開始
                try? FileManager.default.removeItem(atPath: testDBPath)
                try? FileManager.default.removeItem(atPath: testDBPath + "-shm")
                try? FileManager.default.removeItem(atPath: testDBPath + "-wal")
                newContainer = try DependencyContainer(databasePath: testDBPath)

            } else {
                // 通常起動: デフォルトパス
                newContainer = try DependencyContainer()
            }
        } catch {
            fatalError("Failed to initialize DependencyContainer: \(error)")
        }
        _container = StateObject(wrappedValue: newContainer)
        // グローバル共有インスタンスを設定（TaskStore等のフォールバック用）
        DependencyContainer.shared = newContainer
    }

    @State private var isSeeded = false

    var body: some Scene {
        WindowGroup("AI Agent PM") {
            ContentView()
                .environmentObject(container)
                .environment(router)
                .frame(minWidth: 800, minHeight: 600)
                .task {
                    // UIテスト時はテストデータをシードし、完了を通知
                    if Self.isUITesting && !isSeeded {
                        await seedTestData()
                        isSeeded = true
                        // シード完了後、ProjectListViewの再読み込みをトリガー
                        try? "Posting testDataSeeded notification at \(Date())".appendToFile("/tmp/uitest_workflow_debug.txt")
                        NotificationCenter.default.post(name: .testDataSeeded, object: nil)
                        try? "Notification posted at \(Date())".appendToFile("/tmp/uitest_workflow_debug.txt")
                    }
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            // File Menu
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    router.showSheet(.newProject)
                }
                .keyboardShortcut("n", modifiers: [.command])

                // エージェントはプロジェクト非依存のトップレベルエンティティ
                Button("New Agent") {
                    router.showSheet(.newAgent)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                if let projectId = router.selectedProject {
                    Divider()

                    Button("New Task") {
                        router.showSheet(.newTask(projectId))
                    }
                    .keyboardShortcut("t", modifiers: [.command, .shift])

                    Button("New Template") {
                        router.showSheet(.newTemplate)
                    }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                }
            }

            // View Menu additions
            CommandGroup(after: .sidebar) {
                Divider()

                Button("Refresh") {
                    // Trigger refresh
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            // UIテスト用コマンド（-UITestingフラグ時のみ有効）
            if Self.isUITesting {
                CommandGroup(after: .newItem) {
                    Divider()
                    // 依存タスクを選択（Cmd+Shift+D）
                    Button("Select Dependent Task (UITest)") {
                        router.selectTask(TaskID(value: "uitest_dependent_task"))
                    }
                    .keyboardShortcut("d", modifiers: [.command, .shift])

                    // リソーステストタスクを選択（Cmd+Shift+G）
                    Button("Select Resource Test Task (UITest)") {
                        router.selectTask(TaskID(value: "uitest_resource_task"))
                    }
                    .keyboardShortcut("g", modifiers: [.command, .shift])

                    // 作業ディレクトリなしプロジェクトを選択（Cmd+Shift+W）
                    Button("Select No-WorkingDir Project (UITest)") {
                        router.selectProject(ProjectID(value: "uitest_no_wd_project"))
                    }
                    .keyboardShortcut("w", modifiers: [.command, .shift])

                    // トリガーテストタスクを選択（Cmd+Shift+Y）
                    Button("Select Trigger Test Task (UITest)") {
                        router.selectTask(TaskID(value: "uitest_trigger_task"))
                    }
                    .keyboardShortcut("y", modifiers: [.command, .shift])

                    // ロック済みタスクを選択（Cmd+Shift+L）
                    Button("Select Locked Task (UITest)") {
                        router.selectTask(TaskID(value: "uitest_locked_task"))
                    }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(container)
        }
    }

    // MARK: - UIテスト用データシード

    @MainActor
    private func seedTestData() async {
        NSLog("🔧 UITest: seedTestData() called with scenario: \(Self.testScenario.rawValue)")

        // Debug: Write scenario to temp file
        let debugPath = "/tmp/uitest_scenario_debug.txt"
        try? "seedTestData() called at \(Date())\nscenario: \(Self.testScenario.rawValue)\narguments: \(CommandLine.arguments)\n".write(toFile: debugPath, atomically: true, encoding: .utf8)

        let seeder = TestDataSeeder(
            projectRepository: container.projectRepository,
            agentRepository: container.agentRepository,
            taskRepository: container.taskRepository,
            templateRepository: container.workflowTemplateRepository,
            templateTaskRepository: container.templateTaskRepository,
            internalAuditRepository: container.internalAuditRepository,
            auditRuleRepository: container.auditRuleRepository
        )

        do {
            switch Self.testScenario {
            case .empty:
                try await seeder.seedEmptyState()
            case .basic:
                try await seeder.seedBasicData()
            case .multiProject:
                try await seeder.seedMultipleProjects()
            case .uc001:
                try await seeder.seedUC001Data()
            case .noWD:
                try await seeder.seedNoWDData()
            case .internalAudit:
                try await seeder.seedInternalAuditData()
            case .workflowTemplate:
                NSLog("🔧 UITest: Executing seedWorkflowTemplateData()")
                try await seeder.seedWorkflowTemplateData()
            }
            NSLog("✅ UITest: Test data seeded successfully for scenario: \(Self.testScenario.rawValue)")
            try? "Seeding complete at \(Date()), about to post notification".appendToFile("/tmp/uitest_workflow_debug.txt")
        } catch {
            NSLog("⚠️ UITest: Failed to seed test data: \(error)")
            try? "Seeding FAILED: \(error)".appendToFile("/tmp/uitest_workflow_debug.txt")
        }
    }
}

// MARK: - Test Data Seeder

/// UIテスト用のテストデータを生成するシーダー
private final class TestDataSeeder {

    private let projectRepository: ProjectRepository
    private let agentRepository: AgentRepository
    private let taskRepository: TaskRepository
    private let templateRepository: WorkflowTemplateRepository?
    private let templateTaskRepository: TemplateTaskRepository?
    private let internalAuditRepository: InternalAuditRepository?
    private let auditRuleRepository: AuditRuleRepository?

    init(
        projectRepository: ProjectRepository,
        agentRepository: AgentRepository,
        taskRepository: TaskRepository,
        templateRepository: WorkflowTemplateRepository? = nil,
        templateTaskRepository: TemplateTaskRepository? = nil,
        internalAuditRepository: InternalAuditRepository? = nil,
        auditRuleRepository: AuditRuleRepository? = nil
    ) {
        self.projectRepository = projectRepository
        self.agentRepository = agentRepository
        self.taskRepository = taskRepository
        self.templateRepository = templateRepository
        self.templateTaskRepository = templateTaskRepository
        self.internalAuditRepository = internalAuditRepository
        self.auditRuleRepository = auditRuleRepository
    }

    /// 基本的なテストデータを生成（プロジェクト、エージェント、タスク）
    func seedBasicData() async throws {
        // 作業ディレクトリを作成（存在しない場合）
        let workingDir = "/tmp/basic_test"
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: workingDir) {
            try fileManager.createDirectory(atPath: workingDir, withIntermediateDirectories: true)
        }

        // プロジェクト作成（workingDirectory設定済み）
        let project = Project(
            id: .generate(),
            name: "テストプロジェクト",
            description: "UIテスト用のサンプルプロジェクト",
            status: .active,
            workingDirectory: workingDir,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await projectRepository.save(project)

        // エージェント作成（Human - Manager）
        // 要件: エージェントはプロジェクト非依存のトップレベルエンティティ
        let ownerAgent = Agent(
            id: .generate(),
            name: "owner",
            role: "プロジェクトオーナー",
            type: .human,
            roleType: .manager,
            capabilities: [],
            systemPrompt: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(ownerAgent)

        // エージェント作成（AI - Developer、並列数1）
        // maxParallelTasks: 1 でリソースブロックテスト用
        let devAgent = Agent(
            id: .generate(),
            name: "backend-dev",
            role: "バックエンド開発",
            type: .ai,
            roleType: .developer,
            parentAgentId: nil,
            maxParallelTasks: 1,  // 並列数1でテスト用
            capabilities: ["Swift", "Python", "API設計"],
            systemPrompt: "バックエンド開発を担当するAIエージェントです",
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(devAgent)

        // 依存関係テスト用: まず先行タスク（未完了）を作成
        // 注意: backlogステータスにして、todoカラムのスクロール問題を回避
        // UIテスト用に固定IDを使用
        let prerequisiteTaskId = TaskID(value: "uitest_prerequisite_task")
        let prerequisiteTask = Task(
            id: prerequisiteTaskId,
            projectId: project.id,
            title: "先行タスク",
            description: "この先行タスクが完了しないと次のタスクを開始できません",
            status: .backlog,  // backlogで未完了（doneではないので依存タスクはブロックされる）
            priority: .high,
            assigneeId: nil,
            dependencies: [],
            estimatedMinutes: nil,
            actualMinutes: nil,
            createdAt: Date(),
            updatedAt: Date(),
            completedAt: nil
        )
        try await taskRepository.save(prerequisiteTask)

        // 依存関係テスト用: 先行タスクに依存するタスク
        // UIテスト用に固定IDを使用
        let dependentTaskId = TaskID(value: "uitest_dependent_task")
        let dependentTask = Task(
            id: dependentTaskId,
            projectId: project.id,
            title: "依存タスク",
            description: "先行タスク完了後に開始可能（依存関係テスト用）",
            status: .todo,
            priority: .medium,
            assigneeId: devAgent.id,
            dependencies: [prerequisiteTaskId],  // 先行タスクに依存
            estimatedMinutes: nil,
            actualMinutes: nil,
            createdAt: Date(),
            updatedAt: Date(),
            completedAt: nil
        )
        try await taskRepository.save(dependentTask)

        // 各ステータスのタスクを作成
        // 要件: TaskStatusは backlog, todo, in_progress, blocked, done, cancelled のみ
        // 注意: todoカラムには依存タスク・追加開発タスクがあるので、
        //       他のtodoタスクは最小限にしてスクロール問題を回避
        let taskStatuses: [(TaskStatus, String, String, TaskPriority)] = [
            (.backlog, "UI設計", "画面レイアウトの設計", .low),
            // todoには依存テスト用タスクと追加開発タスクのみ
            (.inProgress, "API実装", "REST APIエンドポイントの実装", .high),
            (.done, "要件定義", "プロジェクト要件の定義完了", .high),
            (.blocked, "API統合", "外部APIとの統合（認証待ち）", .urgent),
        ]

        for (status, title, description, priority) in taskStatuses {
            let task = Task(
                id: .generate(),
                projectId: project.id,
                title: title,
                description: description,
                status: status,
                priority: priority,
                assigneeId: status == .inProgress ? devAgent.id : nil,
                dependencies: [],
                estimatedMinutes: nil,
                actualMinutes: nil,
                createdAt: Date(),
                updatedAt: Date(),
                completedAt: status == .done ? Date() : nil
            )
            try await taskRepository.save(task)
        }

        // リソースブロックテスト用: devAgentに追加のtodoタスクをアサイン
        // devAgentは既にAPI実装(inProgress)を持っており、maxParallelTasks=1
        // UIテスト用に固定IDを使用
        let resourceTestTaskId = TaskID(value: "uitest_resource_task")
        let additionalTaskForResourceTest = Task(
            id: resourceTestTaskId,
            projectId: project.id,
            title: "追加開発タスク",
            description: "リソースブロックテスト用（並列数上限確認）",
            status: .todo,  // todoから直接in_progressに遷移を試みる
            priority: .medium,
            assigneeId: devAgent.id,  // devAgentにアサイン
            dependencies: [],
            estimatedMinutes: nil,
            actualMinutes: nil,
            createdAt: Date(),
            updatedAt: Date(),
            completedAt: nil
        )
        try await taskRepository.save(additionalTaskForResourceTest)
    }

    /// 空のプロジェクト状態をシード（プロジェクトなし）
    func seedEmptyState() async throws {
        // 何もしない - 空の状態
    }

    /// UC001用のテストデータを生成（エージェントキック機能用）
    /// - workingDirectory設定済みプロジェクト
    /// - kickMethod=cli設定済みのclaude-code-agent
    ///
    /// 環境変数または引数:
    /// - UC001_WORKING_DIR / -UC001WorkingDir: 作業ディレクトリ（デフォルト: /tmp/uc001_test）
    /// - UC001_OUTPUT_FILE / -UC001OutputFile: 出力ファイル名（デフォルト: test_output.md）
    func seedUC001Data() async throws {
        // 引数から設定を取得（-UC001WorkingDir:/path/to/dir 形式）
        var workingDirArg: String?
        var outputFileArg: String?

        for arg in CommandLine.arguments {
            if arg.hasPrefix("-UC001WorkingDir:") {
                workingDirArg = String(arg.dropFirst("-UC001WorkingDir:".count))
            } else if arg.hasPrefix("-UC001OutputFile:") {
                outputFileArg = String(arg.dropFirst("-UC001OutputFile:".count))
            }
        }

        // 引数になければ環境変数から取得、それもなければデフォルト値
        let workingDir = workingDirArg ?? ProcessInfo.processInfo.environment["UC001_WORKING_DIR"] ?? "/tmp/uc001_test"
        let outputFile = outputFileArg ?? ProcessInfo.processInfo.environment["UC001_OUTPUT_FILE"] ?? "test_output.md"

        // デバッグ出力
        print("=== UC001 Test Data Configuration ===")
        print("Working Directory: \(workingDir)")
        print("Output File: \(outputFile)")

        // 作業ディレクトリを作成（存在しない場合）
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: workingDir) {
            try fileManager.createDirectory(atPath: workingDir, withIntermediateDirectories: true)
        }

        // UC001用プロジェクト（workingDirectory設定済み）
        let uc001Project = Project(
            id: .generate(),
            name: "UC001テストプロジェクト",
            description: "エージェントキック機能テスト用プロジェクト",
            status: .active,
            workingDirectory: workingDir,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await projectRepository.save(uc001Project)

        // workingDirectory未設定のフォールバックプロジェクト（エラーテスト用）
        // 固定IDを使用してUIテストから選択可能にする
        let noWDProject = Project(
            id: ProjectID(value: "uitest_no_wd_project"),
            name: "作業ディレクトリなしPJ",
            description: "作業ディレクトリ未設定のプロジェクト（エラーテスト用）",
            status: .active,
            workingDirectory: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await projectRepository.save(noWDProject)

        // claude-code-agent（kickMethod=cli設定済み）
        let claudeAgent = Agent(
            id: .generate(),
            name: "claude-code-agent",
            role: "Claude Code CLIエージェント",
            type: .ai,
            roleType: .developer,
            parentAgentId: nil,
            maxParallelTasks: 3,
            capabilities: ["TypeScript", "Python", "Swift"],
            systemPrompt: "Claude Codeを使用して開発タスクを実行するエージェントです",
            kickMethod: .cli,
            kickCommand: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(claudeAgent)

        // 人間オーナー（kickMethod=none）
        let ownerAgent = Agent(
            id: .generate(),
            name: "owner",
            role: "プロジェクトオーナー",
            type: .human,
            roleType: .manager,
            capabilities: [],
            systemPrompt: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(ownerAgent)

        // 基本タスク（エージェント未アサイン）
        let basicTask = Task(
            id: .generate(),
            projectId: uc001Project.id,
            title: "基本タスク",
            description: "テスト用の基本タスク",
            status: .backlog,
            priority: .medium,
            assigneeId: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(basicTask)

        // キックテスト用タスク（claude-code-agentがアサイン済み、backlog状態）
        let kickTestTask = Task(
            id: TaskID(value: "uitest_kick_task"),
            projectId: uc001Project.id,
            title: "キックテストタスク",
            description: """
                エージェントキック機能のテスト用タスク。

                【指示】
                ファイル名: \(outputFile)
                内容: テスト用のMarkdownファイルを作成してください。内容には'integration test content'という文字列を含めること。
                """,
            status: .backlog,
            priority: .high,
            assigneeId: claudeAgent.id,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(kickTestTask)

        // 作業ディレクトリ未設定エラーテスト用タスク（noWDProjectに作成）
        // claude-code-agentにアサインされているが、プロジェクトに作業ディレクトリがないためキック時にエラーになる
        // backlogステータスでUIテストのスクロール問題を回避
        let noWDKickTask = Task(
            id: TaskID(value: "uitest_no_wd_kick_task"),
            projectId: noWDProject.id,
            title: "作業ディレクトリなしキックタスク",
            description: "作業ディレクトリ未設定エラーのテスト用",
            status: .backlog,
            priority: .high,
            assigneeId: claudeAgent.id,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(noWDKickTask)

        // kickMethod未設定エージェントテスト用タスク（ownerAgentにアサイン）
        // ownerAgentはhuman型でkickMethodが設定されていないため、キックはスキップされる
        // backlogステータスでUIテストのスクロール問題を回避
        let noKickMethodTask = Task(
            id: TaskID(value: "uitest_no_kick_method_task"),
            projectId: uc001Project.id,
            title: "キックメソッドなしタスク",
            description: "kickMethod未設定エージェントのテスト用（キックがスキップされることを確認）",
            status: .backlog,
            priority: .medium,
            assigneeId: ownerAgent.id,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(noKickMethodTask)

        // 依存関係テスト用: 先行タスク（未完了）
        // UIテスト用に固定IDを使用
        let prerequisiteTaskId = TaskID(value: "uitest_prerequisite_task")
        let prerequisiteTask = Task(
            id: prerequisiteTaskId,
            projectId: uc001Project.id,
            title: "先行タスク",
            description: "この先行タスクが完了しないと次のタスクを開始できません",
            status: .backlog,  // backlogで未完了（doneではないので依存タスクはブロックされる）
            priority: .high,
            assigneeId: nil,
            dependencies: [],
            estimatedMinutes: nil,
            actualMinutes: nil,
            createdAt: Date(),
            updatedAt: Date(),
            completedAt: nil
        )
        try await taskRepository.save(prerequisiteTask)

        // 依存関係テスト用: 先行タスクに依存するタスク
        // UIテスト用に固定IDを使用
        let dependentTaskId = TaskID(value: "uitest_dependent_task")
        let dependentTask = Task(
            id: dependentTaskId,
            projectId: uc001Project.id,
            title: "依存タスク",
            description: "先行タスク完了後に開始可能（依存関係テスト用）",
            status: .todo,
            priority: .medium,
            assigneeId: claudeAgent.id,
            dependencies: [prerequisiteTaskId],  // 先行タスクに依存
            estimatedMinutes: nil,
            actualMinutes: nil,
            createdAt: Date(),
            updatedAt: Date(),
            completedAt: nil
        )
        try await taskRepository.save(dependentTask)
    }

    /// 複数プロジェクトをシード
    func seedMultipleProjects() async throws {
        let projectNames = ["ECサイト開発", "モバイルアプリ", "管理システム"]

        for name in projectNames {
            let project = Project(
                id: .generate(),
                name: name,
                description: "\(name)のプロジェクト",
                status: .active,
                createdAt: Date(),
                updatedAt: Date()
            )
            try await projectRepository.save(project)

            // 各プロジェクトに基本的なエージェントを追加
            // 要件: エージェントはプロジェクト非依存
            let agent = Agent(
                id: .generate(),
                name: "developer-\(name)",
                role: "開発者",
                type: .ai,
                roleType: .developer,
                capabilities: [],
                systemPrompt: nil,
                status: .active,
                createdAt: Date(),
                updatedAt: Date()
            )
            try await agentRepository.save(agent)

            // 基本的なタスクを追加
            let task = Task(
                id: .generate(),
                projectId: project.id,
                title: "初期タスク",
                description: "プロジェクトの初期タスク",
                status: .backlog,
                priority: .medium
            )
            try await taskRepository.save(task)
        }
    }

    /// NoWDシナリオ: workingDirectory未設定プロジェクトのみをシード
    /// キック時にエラーになることをテストするための専用シナリオ
    func seedNoWDData() async throws {
        // workingDirectory未設定のプロジェクト（唯一のプロジェクト）
        let noWDProject = Project(
            id: ProjectID(value: "uitest_no_wd_project"),
            name: "作業ディレクトリなしPJ",
            description: "作業ディレクトリ未設定のプロジェクト（エラーテスト用）",
            status: .active,
            workingDirectory: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await projectRepository.save(noWDProject)

        // claude-code-agent（kickMethod=cli設定済み）
        let claudeAgent = Agent(
            id: .generate(),
            name: "claude-code-agent",
            role: "Claude Code CLIエージェント",
            type: .ai,
            roleType: .developer,
            parentAgentId: nil,
            maxParallelTasks: 3,
            capabilities: ["TypeScript", "Python", "Swift"],
            systemPrompt: "Claude Codeを使用して開発タスクを実行するエージェントです",
            kickMethod: .cli,
            kickCommand: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(claudeAgent)

        // workingDirectory未設定エラーテスト用タスク
        // claude-code-agentにアサインされているが、プロジェクトに作業ディレクトリがないためキック時にエラーになる
        let noWDKickTask = Task(
            id: TaskID(value: "uitest_no_wd_kick_task"),
            projectId: noWDProject.id,
            title: "作業ディレクトリなしキックタスク",
            description: "作業ディレクトリ未設定エラーのテスト用",
            status: .backlog,
            priority: .high,
            assigneeId: claudeAgent.id,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(noWDKickTask)
    }

    /// Internal Audit機能テスト用のデータをシード
    /// - Internal Audit + Audit Rule
    /// - エージェント（タスク割り当て用）
    /// 設計変更: AuditRuleはauditTasksをインラインで保持（WorkflowTemplateはプロジェクトスコープのため）
    func seedInternalAuditData() async throws {
        guard let internalAuditRepository = internalAuditRepository,
              let auditRuleRepository = auditRuleRepository else {
            print("⚠️ UITest: Internal Audit repositories not available")
            return
        }

        // エージェント作成（Audit Rule用）
        let qaAgent = Agent(
            id: AgentID(value: "uitest_qa_agent"),
            name: "qa-agent",
            role: "QA Engineer",
            type: .ai,
            roleType: .developer,
            capabilities: ["Testing", "Quality Assurance"],
            systemPrompt: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(qaAgent)

        let reviewerAgent = Agent(
            id: AgentID(value: "uitest_reviewer_agent"),
            name: "reviewer-agent",
            role: "Code Reviewer",
            type: .ai,
            roleType: .developer,
            capabilities: ["Code Review"],
            systemPrompt: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(reviewerAgent)

        // Internal Audit作成
        let auditId = InternalAuditID(value: "uitest_internal_audit")
        let audit = InternalAudit(
            id: auditId,
            name: "Test QA Audit",
            description: "Quality assurance audit for testing purposes",
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try internalAuditRepository.save(audit)

        // Audit Rule作成（auditTasksをインラインで定義）
        let ruleId = AuditRuleID(value: "uitest_audit_rule")
        let rule = AuditRule(
            id: ruleId,
            auditId: auditId,
            name: "Task Completion Check",
            triggerType: .taskCompleted,
            triggerConfig: nil,
            auditTasks: [
                AuditTask(
                    order: 1,
                    title: "Run Unit Tests",
                    description: "Execute all unit tests",
                    assigneeId: qaAgent.id,
                    priority: .high,
                    dependsOnOrders: []
                ),
                AuditTask(
                    order: 2,
                    title: "Code Review",
                    description: "Review code changes",
                    assigneeId: reviewerAgent.id,
                    priority: .medium,
                    dependsOnOrders: [1]
                )
            ],
            isEnabled: true
        )
        try auditRuleRepository.save(rule)

        // トリガーテスト用プロジェクト作成
        let triggerTestProject = Project(
            id: ProjectID(value: "uitest_trigger_project"),
            name: "トリガーテストPJ",
            description: "Audit Ruleトリガーのテスト用プロジェクト",
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await projectRepository.save(triggerTestProject)

        // WorkflowTemplate作成（AuditRule作成時のテンプレートインポート用）
        if let templateRepository = templateRepository,
           let templateTaskRepository = templateTaskRepository {
            let qaTemplateId = WorkflowTemplateID(value: "uitest_qa_template")
            let qaTemplate = WorkflowTemplate(
                id: qaTemplateId,
                projectId: triggerTestProject.id,
                name: "QA Workflow Template",
                description: "品質保証用ワークフローテンプレート",
                variables: [],
                status: .active,
                createdAt: Date(),
                updatedAt: Date()
            )
            try templateRepository.save(qaTemplate)

            // テンプレートタスク作成
            let task1 = TemplateTask(
                id: TemplateTaskID(value: "uitest_qa_template_task_1"),
                templateId: qaTemplateId,
                title: "Quality Check",
                description: "品質チェックを実行",
                order: 1,
                dependsOnOrders: [],
                defaultAssigneeRole: .developer,
                defaultPriority: .high,
                estimatedMinutes: 60
            )
            try templateTaskRepository.save(task1)

            let task2 = TemplateTask(
                id: TemplateTaskID(value: "uitest_qa_template_task_2"),
                templateId: qaTemplateId,
                title: "Approval",
                description: "承認プロセス",
                order: 2,
                dependsOnOrders: [1],
                defaultAssigneeRole: .manager,
                defaultPriority: .medium,
                estimatedMinutes: 30
            )
            try templateTaskRepository.save(task2)

            print("✅ UITest: QA Workflow Template created with 2 tasks")
        }

        // トリガーテスト用タスク（inProgress状態 → doneに変更でトリガー発火）
        let triggerTestTask = Task(
            id: TaskID(value: "uitest_trigger_task"),
            projectId: triggerTestProject.id,
            title: "トリガーテストタスク",
            description: "このタスクを完了するとAudit Ruleがトリガーされ、QA Workflowタスクが自動生成されます",
            status: .inProgress,  // 完了可能な状態
            priority: .high,
            assigneeId: qaAgent.id,
            dependencies: [],
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(triggerTestTask)

        // 追加：完了済みタスク（トリガー発火後の確認用比較対象）
        let completedTask = Task(
            id: TaskID(value: "uitest_completed_task"),
            projectId: triggerTestProject.id,
            title: "完了済みタスク",
            description: "既に完了したタスク",
            status: .done,
            priority: .medium,
            assigneeId: nil,
            dependencies: [],
            createdAt: Date(),
            updatedAt: Date(),
            completedAt: Date()
        )
        try await taskRepository.save(completedTask)

        // ロックテスト用タスク（既にロック済み）
        let lockedTask = Task(
            id: TaskID(value: "uitest_locked_task"),
            projectId: triggerTestProject.id,
            title: "ロック済みタスク",
            description: "監査によりロックされたタスク - ステータス変更不可",
            status: .inProgress,
            priority: .high,
            assigneeId: qaAgent.id,
            dependencies: [],
            createdAt: Date(),
            updatedAt: Date(),
            isLocked: true,
            lockedByAuditId: auditId,
            lockedAt: Date()
        )
        try await taskRepository.save(lockedTask)

        print("✅ UITest: Internal Audit test data seeded successfully")
    }

    /// WorkflowTemplate機能テスト用のデータをシード
    /// 設計変更: WorkflowTemplateはプロジェクトスコープ（projectIdを持つ）
    /// テンプレートはTaskBoardViewのTemplatesボタン+ポップオーバーからアクセス
    func seedWorkflowTemplateData() async throws {
        NSLog("🔧 UITest: seedWorkflowTemplateData() - START")

        // Debug: Write to temp file to confirm seeder runs
        let debugPath = "/tmp/uitest_workflow_debug.txt"
        try? "seedWorkflowTemplateData() started at \(Date())\n".write(toFile: debugPath, atomically: true, encoding: .utf8)

        // プロジェクト作成（テンプレートが所属するプロジェクト）
        // NOTE: プロジェクトは必須なので、テンプレートリポジトリに関わらず作成
        NSLog("🔧 UITest: Creating project...")
        let project = Project(
            id: ProjectID(value: "uitest_template_project"),
            name: "テンプレートテストPJ",
            description: "ワークフローテンプレート機能のテスト用プロジェクト",
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try projectRepository.save(project)
        NSLog("🔧 UITest: Project saved successfully - id=\(project.id.value)")

        // Debug: verify project was saved
        let savedProjects = try projectRepository.findAll()
        let debugContent = """
        Project saved at \(Date())
        id: \(project.id.value)
        Projects in DB: \(savedProjects.count)
        Project names: \(savedProjects.map { $0.name })
        """
        try? debugContent.appendToFile("/tmp/uitest_workflow_debug.txt")

        NSLog("🔧 UITest: templateRepository=\(String(describing: templateRepository != nil)), templateTaskRepository=\(String(describing: templateTaskRepository != nil))")
        try? "templateRepository=\(templateRepository != nil), templateTaskRepository=\(templateTaskRepository != nil)".appendToFile("/tmp/uitest_workflow_debug.txt")

        guard let templateRepository = templateRepository,
              let templateTaskRepository = templateTaskRepository else {
            NSLog("⚠️ UITest: Workflow Template repositories not available - but project created")
            try? "⚠️ GUARD FAILED: repositories are nil - returning early".appendToFile("/tmp/uitest_workflow_debug.txt")
            return
        }

        try? "✅ Repositories available, creating template...".appendToFile("/tmp/uitest_workflow_debug.txt")

        // エージェント作成（テンプレートタスクのデフォルト担当用）
        NSLog("🔧 UITest: Creating agents...")
        let devAgent = Agent(
            id: AgentID(value: "uitest_template_dev_agent"),
            name: "template-dev",
            role: "開発者",
            type: .ai,
            roleType: .developer,
            capabilities: ["Development"],
            systemPrompt: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try agentRepository.save(devAgent)

        let qaAgent = Agent(
            id: AgentID(value: "uitest_template_qa_agent"),
            name: "template-qa",
            role: "QA担当",
            type: .ai,
            roleType: .developer,
            capabilities: ["Testing", "QA"],
            systemPrompt: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try agentRepository.save(qaAgent)
        NSLog("🔧 UITest: Agents created")

        // ワークフローテンプレート作成（変数付き）
        let templateId = WorkflowTemplateID(value: "uitest_workflow_template")
        let template = WorkflowTemplate(
            id: templateId,
            projectId: project.id,
            name: "Feature Development",
            description: "機能開発用のワークフローテンプレート",
            variables: ["feature_name", "sprint_number"],
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try templateRepository.save(template)
        try? "✅ Template 'Feature Development' saved with id=\(templateId.value)".appendToFile("/tmp/uitest_workflow_debug.txt")
        NSLog("🔧 UITest: Template saved - id=\(templateId.value)")

        // テンプレートタスク作成
        let task1 = TemplateTask(
            id: TemplateTaskID(value: "uitest_template_task_1"),
            templateId: templateId,
            title: "{{feature_name}} 設計",
            description: "Sprint {{sprint_number}}: 機能の設計を行う",
            order: 1,
            dependsOnOrders: [],
            defaultAssigneeRole: .developer,
            defaultPriority: .high,
            estimatedMinutes: 120
        )
        try templateTaskRepository.save(task1)

        let task2 = TemplateTask(
            id: TemplateTaskID(value: "uitest_template_task_2"),
            templateId: templateId,
            title: "{{feature_name}} 実装",
            description: "Sprint {{sprint_number}}: 機能の実装を行う",
            order: 2,
            dependsOnOrders: [1],  // 設計に依存
            defaultAssigneeRole: .developer,
            defaultPriority: .high,
            estimatedMinutes: 240
        )
        try templateTaskRepository.save(task2)

        let task3 = TemplateTask(
            id: TemplateTaskID(value: "uitest_template_task_3"),
            templateId: templateId,
            title: "{{feature_name}} テスト",
            description: "Sprint {{sprint_number}}: 機能のテストを行う",
            order: 3,
            dependsOnOrders: [2],  // 実装に依存
            defaultAssigneeRole: .developer,
            defaultPriority: .medium,
            estimatedMinutes: 180
        )
        try templateTaskRepository.save(task3)

        // アーカイブ済みテンプレート（表示確認用）
        let archivedTemplateId = WorkflowTemplateID(value: "uitest_archived_template")
        let archivedTemplate = WorkflowTemplate(
            id: archivedTemplateId,
            projectId: project.id,
            name: "Archived Template",
            description: "アーカイブ済みのテンプレート",
            variables: [],
            status: .archived,
            createdAt: Date(),
            updatedAt: Date()
        )
        try templateRepository.save(archivedTemplate)

        NSLog("✅ UITest: Workflow Template test data seeded successfully")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// UIテストデータのシードが完了したときに投稿される通知
    static let testDataSeeded = Notification.Name("testDataSeeded")
}

// MARK: - Debug Extensions

private extension String {
    func appendToFile(_ path: String) throws {
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            if let data = (self + "\n").data(using: .utf8) {
                handle.write(data)
            }
        } else {
            try self.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
