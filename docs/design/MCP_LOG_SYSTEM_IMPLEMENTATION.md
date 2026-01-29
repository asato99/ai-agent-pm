# MCP Log System - テストファースト実装計画

テスト駆動開発（TDD）によるMCPログシステムの実装計画。進捗管理を兼ねる。

**関連ドキュメント**: [MCP_LOG_SYSTEM.md](./MCP_LOG_SYSTEM.md)

---

## 進捗サマリー

| Phase | 内容 | 状態 | 進捗 |
|-------|------|------|------|
| Phase 0 | リファクタリング（Logger基盤） | ✅ 完了 | 10/10 |
| Phase 0.5 | MCPツール呼び出しログ | ✅ 完了 | 4/4 |
| Phase 1 | ログローテーション | ✅ 完了 | 6/6 |
| Phase 2 | 構造化ログ | ✅ 完了 | 5/5 |
| Phase 3 | MCPLogView改善 | 未着手 | 0/6 |

### 完了済み（2026-01-28）
- ✅ 0-1: LogLevel定義
- ✅ 0-2: LogCategory定義
- ✅ 0-3: LogEntry定義
- ✅ 0-4: LogOutputプロトコルと実装
- ✅ 0-5: Loggerクラス（MCPLogger）
- ✅ 0-6: MCPServer.swift の移行（MCPLogger に置き換え）
- ✅ 0-7: Transport層の移行（StdioTransport, NullTransport, UnixSocketTransport）
- ✅ 0-8: RESTServer の移行
- ✅ 0-9: MCPDaemonManager の移行
- ✅ 0-10: MockLogger とテストユーティリティ

### 完了済み（2026-01-29）
- ✅ 0.5-1: LogCategoryに`mcp`追加
- ✅ 0.5-2: LogOutputに出力先別最小レベル追加
- ✅ 0.5-3: MCPServer.executeToolにログ追加
- ✅ 0.5-4: truncateユーティリティ（LogUtils）
- ✅ 1-1: LogRotator基本機能（古いファイル削除）
- ✅ 1-2: 日付別ファイル出力（RotatingFileLogOutput）
- ✅ 1-3: デーモン起動時のローテーション実行（UnixSocketServer.start()）
- ✅ 1-4: 環境変数による設定（MCP_LOG_RETENTION_DAYS）
- ✅ 1-5: FileLogOutputをRotatingFileLogOutputに置き換え
- ✅ 1-6: 既存ログファイルの移行（LogMigrator）
- ✅ 2-1: JSON形式出力（既存のFileLogOutput/RotatingFileLogOutputで対応済み）
- ✅ 2-2: ログレベル環境変数対応（MCP_LOG_LEVEL）
- ✅ 2-3: カテゴリ別ログレベル設定（setCategoryLevel/clearCategoryLevel）
- ✅ 2-4: healthCheckをTRACEレベルに変更
- ✅ 2-5: フォーマット切り替え環境変数（MCP_LOG_FORMAT）

### 実装済みファイル
- `Sources/Infrastructure/Logging/LogLevel.swift`
- `Sources/Infrastructure/Logging/LogCategory.swift`
- `Sources/Infrastructure/Logging/LogEntry.swift`
- `Sources/Infrastructure/Logging/LogOutput.swift`
- `Sources/Infrastructure/Logging/LogUtils.swift`
- `Sources/Infrastructure/Logging/MCPLogger.swift`
- `Sources/Infrastructure/Logging/MockLogger.swift`
- `Sources/Infrastructure/Logging/LogRotator.swift` ← NEW
- `Sources/Infrastructure/Logging/RotatingFileLogOutput.swift` ← NEW
- `Tests/InfrastructureTests/Logging/LogLevelTests.swift`
- `Tests/InfrastructureTests/Logging/LogCategoryTests.swift`
- `Tests/InfrastructureTests/Logging/LogEntryTests.swift`
- `Tests/InfrastructureTests/Logging/LogOutputTests.swift`
- `Tests/InfrastructureTests/Logging/LogUtilsTests.swift`
- `Tests/InfrastructureTests/Logging/LoggerTests.swift`
- `Tests/InfrastructureTests/Logging/MockLoggerTests.swift`
- `Tests/InfrastructureTests/Logging/LogRotatorTests.swift` ← NEW
- `Tests/InfrastructureTests/Logging/RotatingFileLogOutputTests.swift` ← NEW

