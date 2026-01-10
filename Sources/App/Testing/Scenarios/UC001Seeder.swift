// Sources/App/Testing/Scenarios/UC001Seeder.swift
// UC001: エージェントキック機能テスト用シーダー

#if DEBUG

import Foundation
import Domain
import Infrastructure

extension TestDataSeeder {

    /// UC001用のテストデータを生成（エージェントキック機能テスト用）
    /// - エージェントへのタスクキック機能
    /// - 依存関係による実行制御
    /// - 作業ディレクトリ未設定エラー
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
}
#endif
