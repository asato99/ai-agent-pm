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
                        NotificationCenter.default.post(name: .testDataSeeded, object: nil)
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
                    .keyboardShortcut("t", modifiers: [.command])
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
        let seeder = TestDataSeeder(
            projectRepository: container.projectRepository,
            agentRepository: container.agentRepository,
            taskRepository: container.taskRepository
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
            }
            print("✅ UITest: Test data seeded successfully")
        } catch {
            print("⚠️ UITest: Failed to seed test data: \(error)")
        }
    }
}

// MARK: - Test Data Seeder

/// UIテスト用のテストデータを生成するシーダー
private final class TestDataSeeder {

    private let projectRepository: ProjectRepository
    private let agentRepository: AgentRepository
    private let taskRepository: TaskRepository

    init(
        projectRepository: ProjectRepository,
        agentRepository: AgentRepository,
        taskRepository: TaskRepository
    ) {
        self.projectRepository = projectRepository
        self.agentRepository = agentRepository
        self.taskRepository = taskRepository
    }

    /// 基本的なテストデータを生成（プロジェクト、エージェント、タスク）
    func seedBasicData() async throws {
        // プロジェクト作成
        let project = Project(
            id: .generate(),
            name: "テストプロジェクト",
            description: "UIテスト用のサンプルプロジェクト",
            status: .active,
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
}

// MARK: - Notification Names

extension Notification.Name {
    /// UIテストデータのシードが完了したときに投稿される通知
    static let testDataSeeded = Notification.Name("testDataSeeded")
}
