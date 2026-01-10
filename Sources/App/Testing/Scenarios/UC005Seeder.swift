// Sources/App/Testing/Scenarios/UC005Seeder.swift
// UC005: マネージャー→ワーカー委任テスト用シーダー

#if DEBUG

import Foundation
import Domain
import Infrastructure

extension TestDataSeeder {

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
}
#endif
