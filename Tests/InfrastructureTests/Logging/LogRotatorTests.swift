// Tests/InfrastructureTests/Logging/LogRotatorTests.swift

import XCTest
@testable import Infrastructure

final class LogRotatorTests: XCTestCase {

    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "log_rotator_test_\(UUID().uuidString)/"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func createLogFile(named fileName: String, modifiedDaysAgo days: Int) {
        let filePath = tempDir + fileName
        FileManager.default.createFile(atPath: filePath, contents: "test log content".data(using: .utf8))

        // ファイルの更新日時を変更
        let modifiedDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        try? FileManager.default.setAttributes(
            [.modificationDate: modifiedDate],
            ofItemAtPath: filePath
        )
    }

    private func fileExists(_ fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: tempDir + fileName)
    }

    private func readFile(_ fileName: String) -> String? {
        try? String(contentsOfFile: tempDir + fileName, encoding: .utf8)
    }

    // MARK: - Deletion Tests

    func testLogRotatorDeletesOldFiles() {
        // 8日前のファイル（保持期間外）
        createLogFile(named: "mcp-server-2026-01-20.log", modifiedDaysAgo: 8)

        // 今日のファイル（保持期間内）
        createLogFile(named: "mcp-server-2026-01-28.log", modifiedDaysAgo: 0)

        let rotator = LogRotator(directory: tempDir, retentionDays: 7)
        rotator.rotate()

        XCTAssertFalse(fileExists("mcp-server-2026-01-20.log"), "8日前のファイルは削除されるべき")
        XCTAssertTrue(fileExists("mcp-server-2026-01-28.log"), "今日のファイルは保持されるべき")
    }

    func testLogRotatorKeepsRecentFiles() {
        // 6日前のファイル（保持期間内）
        createLogFile(named: "mcp-server-2026-01-22.log", modifiedDaysAgo: 6)

        // 3日前のファイル（保持期間内）
        createLogFile(named: "mcp-server-2026-01-25.log", modifiedDaysAgo: 3)

        let rotator = LogRotator(directory: tempDir, retentionDays: 7)
        rotator.rotate()

        XCTAssertTrue(fileExists("mcp-server-2026-01-22.log"), "6日前のファイルは保持されるべき")
        XCTAssertTrue(fileExists("mcp-server-2026-01-25.log"), "3日前のファイルは保持されるべき")
    }

    func testLogRotatorDeletesMultipleOldFiles() {
        // 複数の古いファイル
        createLogFile(named: "mcp-server-2026-01-10.log", modifiedDaysAgo: 18)
        createLogFile(named: "mcp-server-2026-01-15.log", modifiedDaysAgo: 13)
        createLogFile(named: "mcp-server-2026-01-18.log", modifiedDaysAgo: 10)

        // 保持期間内のファイル
        createLogFile(named: "mcp-server-2026-01-27.log", modifiedDaysAgo: 1)

        let rotator = LogRotator(directory: tempDir, retentionDays: 7)
        rotator.rotate()

        XCTAssertFalse(fileExists("mcp-server-2026-01-10.log"))
        XCTAssertFalse(fileExists("mcp-server-2026-01-15.log"))
        XCTAssertFalse(fileExists("mcp-server-2026-01-18.log"))
        XCTAssertTrue(fileExists("mcp-server-2026-01-27.log"))
    }

    func testLogRotatorOnlyDeletesLogFiles() {
        // ログファイル（古い）
        createLogFile(named: "mcp-server-2026-01-10.log", modifiedDaysAgo: 18)

        // 非ログファイル（古い）- 削除されるべきではない
        createLogFile(named: "config.json", modifiedDaysAgo: 100)
        createLogFile(named: "readme.txt", modifiedDaysAgo: 100)

        let rotator = LogRotator(directory: tempDir, retentionDays: 7, filePattern: "*.log")
        rotator.rotate()

        XCTAssertFalse(fileExists("mcp-server-2026-01-10.log"), "古いログファイルは削除")
        XCTAssertTrue(fileExists("config.json"), "非ログファイルは保持")
        XCTAssertTrue(fileExists("readme.txt"), "非ログファイルは保持")
    }

    // MARK: - Boundary Tests

    func testLogRotatorAtRetentionBoundary() {
        // 6日前（保持期間内 - 安全マージン）
        createLogFile(named: "mcp-server-within.log", modifiedDaysAgo: 6)

        // 8日前（保持期間外）
        createLogFile(named: "mcp-server-outside.log", modifiedDaysAgo: 8)

        let rotator = LogRotator(directory: tempDir, retentionDays: 7)
        rotator.rotate()

        XCTAssertTrue(fileExists("mcp-server-within.log"), "6日前のファイルは7日保持期間内")
        XCTAssertFalse(fileExists("mcp-server-outside.log"), "8日前のファイルは7日保持期間外")
    }

    func testLogRotatorJustOverRetentionBoundary() {
        // 8日前（境界を超えた）
        createLogFile(named: "mcp-server-over.log", modifiedDaysAgo: 8)

        let rotator = LogRotator(directory: tempDir, retentionDays: 7)
        rotator.rotate()

        XCTAssertFalse(fileExists("mcp-server-over.log"), "8日前のファイルは削除")
    }

    // MARK: - Custom Retention Days Tests

    func testLogRotatorWithCustomRetentionDays() {
        // 15日前のファイル
        createLogFile(named: "mcp-server-old.log", modifiedDaysAgo: 15)

        // 10日前のファイル
        createLogFile(named: "mcp-server-recent.log", modifiedDaysAgo: 10)

        let rotator = LogRotator(directory: tempDir, retentionDays: 14)
        rotator.rotate()

        XCTAssertFalse(fileExists("mcp-server-old.log"), "15日前は14日保持を超える")
        XCTAssertTrue(fileExists("mcp-server-recent.log"), "10日前は14日保持内")
    }

    // MARK: - Empty Directory Tests

    func testLogRotatorWithEmptyDirectory() {
        let rotator = LogRotator(directory: tempDir, retentionDays: 7)

        // 例外なく完了することを確認
        XCTAssertNoThrow(rotator.rotate())
    }

    func testLogRotatorWithNonExistentDirectory() {
        let nonExistentDir = tempDir + "nonexistent/"
        let rotator = LogRotator(directory: nonExistentDir, retentionDays: 7)

        // 例外なく完了することを確認（ディレクトリがなくてもクラッシュしない）
        XCTAssertNoThrow(rotator.rotate())
    }

    // MARK: - Deletion Count Tests

    func testLogRotatorReturnsDeletedCount() {
        createLogFile(named: "mcp-server-1.log", modifiedDaysAgo: 10)
        createLogFile(named: "mcp-server-2.log", modifiedDaysAgo: 15)
        createLogFile(named: "mcp-server-3.log", modifiedDaysAgo: 1)

        let rotator = LogRotator(directory: tempDir, retentionDays: 7)
        let deletedCount = rotator.rotate()

        XCTAssertEqual(deletedCount, 2, "2つのファイルが削除されるべき")
    }

    // MARK: - LogRotationConfig Tests

    func testLogRotationConfigDefaultValues() {
        let config = LogRotationConfig.default

        XCTAssertEqual(config.retentionDays, 7)
        XCTAssertEqual(config.filePattern, "*.log")
    }

    func testLogRotationConfigFromEnvironmentWithValidValue() {
        setenv("MCP_LOG_RETENTION_DAYS", "14", 1)
        defer { unsetenv("MCP_LOG_RETENTION_DAYS") }

        let config = LogRotationConfig.fromEnvironment()

        XCTAssertEqual(config.retentionDays, 14)
    }

    func testLogRotationConfigFromEnvironmentWithInvalidValue() {
        setenv("MCP_LOG_RETENTION_DAYS", "invalid", 1)
        defer { unsetenv("MCP_LOG_RETENTION_DAYS") }

        let config = LogRotationConfig.fromEnvironment()

        // 無効な値の場合はデフォルト値を使用
        XCTAssertEqual(config.retentionDays, 7)
    }

    func testLogRotationConfigFromEnvironmentWithZeroValue() {
        setenv("MCP_LOG_RETENTION_DAYS", "0", 1)
        defer { unsetenv("MCP_LOG_RETENTION_DAYS") }

        let config = LogRotationConfig.fromEnvironment()

        // 0以下の場合はデフォルト値を使用
        XCTAssertEqual(config.retentionDays, 7)
    }

    func testLogRotationConfigFromEnvironmentWithNegativeValue() {
        setenv("MCP_LOG_RETENTION_DAYS", "-5", 1)
        defer { unsetenv("MCP_LOG_RETENTION_DAYS") }

        let config = LogRotationConfig.fromEnvironment()

        // 負の値の場合はデフォルト値を使用
        XCTAssertEqual(config.retentionDays, 7)
    }

    func testLogRotationConfigFromEnvironmentWithNoValue() {
        unsetenv("MCP_LOG_RETENTION_DAYS")

        let config = LogRotationConfig.fromEnvironment()

        // 環境変数が未設定の場合はデフォルト値を使用
        XCTAssertEqual(config.retentionDays, 7)
    }

    // MARK: - LogMigrator Tests

    func testLogMigratorMigratesExistingFile() {
        // 既存のログファイルを作成
        let oldFilePath = tempDir + "mcp-server.log"
        FileManager.default.createFile(atPath: oldFilePath, contents: "old log content".data(using: .utf8))

        // ファイルの更新日時を設定
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        try? FileManager.default.setAttributes([.modificationDate: yesterday], ofItemAtPath: oldFilePath)

        let migrator = LogMigrator(directory: tempDir)
        let result = migrator.migrateIfNeeded(prefix: "mcp-server")

        XCTAssertTrue(result, "移行が実行されるべき")
        XCTAssertFalse(fileExists("mcp-server.log"), "元のファイルは削除されるべき")

        // 日付付きファイルが作成されていることを確認
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let expectedFileName = "mcp-server-\(formatter.string(from: yesterday)).log"
        XCTAssertTrue(fileExists(expectedFileName), "日付付きファイルが作成されるべき")
    }

    func testLogMigratorDoesNothingWhenNoExistingFile() {
        let migrator = LogMigrator(directory: tempDir)
        let result = migrator.migrateIfNeeded(prefix: "mcp-server")

        XCTAssertFalse(result, "ファイルがない場合は移行しない")
    }

    func testLogMigratorAppendsToExistingDatedFile() {
        // 既存の日付なしログファイルを作成
        let oldFilePath = tempDir + "mcp-server.log"
        FileManager.default.createFile(atPath: oldFilePath, contents: "old content\n".data(using: .utf8))

        // 同じ日付の既存ファイルを作成
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = Date()
        let datedFileName = "mcp-server-\(formatter.string(from: today)).log"
        let datedFilePath = tempDir + datedFileName
        FileManager.default.createFile(atPath: datedFilePath, contents: "existing content\n".data(using: .utf8))

        // 日付なしファイルの更新日時を今日に設定
        try? FileManager.default.setAttributes([.modificationDate: today], ofItemAtPath: oldFilePath)

        let migrator = LogMigrator(directory: tempDir)
        let result = migrator.migrateIfNeeded(prefix: "mcp-server")

        XCTAssertTrue(result, "移行が実行されるべき")
        XCTAssertFalse(fileExists("mcp-server.log"), "元のファイルは削除されるべき")

        // 日付付きファイルに追記されていることを確認
        let content = readFile(datedFileName)
        XCTAssertNotNil(content)
        XCTAssertTrue(content!.contains("existing content"), "既存の内容が保持されるべき")
        XCTAssertTrue(content!.contains("old content"), "古い内容が追記されるべき")
    }
}
