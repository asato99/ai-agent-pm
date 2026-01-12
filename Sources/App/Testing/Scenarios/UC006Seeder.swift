// Sources/App/Testing/Scenarios/UC006Seeder.swift
// UC006: 複数ワーカーへのタスク割り当てテスト用シーダー

#if DEBUG

import Foundation
import Domain
import Infrastructure

extension TestDataSeeder {

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
}
#endif
