// Tests/InfrastructureTests/SkillDefinitionRepositoryTests.swift
// スキル定義リポジトリ - Infrastructure層テスト
// 参照: docs/design/AGENT_SKILLS.md

import XCTest
import GRDB
@testable import Domain
@testable import Infrastructure

final class SkillDefinitionRepositoryTests: XCTestCase {
    private var dbQueue: DatabaseQueue!
    private var repository: SkillDefinitionRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_skill_\(UUID().uuidString).db").path
        dbQueue = try DatabaseSetup.createDatabase(at: dbPath)
        repository = SkillDefinitionRepository(database: dbQueue)
    }

    override func tearDownWithError() throws {
        repository = nil
        dbQueue = nil
        try super.tearDownWithError()
    }

    // MARK: - Helper Methods

    private func createTestSkill(
        id: String = "skl_test001",
        name: String = "コードレビュー",
        description: String = "コードの品質をレビューする",
        directoryName: String = "code-review",
        content: String = "---\nname: code-review\n---\n## レビュー手順"
    ) -> SkillDefinition {
        SkillDefinition(
            id: SkillID(value: id),
            name: name,
            description: description,
            directoryName: directoryName,
            content: content,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // MARK: - Save & Find Tests

    func testSaveAndFindById() throws {
        let skill = createTestSkill()

        try repository.save(skill)

        let found = try repository.findById(skill.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, skill.id)
        XCTAssertEqual(found?.name, "コードレビュー")
        XCTAssertEqual(found?.description, "コードの品質をレビューする")
        XCTAssertEqual(found?.directoryName, "code-review")
        XCTAssertTrue(found?.content.contains("レビュー手順") ?? false)
    }

    func testFindByIdNotFound() throws {
        let found = try repository.findById(SkillID(value: "skl_nonexistent"))
        XCTAssertNil(found)
    }

    func testFindByDirectoryName() throws {
        let skill = createTestSkill()
        try repository.save(skill)

        let found = try repository.findByDirectoryName("code-review")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, skill.id)
    }

    func testFindByDirectoryNameNotFound() throws {
        let found = try repository.findByDirectoryName("nonexistent-skill")
        XCTAssertNil(found)
    }

    // MARK: - FindAll Tests

    func testFindAllReturnsOrderedByName() throws {
        let skill1 = createTestSkill(id: "skl_001", name: "Zテスト作成", directoryName: "test-creation")
        let skill2 = createTestSkill(id: "skl_002", name: "Aコードレビュー", directoryName: "code-review")
        let skill3 = createTestSkill(id: "skl_003", name: "Mドキュメント", directoryName: "documentation")

        try repository.save(skill1)
        try repository.save(skill2)
        try repository.save(skill3)

        let all = try repository.findAll()
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all[0].name, "Aコードレビュー")
        XCTAssertEqual(all[1].name, "Mドキュメント")
        XCTAssertEqual(all[2].name, "Zテスト作成")
    }

    func testFindAllEmpty() throws {
        let all = try repository.findAll()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - Update Tests

    func testUpdateSkill() throws {
        var skill = createTestSkill()
        try repository.save(skill)

        skill.name = "更新されたスキル"
        skill.description = "更新された説明"
        skill.updatedAt = Date()
        try repository.save(skill)

        let found = try repository.findById(skill.id)
        XCTAssertEqual(found?.name, "更新されたスキル")
        XCTAssertEqual(found?.description, "更新された説明")
    }

    // MARK: - Delete Tests

    func testDelete() throws {
        let skill = createTestSkill()
        try repository.save(skill)

        try repository.delete(skill.id)

        let found = try repository.findById(skill.id)
        XCTAssertNil(found)
    }

    func testDeleteNonexistent() throws {
        // 存在しないIDを削除しても例外は発生しない
        XCTAssertNoThrow(try repository.delete(SkillID(value: "skl_nonexistent")))
    }

    // MARK: - IsInUse Tests

    func testIsInUseReturnsFalseWhenNotAssigned() throws {
        let skill = createTestSkill()
        try repository.save(skill)

        let inUse = try repository.isInUse(skill.id)
        XCTAssertFalse(inUse)
    }

    // MARK: - Unique Constraint Tests

    func testDirectoryNameUniqueConstraint() throws {
        let skill1 = createTestSkill(id: "skl_001", directoryName: "unique-name")
        let skill2 = createTestSkill(id: "skl_002", directoryName: "unique-name")

        try repository.save(skill1)

        XCTAssertThrowsError(try repository.save(skill2)) { error in
            // GRDB/SQLiteのUNIQUE制約違反エラー
            XCTAssertTrue(error is DatabaseError)
        }
    }
}