### 移行済みファイル
- `Sources/MCPServer/MCPServer.swift` - MCPLogger に移行
- `Sources/MCPServer/Transport/Transport.swift` - NullTransport を MCPLogger に移行
- `Sources/MCPServer/Transport/StdioTransport.swift` - MCPLogger に移行
- `Sources/MCPServer/Transport/UnixSocketTransport.swift` - MCPLogger に移行
- `Sources/RESTServer/main.swift` - MCPLogger に移行
- `Sources/App/Core/Services/MCPDaemonManager.swift` - MCPLogger に移行

---

## Phase 0: リファクタリング（Logger基盤）

### 0-1. LogLevel定義

**テスト（RED）**:
```swift
// Tests/InfrastructureTests/Logging/LogLevelTests.swift
func testLogLevelOrdering() {
    XCTAssertTrue(LogLevel.trace < LogLevel.debug)
    XCTAssertTrue(LogLevel.debug < LogLevel.info)
    XCTAssertTrue(LogLevel.info < LogLevel.warn)
    XCTAssertTrue(LogLevel.warn < LogLevel.error)
}

func testLogLevelFromString() {
    XCTAssertEqual(LogLevel(rawString: "trace"), .trace)
    XCTAssertEqual(LogLevel(rawString: "DEBUG"), .debug)
    XCTAssertEqual(LogLevel(rawString: "invalid"), nil)
}
```

**実装（GREEN）**:
- [ ] `Sources/Infrastructure/Logging/LogLevel.swift` 作成
- [ ] テスト実行・成功確認

---

### 0-2. LogCategory定義

**テスト（RED）**:
```swift
// Tests/InfrastructureTests/Logging/LogCategoryTests.swift
func testLogCategoryRawValue() {
    XCTAssertEqual(LogCategory.system.rawValue, "system")
    XCTAssertEqual(LogCategory.health.rawValue, "health")
    XCTAssertEqual(LogCategory.agent.rawValue, "agent")
}

func testAllCategories() {
    // 全カテゴリが定義されていることを確認
    let expected: Set<LogCategory> = [
        .system, .health, .auth, .agent, .task, .chat, .project, .mcp, .transport
    ]
    XCTAssertEqual(Set(LogCategory.allCases), expected)
}
```

**実装（GREEN）**:
- [ ] `Sources/Infrastructure/Logging/LogCategory.swift` 作成
- [ ] テスト実行・成功確認

---

### 0-3. LogEntry定義

**テスト（RED）**:
```swift
// Tests/InfrastructureTests/Logging/LogEntryTests.swift
func testLogEntryCreation() {
    let entry = LogEntry(
        timestamp: Date(),
        level: .info,
        category: .agent,
        message: "Test message"
    )
    XCTAssertEqual(entry.level, .info)
    XCTAssertEqual(entry.category, .agent)
    XCTAssertEqual(entry.message, "Test message")
}

func testLogEntryToJSON() {
    let entry = LogEntry(
        timestamp: Date(timeIntervalSince1970: 0),
        level: .error,
        category: .task,
        message: "Error occurred",
        operation: "completeTask",
        agentId: "agt_123",
        projectId: "prj_456"
    )
    let json = entry.toJSON()
    XCTAssertTrue(json.contains("\"level\":\"ERROR\""))
    XCTAssertTrue(json.contains("\"category\":\"task\""))
    XCTAssertTrue(json.contains("\"agent_id\":\"agt_123\""))
}

func testLogEntryToText() {
    let entry = LogEntry(
        timestamp: Date(timeIntervalSince1970: 0),
        level: .info,
        category: .agent,
        message: "Action determined"
    )
    let text = entry.toText()
    XCTAssertTrue(text.contains("[INFO]"))
    XCTAssertTrue(text.contains("[agent]"))
    XCTAssertTrue(text.contains("Action determined"))
}
```

**実装（GREEN）**:
- [ ] `Sources/Infrastructure/Logging/LogEntry.swift` 作成
- [ ] テスト実行・成功確認

---

### 0-4. LogOutputプロトコルと実装

