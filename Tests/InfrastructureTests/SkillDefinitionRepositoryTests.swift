// Tests/InfrastructureTests/SkillDefinitionRepositoryTests.swift
// スキル定義リポジトリ - Infrastructure層テスト
// 参照: docs/design/AGENT_SKILLS.md

import XCTest
import GRDB
@testable import Domain
@testable import Infrastructure

/// テスト用のZIPアーカイブを作成
private func createTestArchive(content: String = "") -> Data {
    let contentData = content.data(using: .utf8) ?? Data()
    let fileName = "SKILL.md"
    let fileNameData = fileName.data(using: .utf8)!

    // CRC-32計算
    var crc: UInt32 = 0xFFFFFFFF
    let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }
    for byte in contentData {
        crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
    }
    crc = crc ^ 0xFFFFFFFF

    var data = Data()

    // Local File Header
    data.append(contentsOf: [0x50, 0x4b, 0x03, 0x04])
    data.append(contentsOf: [0x0a, 0x00])
    data.append(contentsOf: [0x00, 0x00])
    data.append(contentsOf: [0x00, 0x00])
    data.append(contentsOf: [0x00, 0x00])
    data.append(contentsOf: [0x00, 0x00])
    data.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt16(fileNameData.count).littleEndian) { Array($0) })
    data.append(contentsOf: [0x00, 0x00])
    data.append(fileNameData)
    data.append(contentData)

    // Central Directory Entry
    var centralDirectory = Data()
    centralDirectory.append(contentsOf: [0x50, 0x4b, 0x01, 0x02])
    centralDirectory.append(contentsOf: [0x14, 0x00])
    centralDirectory.append(contentsOf: [0x0a, 0x00])
    centralDirectory.append(contentsOf: [0x00, 0x00])
    centralDirectory.append(contentsOf: [0x00, 0x00])
    centralDirectory.append(contentsOf: [0x00, 0x00])
    centralDirectory.append(contentsOf: [0x00, 0x00])
    centralDirectory.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
    centralDirectory.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) })
    centralDirectory.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) })
    centralDirectory.append(contentsOf: withUnsafeBytes(of: UInt16(fileNameData.count).littleEndian) { Array($0) })
    centralDirectory.append(contentsOf: [0x00, 0x00])
    centralDirectory.append(contentsOf: [0x00, 0x00])
    centralDirectory.append(contentsOf: [0x00, 0x00])
    centralDirectory.append(contentsOf: [0x00, 0x00])
    centralDirectory.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
    centralDirectory.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
    centralDirectory.append(fileNameData)

    let centralDirOffset = data.count
    data.append(centralDirectory)

    // End of Central Directory
    data.append(contentsOf: [0x50, 0x4b, 0x05, 0x06])
    data.append(contentsOf: [0x00, 0x00])
    data.append(contentsOf: [0x00, 0x00])
    data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(centralDirectory.count).littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(centralDirOffset).littleEndian) { Array($0) })
    data.append(contentsOf: [0x00, 0x00])

    return data
}

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
            archiveData: createTestArchive(content: content),
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
        XCTAssertFalse(found?.archiveData.isEmpty ?? true)
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
