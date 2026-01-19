// Sources/App/AIAgentPMApp.swift
// SwiftUI Mac App エントリーポイント

import SwiftUI
import AppKit
import Domain
import Infrastructure

// MARK: - Notification Names

extension Notification.Name {
    static let testDataSeeded = Notification.Name("testDataSeeded")
}

/// AppDelegate for proper window management in macOS
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        appDebugLog("applicationDidFinishLaunching called")
        #endif

        // Ensure app is active and windows are visible
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Force window to front for UI testing
        if CommandLine.arguments.contains("-UITesting") {
            #if DEBUG
            appDebugLog("UITesting mode detected")
            #endif
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
            }
        }

        // Auto-start MCP daemon
        // Passes database path to daemon via AIAGENTPM_DB_PATH environment variable
        // This ensures the daemon uses the same database as the app (especially during UITest)
        _Concurrency.Task { @MainActor in
            #if DEBUG
            appDebugLog("Starting MCP daemon task")
            #endif
            guard let container = DependencyContainer.shared else {
                #if DEBUG
                appDebugLog("DependencyContainer.shared is nil, cannot start daemon")
                #endif
                return
            }
            #if DEBUG
            appDebugLog("Container found, databasePath: \(container.databasePath)")
            #endif
            do {
                try await container.mcpDaemonManager.start(databasePath: container.databasePath)
                #if DEBUG
                appDebugLog("MCP daemon started successfully")
                #endif
            } catch {
                #if DEBUG
                appDebugLog("Failed to start MCP daemon: \(error)")
                #endif
            }

            // Auto-start Web Server
            do {
                try await container.webServerManager.start(databasePath: container.databasePath)
                #if DEBUG
                appDebugLog("Web server started successfully")
                #endif
            } catch {
                #if DEBUG
                appDebugLog("Failed to start Web server: \(error)")
                #endif
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stop servers on app quit (skip during UITest to let Coordinator use the daemon)
        if !CommandLine.arguments.contains("-UITesting") {
            _Concurrency.Task { @MainActor in
                await DependencyContainer.shared?.mcpDaemonManager.stop()
                await DependencyContainer.shared?.webServerManager.stop()
                NSLog("[AppDelegate] MCP daemon and Web server stopped")
            }
        } else {
            NSLog("[AppDelegate] UITesting mode - keeping servers running for Coordinator")
        }
    }
}

@main
struct AIAgentPMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var container: DependencyContainer
    @State private var router = Router()

    // MARK: - UIテスト用フラグ

    /// UIテストモードかどうか（AppEnvironmentへ委譲）
    static var isUITesting: Bool {
        AppEnvironment.isUITesting
    }

    #if DEBUG
    /// テストシナリオ（AppEnvironmentへ委譲）
    /// DEBUG ビルドでのみ利用可能
    static var testScenario: TestScenario {
        AppEnvironment.testScenario
    }
    #endif

    init() {
        // Initialize container - any error here is fatal
        let newContainer: DependencyContainer
        do {
            if Self.isUITesting {
                // UIテスト用: /tmp に専用DBを作成（テストスクリプトと同じパスを使用）
                // クリーンアップとパス取得はAppEnvironmentに集約
                AppEnvironment.cleanupTestDatabase()
                newContainer = try DependencyContainer(databasePath: AppEnvironment.uiTestDatabasePath)
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
                    #if DEBUG
                    // UIテスト時はテストデータをシードし、完了を通知
                    if Self.isUITesting && !isSeeded {
                        await seedTestData()
                        isSeeded = true
                        // シード完了後、ProjectListViewの再読み込みをトリガー
                        try? "Posting testDataSeeded notification at \(Date())".appendToFile("/tmp/uitest_workflow_debug.txt")
                        NotificationCenter.default.post(name: .testDataSeeded, object: nil)
                        try? "Notification posted at \(Date())".appendToFile("/tmp/uitest_workflow_debug.txt")
                    }
                    #endif
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

            #if DEBUG
            // UIテスト用コマンド（DEBUG ビルドかつ -UITestingフラグ時のみ有効）
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
            #endif
        }

        Settings {
            SettingsView()
                .environmentObject(container)
        }
    }

    // MARK: - UIテスト用データシード

    #if DEBUG
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
            projectAgentAssignmentRepository: container.projectAgentAssignmentRepository,
            appSettingsRepository: container.appSettingsRepository
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
            case .uc008:
                try await seeder.seedUC008Data()
            case .uc009:
                try await seeder.seedUC009Data()
            case .uc010:
                try await seeder.seedUC010Data()
            case .uc011:
                try await seeder.seedUC011Data()
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
    #endif
}