**テスト（RED）**:
```swift
// Tests/InfrastructureTests/Logging/LogOutputTests.swift
func testStderrLogOutput() {
    // stderrへの出力をキャプチャしてテスト
    let output = StderrLogOutput()
    let entry = LogEntry(timestamp: Date(), level: .info, category: .system, message: "Test")

    // 出力が例外なく完了することを確認
    XCTAssertNoThrow(output.write(entry))
}

func testFileLogOutput() {
    let tempPath = NSTemporaryDirectory() + "test_log_\(UUID().uuidString).log"
    defer { try? FileManager.default.removeItem(atPath: tempPath) }

    let output = FileLogOutput(filePath: tempPath)
    let entry = LogEntry(timestamp: Date(), level: .info, category: .system, message: "Test message")

    output.write(entry)

    let content = try! String(contentsOfFile: tempPath, encoding: .utf8)
    XCTAssertTrue(content.contains("Test message"))
}

func testFileLogOutputAppendsToExisting() {
    let tempPath = NSTemporaryDirectory() + "test_log_\(UUID().uuidString).log"
    defer { try? FileManager.default.removeItem(atPath: tempPath) }

    let output = FileLogOutput(filePath: tempPath)

    output.write(LogEntry(timestamp: Date(), level: .info, category: .system, message: "First"))
    output.write(LogEntry(timestamp: Date(), level: .info, category: .system, message: "Second"))

    let content = try! String(contentsOfFile: tempPath, encoding: .utf8)
    XCTAssertTrue(content.contains("First"))
    XCTAssertTrue(content.contains("Second"))
}
```

**実装（GREEN）**:
- [ ] `Sources/Infrastructure/Logging/LogOutput.swift` 作成（プロトコル）
- [ ] `Sources/Infrastructure/Logging/StderrLogOutput.swift` 作成
- [ ] `Sources/Infrastructure/Logging/FileLogOutput.swift` 作成
- [ ] テスト実行・成功確認

---

### 0-5. Loggerクラス

**テスト（RED）**:
```swift
// Tests/InfrastructureTests/Logging/LoggerTests.swift
class MockLogOutput: LogOutput {
    var entries: [LogEntry] = []
    func write(_ entry: LogEntry) {
        entries.append(entry)
    }
}

func testLoggerWritesToOutput() {
    let mockOutput = MockLogOutput()
    let logger = Logger()
    logger.addOutput(mockOutput)

    logger.info("Test message", category: .system)

    XCTAssertEqual(mockOutput.entries.count, 1)
    XCTAssertEqual(mockOutput.entries[0].message, "Test message")
    XCTAssertEqual(mockOutput.entries[0].level, .info)
}

func testLoggerRespectsMinimumLevel() {
    let mockOutput = MockLogOutput()
    let logger = Logger()
    logger.addOutput(mockOutput)
    logger.setMinimumLevel(.warn)

    logger.debug("Should not appear", category: .system)
    logger.info("Should not appear", category: .system)
    logger.warn("Should appear", category: .system)
    logger.error("Should appear", category: .system)

    XCTAssertEqual(mockOutput.entries.count, 2)
}

func testLoggerWithContextFields() {
    let mockOutput = MockLogOutput()
    let logger = Logger()
    logger.addOutput(mockOutput)

    logger.log(.info, category: .agent, message: "Action",
               operation: "getAgentAction",
               agentId: "agt_123",
               projectId: "prj_456")

    let entry = mockOutput.entries[0]
    XCTAssertEqual(entry.operation, "getAgentAction")
    XCTAssertEqual(entry.agentId, "agt_123")
    XCTAssertEqual(entry.projectId, "prj_456")
}

func testLoggerMultipleOutputs() {
    let output1 = MockLogOutput()
    let output2 = MockLogOutput()
    let logger = Logger()
    logger.addOutput(output1)
    logger.addOutput(output2)

    logger.info("Test", category: .system)

    XCTAssertEqual(output1.entries.count, 1)
    XCTAssertEqual(output2.entries.count, 1)
}
```

**実装（GREEN）**:
- [ ] `Sources/Infrastructure/Logging/Logger.swift` 作成
- [ ] テスト実行・成功確認

---

### 0-6. MCPServer.swift の移行

**テスト（RED）**:
```swift
// 既存のMCPServerテストが引き続き成功することを確認
// + ログ出力が新しいLoggerを経由していることを確認

func testMCPServerUsesLogger() {
    // MCPServerがLoggerを使用していることを間接的に確認
    // （ログファイルの内容がJSON形式になっていることで確認）
}
```

