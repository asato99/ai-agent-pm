// Tests/UseCaseTests/SkillUseCasesTests.swift
// スキル機能 - ユースケーステスト
// 参照: docs/design/AGENT_SKILLS.md

import XCTest
@testable import Domain
@testable import UseCase

// MARK: - Mock Repositories

final class MockSkillDefinitionRepository: SkillDefinitionRepositoryProtocol, @unchecked Sendable {
    var skills: [SkillID: SkillDefinition] = [:]
    var assignedSkillIds: Set<SkillID> = []

    func findAll() throws -> [SkillDefinition] {
        Array(skills.values).sorted { $0.name < $1.name }
    }

    func findById(_ id: SkillID) throws -> SkillDefinition? {
        skills[id]
    }

    func findByDirectoryName(_ directoryName: String) throws -> SkillDefinition? {
        skills.values.first { $0.directoryName == directoryName }
    }

    func save(_ skill: SkillDefinition) throws {
        skills[skill.id] = skill
    }

    func delete(_ id: SkillID) throws {
        skills.removeValue(forKey: id)
    }

    func isInUse(_ id: SkillID) throws -> Bool {
        assignedSkillIds.contains(id)
    }
}

final class MockAgentSkillAssignmentRepository: AgentSkillAssignmentRepositoryProtocol, @unchecked Sendable {
    var assignments: [AgentID: [SkillID]] = [:]
    var skillRepository: MockSkillDefinitionRepository

    init(skillRepository: MockSkillDefinitionRepository) {
        self.skillRepository = skillRepository
    }

    func findByAgentId(_ agentId: AgentID) throws -> [SkillDefinition] {
        let skillIds = assignments[agentId] ?? []
        return try skillIds.compactMap { try skillRepository.findById($0) }
    }

    func findBySkillId(_ skillId: SkillID) throws -> [AgentID] {
        assignments.filter { $0.value.contains(skillId) }.map { $0.key }
    }

    func assignSkills(agentId: AgentID, skillIds: [SkillID]) throws {
        // 古い割り当てを削除してから新しいものを追加
        if let oldSkillIds = assignments[agentId] {
            for id in oldSkillIds {
                skillRepository.assignedSkillIds.remove(id)
            }
        }
        assignments[agentId] = skillIds
        for id in skillIds {
            skillRepository.assignedSkillIds.insert(id)
        }
    }

    func removeAllSkills(agentId: AgentID) throws {
        if let skillIds = assignments[agentId] {
            for id in skillIds {
                skillRepository.assignedSkillIds.remove(id)
            }
        }
        assignments.removeValue(forKey: agentId)
    }

    func isAssigned(agentId: AgentID, skillId: SkillID) throws -> Bool {
        assignments[agentId]?.contains(skillId) ?? false
    }
}

// MARK: - SkillDefinitionUseCasesTests

final class SkillDefinitionUseCasesTests: XCTestCase {
    private var mockRepository: MockSkillDefinitionRepository!
    private var useCases: SkillDefinitionUseCases!

    override func setUpWithError() throws {
        try super.setUpWithError()
        mockRepository = MockSkillDefinitionRepository()
        useCases = SkillDefinitionUseCases(skillRepository: mockRepository)
    }

    override func tearDownWithError() throws {
        useCases = nil
        mockRepository = nil
        try super.tearDownWithError()
    }

    // MARK: - Create Tests

    func testCreateSkill() throws {
        let skill = try useCases.create(
            name: "コードレビュー",
            description: "コードの品質をレビューする",
            directoryName: "code-review",
            content: "---\nname: code-review\n---\n## 手順"
        )

        XCTAssertFalse(skill.id.value.isEmpty)
        XCTAssertEqual(skill.name, "コードレビュー")
        XCTAssertEqual(skill.description, "コードの品質をレビューする")
        XCTAssertEqual(skill.directoryName, "code-review")

        // リポジトリに保存されていることを確認
        let found = try mockRepository.findById(skill.id)
        XCTAssertNotNil(found)
    }

    func testCreateSkillWithEmptyNameThrows() {
        XCTAssertThrowsError(try useCases.create(
            name: "  ",
            description: "",
            directoryName: "test",
            content: "content"
        )) { error in
            XCTAssertEqual(error as? SkillError, .emptyName)
        }
    }

    func testCreateSkillWithInvalidDirectoryNameThrows() {
        XCTAssertThrowsError(try useCases.create(
            name: "Test",
            description: "",
            directoryName: "Invalid Name",
            content: "content"
        )) { error in
            XCTAssertEqual(error as? SkillError, .invalidDirectoryName("Invalid Name"))
        }
    }

