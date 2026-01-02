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
            parentTaskId: nil,
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
            parentTaskId: nil,
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
                parentTaskId: nil,
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
            parentTaskId: nil,
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
}

// MARK: - Notification Names

extension Notification.Name {
    /// UIテストデータのシードが完了したときに投稿される通知
    static let testDataSeeded = Notification.Name("testDataSeeded")
}