**実装（GREEN）**:
- [ ] `MCPServer.swift` の `Self.log()` を `Logger.shared` に置き換え
- [ ] 既存テスト実行・成功確認
- [ ] 動作確認（手動）

---

### 0-7. Transport層の移行

**実装（GREEN）**:
- [ ] `StdioTransport.swift` の `log()` を `Logger.shared` に置き換え
- [ ] `NullTransport` の `log()` を `Logger.shared` に置き換え
- [ ] `UnixSocketTransport` の `log()` を `Logger.shared` に置き換え
- [ ] 既存テスト実行・成功確認

---

### 0-8. RESTServer の移行

**実装（GREEN）**:
- [ ] `RESTServer/main.swift` のグローバル `log()` を `Logger.shared` に置き換え
- [ ] 動作確認（手動）

---

### 0-9. MCPDaemonManager の移行

**実装（GREEN）**:
- [ ] `MCPDaemonManager.swift` の `debugLog()` を `Logger.shared` に置き換え
- [ ] 既存テスト実行・成功確認

---

### 0-10. MockLogger とテストユーティリティ

**テスト（RED）**:
```swift
// Tests/InfrastructureTests/Logging/MockLoggerTests.swift
func testMockLoggerCapturesLogs() {
    let mockLogger = MockLogger()

    mockLogger.info("Test message", category: .system)

    XCTAssertEqual(mockLogger.logs.count, 1)
    XCTAssertTrue(mockLogger.hasLog(level: .info, containing: "Test"))
}

func testMockLoggerFiltersByLevel() {
    let mockLogger = MockLogger()

    mockLogger.debug("Debug message", category: .system)
    mockLogger.error("Error message", category: .system)

    XCTAssertEqual(mockLogger.logs(level: .error).count, 1)
}
```

**実装（GREEN）**:
- [ ] `Sources/Infrastructure/Logging/MockLogger.swift` 作成（テスト用）
- [ ] テスト実行・成功確認

---

## Phase 0.5: MCPツール呼び出しログ

MCPツールの呼び出しと戻り値を記録する機能を追加。

### 0.5-1. LogCategoryに`mcp`追加

**テスト（RED）**:
```swift
// Tests/InfrastructureTests/Logging/LogCategoryTests.swift
func testMCPCategoryExists() {
    XCTAssertEqual(LogCategory.mcp.rawValue, "mcp")
}

func testAllCategoriesIncludesMCP() {
    XCTAssertTrue(LogCategory.allCases.contains(.mcp))
}
```

**実装（GREEN）**:
- [ ] `Sources/Infrastructure/Logging/LogCategory.swift` に `.mcp` 追加
- [ ] テスト実行・成功確認

---

### 0.5-2. LogOutputに出力先別最小レベル追加

**テスト（RED）**:
```swift
// Tests/InfrastructureTests/Logging/LogOutputTests.swift
func testStderrLogOutputRespectsMinimumLevel() {
    let output = StderrLogOutput(minimumLevel: .warn)

    // INFO レベルはスキップされる
    let infoEntry = LogEntry(timestamp: Date(), level: .info, category: .system, message: "Info")
    XCTAssertFalse(output.shouldWrite(infoEntry))

    // WARN レベルは出力される
    let warnEntry = LogEntry(timestamp: Date(), level: .warn, category: .system, message: "Warn")
    XCTAssertTrue(output.shouldWrite(warnEntry))
}

func testFileLogOutputWritesAllLevels() {
    let output = FileLogOutput(filePath: tempPath)  // minimumLevel = nil

    let traceEntry = LogEntry(timestamp: Date(), level: .trace, category: .system, message: "Trace")
    XCTAssertTrue(output.shouldWrite(traceEntry))
}
```

**実装（GREEN）**:
- [ ] `LogOutput` プロトコルに `minimumLevel` プロパティ追加
- [ ] `StderrLogOutput` に `minimumLevel` パラメータ追加（デフォルト: `.info`）
- [ ] `FileLogOutput` は `minimumLevel = nil`（全レベル記録）
- [ ] テスト実行・成功確認

---

### 0.5-3. MCPServer.executeToolにログ追加

