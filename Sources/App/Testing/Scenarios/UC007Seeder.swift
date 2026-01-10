// Sources/App/Testing/Scenarios/UC007Seeder.swift
// UC007: 依存関係のあるタスク実行テスト用シーダー

#if DEBUG

import Foundation
import Domain
import Infrastructure

extension TestDataSeeder {

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
            systemPrompt: "タスクを分解しワーカーに委譲するマネージャーエージェントです",
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
            systemPrompt: "乱数生成を担当するワーカーエージェントです",
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
            systemPrompt: "計算処理を担当するワーカーエージェントです",
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
                生成タスク: random.randint(1,1000)の結果を/tmp/uc007/seed.txtに出力
                計算タスク: /tmp/uc007/seed.txtを読み2倍した値を/tmp/uc007/result.txtに出力
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
}
#endif
