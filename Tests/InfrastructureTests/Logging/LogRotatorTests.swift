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

    // MARK: - Rotated Files Pattern Matching Tests

    func testLogRotatorDeletesRotatedFiles() {
        // 古いログファイル（.log）
        createLogFile(named: "mcp-server-2026-01-10.log", modifiedDaysAgo: 20)

        // 古いローテーションファイル（.log.1, .log.2）
        createLogFile(named: "mcp-server-2026-01-10.log.1", modifiedDaysAgo: 20)
        createLogFile(named: "mcp-server-2026-01-10.log.2", modifiedDaysAgo: 20)

        // 新しいファイル（保持されるべき）
        createLogFile(named: "mcp-server-2026-01-28.log", modifiedDaysAgo: 0)
        createLogFile(named: "mcp-server-2026-01-28.log.1", modifiedDaysAgo: 0)

        let rotator = LogRotator(directory: tempDir, retentionDays: 7)
        rotator.rotate()

        XCTAssertFalse(fileExists("mcp-server-2026-01-10.log"), "古いログは削除")
        XCTAssertFalse(fileExists("mcp-server-2026-01-10.log.1"), "古いローテーションファイルも削除")
        XCTAssertFalse(fileExists("mcp-server-2026-01-10.log.2"), "古いローテーションファイルも削除")
        XCTAssertTrue(fileExists("mcp-server-2026-01-28.log"), "新しいログは保持")
        XCTAssertTrue(fileExists("mcp-server-2026-01-28.log.1"), "新しいローテーションファイルは保持")
    }

    // MARK: - Total Size Based Rotation Tests

    private func createLogFileWithSize(named fileName: String, modifiedDaysAgo days: Int, sizeInKB: Int) {
        let filePath = tempDir + fileName
        let data = Data(repeating: 0x41, count: sizeInKB * 1024)
        FileManager.default.createFile(atPath: filePath, contents: data)

        let modifiedDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        try? FileManager.default.setAttributes(
            [.modificationDate: modifiedDate],
            ofItemAtPath: filePath
        )
    }

    func testLogRotatorDeletesOldestFilesWhenTotalSizeExceeded() {
        // 全体サイズ制限: 50KB
        // ファイル: 各20KB × 3 = 60KB（制限超過）
        createLogFileWithSize(named: "mcp-server-1.log", modifiedDaysAgo: 3, sizeInKB: 20)  // 最古
        createLogFileWithSize(named: "mcp-server-2.log", modifiedDaysAgo: 2, sizeInKB: 20)
        createLogFileWithSize(named: "mcp-server-3.log", modifiedDaysAgo: 1, sizeInKB: 20)  // 最新

        let rotator = LogRotator(
            directory: tempDir,
            retentionDays: 7,
            maxTotalSize: 50 * 1024  // 50KB
        )
        let deletedCount = rotator.rotate()

        XCTAssertEqual(deletedCount, 1, "1ファイル削除で50KB以下になる")
        XCTAssertFalse(fileExists("mcp-server-1.log"), "最古のファイルが削除される")
        XCTAssertTrue(fileExists("mcp-server-2.log"), "新しいファイルは保持")
        XCTAssertTrue(fileExists("mcp-server-3.log"), "最新のファイルは保持")
    }

    func testLogRotatorDeletesMultipleFilesWhenTotalSizeExceeded() {
        // 全体サイズ制限: 30KB
        // ファイル: 各20KB × 3 = 60KB（大幅超過）
        createLogFileWithSize(named: "mcp-server-1.log", modifiedDaysAgo: 3, sizeInKB: 20)  // 最古
        createLogFileWithSize(named: "mcp-server-2.log", modifiedDaysAgo: 2, sizeInKB: 20)
        createLogFileWithSize(named: "mcp-server-3.log", modifiedDaysAgo: 1, sizeInKB: 20)  // 最新

        let rotator = LogRotator(
            directory: tempDir,
            retentionDays: 7,
            maxTotalSize: 30 * 1024  // 30KB
        )
        let deletedCount = rotator.rotate()

        XCTAssertEqual(deletedCount, 2, "2ファイル削除で30KB以下になる")
        XCTAssertFalse(fileExists("mcp-server-1.log"), "最古のファイルが削除")
        XCTAssertFalse(fileExists("mcp-server-2.log"), "2番目に古いファイルも削除")
        XCTAssertTrue(fileExists("mcp-server-3.log"), "最新のファイルは保持")
    }

    func testLogRotatorDoesNothingWhenTotalSizeUnderLimit() {
        // 全体サイズ制限: 100KB
        // ファイル: 各20KB × 3 = 60KB（制限未満）
        createLogFileWithSize(named: "mcp-server-1.log", modifiedDaysAgo: 3, sizeInKB: 20)
        createLogFileWithSize(named: "mcp-server-2.log", modifiedDaysAgo: 2, sizeInKB: 20)
        createLogFileWithSize(named: "mcp-server-3.log", modifiedDaysAgo: 1, sizeInKB: 20)

        let rotator = LogRotator(
            directory: tempDir,
            retentionDays: 7,
            maxTotalSize: 100 * 1024  // 100KB
        )
        let deletedCount = rotator.rotate()

        XCTAssertEqual(deletedCount, 0, "制限未満なので削除なし")
        XCTAssertTrue(fileExists("mcp-server-1.log"))
        XCTAssertTrue(fileExists("mcp-server-2.log"))
        XCTAssertTrue(fileExists("mcp-server-3.log"))
    }

    func testLogRotatorCombinesAgeAndSizeBasedDeletion() {
        // 年齢ベース: 8日以上古いファイルを削除
        // サイズベース: 30KB超過で古いファイルから削除
        createLogFileWithSize(named: "mcp-server-old.log", modifiedDaysAgo: 10, sizeInKB: 20)  // 年齢で削除
        createLogFileWithSize(named: "mcp-server-mid.log", modifiedDaysAgo: 3, sizeInKB: 20)   // サイズで削除
        createLogFileWithSize(named: "mcp-server-new.log", modifiedDaysAgo: 1, sizeInKB: 20)   // 保持

        let rotator = LogRotator(
            directory: tempDir,
            retentionDays: 7,
            maxTotalSize: 30 * 1024  // 30KB（年齢削除後も40KB残るので超過）
        )
        let deletedCount = rotator.rotate()

        XCTAssertEqual(deletedCount, 2, "年齢で1、サイズで1、計2削除")
        XCTAssertFalse(fileExists("mcp-server-old.log"), "古いファイルは年齢ベースで削除")
        XCTAssertFalse(fileExists("mcp-server-mid.log"), "中間のファイルはサイズベースで削除")
        XCTAssertTrue(fileExists("mcp-server-new.log"), "最新のファイルは保持")
    }

    func testLogRotatorWithZeroMaxTotalSizeDisablesSizeCheck() {
        // maxTotalSize: 0 はサイズチェックを無効化
        createLogFileWithSize(named: "mcp-server-1.log", modifiedDaysAgo: 1, sizeInKB: 1000)
        createLogFileWithSize(named: "mcp-server-2.log", modifiedDaysAgo: 1, sizeInKB: 1000)

        let rotator = LogRotator(
            directory: tempDir,
            retentionDays: 7,
            maxTotalSize: 0  // 無効化
        )
        let deletedCount = rotator.rotate()

        XCTAssertEqual(deletedCount, 0, "サイズチェック無効なので削除なし")
        XCTAssertTrue(fileExists("mcp-server-1.log"))
        XCTAssertTrue(fileExists("mcp-server-2.log"))
    }

    func testLogRotatorGetTotalSize() {
        createLogFileWithSize(named: "mcp-server-1.log", modifiedDaysAgo: 1, sizeInKB: 10)
        createLogFileWithSize(named: "mcp-server-2.log", modifiedDaysAgo: 1, sizeInKB: 20)
        createLogFileWithSize(named: "config.json", modifiedDaysAgo: 1, sizeInKB: 5)  // 非ログファイル

        let rotator = LogRotator(directory: tempDir, retentionDays: 7)
        let totalSize = rotator.getTotalSize()

        XCTAssertEqual(totalSize, 30 * 1024, "ログファイルのみの合計サイズ")
    }

    // MARK: - LogRotationConfig Total Size Tests

    func testLogRotationConfigDefaultMaxTotalSize() {
        let config = LogRotationConfig.default

        XCTAssertEqual(config.maxTotalSize, 500 * 1024 * 1024, "デフォルトは500MB")
    }

    func testLogRotationConfigFromEnvironmentWithMaxTotalSize() {
        setenv("MCP_LOG_MAX_TOTAL_SIZE_MB", "200", 1)
        defer { unsetenv("MCP_LOG_MAX_TOTAL_SIZE_MB") }

        let config = LogRotationConfig.fromEnvironment()

        XCTAssertEqual(config.maxTotalSize, 200 * 1024 * 1024, "200MBに設定")
    }

    func testLogRotationConfigFromEnvironmentWithInvalidMaxTotalSize() {
        setenv("MCP_LOG_MAX_TOTAL_SIZE_MB", "invalid", 1)
        defer { unsetenv("MCP_LOG_MAX_TOTAL_SIZE_MB") }

        let config = LogRotationConfig.fromEnvironment()

        XCTAssertEqual(config.maxTotalSize, 500 * 1024 * 1024, "無効値はデフォルト500MB")
    }
}