**テスト（RED）**:
```swift
// Tests/MCPServerTests/MCPServerLoggingTests.swift
func testExecuteToolLogsAtDebugLevel() {
    let mockLogger = MockLogger()
    // MCPServerにloggerを注入
    let mcpServer = MCPServer(database: db, logger: mockLogger)

    _ = try mcpServer.executeTool(name: "health_check", arguments: [:], caller: .coordinator)

    // DEBUGレベルでツール呼び出しがログされている
    XCTAssertTrue(mockLogger.hasLog(level: .debug, category: .mcp, containing: "health_check"))
}

func testExecuteToolLogsArgumentsAtTraceLevel() {
    let mockLogger = MockLogger()
    let mcpServer = MCPServer(database: db, logger: mockLogger)

    _ = try mcpServer.executeTool(
        name: "get_agent_action",
        arguments: ["agent_id": "agt_123", "project_id": "prj_456"],
        caller: .coordinator
    )

    // TRACEレベルで引数がログされている
    XCTAssertTrue(mockLogger.hasLog(level: .trace, category: .mcp, containing: "arguments"))
}

func testExecuteToolLogsErrorOnFailure() {
    let mockLogger = MockLogger()
    let mcpServer = MCPServer(database: db, logger: mockLogger)

    XCTAssertThrowsError(try mcpServer.executeTool(
        name: "invalid_tool",
        arguments: [:],
        caller: .coordinator
    ))

    // ERRORレベルでエラーがログされている
    XCTAssertTrue(mockLogger.hasLog(level: .error, category: .mcp))
}
```

**実装（GREEN）**:
- [ ] `MCPServer` に `logger` プロパティ追加（DIまたはデフォルトで `MCPLogger.shared`）
- [ ] `executeTool` の開始時に DEBUG ログ
- [ ] 引数を TRACE ログ（truncate付き）
- [ ] 成功時に DEBUG ログ（実行時間含む）
- [ ] 戻り値を TRACE ログ（truncate付き）
- [ ] エラー時に ERROR ログ
- [ ] テスト実行・成功確認

---

### 0.5-4. truncateユーティリティ

**テスト（RED）**:
```swift
// Tests/InfrastructureTests/Logging/LogUtilsTests.swift
func testTruncateShortString() {
    let result = LogUtils.truncate("short", maxLength: 100)
    XCTAssertEqual(result, "short")
    XCTAssertFalse(result.contains("truncated"))
}

func testTruncateLongString() {
    let longString = String(repeating: "a", count: 3000)
    let result = LogUtils.truncate(longString, maxLength: 2000)
    XCTAssertLessThanOrEqual(result.count, 2100)  // maxLength + マーカー
    XCTAssertTrue(result.contains("...[truncated]"))
}

func testTruncateDictionary() {
    let dict: [String: Any] = ["key": String(repeating: "x", count: 3000)]
    let result = LogUtils.truncate(dict, maxLength: 2000)
    // JSON文字列として切り詰められている
    XCTAssertTrue(result.contains("truncated"))
}
```

**実装（GREEN）**:
- [ ] `Sources/Infrastructure/Logging/LogUtils.swift` 作成
- [ ] `truncate(_:maxLength:)` 関数実装
- [ ] テスト実行・成功確認

---

## Phase 1: ログローテーション

### 1-1. LogRotator基本機能

**テスト（RED）**:
```swift
// Tests/InfrastructureTests/Logging/LogRotatorTests.swift
func testLogRotatorDeletesOldFiles() {
    let tempDir = NSTemporaryDirectory() + "log_test_\(UUID().uuidString)/"
    try! FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    // 古いログファイルを作成（8日前）
    let oldDate = Calendar.current.date(byAdding: .day, value: -8, to: Date())!
    let oldFileName = "mcp-server-\(formatDate(oldDate)).log"
    FileManager.default.createFile(atPath: tempDir + oldFileName, contents: Data())

    // 新しいログファイルを作成（今日）
    let newFileName = "mcp-server-\(formatDate(Date())).log"
    FileManager.default.createFile(atPath: tempDir + newFileName, contents: Data())

    let rotator = LogRotator(directory: tempDir, retentionDays: 7)
    rotator.rotate()

    XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir + oldFileName))
    XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir + newFileName))
}

func testLogRotatorKeepsRecentFiles() {
    let tempDir = NSTemporaryDirectory() + "log_test_\(UUID().uuidString)/"
    try! FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    // 6日前のファイル（保持期間内）
    let recentDate = Calendar.current.date(byAdding: .day, value: -6, to: Date())!
    let recentFileName = "mcp-server-\(formatDate(recentDate)).log"
    FileManager.default.createFile(atPath: tempDir + recentFileName, contents: Data())

    let rotator = LogRotator(directory: tempDir, retentionDays: 7)
    rotator.rotate()

    XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir + recentFileName))
}
```