    func testCreateSkillWithDuplicateDirectoryNameThrows() throws {
        _ = try useCases.create(
            name: "Skill 1",
            description: "",
            directoryName: "duplicate-name",
            content: "content"
        )

        XCTAssertThrowsError(try useCases.create(
            name: "Skill 2",
            description: "",
            directoryName: "duplicate-name",
            content: "content"
        )) { error in
            if case .directoryNameAlreadyExists(let name, _) = error as? SkillError {
                XCTAssertEqual(name, "duplicate-name")
            } else {
                XCTFail("Expected directoryNameAlreadyExists error")
            }
        }
    }

    func testCreateSkillWithDescriptionTooLongThrows() {
        let longDescription = String(repeating: "a", count: 300)

        XCTAssertThrowsError(try useCases.create(
            name: "Test",
            description: longDescription,
            directoryName: "test",
            content: "content"
        )) { error in
            if case .descriptionTooLong(let count) = error as? SkillError {
                XCTAssertEqual(count, 300)
            } else {
                XCTFail("Expected descriptionTooLong error")
            }
        }
    }

    // MARK: - Update Tests

    func testUpdateSkill() throws {
        let skill = try useCases.create(
            name: "Original",
            description: "Original description",
            directoryName: "original",
            content: "content"
        )

        let updated = try useCases.update(
            id: skill.id,
            name: "Updated",
            description: "Updated description"
        )

        XCTAssertEqual(updated.name, "Updated")
        XCTAssertEqual(updated.description, "Updated description")
        XCTAssertEqual(updated.directoryName, "original")
    }

    func testUpdateSkillNotFoundThrows() {
        XCTAssertThrowsError(try useCases.update(
            id: SkillID(value: "nonexistent"),
            name: "Test"
        )) { error in
            XCTAssertEqual(error as? SkillError, .skillNotFound("nonexistent"))
        }
    }

    func testUpdateSkillWithDuplicateDirectoryNameThrows() throws {
        _ = try useCases.create(
            name: "Skill 1",
            description: "",
            directoryName: "skill-1",
            content: "content"
        )

        let skill2 = try useCases.create(
            name: "Skill 2",
            description: "",
            directoryName: "skill-2",
            content: "content"
        )

        XCTAssertThrowsError(try useCases.update(
            id: skill2.id,
            directoryName: "skill-1"
        )) { error in
            if case .directoryNameAlreadyExists(let name, _) = error as? SkillError {
                XCTAssertEqual(name, "skill-1")
            } else {
                XCTFail("Expected directoryNameAlreadyExists error")
            }
        }
    }

    // MARK: - Delete Tests

    func testDeleteSkill() throws {
        let skill = try useCases.create(
            name: "To Delete",
            description: "",
            directoryName: "to-delete",
            content: "content"
        )

        try useCases.delete(skill.id)

        let found = try useCases.findById(skill.id)
        XCTAssertNil(found)
    }

    func testDeleteSkillNotFoundThrows() {
        XCTAssertThrowsError(try useCases.delete(SkillID(value: "nonexistent"))) { error in
            XCTAssertEqual(error as? SkillError, .skillNotFound("nonexistent"))
        }
    }

    func testDeleteSkillInUseThrows() throws {
        let skill = try useCases.create(
            name: "In Use",
            description: "",
            directoryName: "in-use",
            content: "content"
        )
        mockRepository.assignedSkillIds.insert(skill.id)

        XCTAssertThrowsError(try useCases.delete(skill.id)) { error in
            if case .skillInUse(let id) = error as? SkillError {
                XCTAssertEqual(id, skill.id.value)
            } else {
                XCTFail("Expected skillInUse error")
            }
        }
    }

    // MARK: - Find Tests

    func testFindAll() throws {
        _ = try useCases.create(name: "Skill A", description: "", directoryName: "skill-a", content: "")
        _ = try useCases.create(name: "Skill B", description: "", directoryName: "skill-b", content: "")

        let all = try useCases.findAll()
        XCTAssertEqual(all.count, 2)
    }

    func testFindByDirectoryName() throws {
        let skill = try useCases.create(
            name: "Test",
            description: "",
            directoryName: "test-skill",
            content: ""
        )

        let found = try useCases.findByDirectoryName("test-skill")
        XCTAssertEqual(found?.id, skill.id)
    }
}

// MARK: - AgentSkillUseCasesTests

final class AgentSkillUseCasesTests: XCTestCase {
    private var mockSkillRepository: MockSkillDefinitionRepository!
    private var mockAssignmentRepository: MockAgentSkillAssignmentRepository!
    private var useCases: AgentSkillUseCases!

    override func setUpWithError() throws {
        try super.setUpWithError()
        mockSkillRepository = MockSkillDefinitionRepository()
        mockAssignmentRepository = MockAgentSkillAssignmentRepository(skillRepository: mockSkillRepository)
        useCases = AgentSkillUseCases(
            assignmentRepository: mockAssignmentRepository,
            skillRepository: mockSkillRepository
        )
    }

