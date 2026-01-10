// Sources/App/AIAgentPMApp.swift
// SwiftUI Mac App エントリーポイント

import SwiftUI
import AppKit
import Domain
import Infrastructure

// MARK: - Debug Logging for XCUITest
private func appDebugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logMessage = "[\(timestamp)] [AppDelegate] \(message)\n"
    NSLog("[AppDelegate] %@", message)

    let logFile = "/tmp/aiagentpm_debug.log"
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
}

/// AppDelegate for proper window management in macOS
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        appDebugLog("applicationDidFinishLaunching called")

        // Ensure app is active and windows are visible
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Force window to front for UI testing
        if CommandLine.arguments.contains("-UITesting") {
            appDebugLog("UITesting mode detected")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
            }
        }

        // Auto-start MCP daemon
        // Passes database path to daemon via AIAGENTPM_DB_PATH environment variable
        // This ensures the daemon uses the same database as the app (especially during UITest)
        _Concurrency.Task { @MainActor in
            appDebugLog("Starting MCP daemon task")
            guard let container = DependencyContainer.shared else {
                appDebugLog("DependencyContainer.shared is nil, cannot start daemon")
                return
            }
            appDebugLog("Container found, databasePath: \(container.databasePath)")
            do {
                try await container.mcpDaemonManager.start(databasePath: container.databasePath)
                appDebugLog("MCP daemon started successfully")
            } catch {
                appDebugLog("Failed to start MCP daemon: \(error)")
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stop MCP daemon on app quit (skip during UITest to let Coordinator use the daemon)
        if !CommandLine.arguments.contains("-UITesting") {
            _Concurrency.Task { @MainActor in
                await DependencyContainer.shared?.mcpDaemonManager.stop()
                NSLog("[AppDelegate] MCP daemon stopped")
            }
        } else {
            NSLog("[AppDelegate] UITesting mode - keeping daemon running for Coordinator")
        }
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
        case uc002 = "UC002"           // UC002: マルチエージェント協調（system_prompt差異検証）
        case uc003 = "UC003"           // UC003: AIタイプ切り替え（kickCommand検証）
        case uc004 = "UC004"           // UC004: 複数プロジェクト×同一エージェント
        case uc005 = "UC005"           // UC005: マネージャー→ワーカー委任
        case uc006 = "UC006"           // UC006: 複数ワーカーへのタスク割り当て
        case uc007 = "UC007"           // UC007: 依存関係のあるタスク実行（実装→テスト）
        case noWD = "NoWD"             // NoWD: workingDirectory未設定エラーテスト用
        case internalAudit = "InternalAudit" // Internal Audit機能テスト用
        case workflowTemplate = "WorkflowTemplate" // ワークフローテンプレート機能テスト用
    }

    init() {
        // Initialize container - any error here is fatal
        let newContainer: DependencyContainer
        do {
            if Self.isUITesting {
                // UIテスト用: /tmp に専用DBを作成（テストスクリプトと同じパスを使用）
                // Note: NSTemporaryDirectory() returns /var/folders/... on macOS, not /tmp
                // Test scripts expect /tmp/AIAgentPM_UITest.db for the database path
                let testDBPath = "/tmp/AIAgentPM_UITest.db"
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
            auditRuleRepository: container.auditRuleRepository,
            credentialRepository: container.agentCredentialRepository,
            projectAgentAssignmentRepository: container.projectAgentAssignmentRepository
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
            case .uc002:
                try await seeder.seedUC002Data()
            case .uc003:
                try await seeder.seedUC003Data()
            case .uc004:
                try await seeder.seedUC004Data()
            case .uc005:
                try await seeder.seedUC005Data()
            case .uc006:
                try await seeder.seedUC006Data()
            case .uc007:
                try await seeder.seedUC007Data()
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
    private let credentialRepository: AgentCredentialRepository?
    private let projectAgentAssignmentRepository: ProjectAgentAssignmentRepository?

    init(
        projectRepository: ProjectRepository,
        agentRepository: AgentRepository,
        taskRepository: TaskRepository,
        templateRepository: WorkflowTemplateRepository? = nil,
        templateTaskRepository: TemplateTaskRepository? = nil,
        internalAuditRepository: InternalAuditRepository? = nil,
        auditRuleRepository: AuditRuleRepository? = nil,
        credentialRepository: AgentCredentialRepository? = nil,
        projectAgentAssignmentRepository: ProjectAgentAssignmentRepository? = nil
    ) {
        self.projectRepository = projectRepository
        self.agentRepository = agentRepository
        self.taskRepository = taskRepository
        self.templateRepository = templateRepository
        self.templateTaskRepository = templateTaskRepository
        self.internalAuditRepository = internalAuditRepository
        self.auditRuleRepository = auditRuleRepository
        self.credentialRepository = credentialRepository
        self.projectAgentAssignmentRepository = projectAgentAssignmentRepository
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

        // Phase 3 Pull Architecture用: Runner統合テスト用エージェント
        // Runnerはこのエージェントとしてタスクをポーリング・実行する
        let runnerAgentId = AgentID(value: "agt_uitest_runner")
        let runnerAgent = Agent(
            id: runnerAgentId,
            name: "runner-test-agent",
            role: "Runner統合テスト用エージェント",
            type: .ai,
            roleType: .developer,
            parentAgentId: nil,
            maxParallelTasks: 1,
            capabilities: ["TypeScript", "Python", "Swift"],
            systemPrompt: "Runner経由でClaude Codeを実行するテスト用エージェント",
            kickMethod: .cli,
            kickCommand: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(runnerAgent)

        // Runner認証用クレデンシャル（Passkey: test_passkey_12345）
        if let credentialRepository = credentialRepository {
            let credential = AgentCredential(
                agentId: runnerAgentId,
                rawPasskey: "test_passkey_12345"
            )
            try credentialRepository.save(credential)
            print("✅ UC001: Runner credential created for agent \(runnerAgentId.value)")
        }

        // Phase 4 Coordinator: エージェントをプロジェクトに割り当て
        // list_active_projects_with_agents で検出されるために必要
        if let projectAgentAssignmentRepository = projectAgentAssignmentRepository {
            _ = try projectAgentAssignmentRepository.assign(projectId: uc001Project.id, agentId: runnerAgentId)
            print("✅ UC001: Agent assigned to project")
        }

        // Runner統合テスト用タスク（runnerAgentにアサイン、backlog状態）
        // UIテストでin_progressに変更後、Runnerが検出して実行する
        let runnerTestTask = Task(
            id: TaskID(value: "uitest_runner_task"),
            projectId: uc001Project.id,
            title: "Runner統合テストタスク",
            description: """
                プロジェクトのドキュメント基盤を構築する。

                【目標】
                作業ディレクトリにMarkdownドキュメントを作成し、プロジェクトの基本情報を記録する。

                【成果物要件】
                - 出力ディレクトリ: 作業ディレクトリ直下
                - ファイル名: \(outputFile)
                - 必須コンテンツ: 'integration test content' という文字列を含めること
                """,
            status: .backlog,
            priority: .high,
            assigneeId: runnerAgentId,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(runnerTestTask)
        print("✅ UC001: Runner test task created - id=\(runnerTestTask.id.value)")

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

    /// UC002用のテストデータを生成（マルチエージェント協調テスト用）
    /// - 2つのエージェント（詳細ライター、簡潔ライター）
    /// - 両方ともclaude、異なるsystem_promptで出力差異を検証
    /// - 出力ファイル: PROJECT_SUMMARY.md
    ///
    /// 環境変数または引数:
    /// UC002: マルチエージェント協調テスト用シードデータ
    ///
    /// 設計A: 1プロジェクト + 2タスク（同一内容、異なるエージェント）
    /// - 同じタスク指示で異なるsystem_promptによる出力差異を検証
    /// - 各Runnerは異なる作業ディレクトリで実行（Runner config側で指定）
    func seedUC002Data() async throws {
        // デバッグ出力
        print("=== UC002 Test Data Configuration ===")
        print("Design: Single project + 2 identical tasks with different agents")

        // Debug: Log to file for investigation
        let debugPath = "/tmp/uc002_seed_debug.txt"
        try? "UC002 seeding started at \(Date())\n".write(toFile: debugPath, atomically: true, encoding: .utf8)

        // UC002用プロジェクト（1つのみ）
        let projectId = ProjectID(value: "prj_uc002_test")
        let project = Project(
            id: projectId,
            name: "UC002マルチエージェントテストPJ",
            description: "マルチエージェント協調テスト - 同一タスク指示で異なるsystem_promptによる出力差異を検証",
            status: .active,
            workingDirectory: "/tmp/uc002_test",
            createdAt: Date(),
            updatedAt: Date()
        )
        try await projectRepository.save(project)
        try? "Project saved: \(project.id.value)\n".appendToFile("/tmp/uc002_seed_debug.txt")
        print("✅ UC002: Project created - \(project.name)")

        // 詳細ライターエージェント（Claude / 詳細system_prompt）
        let detailedAgentId = AgentID(value: "agt_detailed_writer")
        let detailedAgent = Agent(
            id: detailedAgentId,
            name: "詳細ライター",
            role: "詳細なドキュメント作成",
            type: .ai,
            roleType: .developer,
            parentAgentId: nil,
            maxParallelTasks: 1,
            capabilities: ["Documentation", "Writing"],
            systemPrompt: "詳細で包括的なドキュメントを作成してください。背景、目的、使用例を必ず含めてください。",
            kickMethod: .cli,
            kickCommand: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(detailedAgent)

        // 簡潔ライターエージェント（Claude / 簡潔system_prompt）
        let conciseAgentId = AgentID(value: "agt_concise_writer")
        let conciseAgent = Agent(
            id: conciseAgentId,
            name: "簡潔ライター",
            role: "簡潔なドキュメント作成",
            type: .ai,
            roleType: .developer,
            parentAgentId: nil,
            maxParallelTasks: 1,
            capabilities: ["Documentation", "Writing"],
            systemPrompt: "簡潔に要点のみ記載してください。箇条書きで3項目以内にまとめてください。",
            kickMethod: .cli,
            kickCommand: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(conciseAgent)
        try? "Agents saved: \(detailedAgentId.value), \(conciseAgentId.value)\n".appendToFile("/tmp/uc002_seed_debug.txt")
        print("✅ UC002: Agents created - 詳細ライター, 簡潔ライター")

        // Runner認証用クレデンシャル
        if let credentialRepository = credentialRepository {
            let detailedCredential = AgentCredential(
                agentId: detailedAgentId,
                rawPasskey: "test_passkey_detailed"
            )
            try credentialRepository.save(detailedCredential)

            let conciseCredential = AgentCredential(
                agentId: conciseAgentId,
                rawPasskey: "test_passkey_concise"
            )
            try credentialRepository.save(conciseCredential)
            print("✅ UC002: Runner credentials created")
        }

        // エージェントをプロジェクトに割り当て（Coordinator用）
        if let projectAgentAssignmentRepository = projectAgentAssignmentRepository {
            _ = try projectAgentAssignmentRepository.assign(projectId: projectId, agentId: detailedAgentId)
            _ = try projectAgentAssignmentRepository.assign(projectId: projectId, agentId: conciseAgentId)
            print("✅ UC002: Agents assigned to project")
        }

        // タスク1: 詳細ライター用（backlog状態 → UIテストでin_progressに変更）
        // Note: タスク指示は「内容」のみ同一。ファイル名は各タスクで異なる。
        // system_promptの違いで出力スタイルが変わることを検証。
        let detailedTaskDescription = """
            OUTPUT_A.md にプロジェクトサマリードキュメントを作成してください。

            【対象トピック】
            - プロジェクトの目的
            - 主要な機能
            - 今後の展望
            """
        let detailedTask = Task(
            id: TaskID(value: "tsk_uc002_detailed"),
            projectId: projectId,
            title: "プロジェクトサマリー作成",
            description: detailedTaskDescription,
            status: .backlog,
            priority: .high,
            assigneeId: detailedAgentId,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(detailedTask)
        print("✅ UC002: Task 1 created - assigned to 詳細ライター (OUTPUT_A.md)")

        // タスク2: 簡潔ライター用（backlog状態 → UIテストでin_progressに変更）
        // Note: タスク指示は「内容」のみ同一。ファイル名は各タスクで異なる。
        let conciseTaskDescription = """
            OUTPUT_B.md にプロジェクトサマリードキュメントを作成してください。

            【対象トピック】
            - プロジェクトの目的
            - 主要な機能
            - 今後の展望
            """
        let conciseTask = Task(
            id: TaskID(value: "tsk_uc002_concise"),
            projectId: projectId,
            title: "プロジェクトサマリー作成",
            description: conciseTaskDescription,
            status: .backlog,
            priority: .high,
            assigneeId: conciseAgentId,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(conciseTask)
        print("✅ UC002: Task 2 created - assigned to 簡潔ライター (OUTPUT_B.md)")

        print("✅ UC002: All test data seeded successfully (1 project, 2 identical tasks)")

        // Debug: Verify data in database after seeding
        let allProjects = try await projectRepository.findAll()
        let allAgents = try await agentRepository.findAll()
        try? "After seeding - Projects: \(allProjects.map { $0.id.value }), Agents: \(allAgents.map { $0.id.value })\n".appendToFile("/tmp/uc002_seed_debug.txt")
    }

    /// UC003用のテストデータを生成（AIタイプ切り替え検証）
    /// - 1つのプロジェクト
    /// - 2つのエージェント（Claude標準、カスタムkickCommand）
    /// - 各エージェントに1タスク
    ///
    /// 検証内容:
    /// - aiTypeがshould_start APIで正しく返されること
    /// - kickCommandがaiTypeより優先されること
    func seedUC003Data() async throws {
        print("=== UC003 Test Data Configuration ===")
        print("Design: 1 project + 2 agents (different aiType/kickCommand)")

        guard let projectAgentAssignmentRepository = projectAgentAssignmentRepository else {
            print("⚠️ UC003: projectAgentAssignmentRepository not available")
            return
        }

        // 作業ディレクトリを作成
        let fileManager = FileManager.default
        let workingDir = "/tmp/uc003"
        if !fileManager.fileExists(atPath: workingDir) {
            try fileManager.createDirectory(atPath: workingDir, withIntermediateDirectories: true)
        }

        // UC003用プロジェクト
        let projectId = ProjectID(value: "prj_uc003")
        let project = Project(
            id: projectId,
            name: "UC003 AIType Test",
            description: "AIタイプ切り替え検証用プロジェクト",
            status: .active,
            workingDirectory: workingDir,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await projectRepository.save(project)
        print("✅ UC003: Project created - \(project.name)")

        // UC003用エージェント1: Claude Sonnet 4.5（kickCommand=nil）
        let sonnetAgentId = AgentID(value: "agt_uc003_sonnet")
        let sonnetAgent = Agent(
            id: sonnetAgentId,
            name: "UC003 Sonnet Agent",
            role: "Claude Sonnet 4.5エージェント",
            type: .ai,
            aiType: .claudeSonnet4_5,
            roleType: .developer,
            parentAgentId: nil,
            maxParallelTasks: 1,
            capabilities: ["TypeScript", "Python"],
            systemPrompt: "あなたは開発タスクを実行するAIエージェントです。指示されたファイルを作成してください。",
            kickMethod: .cli,
            kickCommand: nil,  // kickCommand未設定 → aiTypeが使われる
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(sonnetAgent)
        print("✅ UC003: Sonnet agent created - \(sonnetAgent.name) (aiType=claudeSonnet4_5, kickCommand=nil)")

        // UC003用エージェント2: Claude Opus 4（カスタムkickCommand）
        let opusAgentId = AgentID(value: "agt_uc003_opus")
        let opusAgent = Agent(
            id: opusAgentId,
            name: "UC003 Opus Agent",
            role: "Claude Opus 4エージェント",
            type: .ai,
            aiType: .claudeOpus4,
            roleType: .developer,
            parentAgentId: nil,
            maxParallelTasks: 1,
            capabilities: ["TypeScript", "Python"],
            systemPrompt: "あなたは開発タスクを実行するAIエージェントです。指示されたファイルを作成してください。",
            kickMethod: .cli,
            kickCommand: "claude --model opus --dangerously-skip-permissions --max-turns 80",  // kickCommandが優先される
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(opusAgent)
        print("✅ UC003: Opus agent created - \(opusAgent.name) (aiType=claudeOpus4, kickCommand includes --max-turns 50)")

        // Runner認証用クレデンシャル
        if let credentialRepository = credentialRepository {
            let sonnetCredential = AgentCredential(
                agentId: sonnetAgentId,
                rawPasskey: "test_passkey_uc003_sonnet"
            )
            try credentialRepository.save(sonnetCredential)
            print("✅ UC003: Credential created for \(sonnetAgentId.value)")

            let opusCredential = AgentCredential(
                agentId: opusAgentId,
                rawPasskey: "test_passkey_uc003_opus"
            )
            try credentialRepository.save(opusCredential)
            print("✅ UC003: Credential created for \(opusAgentId.value)")
        }

        // エージェントをプロジェクトに割り当て
        _ = try projectAgentAssignmentRepository.assign(projectId: projectId, agentId: sonnetAgentId)
        print("✅ UC003: Sonnet agent assigned to project")
        _ = try projectAgentAssignmentRepository.assign(projectId: projectId, agentId: opusAgentId)
        print("✅ UC003: Opus agent assigned to project")

        // Sonnetエージェント用タスク
        let sonnetTask = Task(
            id: TaskID(value: "tsk_uc003_sonnet"),
            projectId: projectId,
            title: "Sonnet Task",
            description: """
                【タスク指示】
                OUTPUT_1.md というファイルを作成してください。
                内容は「タスク完了」という文字列を含めてください。
                """,
            status: .backlog,
            priority: .high,
            assigneeId: sonnetAgentId,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(sonnetTask)
        print("✅ UC003: Sonnet task created")

        // Opusエージェント用タスク
        let opusTask = Task(
            id: TaskID(value: "tsk_uc003_opus"),
            projectId: projectId,
            title: "Opus Task",
            description: """
                【タスク指示】
                OUTPUT_2.md というファイルを作成してください。
                内容は「タスク完了」という文字列を含めてください。
                """,
            status: .backlog,
            priority: .high,
            assigneeId: opusAgentId,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(opusTask)
        print("✅ UC003: Opus task created")

        print("✅ UC003: All test data seeded successfully (1 project, 2 agents, 2 tasks)")
    }

    /// UC004用のテストデータを生成（複数プロジェクト×同一エージェント）
    /// - 2つのプロジェクト（フロントエンド、バックエンド）
    /// - 1つのエージェント（両プロジェクトに割り当て）
    /// - 各プロジェクトに1タスク
    ///
    /// 検証内容:
    /// - 同一エージェントが複数プロジェクトに割り当て可能
    /// - 各プロジェクトで異なるworking_directoryで実行
    /// - list_active_projects_with_agents APIが正しいマッピングを返す
    func seedUC004Data() async throws {
        print("=== UC004 Test Data Configuration ===")
        print("Design: 2 projects + 1 agent assigned to both")

        guard let projectAgentAssignmentRepository = projectAgentAssignmentRepository else {
            print("⚠️ UC004: projectAgentAssignmentRepository not available")
            return
        }

        // 作業ディレクトリを作成
        let fileManager = FileManager.default
        let frontendDir = "/tmp/uc004/frontend"
        let backendDir = "/tmp/uc004/backend"
        if !fileManager.fileExists(atPath: frontendDir) {
            try fileManager.createDirectory(atPath: frontendDir, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: backendDir) {
            try fileManager.createDirectory(atPath: backendDir, withIntermediateDirectories: true)
        }

        // UC004用プロジェクト1: フロントエンド
        let frontendProjectId = ProjectID(value: "prj_uc004_fe")
        let frontendProject = Project(
            id: frontendProjectId,
            name: "UC004 Frontend",
            description: "フロントエンドアプリ（UC004テスト用）",
            status: .active,
            workingDirectory: frontendDir,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await projectRepository.save(frontendProject)
        print("✅ UC004: Frontend project created - \(frontendProject.name)")

        // UC004用プロジェクト2: バックエンド
        let backendProjectId = ProjectID(value: "prj_uc004_be")
        let backendProject = Project(
            id: backendProjectId,
            name: "UC004 Backend",
            description: "バックエンドAPI（UC004テスト用）",
            status: .active,
            workingDirectory: backendDir,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await projectRepository.save(backendProject)
        print("✅ UC004: Backend project created - \(backendProject.name)")

        // UC004用エージェント: 両プロジェクトに割り当てられる開発者
        let devAgentId = AgentID(value: "agt_uc004_dev")
        let devAgent = Agent(
            id: devAgentId,
            name: "UC004開発者",
            role: "フルスタック開発者",
            type: .ai,
            roleType: .developer,
            parentAgentId: nil,
            maxParallelTasks: 2,  // 並列2タスクまで可能
            capabilities: ["TypeScript", "Python", "Swift"],
            systemPrompt: "フロントエンドとバックエンド両方の開発を担当するエージェントです",
            kickMethod: .cli,
            kickCommand: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(devAgent)
        print("✅ UC004: Developer agent created - \(devAgent.name)")

        // Runner認証用クレデンシャル
        if let credentialRepository = credentialRepository {
            let credential = AgentCredential(
                agentId: devAgentId,
                rawPasskey: "test_passkey_uc004"
            )
            try credentialRepository.save(credential)
            print("✅ UC004: Credential created for \(devAgentId.value)")
        }

        // エージェントを両プロジェクトに割り当て
        _ = try projectAgentAssignmentRepository.assign(projectId: frontendProjectId, agentId: devAgentId)
        print("✅ UC004: Agent assigned to Frontend project")
        _ = try projectAgentAssignmentRepository.assign(projectId: backendProjectId, agentId: devAgentId)
        print("✅ UC004: Agent assigned to Backend project")

        // フロントエンドプロジェクトのタスク
        let frontendTask = Task(
            id: TaskID(value: "tsk_uc004_fe"),
            projectId: frontendProjectId,
            title: "README作成（Frontend）",
            description: """
                【タスク指示】
                ファイル名: README.md
                内容: フロントエンドプロジェクトのREADMEを作成してください。
                プロジェクト名とworking_directoryのパスを含めてください。
                """,
            status: .backlog,
            priority: .high,
            assigneeId: devAgentId,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(frontendTask)
        print("✅ UC004: Frontend task created")

        // バックエンドプロジェクトのタスク
        let backendTask = Task(
            id: TaskID(value: "tsk_uc004_be"),
            projectId: backendProjectId,
            title: "README作成（Backend）",
            description: """
                【タスク指示】
                ファイル名: README.md
                内容: バックエンドプロジェクトのREADMEを作成してください。
                プロジェクト名とworking_directoryのパスを含めてください。
                """,
            status: .backlog,
            priority: .high,
            assigneeId: devAgentId,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(backendTask)
        print("✅ UC004: Backend task created")

        print("✅ UC004: All test data seeded successfully (2 projects, 1 agent, 2 tasks)")
    }

    /// UC005: マネージャー→ワーカー委任テスト用シードデータ
    ///
    /// 構成:
    /// - 1プロジェクト
    /// - 2エージェント（マネージャー、ワーカー）
    /// - 1タスク（親タスク、マネージャーに割り当て）
    ///
    /// 検証内容:
    /// - マネージャーがサブタスクを作成してワーカーに委任
    /// - ワーカーがサブサブタスクを作成して実行
    /// - 全タスクがdoneになる
    func seedUC005Data() async throws {
        print("=== UC005 Test Data Configuration ===")
        print("Design: Manager → Worker delegation with subtask hierarchy")

        guard let projectAgentAssignmentRepository = projectAgentAssignmentRepository else {
            print("⚠️ UC005: projectAgentAssignmentRepository not available")
            return
        }

        // 作業ディレクトリを作成
        let fileManager = FileManager.default
        let workingDir = "/tmp/uc005"
        if !fileManager.fileExists(atPath: workingDir) {
            try fileManager.createDirectory(atPath: workingDir, withIntermediateDirectories: true)
        }

        // UC005用プロジェクト
        let projectId = ProjectID(value: "prj_uc005")
        let project = Project(
            id: projectId,
            name: "UC005 Manager Test",
            description: "マネージャー→ワーカー委任テスト用プロジェクト",
            status: .active,
            workingDirectory: workingDir,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await projectRepository.save(project)
        print("✅ UC005: Project created - \(project.name)")

        // マネージャーエージェント
        let managerAgentId = AgentID(value: "agt_uc005_manager")
        let managerAgent = Agent(
            id: managerAgentId,
            name: "UC005マネージャー",
            role: "タスク分解と委任",
            type: .ai,
            aiType: .claudeSonnet4_5,  // AIプロバイダー種別
            hierarchyType: .manager,  // MCP制御用: マネージャーとして動作
            roleType: .manager,
            parentAgentId: nil,
            maxParallelTasks: 1,
            capabilities: ["TaskDecomposition", "Delegation"],
            systemPrompt: """
                あなたはマネージャーエージェントです。
                get_next_actionで指示されたアクションに従ってください。

                delegateアクションの場合:
                1. assign_taskツールでサブタスクをワーカーに割り当て
                2. update_task_statusでサブタスクをin_progressに変更
                3. get_next_actionを再度呼び出す

                waitアクションの場合:
                少し待ってからget_next_actionを呼び出してください。

                report_completionアクションの場合:
                report_completedでタスクを完了してください。
                """,
            kickMethod: .cli,
            kickCommand: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(managerAgent)
        print("✅ UC005: Manager agent created - \(managerAgent.name)")

        // ワーカーエージェント
        let workerAgentId = AgentID(value: "agt_uc005_worker")
        let workerAgent = Agent(
            id: workerAgentId,
            name: "UC005ワーカー",
            role: "実作業の実行",
            type: .ai,
            aiType: .claudeSonnet4_5,  // AIプロバイダー種別
            hierarchyType: .worker,  // MCP制御用: ワーカーとして動作
            roleType: .developer,
            parentAgentId: managerAgentId,  // マネージャーの下位エージェント
            maxParallelTasks: 1,
            capabilities: ["FileCreation", "Documentation"],
            systemPrompt: """
                あなたはワーカーエージェントです。
                get_next_actionで指示されたアクションに従ってください。

                create_subtasksアクションの場合:
                1. create_taskでサブサブタスクを作成
                2. get_next_actionを呼び出す

                execute_subtaskアクションの場合:
                1. 指定されたサブタスクを実行（ファイル作成など）
                2. update_task_statusでサブサブタスクをdoneに変更
                3. get_next_actionを呼び出す

                report_completionアクションの場合:
                report_completedでタスクを完了してください。
                """,
            kickMethod: .cli,
            kickCommand: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(workerAgent)
        print("✅ UC005: Worker agent created - \(workerAgent.name)")

        // Runner認証用クレデンシャル
        if let credentialRepository = credentialRepository {
            let managerCredential = AgentCredential(
                agentId: managerAgentId,
                rawPasskey: "test_passkey_uc005_manager"
            )
            try credentialRepository.save(managerCredential)

            let workerCredential = AgentCredential(
                agentId: workerAgentId,
                rawPasskey: "test_passkey_uc005_worker"
            )
            try credentialRepository.save(workerCredential)
            print("✅ UC005: Credentials created")
        }

        // エージェントをプロジェクトに割り当て
        _ = try projectAgentAssignmentRepository.assign(projectId: projectId, agentId: managerAgentId)
        _ = try projectAgentAssignmentRepository.assign(projectId: projectId, agentId: workerAgentId)
        print("✅ UC005: Agents assigned to project")

        // 親タスク（マネージャーに割り当て）
        let parentTask = Task(
            id: TaskID(value: "tsk_uc005_main"),
            projectId: projectId,
            title: "READMEを作成",
            description: """
                【タスク指示】
                working_directory内にREADME.mdを作成してください。

                このタスクはサブタスクに分解してワーカーに委任してください。
                """,
            status: .backlog,
            priority: .high,
            assigneeId: managerAgentId,
            parentTaskId: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(parentTask)
        print("✅ UC005: Parent task created - \(parentTask.title)")

        print("✅ UC005: All test data seeded successfully (1 project, 2 agents, 1 task)")
    }

    /// UC006: 複数ワーカーへのタスク割り当てテスト用シードデータ
    ///
    /// 構成:
    /// - 1プロジェクト
    /// - 3エージェント（マネージャー、日本語ワーカー、中国語ワーカー）
    /// - 1タスク（親タスク、マネージャーに割り当て）
    /// - 入力ファイル（hello.txt）
    ///
    /// 検証内容:
    /// - マネージャーが2つのサブタスクを作成
    /// - 日本語タスクは日本語担当ワーカーに割り当て
    /// - 中国語タスクは中国語担当ワーカーに割り当て
    /// - 各ワーカーが翻訳ファイルを生成
    func seedUC006Data() async throws {
        print("=== UC006 Test Data Configuration ===")
        print("Design: Manager → Multiple Workers assignment based on specialization")

        guard let projectAgentAssignmentRepository = projectAgentAssignmentRepository else {
            print("⚠️ UC006: projectAgentAssignmentRepository not available")
            return
        }

        // 作業ディレクトリを作成
        let fileManager = FileManager.default
        let workingDir = "/tmp/uc006"
        if !fileManager.fileExists(atPath: workingDir) {
            try fileManager.createDirectory(atPath: workingDir, withIntermediateDirectories: true)
        }

        // 入力ファイルを作成
        let inputFilePath = "\(workingDir)/hello.txt"
        try "Hello, World!".write(toFile: inputFilePath, atomically: true, encoding: .utf8)
        print("✅ UC006: Input file created - \(inputFilePath)")

        // UC006用プロジェクト
        let projectId = ProjectID(value: "prj_uc006")
        let project = Project(
            id: projectId,
            name: "UC006 Translation Test",
            description: "複数ワーカーへのタスク割り当てテスト用プロジェクト",
            status: .active,
            workingDirectory: workingDir,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await projectRepository.save(project)
        print("✅ UC006: Project created - \(project.name)")

        // マネージャーエージェント
        let managerAgentId = AgentID(value: "agt_uc006_manager")
        let managerAgent = Agent(
            id: managerAgentId,
            name: "UC006翻訳マネージャー",
            role: "翻訳タスクの分配",
            type: .ai,
            aiType: .claudeSonnet4_5,
            hierarchyType: .manager,
            roleType: .manager,
            parentAgentId: nil,
            maxParallelTasks: 1,
            capabilities: ["TaskDecomposition", "Delegation"],
            systemPrompt: """
                あなたはマネージャーエージェントです。
                get_next_actionで指示されたアクションに従ってください。

                delegateアクションの場合:
                1. assign_taskツールでサブタスクを適切なエージェントに割り当て
                2. update_task_statusでサブタスクをin_progressに変更
                3. get_next_actionを再度呼び出す

                waitアクションの場合:
                少し待ってからget_next_actionを呼び出してください。

                report_completionアクションの場合:
                report_completedでタスクを完了してください。
                """,
            kickMethod: .cli,
            kickCommand: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(managerAgent)
        print("✅ UC006: Manager agent created - \(managerAgent.name)")

        // 日本語翻訳ワーカーエージェント
        let jaWorkerAgentId = AgentID(value: "agt_uc006_ja")
        let jaWorkerAgent = Agent(
            id: jaWorkerAgentId,
            name: "UC006日本語翻訳担当",
            role: "日本語への翻訳",
            type: .ai,
            aiType: .claudeSonnet4_5,
            hierarchyType: .worker,
            roleType: .developer,
            parentAgentId: managerAgentId,
            maxParallelTasks: 1,
            capabilities: ["Translation", "Japanese"],
            systemPrompt: """
                あなたは日本語翻訳担当のワーカーです。
                get_next_actionで指示されたアクションに従ってください。

                executeアクションの場合:
                1. 指定されたファイルを日本語に翻訳してください
                2. 翻訳結果を hello_ja.txt として保存してください
                3. update_task_statusでタスクをdoneに変更
                4. get_next_actionを呼び出す

                report_completionアクションの場合:
                report_completedでタスクを完了してください。
                """,
            kickMethod: .cli,
            kickCommand: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(jaWorkerAgent)
        print("✅ UC006: Japanese worker agent created - \(jaWorkerAgent.name)")

        // 中国語翻訳ワーカーエージェント
        let zhWorkerAgentId = AgentID(value: "agt_uc006_zh")
        let zhWorkerAgent = Agent(
            id: zhWorkerAgentId,
            name: "UC006中国語翻訳担当",
            role: "中国語への翻訳",
            type: .ai,
            aiType: .claudeSonnet4_5,
            hierarchyType: .worker,
            roleType: .developer,
            parentAgentId: managerAgentId,
            maxParallelTasks: 1,
            capabilities: ["Translation", "Chinese"],
            systemPrompt: """
                あなたは中国語翻訳担当のワーカーです。
                get_next_actionで指示されたアクションに従ってください。

                executeアクションの場合:
                1. 指定されたファイルを中国語に翻訳してください
                2. 翻訳結果を hello_zh.txt として保存してください
                3. update_task_statusでタスクをdoneに変更
                4. get_next_actionを呼び出す

                report_completionアクションの場合:
                report_completedでタスクを完了してください。
                """,
            kickMethod: .cli,
            kickCommand: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(zhWorkerAgent)
        print("✅ UC006: Chinese worker agent created - \(zhWorkerAgent.name)")

        // Runner認証用クレデンシャル
        if let credentialRepository = credentialRepository {
            let managerCredential = AgentCredential(
                agentId: managerAgentId,
                rawPasskey: "test_passkey_uc006_manager"
            )
            try credentialRepository.save(managerCredential)

            let jaWorkerCredential = AgentCredential(
                agentId: jaWorkerAgentId,
                rawPasskey: "test_passkey_uc006_ja"
            )
            try credentialRepository.save(jaWorkerCredential)

            let zhWorkerCredential = AgentCredential(
                agentId: zhWorkerAgentId,
                rawPasskey: "test_passkey_uc006_zh"
            )
            try credentialRepository.save(zhWorkerCredential)
            print("✅ UC006: Credentials created")
        }

        // エージェントをプロジェクトに割り当て
        _ = try projectAgentAssignmentRepository.assign(projectId: projectId, agentId: managerAgentId)
        _ = try projectAgentAssignmentRepository.assign(projectId: projectId, agentId: jaWorkerAgentId)
        _ = try projectAgentAssignmentRepository.assign(projectId: projectId, agentId: zhWorkerAgentId)
        print("✅ UC006: Agents assigned to project")

        // 親タスク（マネージャーに割り当て）
        let parentTask = Task(
            id: TaskID(value: "tsk_uc006_main"),
            projectId: projectId,
            title: "ドキュメントを翻訳してください",
            description: """
                【タスク指示】
                hello.txt を日本語と中国語に翻訳してください。
                """,
            status: .backlog,
            priority: .high,
            assigneeId: managerAgentId,
            parentTaskId: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(parentTask)
        print("✅ UC006: Parent task created - \(parentTask.title)")

        print("✅ UC006: All test data seeded successfully (1 project, 3 agents, 1 task, 1 input file)")
    }

    /// UC007: 依存関係のあるタスク実行テスト用シードデータ
    ///
    /// 構成:
    /// - 1プロジェクト
    /// - 3エージェント（マネージャー、実装ワーカー、テストワーカー）
    /// - 1タスク（親タスク、マネージャーに割り当て）
    ///
    /// 検証内容:
    /// - マネージャーが2つのサブタスクを作成（実装タスク、テストタスク）
    /// - テストタスクは実装タスクに依存（依存関係あり）
    /// - 実装ワーカーが先に完了してからテストワーカーが実行される
    /// - 各ワーカーが成果物を生成
    func seedUC007Data() async throws {
        print("=== UC007 Test Data Configuration ===")
        print("Design: Manager → Workers with dependent tasks (generator → calculator)")

        guard let projectAgentAssignmentRepository = projectAgentAssignmentRepository else {
            print("⚠️ UC007: projectAgentAssignmentRepository not available")
            return
        }

        // 作業ディレクトリを作成
        let fileManager = FileManager.default
        let workingDir = "/tmp/uc007"
        if !fileManager.fileExists(atPath: workingDir) {
            try fileManager.createDirectory(atPath: workingDir, withIntermediateDirectories: true)
        }
        print("✅ UC007: Working directory created - \(workingDir)")

        // UC007用プロジェクト
        let projectId = ProjectID(value: "prj_uc007")
        let project = Project(
            id: projectId,
            name: "UC007 Dependent Task Test",
            description: "依存関係のあるタスク実行テスト用プロジェクト（生成→計算）",
            status: .active,
            workingDirectory: workingDir,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await projectRepository.save(project)
        print("✅ UC007: Project created - \(project.name)")

        // マネージャーエージェント
        let managerAgentId = AgentID(value: "agt_uc007_manager")
        let managerAgent = Agent(
            id: managerAgentId,
            name: "UC007マネージャー",
            role: "タスク分配",
            type: .ai,
            aiType: .claudeSonnet4_5,
            hierarchyType: .manager,
            roleType: .manager,
            parentAgentId: nil,
            maxParallelTasks: 1,
            capabilities: ["TaskDecomposition", "Delegation"],
            systemPrompt: """
                あなたはマネージャーエージェントです。
                get_next_actionで指示されたアクションに従ってください。

                create_subtasksアクションの場合:
                create_taskツールを使って2つのサブタスクを作成してください:

                1. 生成タスク:
                   - title: "乱数を生成"
                   - description: "Pythonで random.randint(1, 1000) を実行し、その数値だけを /tmp/uc007/seed.txt に書いてください（改行なし）"
                   - 作成後、assign_task で agt_uc007_generator に割り当て

                2. 計算タスク:
                   - title: "2倍を計算"
                   - description: "/tmp/uc007/seed.txt を読み込み、その値を2倍にして /tmp/uc007/result.txt に書いてください（改行なし）"
                   - dependencies: [生成タスクのID] ← 重要！
                   - 作成後、assign_task で agt_uc007_calculator に割り当て

                重要: 計算タスクには必ず dependencies パラメータで生成タスクのIDを指定してください。

                delegateアクションの場合:
                サブタスクを適切なエージェントに割り当ててください。

                waitアクションの場合:
                少し待ってからget_next_actionを呼び出してください。

                report_completionアクションの場合:
                report_completedでタスクを完了してください。
                """,
            kickMethod: .cli,
            kickCommand: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(managerAgent)
        print("✅ UC007: Manager agent created - \(managerAgent.name)")

        // 生成ワーカーエージェント
        let generatorAgentId = AgentID(value: "agt_uc007_generator")
        let generatorAgent = Agent(
            id: generatorAgentId,
            name: "UC007生成担当",
            role: "乱数生成",
            type: .ai,
            aiType: .claudeSonnet4_5,
            hierarchyType: .worker,
            roleType: .developer,
            parentAgentId: managerAgentId,
            maxParallelTasks: 1,
            capabilities: ["Python", "Generation"],
            systemPrompt: """
                あなたは生成担当のワーカーです。
                get_next_actionで指示されたアクションに従ってください。

                executeアクションの場合:
                1. Pythonで乱数を生成してください
                2. import random; print(random.randint(1, 1000)) を実行
                3. その数値だけを /tmp/uc007/seed.txt に書く（改行なし）
                4. update_task_statusでタスクをdoneに変更
                5. get_next_actionを呼び出す

                report_completionアクションの場合:
                report_completedでタスクを完了してください。
                """,
            kickMethod: .cli,
            kickCommand: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(generatorAgent)
        print("✅ UC007: Generator worker agent created - \(generatorAgent.name)")

        // 計算ワーカーエージェント
        let calculatorAgentId = AgentID(value: "agt_uc007_calculator")
        let calculatorAgent = Agent(
            id: calculatorAgentId,
            name: "UC007計算担当",
            role: "計算処理",
            type: .ai,
            aiType: .claudeSonnet4_5,
            hierarchyType: .worker,
            roleType: .developer,
            parentAgentId: managerAgentId,
            maxParallelTasks: 1,
            capabilities: ["Python", "Calculation"],
            systemPrompt: """
                あなたは計算担当のワーカーです。
                get_next_actionで指示されたアクションに従ってください。

                executeアクションの場合:
                1. /tmp/uc007/seed.txt を読み込む
                2. その値を整数として解釈
                3. 2倍にした値を /tmp/uc007/result.txt に書く（改行なし）
                4. update_task_statusでタスクをdoneに変更
                5. get_next_actionを呼び出す

                report_completionアクションの場合:
                report_completedでタスクを完了してください。
                """,
            kickMethod: .cli,
            kickCommand: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await agentRepository.save(calculatorAgent)
        print("✅ UC007: Calculator worker agent created - \(calculatorAgent.name)")

        // Runner認証用クレデンシャル
        if let credentialRepository = credentialRepository {
            let managerCredential = AgentCredential(
                agentId: managerAgentId,
                rawPasskey: "test_passkey_uc007_manager"
            )
            try credentialRepository.save(managerCredential)

            let generatorCredential = AgentCredential(
                agentId: generatorAgentId,
                rawPasskey: "test_passkey_uc007_generator"
            )
            try credentialRepository.save(generatorCredential)

            let calculatorCredential = AgentCredential(
                agentId: calculatorAgentId,
                rawPasskey: "test_passkey_uc007_calculator"
            )
            try credentialRepository.save(calculatorCredential)
            print("✅ UC007: Credentials created")
        }

        // エージェントをプロジェクトに割り当て
        _ = try projectAgentAssignmentRepository.assign(projectId: projectId, agentId: managerAgentId)
        _ = try projectAgentAssignmentRepository.assign(projectId: projectId, agentId: generatorAgentId)
        _ = try projectAgentAssignmentRepository.assign(projectId: projectId, agentId: calculatorAgentId)
        print("✅ UC007: Agents assigned to project")

        // 親タスク（マネージャーに割り当て）
        let parentTask = Task(
            id: TaskID(value: "tsk_uc007_main"),
            projectId: projectId,
            title: "乱数を生成し、その2倍を計算せよ",
            description: """
                以下の作業を2つのサブタスクに分けて実行してください:

                1. 生成タスク: random.randint(1, 1000) で乱数を生成し /tmp/uc007/seed.txt に書く
                2. 計算タスク: seed.txt を読み込み、2倍にして /tmp/uc007/result.txt に書く

                重要: 計算タスクは生成タスクに依存します。create_task時に dependencies パラメータで依存関係を設定してください。
                """,
            status: .backlog,
            priority: .high,
            assigneeId: managerAgentId,
            parentTaskId: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await taskRepository.save(parentTask)
        print("✅ UC007: Parent task created - \(parentTask.title)")

        print("✅ UC007: All test data seeded successfully (1 project, 3 agents, 1 task)")
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