**実装（GREEN）**:
- [ ] `Sources/Infrastructure/Logging/LogRotator.swift` 作成
- [ ] テスト実行・成功確認

---

### 1-2. 日付別ファイル出力

**テスト（RED）**:
```swift
// Tests/InfrastructureTests/Logging/RotatingFileLogOutputTests.swift
func testRotatingFileLogOutputCreatesDateFile() {
    let tempDir = NSTemporaryDirectory() + "log_test_\(UUID().uuidString)/"
    try! FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let output = RotatingFileLogOutput(directory: tempDir, prefix: "mcp-server")
    let entry = LogEntry(timestamp: Date(), level: .info, category: .system, message: "Test")

    output.write(entry)

    let expectedFileName = "mcp-server-\(formatDate(Date())).log"
    XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir + expectedFileName))
}

func testRotatingFileLogOutputRotatesOnDateChange() {
    // 日付が変わったらファイルを切り替えることをテスト
}
```

**実装（GREEN）**:
- [ ] `Sources/Infrastructure/Logging/RotatingFileLogOutput.swift` 作成
- [ ] テスト実行・成功確認

---

### 1-3. デーモン起動時のローテーション実行

**テスト（RED）**:
```swift
// MCPデーモン起動時にLogRotatorが呼ばれることを確認
func testDaemonStartTriggersLogRotation() {
    // 統合テストとして実装
}
```

**実装（GREEN）**:
- [ ] `UnixSocketServer.start()` でローテーション実行
- [ ] テスト実行・成功確認

---

### 1-4. 環境変数による設定

**テスト（RED）**:
```swift
func testLogRotatorReadsRetentionDaysFromEnvironment() {
    setenv("MCP_LOG_RETENTION_DAYS", "14", 1)
    defer { unsetenv("MCP_LOG_RETENTION_DAYS") }

    let config = LogRotationConfig.fromEnvironment()
    XCTAssertEqual(config.retentionDays, 14)
}
```

**実装（GREEN）**:
- [ ] `LogRotationConfig` に環境変数対応を追加
- [ ] テスト実行・成功確認

---

### 1-5. FileLogOutputをRotatingFileLogOutputに置き換え

**実装（GREEN）**:
- [ ] Logger初期化時にRotatingFileLogOutputを使用
- [ ] 動作確認（手動）

---

### 1-6. 既存ログファイルの移行

**実装（GREEN）**:
- [ ] 初回起動時に既存の `mcp-server.log` を日付付きファイルに移行
- [ ] 動作確認（手動）

---

## Phase 2: 構造化ログ

### 2-1. JSON形式出力

**テスト（RED）**:
```swift
// Tests/InfrastructureTests/Logging/JsonLogOutputTests.swift
func testJsonLogOutputWritesValidJSON() {
    let tempPath = NSTemporaryDirectory() + "test_log_\(UUID().uuidString).log"
    defer { try? FileManager.default.removeItem(atPath: tempPath) }

    let output = JsonLogOutput(filePath: tempPath)
    let entry = LogEntry(
        timestamp: Date(timeIntervalSince1970: 1706400000),
        level: .info,
        category: .agent,
        message: "Test",
        agentId: "agt_123"
    )

    output.write(entry)

    let content = try! String(contentsOfFile: tempPath, encoding: .utf8)
    let json = try! JSONSerialization.jsonObject(with: content.data(using: .utf8)!) as! [String: Any]

    XCTAssertEqual(json["level"] as? String, "INFO")
    XCTAssertEqual(json["category"] as? String, "agent")
    XCTAssertEqual(json["message"] as? String, "Test")
    XCTAssertEqual(json["agent_id"] as? String, "agt_123")
}

func testJsonLogOutputOneEntryPerLine() {
    let tempPath = NSTemporaryDirectory() + "test_log_\(UUID().uuidString).log"
    defer { try? FileManager.default.removeItem(atPath: tempPath) }

    let output = JsonLogOutput(filePath: tempPath)

    output.write(LogEntry(timestamp: Date(), level: .info, category: .system, message: "First"))
    output.write(LogEntry(timestamp: Date(), level: .info, category: .system, message: "Second"))

    let content = try! String(contentsOfFile: tempPath, encoding: .utf8)
    let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

    XCTAssertEqual(lines.count, 2)
    // 各行が有効なJSONであることを確認
    for line in lines {
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: line.data(using: .utf8)!))
    }
}
```