// MARK: - SizeBasedLogRotatorTests

final class SizeBasedLogRotatorTests: XCTestCase {

    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "size_rotator_test_\(UUID().uuidString)/"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func createFileWithSize(named fileName: String, sizeInBytes: Int) {
        let filePath = tempDir + fileName
        let data = Data(repeating: 0x41, count: sizeInBytes) // 'A' で埋める
        FileManager.default.createFile(atPath: filePath, contents: data)
    }

    private func fileExists(_ fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: tempDir + fileName)
    }

    private func getFileSize(_ fileName: String) -> UInt64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: tempDir + fileName),
              let size = attrs[.size] as? UInt64 else {
            return 0
        }
        return size
    }

    // MARK: - Rotation Tests

    func testRotateIfNeededDoesNothingWhenUnderLimit() {
        // 1KBのファイル作成（制限: 10KB）
        createFileWithSize(named: "test.log", sizeInBytes: 1024)

        let rotator = SizeBasedLogRotator(maxFileSize: 10 * 1024, maxRotations: 5)
        let rotated = rotator.rotateIfNeeded(filePath: tempDir + "test.log")

        XCTAssertFalse(rotated, "制限未満ならローテーションしない")
        XCTAssertTrue(fileExists("test.log"), "元のファイルは残る")
        XCTAssertFalse(fileExists("test.log.1"), "ローテーションファイルは作成されない")
    }

    func testRotateIfNeededRotatesWhenOverLimit() {
        // 15KBのファイル作成（制限: 10KB）
        createFileWithSize(named: "test.log", sizeInBytes: 15 * 1024)

        let rotator = SizeBasedLogRotator(maxFileSize: 10 * 1024, maxRotations: 5)
        let rotated = rotator.rotateIfNeeded(filePath: tempDir + "test.log")

        XCTAssertTrue(rotated, "制限超過でローテーション実行")
        XCTAssertFalse(fileExists("test.log"), "元のファイルはリネームされる")
        XCTAssertTrue(fileExists("test.log.1"), "ローテーションファイルが作成される")
        XCTAssertEqual(getFileSize("test.log.1"), UInt64(15 * 1024), "ファイルサイズは保持される")
    }

    func testRotateShiftsExistingRotatedFiles() {
        // 既存のローテーションファイルを作成
        createFileWithSize(named: "test.log.1", sizeInBytes: 1000)
        createFileWithSize(named: "test.log.2", sizeInBytes: 2000)

        // 新しいログファイル（制限超過）
        createFileWithSize(named: "test.log", sizeInBytes: 15 * 1024)

        let rotator = SizeBasedLogRotator(maxFileSize: 10 * 1024, maxRotations: 5)
        let rotated = rotator.rotateIfNeeded(filePath: tempDir + "test.log")

        XCTAssertTrue(rotated)
        XCTAssertFalse(fileExists("test.log"), "元のファイルはリネーム")
        XCTAssertTrue(fileExists("test.log.1"), "新しい.1が作成")
        XCTAssertTrue(fileExists("test.log.2"), "旧.1は.2にシフト")
        XCTAssertTrue(fileExists("test.log.3"), "旧.2は.3にシフト")

        // サイズでシフトを確認
        XCTAssertEqual(getFileSize("test.log.1"), UInt64(15 * 1024), "新しい.1は元のログ")
        XCTAssertEqual(getFileSize("test.log.2"), 1000, ".2は旧.1")
        XCTAssertEqual(getFileSize("test.log.3"), 2000, ".3は旧.2")
    }

    func testRotateDeletesOldestWhenMaxReached() {
        // maxRotations: 3 で、既存の.1, .2, .3を作成
        createFileWithSize(named: "test.log.1", sizeInBytes: 100)
        createFileWithSize(named: "test.log.2", sizeInBytes: 200)
        createFileWithSize(named: "test.log.3", sizeInBytes: 300)

        // 新しいログファイル（制限超過）
        createFileWithSize(named: "test.log", sizeInBytes: 15 * 1024)

        let rotator = SizeBasedLogRotator(maxFileSize: 10 * 1024, maxRotations: 3)
        let rotated = rotator.rotateIfNeeded(filePath: tempDir + "test.log")

        XCTAssertTrue(rotated)
        XCTAssertTrue(fileExists("test.log.1"), ".1は存在")
        XCTAssertTrue(fileExists("test.log.2"), ".2は存在")
        XCTAssertTrue(fileExists("test.log.3"), ".3は存在")
        XCTAssertFalse(fileExists("test.log.4"), ".4は作成されない（max=3）")

        // 古い.3は削除され、新しいチェーンになる
        XCTAssertEqual(getFileSize("test.log.1"), UInt64(15 * 1024), ".1は元のログ")
        XCTAssertEqual(getFileSize("test.log.2"), 100, ".2は旧.1")
        XCTAssertEqual(getFileSize("test.log.3"), 200, ".3は旧.2（旧.3は削除）")
    }

    func testRotateIfNeededWithNonExistentFile() {
        let rotator = SizeBasedLogRotator(maxFileSize: 10 * 1024, maxRotations: 5)
        let rotated = rotator.rotateIfNeeded(filePath: tempDir + "nonexistent.log")

        XCTAssertFalse(rotated, "存在しないファイルはローテーションしない")
    }

    // MARK: - Utility Tests

    func testGetRotatedFilesReturnsExistingFiles() {
        createFileWithSize(named: "test.log", sizeInBytes: 100)
        createFileWithSize(named: "test.log.1", sizeInBytes: 100)
        createFileWithSize(named: "test.log.2", sizeInBytes: 100)
        // .3は作成しない（欠番）
        createFileWithSize(named: "test.log.4", sizeInBytes: 100)

        let rotator = SizeBasedLogRotator(maxFileSize: 10 * 1024, maxRotations: 10)
        let files = rotator.getRotatedFiles(basePath: tempDir + "test.log")

        XCTAssertEqual(files.count, 3, ".1, .2, .4が存在")
        XCTAssertTrue(files.contains(tempDir + "test.log.1"))
        XCTAssertTrue(files.contains(tempDir + "test.log.2"))
        XCTAssertTrue(files.contains(tempDir + "test.log.4"))
    }

    func testGetTotalSizeIncludesAllFiles() {
        createFileWithSize(named: "test.log", sizeInBytes: 1000)
        createFileWithSize(named: "test.log.1", sizeInBytes: 2000)
        createFileWithSize(named: "test.log.2", sizeInBytes: 3000)

        let rotator = SizeBasedLogRotator(maxFileSize: 10 * 1024, maxRotations: 10)
        let totalSize = rotator.getTotalSize(basePath: tempDir + "test.log")

        XCTAssertEqual(totalSize, 6000, "合計サイズは6000バイト")
    }

    // MARK: - Default Values Tests

    func testDefaultMaxFileSize() {
        XCTAssertEqual(SizeBasedLogRotator.defaultMaxFileSize, 50 * 1024 * 1024, "デフォルトは50MB")
    }

    func testDefaultMaxRotations() {
        XCTAssertEqual(SizeBasedLogRotator.defaultMaxRotations, 10, "デフォルトは10ファイル")
    }

    // MARK: - LogRotationConfig Size Tests

    func testLogRotationConfigDefaultSizeValues() {
        let config = LogRotationConfig.default

        XCTAssertEqual(config.maxFileSize, 50 * 1024 * 1024, "デフォルトは50MB")
        XCTAssertEqual(config.maxRotations, 10, "デフォルトは10ファイル")
    }

    func testLogRotationConfigFromEnvironmentWithSizeValue() {
        setenv("MCP_LOG_MAX_FILE_SIZE_MB", "100", 1)
        setenv("MCP_LOG_MAX_ROTATIONS", "5", 1)
        defer {
            unsetenv("MCP_LOG_MAX_FILE_SIZE_MB")
            unsetenv("MCP_LOG_MAX_ROTATIONS")
        }

        let config = LogRotationConfig.fromEnvironment()

        XCTAssertEqual(config.maxFileSize, 100 * 1024 * 1024, "100MBに設定")
        XCTAssertEqual(config.maxRotations, 5, "5ファイルに設定")
    }

    func testLogRotationConfigFromEnvironmentWithInvalidSizeValue() {
        setenv("MCP_LOG_MAX_FILE_SIZE_MB", "invalid", 1)
        setenv("MCP_LOG_MAX_ROTATIONS", "-1", 1)
        defer {
            unsetenv("MCP_LOG_MAX_FILE_SIZE_MB")
            unsetenv("MCP_LOG_MAX_ROTATIONS")
        }

        let config = LogRotationConfig.fromEnvironment()

        XCTAssertEqual(config.maxFileSize, 50 * 1024 * 1024, "無効値はデフォルト")
        XCTAssertEqual(config.maxRotations, 10, "無効値はデフォルト")
    }
}