    override func tearDownWithError() throws {
        useCases = nil
        mockAssignmentRepository = nil
        mockSkillRepository = nil
        try super.tearDownWithError()
    }

    // MARK: - Helper Methods

    private func createTestSkill(id: String, directoryName: String) -> SkillDefinition {
        SkillDefinition(
            id: SkillID(value: id),
            name: "Test Skill",
            description: "",
            directoryName: directoryName,
            content: "",
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // MARK: - AssignSkills Tests

    func testAssignSkills() throws {
        let agentId = AgentID(value: "agt_001")
        let skill1 = createTestSkill(id: "skl_001", directoryName: "skill-1")
        let skill2 = createTestSkill(id: "skl_002", directoryName: "skill-2")

        try mockSkillRepository.save(skill1)
        try mockSkillRepository.save(skill2)

        try useCases.assignSkills(agentId: agentId, skillIds: [skill1.id, skill2.id])

        let assigned = try useCases.getAgentSkills(agentId)
        XCTAssertEqual(assigned.count, 2)
    }

    func testAssignSkillsWithNonexistentSkillThrows() throws {
        let agentId = AgentID(value: "agt_001")

        XCTAssertThrowsError(try useCases.assignSkills(
            agentId: agentId,
            skillIds: [SkillID(value: "nonexistent")]
        )) { error in
            XCTAssertEqual(error as? SkillError, .skillNotFound("nonexistent"))
        }
    }

    func testAssignSkillsReplacesExisting() throws {
        let agentId = AgentID(value: "agt_001")
        let skill1 = createTestSkill(id: "skl_001", directoryName: "skill-1")
        let skill2 = createTestSkill(id: "skl_002", directoryName: "skill-2")
        let skill3 = createTestSkill(id: "skl_003", directoryName: "skill-3")

        try mockSkillRepository.save(skill1)
        try mockSkillRepository.save(skill2)
        try mockSkillRepository.save(skill3)

        // 初回割り当て
        try useCases.assignSkills(agentId: agentId, skillIds: [skill1.id, skill2.id])
        var assigned = try useCases.getAgentSkills(agentId)
        XCTAssertEqual(assigned.count, 2)

        // 2回目（全置換）
        try useCases.assignSkills(agentId: agentId, skillIds: [skill3.id])
        assigned = try useCases.getAgentSkills(agentId)
        XCTAssertEqual(assigned.count, 1)
        XCTAssertEqual(assigned.first?.id, skill3.id)
    }

    // MARK: - GetAgentSkills Tests

    func testGetAgentSkillsReturnsEmpty() throws {
        let agentId = AgentID(value: "agt_001")

        let skills = try useCases.getAgentSkills(agentId)
        XCTAssertTrue(skills.isEmpty)
    }

    // MARK: - GetAgentsUsingSkill Tests

    func testGetAgentsUsingSkill() throws {
        let agent1 = AgentID(value: "agt_001")
        let agent2 = AgentID(value: "agt_002")
        let skill = createTestSkill(id: "skl_001", directoryName: "shared-skill")

        try mockSkillRepository.save(skill)

        try useCases.assignSkills(agentId: agent1, skillIds: [skill.id])
        try useCases.assignSkills(agentId: agent2, skillIds: [skill.id])

        let agents = try useCases.getAgentsUsingSkill(skill.id)
        XCTAssertEqual(agents.count, 2)
    }

    // MARK: - RemoveAllSkills Tests

    func testRemoveAllSkills() throws {
        let agentId = AgentID(value: "agt_001")
        let skill = createTestSkill(id: "skl_001", directoryName: "skill-1")

        try mockSkillRepository.save(skill)
        try useCases.assignSkills(agentId: agentId, skillIds: [skill.id])

        try useCases.removeAllSkills(agentId)

        let skills = try useCases.getAgentSkills(agentId)
        XCTAssertTrue(skills.isEmpty)
    }

    // MARK: - IsAssigned Tests

    func testIsAssigned() throws {
        let agentId = AgentID(value: "agt_001")
        let skill1 = createTestSkill(id: "skl_001", directoryName: "skill-1")
        let skill2 = createTestSkill(id: "skl_002", directoryName: "skill-2")

        try mockSkillRepository.save(skill1)
        try mockSkillRepository.save(skill2)
        try useCases.assignSkills(agentId: agentId, skillIds: [skill1.id])

        XCTAssertTrue(try useCases.isAssigned(agentId: agentId, skillId: skill1.id))
        XCTAssertFalse(try useCases.isAssigned(agentId: agentId, skillId: skill2.id))
    }
}