**実装（GREEN）**:
- [ ] `Sources/Infrastructure/Logging/JsonLogOutput.swift` 作成
- [ ] テスト実行・成功確認

---

### 2-2. ログレベル環境変数対応

**テスト（RED）**:
```swift
func testLoggerReadsLevelFromEnvironment() {
    setenv("MCP_LOG_LEVEL", "DEBUG", 1)
    defer { unsetenv("MCP_LOG_LEVEL") }

    let logger = Logger.createFromEnvironment()
    // DEBUGレベルが有効になっていることを確認
}
```

**実装（GREEN）**:
- [ ] `Logger.createFromEnvironment()` メソッド追加
- [ ] テスト実行・成功確認

---

### 2-3. カテゴリ別ログレベル設定

**テスト（RED）**:
```swift
func testLoggerCategorySpecificLevel() {
    let mockOutput = MockLogOutput()
    let logger = Logger()
    logger.addOutput(mockOutput)
    logger.setMinimumLevel(.info)
    logger.setCategoryLevel(.health, level: .warn)  // healthカテゴリはWARN以上のみ

    logger.log(.info, category: .health, message: "Should not appear")
    logger.log(.warn, category: .health, message: "Should appear")
    logger.log(.info, category: .agent, message: "Should appear")

    XCTAssertEqual(mockOutput.entries.count, 2)
}
```

**実装（GREEN）**:
- [ ] `Logger.setCategoryLevel()` メソッド追加
- [ ] テスト実行・成功確認

---

### 2-4. healthCheckをTRACEレベルに変更

**実装（GREEN）**:
- [ ] `MCPServer.swift` の healthCheck ログを `.trace` に変更
- [ ] デフォルトでhealthCheckが出力されないことを確認

---

### 2-5. フォーマット切り替え環境変数

**テスト（RED）**:
```swift
func testLogFormatEnvironmentVariable() {
    setenv("MCP_LOG_FORMAT", "text", 1)
    defer { unsetenv("MCP_LOG_FORMAT") }

    let config = LogConfig.fromEnvironment()
    XCTAssertEqual(config.format, .text)
}
```

**実装（GREEN）**:
- [ ] `MCP_LOG_FORMAT` 環境変数対応
- [ ] テスト実行・成功確認

---

## Phase 3: MCPLogView改善

### 3-1. JSONログのパース対応

**テスト（RED）**:
```swift
// Tests/AppTests/Features/MCPServer/LogParserTests.swift
func testParseJsonLogEntry() {
    let json = """
    {"timestamp":"2026-01-28T09:21:35.123Z","level":"INFO","category":"agent","message":"Test"}
    """

    let entry = LogParser.parse(json)

    XCTAssertNotNil(entry)
    XCTAssertEqual(entry?.level, .info)
    XCTAssertEqual(entry?.category, .agent)
    XCTAssertEqual(entry?.message, "Test")
}

func testParseLegacyLogLine() {
    let line = "[2026-01-28T09:21:35Z] [MCP] Test message"

    let entry = LogParser.parse(line)

    XCTAssertNotNil(entry)
    XCTAssertEqual(entry?.message, "[MCP] Test message")
}
```

**実装（GREEN）**:
- [ ] `Sources/App/Features/MCPServer/LogParser.swift` 作成
- [ ] テスト実行・成功確認

---

### 3-2. フィルタリングViewModel

