// Tests/InfrastructureTests/AgentSkillAssignmentRepositoryTests.swift
// エージェントスキル割り当てリポジトリ - Infrastructure層テスト
// 参照: docs/design/AGENT_SKILLS.md

import XCTest
import GRDB
@testable import Domain
@testable import Infrastructure

final class AgentSkillAssignmentRepositoryTests: XCTestCase {
    private var dbQueue: DatabaseQueue!
    private var skillRepository: SkillDefinitionRepository!
    private var assignmentRepository: AgentSkillAssignmentRepository!
    private var agentRepository: AgentRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_assignment_\(UUID().uuidString).db").path
        dbQueue = try DatabaseSetup.createDatabase(at: dbPath)
        skillRepository = SkillDefinitionRepository(database: dbQueue)
        assignmentRepository = AgentSkillAssignmentRepository(database: dbQueue)
        agentRepository = AgentRepository(database: dbQueue)
    }

    override func tearDownWithError() throws {
        assignmentRepository = nil
        skillRepository = nil
        agentRepository = nil
        dbQueue = nil
        try super.tearDownWithError()
    }

    // MARK: - Helper Methods

    private func createTestAgent(id: String = "agt_test001", name: String = "TestAgent") -> Agent {
        Agent(
            id: AgentID(value: id),
            name: name,
            role: "Test role",
            type: .ai,
            aiType: .claudeSonnet4,
            provider: "anthropic",
            modelId: "claude-3-5-sonnet",
            hierarchyType: .worker,
            roleType: .developer,
            parentAgentId: nil,
            maxParallelTasks: 1,
            capabilities: [],
            systemPrompt: "Test system prompt",
            kickMethod: .cli,
            authLevel: .level0,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func createTestSkill(
        id: String = "skl_test001",
        name: String = "コードレビュー",
        directoryName: String = "code-review"
    ) -> SkillDefinition {
        SkillDefinition(
            id: SkillID(value: id),
            name: name,
            description: "テスト用スキル",
            directoryName: directoryName,
            content: "---\nname: \(directoryName)\n---\n## 手順",
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // MARK: - AssignSkills Tests

    func testAssignSkillsToAgent() throws {
        // エージェントとスキルを作成
        let agent = createTestAgent()
        let skill1 = createTestSkill(id: "skl_001", name: "スキル1", directoryName: "skill-1")
        let skill2 = createTestSkill(id: "skl_002", name: "スキル2", directoryName: "skill-2")

        try agentRepository.save(agent)
        try skillRepository.save(skill1)
        try skillRepository.save(skill2)

        // スキルを割り当て
        try assignmentRepository.assignSkills(
            agentId: agent.id,
            skillIds: [skill1.id, skill2.id]
        )

        // 割り当てを確認
        let assigned = try assignmentRepository.findByAgentId(agent.id)
        XCTAssertEqual(assigned.count, 2)
        XCTAssertTrue(assigned.contains { $0.id == skill1.id })
        XCTAssertTrue(assigned.contains { $0.id == skill2.id })
    }

    func testAssignSkillsReplacesExisting() throws {
        let agent = createTestAgent()
        let skill1 = createTestSkill(id: "skl_001", name: "スキル1", directoryName: "skill-1")
        let skill2 = createTestSkill(id: "skl_002", name: "スキル2", directoryName: "skill-2")
        let skill3 = createTestSkill(id: "skl_003", name: "スキル3", directoryName: "skill-3")

        try agentRepository.save(agent)
        try skillRepository.save(skill1)
        try skillRepository.save(skill2)
        try skillRepository.save(skill3)

        // 最初の割り当て
        try assignmentRepository.assignSkills(agentId: agent.id, skillIds: [skill1.id, skill2.id])
        var assigned = try assignmentRepository.findByAgentId(agent.id)
        XCTAssertEqual(assigned.count, 2)

        // 新しい割り当てで置換
        try assignmentRepository.assignSkills(agentId: agent.id, skillIds: [skill3.id])
        assigned = try assignmentRepository.findByAgentId(agent.id)
        XCTAssertEqual(assigned.count, 1)
        XCTAssertEqual(assigned[0].id, skill3.id)
    }

    func testAssignEmptySkillsRemovesAll() throws {
        let agent = createTestAgent()
        let skill = createTestSkill()

        try agentRepository.save(agent)
        try skillRepository.save(skill)
        try assignmentRepository.assignSkills(agentId: agent.id, skillIds: [skill.id])

        // 空配列で割り当て = 全削除
        try assignmentRepository.assignSkills(agentId: agent.id, skillIds: [])
        let assigned = try assignmentRepository.findByAgentId(agent.id)
        XCTAssertTrue(assigned.isEmpty)
    }

    // MARK: - FindByAgentId Tests

    func testFindByAgentIdReturnsOrderedByName() throws {
        let agent = createTestAgent()
        let skill1 = createTestSkill(id: "skl_001", name: "Zスキル", directoryName: "z-skill")
        let skill2 = createTestSkill(id: "skl_002", name: "Aスキル", directoryName: "a-skill")

        try agentRepository.save(agent)
        try skillRepository.save(skill1)
        try skillRepository.save(skill2)
        try assignmentRepository.assignSkills(agentId: agent.id, skillIds: [skill1.id, skill2.id])

        let assigned = try assignmentRepository.findByAgentId(agent.id)
        XCTAssertEqual(assigned.count, 2)
        XCTAssertEqual(assigned[0].name, "Aスキル")
        XCTAssertEqual(assigned[1].name, "Zスキル")
    }

    func testFindByAgentIdReturnsEmptyForUnknownAgent() throws {
        let assigned = try assignmentRepository.findByAgentId(AgentID(value: "agt_unknown"))
        XCTAssertTrue(assigned.isEmpty)
    }

    // MARK: - FindBySkillId Tests

    func testFindBySkillId() throws {
        let agent1 = createTestAgent(id: "agt_001", name: "Agent1")
        let agent2 = createTestAgent(id: "agt_002", name: "Agent2")
        let skill = createTestSkill()

        try agentRepository.save(agent1)
        try agentRepository.save(agent2)
        try skillRepository.save(skill)
        try assignmentRepository.assignSkills(agentId: agent1.id, skillIds: [skill.id])
        try assignmentRepository.assignSkills(agentId: agent2.id, skillIds: [skill.id])

        let agents = try assignmentRepository.findBySkillId(skill.id)
        XCTAssertEqual(agents.count, 2)
        XCTAssertTrue(agents.contains { $0.value == "agt_001" })
        XCTAssertTrue(agents.contains { $0.value == "agt_002" })
    }

    // MARK: - RemoveAllSkills Tests

    func testRemoveAllSkills() throws {
        let agent = createTestAgent()
        let skill1 = createTestSkill(id: "skl_001", directoryName: "skill-1")
        let skill2 = createTestSkill(id: "skl_002", directoryName: "skill-2")

        try agentRepository.save(agent)
        try skillRepository.save(skill1)
        try skillRepository.save(skill2)
        try assignmentRepository.assignSkills(agentId: agent.id, skillIds: [skill1.id, skill2.id])

        try assignmentRepository.removeAllSkills(agentId: agent.id)

        let assigned = try assignmentRepository.findByAgentId(agent.id)
        XCTAssertTrue(assigned.isEmpty)
    }

    // MARK: - IsAssigned Tests

    func testIsAssigned() throws {
        let agent = createTestAgent()
        let skill1 = createTestSkill(id: "skl_001", directoryName: "skill-1")
        let skill2 = createTestSkill(id: "skl_002", directoryName: "skill-2")

        try agentRepository.save(agent)
        try skillRepository.save(skill1)
        try skillRepository.save(skill2)
        try assignmentRepository.assignSkills(agentId: agent.id, skillIds: [skill1.id])

        XCTAssertTrue(try assignmentRepository.isAssigned(agentId: agent.id, skillId: skill1.id))
        XCTAssertFalse(try assignmentRepository.isAssigned(agentId: agent.id, skillId: skill2.id))
    }

    // MARK: - IsInUse Tests (via SkillRepository)

    func testSkillIsInUseWhenAssigned() throws {
        let agent = createTestAgent()
        let skill = createTestSkill()

        try agentRepository.save(agent)
        try skillRepository.save(skill)

        // 割り当て前
        XCTAssertFalse(try skillRepository.isInUse(skill.id))

        // 割り当て後
        try assignmentRepository.assignSkills(agentId: agent.id, skillIds: [skill.id])
        XCTAssertTrue(try skillRepository.isInUse(skill.id))
    }

    // MARK: - Cascade Delete Tests

    func testAgentDeleteCascadesAssignments() throws {
        let agent = createTestAgent()
        let skill = createTestSkill()

        try agentRepository.save(agent)
        try skillRepository.save(skill)
        try assignmentRepository.assignSkills(agentId: agent.id, skillIds: [skill.id])

        // エージェント削除
        try agentRepository.delete(agent.id)

        // 割り当ても削除されている
        let assigned = try assignmentRepository.findByAgentId(agent.id)
        XCTAssertTrue(assigned.isEmpty)

        // スキル自体は残っている
        let foundSkill = try skillRepository.findById(skill.id)
        XCTAssertNotNil(foundSkill)
    }

    func testSkillDeleteCascadesAssignments() throws {
        let agent = createTestAgent()
        let skill = createTestSkill()

        try agentRepository.save(agent)
        try skillRepository.save(skill)
        try assignmentRepository.assignSkills(agentId: agent.id, skillIds: [skill.id])

        // スキル削除
        try skillRepository.delete(skill.id)

        // 割り当ても削除されている
        let assigned = try assignmentRepository.findByAgentId(agent.id)
        XCTAssertTrue(assigned.isEmpty)

        // エージェント自体は残っている
        let foundAgent = try agentRepository.findById(agent.id)
        XCTAssertNotNil(foundAgent)
    }
}