**テスト（RED）**:
```swift
// Tests/AppTests/Features/MCPServer/MCPLogViewModelTests.swift
func testFilterByLevel() {
    let viewModel = MCPLogViewModel()
    viewModel.setLogs([
        LogEntry(level: .debug, message: "Debug"),
        LogEntry(level: .info, message: "Info"),
        LogEntry(level: .error, message: "Error")
    ])

    viewModel.setLevelFilter([.info, .error])

    XCTAssertEqual(viewModel.filteredLogs.count, 2)
}

func testFilterByCategory() {
    let viewModel = MCPLogViewModel()
    viewModel.setLogs([
        LogEntry(category: .agent, message: "Agent log"),
        LogEntry(category: .task, message: "Task log"),
        LogEntry(category: .health, message: "Health log")
    ])

    viewModel.setCategoryFilter(.agent)

    XCTAssertEqual(viewModel.filteredLogs.count, 1)
    XCTAssertEqual(viewModel.filteredLogs[0].category, .agent)
}

func testFilterByAgentId() {
    let viewModel = MCPLogViewModel()
    viewModel.setLogs([
        LogEntry(agentId: "agt_123", message: "Log 1"),
        LogEntry(agentId: "agt_456", message: "Log 2"),
        LogEntry(agentId: nil, message: "Log 3")
    ])

    viewModel.setAgentIdFilter("agt_123")

    XCTAssertEqual(viewModel.filteredLogs.count, 1)
}
```

**実装（GREEN）**:
- [ ] `Sources/App/Features/MCPServer/MCPLogViewModel.swift` 作成
- [ ] テスト実行・成功確認

---

### 3-3. カテゴリフィルタUI

**実装（GREEN）**:
- [ ] `MCPLogView.swift` にカテゴリドロップダウン追加
- [ ] UIテスト作成・実行

---

### 3-4. ログレベルフィルタUI

**実装（GREEN）**:
- [ ] `MCPLogView.swift` にログレベルチェックボックス追加
- [ ] UIテスト作成・実行

---

### 3-5. 時間範囲フィルタ

**テスト（RED）**:
```swift
func testFilterByTimeRange() {
    let now = Date()
    let viewModel = MCPLogViewModel()
    viewModel.setLogs([
        LogEntry(timestamp: now.addingTimeInterval(-3600), message: "1 hour ago"),
        LogEntry(timestamp: now.addingTimeInterval(-7200), message: "2 hours ago"),
        LogEntry(timestamp: now.addingTimeInterval(-86400), message: "1 day ago")
    ])

    viewModel.setTimeRange(.lastHour)

    XCTAssertEqual(viewModel.filteredLogs.count, 1)
}
```

**実装（GREEN）**:
- [ ] `MCPLogViewModel` に時間範囲フィルタ追加
- [ ] `MCPLogView.swift` に時間範囲ドロップダウン追加
- [ ] テスト実行・成功確認

---

### 3-6. 詳細表示モード

**実装（GREEN）**:
- [ ] ログ行クリックで詳細JSON表示
- [ ] UIテスト作成・実行

---

## 完了基準

### Phase 0 完了基準
- [x] 全テストが成功
- [x] 既存の機能が破壊されていない
- [x] 全てのログ出力がLogger経由になっている

### Phase 0.5 完了基準
- [x] `mcp` カテゴリが追加されている
- [x] 出力先ごとの最小レベル設定が機能する
- [x] `executeTool` がツール呼び出しをログする
- [x] 引数・戻り値がTRACEレベルでログされる
- [x] 大きなデータは切り詰められる

### Phase 1 完了基準
- [ ] 全テストが成功
- [ ] 7日以上前のログが自動削除される
- [ ] 日付別のログファイルが生成される

### Phase 2 完了基準
- [ ] 全テストが成功
- [ ] ログがJSON形式で出力される
- [ ] healthCheckがデフォルトで出力されない
- [ ] 環境変数でログレベル制御可能

### Phase 3 完了基準
- [ ] 全テストが成功
- [ ] カテゴリ・レベル・時間範囲でフィルタ可能
- [ ] JSON/レガシー両形式のログを表示可能

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-01-28 | 初版作成 |
| 2026-01-29 | Phase 0.5（MCPツール呼び出しログ）追加、`mcp`カテゴリ追加、出力先別フィルタリング設計追加 |
| 2026-01-29 | Phase 0.5 実装完了: LogUtils, LogOutput minimumLevel, executeTool ログ追加 |
