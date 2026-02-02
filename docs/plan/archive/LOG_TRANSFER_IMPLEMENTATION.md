# ログ転送機能 TDD実装計画

## 概要

`LOG_TRANSFER_DESIGN.md` に基づく、TDD（テスト駆動開発）による実装計画。

---

## Phase 1: サーバー側実装

### 1.1 ProjectDirectoryManager拡張

#### RED: テストを先に書く

**ファイル**: `Tests/InfrastructureTests/ProjectDirectoryManagerTests.swift`

```swift
final class ProjectDirectoryManagerLogDirectoryTests: XCTestCase {
    var sut: ProjectDirectoryManager!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut = ProjectDirectoryManager()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // TEST 1: ログディレクトリが作成される
    func testGetOrCreateLogDirectory_CreatesDirectory() throws {
        let agentId = AgentID(value: "agt_test123")

        let logDir = try sut.getOrCreateLogDirectory(
            workingDirectory: tempDir.path,
            agentId: agentId
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: logDir.path))
        XCTAssertTrue(logDir.path.contains(".ai-pm/logs/agt_test123"))
    }

    // TEST 2: 既存ディレクトリがあっても正常に動作
    func testGetOrCreateLogDirectory_ExistingDirectory_ReturnsPath() throws {
        let agentId = AgentID(value: "agt_test123")

        // 1回目の呼び出し
        let logDir1 = try sut.getOrCreateLogDirectory(
            workingDirectory: tempDir.path,
            agentId: agentId
        )

        // 2回目の呼び出し（既存）
        let logDir2 = try sut.getOrCreateLogDirectory(
            workingDirectory: tempDir.path,
            agentId: agentId
        )

        XCTAssertEqual(logDir1.path, logDir2.path)
    }

    // TEST 3: workingDirectoryがnilの場合はエラー
    func testGetOrCreateLogDirectory_NilWorkingDirectory_ThrowsError() {
        let agentId = AgentID(value: "agt_test123")

        XCTAssertThrowsError(
            try sut.getOrCreateLogDirectory(workingDirectory: nil, agentId: agentId)
        )
    }
}
```

#### GREEN: 実装

**ファイル**: `Sources/Infrastructure/FileStorage/ProjectDirectoryManager.swift`

```swift
/// 実行ログディレクトリを取得（なければ作成）
public func getOrCreateLogDirectory(
    workingDirectory: String?,
    agentId: AgentID
) throws -> URL {
    guard let workingDir = workingDirectory else {
        throw ProjectDirectoryError.workingDirectoryNotConfigured
    }

    let appDirURL = try getOrCreateAppDirectory(workingDirectory: workingDir)
    let logsDirURL = appDirURL.appendingPathComponent("logs")
    try createDirectoryIfNeeded(at: logsDirURL)
    let agentLogDirURL = logsDirURL.appendingPathComponent(agentId.value)
    try createDirectoryIfNeeded(at: agentLogDirURL)
    return agentLogDirURL
}
```

---

### 1.2 ログアップロードAPIエンドポイント

#### RED: テストを先に書く

**ファイル**: `Tests/RESTServerTests/LogUploadEndpointTests.swift`

```swift
final class LogUploadEndpointTests: XCTestCase {
    var app: Application!
    var projectRepository: MockProjectRepository!
    var executionLogRepository: MockExecutionLogRepository!
    var appSettingsRepository: MockAppSettingsRepository!

    override func setUp() async throws {
        // テスト用のHummingbirdアプリケーションをセットアップ
        app = try await createTestApplication()
        projectRepository = MockProjectRepository()
        executionLogRepository = MockExecutionLogRepository()
        appSettingsRepository = MockAppSettingsRepository()

        // 有効なCoordinator Tokenを設定
        appSettingsRepository.settings = AppSettings(
            coordinatorToken: "valid-token"
        )
    }

    // TEST 1: 正常なアップロード
    func testUploadLog_ValidRequest_ReturnsSuccess() async throws {
        // Arrange
        let project = Project(
            id: ProjectID(value: "proj_123"),
            name: "Test Project",
            workingDirectory: tempDir.path
        )
        projectRepository.projects[project.id] = project

        let logContent = "Test log content\nLine 2\n"

        // Act
        let response = try await app.sendRequest(
            .POST,
            "/api/v1/execution-logs/upload",
            headers: [
                "Authorization": "Bearer valid-token",
                "Content-Type": "multipart/form-data; boundary=----TestBoundary"
            ],
            body: createMultipartBody(
                executionLogId: "exec_123",
                agentId: "agt_456",
                taskId: "task_789",
                projectId: "proj_123",
                logContent: logContent,
                filename: "20260125_143022.log"
            )
        )

        // Assert
        XCTAssertEqual(response.status, .ok)

        let result = try response.decode(LogUploadResponse.self)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.executionLogId, "exec_123")
        XCTAssertTrue(result.logFilePath.contains(".ai-pm/logs/agt_456"))
        XCTAssertTrue(result.logFilePath.hasSuffix("20260125_143022.log"))
    }

    // TEST 2: 認証なし → 401
    func testUploadLog_NoAuth_Returns401() async throws {
        let response = try await app.sendRequest(
            .POST,
            "/api/v1/execution-logs/upload",
            headers: [:],
            body: Data()
        )

        XCTAssertEqual(response.status, .unauthorized)
    }

    // TEST 3: 無効なトークン → 401
    func testUploadLog_InvalidToken_Returns401() async throws {
        let response = try await app.sendRequest(
            .POST,
            "/api/v1/execution-logs/upload",
            headers: ["Authorization": "Bearer invalid-token"],
            body: Data()
        )

        XCTAssertEqual(response.status, .unauthorized)
    }

    // TEST 4: 必須フィールド欠落 → 400
    func testUploadLog_MissingField_Returns400() async throws {
        let response = try await app.sendRequest(
            .POST,
            "/api/v1/execution-logs/upload",
            headers: ["Authorization": "Bearer valid-token"],
            body: createMultipartBody(
                executionLogId: "exec_123",
                agentId: nil,  // 欠落
                taskId: "task_789",
                projectId: "proj_123",
                logContent: "test",
                filename: "test.log"
            )
        )

        XCTAssertEqual(response.status, .badRequest)
    }

    // TEST 5: プロジェクトWDなし → 404
    func testUploadLog_NoWorkingDirectory_Returns404() async throws {
        let project = Project(
            id: ProjectID(value: "proj_123"),
            name: "Test Project",
            workingDirectory: nil  // 未設定
        )
        projectRepository.projects[project.id] = project

        let response = try await app.sendRequest(
            .POST,
            "/api/v1/execution-logs/upload",
            headers: ["Authorization": "Bearer valid-token"],
            body: createMultipartBody(
                executionLogId: "exec_123",
                agentId: "agt_456",
                taskId: "task_789",
                projectId: "proj_123",
                logContent: "test",
                filename: "test.log"
            )
        )

        XCTAssertEqual(response.status, .notFound)
    }

    // TEST 6: ファイルサイズ超過 → 413
    func testUploadLog_FileTooLarge_Returns413() async throws {
        let project = Project(
            id: ProjectID(value: "proj_123"),
            name: "Test Project",
            workingDirectory: tempDir.path
        )
        projectRepository.projects[project.id] = project

        // 11MB のログ（制限は10MB）
        let largeContent = String(repeating: "x", count: 11 * 1024 * 1024)

        let response = try await app.sendRequest(
            .POST,
            "/api/v1/execution-logs/upload",
            headers: ["Authorization": "Bearer valid-token"],
            body: createMultipartBody(
                executionLogId: "exec_123",
                agentId: "agt_456",
                taskId: "task_789",
                projectId: "proj_123",
                logContent: largeContent,
                filename: "large.log"
            )
        )

        XCTAssertEqual(response.status, .payloadTooLarge)
    }

    // TEST 7: ExecutionLogのlogFilePathが更新される
    func testUploadLog_UpdatesExecutionLog() async throws {
        let project = Project(
            id: ProjectID(value: "proj_123"),
            name: "Test Project",
            workingDirectory: tempDir.path
        )
        projectRepository.projects[project.id] = project

        var executionLog = ExecutionLog(
            id: ExecutionLogID(value: "exec_123"),
            taskId: TaskID(value: "task_789"),
            agentId: AgentID(value: "agt_456"),
            status: .completed,
            logFilePath: nil  // 初期状態
        )
        executionLogRepository.logs[executionLog.id] = executionLog

        _ = try await app.sendRequest(
            .POST,
            "/api/v1/execution-logs/upload",
            headers: ["Authorization": "Bearer valid-token"],
            body: createMultipartBody(
                executionLogId: "exec_123",
                agentId: "agt_456",
                taskId: "task_789",
                projectId: "proj_123",
                logContent: "test log",
                filename: "test.log"
            )
        )

        // ExecutionLogが更新されたことを確認
        let updatedLog = executionLogRepository.logs[ExecutionLogID(value: "exec_123")]
        XCTAssertNotNil(updatedLog?.logFilePath)
        XCTAssertTrue(updatedLog!.logFilePath!.contains(".ai-pm/logs"))
    }
}
```

#### GREEN: 実装

**ファイル**: `Sources/RESTServer/RESTServer.swift`

ルーティング追加とハンドラ実装（設計書参照）

---

## Phase 2: Coordinator側実装（Python）

### 2.1 LogUploaderクラス

#### RED: テストを先に書く

**ファイル**: `runner/tests/test_log_uploader.py`

```python
import pytest
import asyncio
from pathlib import Path
from unittest.mock import AsyncMock, patch, MagicMock
from aiagent_runner.log_uploader import LogUploader, LogUploadConfig


class TestLogUploader:
    @pytest.fixture
    def config(self):
        return LogUploadConfig(
            enabled=True,
            endpoint="http://localhost:8080/api/v1/execution-logs/upload",
            max_file_size_mb=10,
            retry_count=3,
            retry_delay_seconds=1
        )

    @pytest.fixture
    def uploader(self, config):
        return LogUploader(config, coordinator_token="test-token")

    # TEST 1: アップロード無効時はNoneを返す
    @pytest.mark.asyncio
    async def test_upload_disabled_returns_none(self):
        config = LogUploadConfig(enabled=False)
        uploader = LogUploader(config, coordinator_token="token")

        result = await uploader.upload(
            log_file_path="/tmp/test.log",
            execution_log_id="exec_123",
            agent_id="agt_456",
            task_id="task_789",
            project_id="proj_123"
        )

        assert result is None

    # TEST 2: ファイルが存在しない場合はNoneを返す
    @pytest.mark.asyncio
    async def test_upload_file_not_found_returns_none(self, uploader):
        result = await uploader.upload(
            log_file_path="/nonexistent/file.log",
            execution_log_id="exec_123",
            agent_id="agt_456",
            task_id="task_789",
            project_id="proj_123"
        )

        assert result is None

    # TEST 3: ファイルサイズ超過時はNoneを返す
    @pytest.mark.asyncio
    async def test_upload_file_too_large_returns_none(self, uploader, tmp_path):
        # 11MB のファイルを作成
        large_file = tmp_path / "large.log"
        large_file.write_bytes(b"x" * (11 * 1024 * 1024))

        result = await uploader.upload(
            log_file_path=str(large_file),
            execution_log_id="exec_123",
            agent_id="agt_456",
            task_id="task_789",
            project_id="proj_123"
        )

        assert result is None

    # TEST 4: 正常なアップロード
    @pytest.mark.asyncio
    async def test_upload_success(self, uploader, tmp_path):
        log_file = tmp_path / "test.log"
        log_file.write_text("test log content")

        with patch("aiohttp.ClientSession") as mock_session:
            mock_response = AsyncMock()
            mock_response.status = 200
            mock_response.json = AsyncMock(return_value={
                "success": True,
                "log_file_path": "/project/.ai-pm/logs/agt_456/test.log"
            })

            mock_session.return_value.__aenter__.return_value.post.return_value.__aenter__.return_value = mock_response

            result = await uploader.upload(
                log_file_path=str(log_file),
                execution_log_id="exec_123",
                agent_id="agt_456",
                task_id="task_789",
                project_id="proj_123"
            )

        assert result == "/project/.ai-pm/logs/agt_456/test.log"

    # TEST 5: リトライ動作
    @pytest.mark.asyncio
    async def test_upload_retries_on_failure(self, uploader, tmp_path):
        log_file = tmp_path / "test.log"
        log_file.write_text("test log content")

        call_count = 0

        async def mock_post(*args, **kwargs):
            nonlocal call_count
            call_count += 1
            if call_count < 3:
                # 最初の2回は失敗
                response = AsyncMock()
                response.status = 500
                response.text = AsyncMock(return_value="Server error")
                return response
            else:
                # 3回目は成功
                response = AsyncMock()
                response.status = 200
                response.json = AsyncMock(return_value={
                    "success": True,
                    "log_file_path": "/project/.ai-pm/logs/test.log"
                })
                return response

        with patch("aiohttp.ClientSession") as mock_session:
            mock_session.return_value.__aenter__.return_value.post = mock_post

            result = await uploader.upload(
                log_file_path=str(log_file),
                execution_log_id="exec_123",
                agent_id="agt_456",
                task_id="task_789",
                project_id="proj_123"
            )

        assert result == "/project/.ai-pm/logs/test.log"
        assert call_count == 3

    # TEST 6: 全リトライ失敗時はNoneを返す
    @pytest.mark.asyncio
    async def test_upload_all_retries_failed_returns_none(self, uploader, tmp_path):
        log_file = tmp_path / "test.log"
        log_file.write_text("test log content")

        with patch("aiohttp.ClientSession") as mock_session:
            mock_response = AsyncMock()
            mock_response.status = 500
            mock_response.text = AsyncMock(return_value="Server error")

            mock_session.return_value.__aenter__.return_value.post.return_value.__aenter__.return_value = mock_response

            result = await uploader.upload(
                log_file_path=str(log_file),
                execution_log_id="exec_123",
                agent_id="agt_456",
                task_id="task_789",
                project_id="proj_123"
            )

        assert result is None
```

#### GREEN: 実装

**ファイル**: `runner/src/aiagent_runner/log_uploader.py`

設計書の実装コード参照

---

### 2.2 Coordinator非同期アップロード統合

#### RED: テストを先に書く

**ファイル**: `runner/tests/test_coordinator_log_upload.py`

```python
import pytest
import asyncio
from unittest.mock import AsyncMock, MagicMock, patch
from pathlib import Path
from datetime import datetime

from aiagent_runner.coordinator import Coordinator, AgentInstanceKey, AgentInstanceInfo


class TestCoordinatorAsyncLogUpload:
    @pytest.fixture
    def coordinator_with_uploader(self, tmp_path):
        """LogUploaderが有効なCoordinatorを作成"""
        config = MagicMock()
        config.log_upload = MagicMock()
        config.log_upload.enabled = True
        config.log_upload.endpoint = "http://localhost:8080/api/v1/execution-logs/upload"
        config.coordinator_token = "test-token"

        coordinator = Coordinator(config)
        coordinator.log_uploader = MagicMock()
        coordinator.mcp_client = AsyncMock()

        return coordinator

    # TEST 1: プロセス完了時に非同期アップロードが開始される
    @pytest.mark.asyncio
    async def test_cleanup_finished_starts_async_upload(self, coordinator_with_uploader, tmp_path):
        coordinator = coordinator_with_uploader

        # ログファイルを作成
        log_file = tmp_path / "test.log"
        log_file.write_text("test content")

        # 終了したプロセスをシミュレート
        mock_process = MagicMock()
        mock_process.poll.return_value = 0  # 終了コード

        mock_log_handle = MagicMock()

        key = AgentInstanceKey("agt_123", "proj_456")
        info = AgentInstanceInfo(
            key=key,
            process=mock_process,
            working_directory="/tmp",
            provider="claude",
            model="opus",
            started_at=datetime.now(),
            log_file_handle=mock_log_handle,
            task_id="task_789",
            log_file_path=str(log_file),
            execution_log_id="exec_001",
            mcp_config_file=None
        )
        coordinator._instances[key] = info

        # cleanup_finished を実行
        finished = coordinator._cleanup_finished()

        # ログファイルハンドルがクローズされた
        mock_log_handle.close.assert_called_once()

        # 非同期タスクが作成された
        assert len(coordinator._pending_uploads) == 1
        assert "exec_001" in coordinator._pending_uploads

        # プロセスがfinishedリストに含まれる
        assert len(finished) == 1
        assert finished[0][0] == key

    # TEST 2: 非同期アップロード成功時、一時ファイルが削除される
    @pytest.mark.asyncio
    async def test_async_upload_success_deletes_temp_file(self, coordinator_with_uploader, tmp_path):
        coordinator = coordinator_with_uploader

        # ログファイルを作成
        log_file = tmp_path / "test.log"
        log_file.write_text("test content")

        # アップロード成功をシミュレート
        coordinator.log_uploader.upload = AsyncMock(
            return_value="/project/.ai-pm/logs/test.log"
        )

        upload_info = MagicMock()
        upload_info.log_file_path = str(log_file)
        upload_info.execution_log_id = "exec_001"
        upload_info.agent_id = "agt_123"
        upload_info.task_id = "task_789"
        upload_info.project_id = "proj_456"

        await coordinator._upload_log_async(upload_info)

        # ファイルが削除された
        assert not log_file.exists()

    # TEST 3: 非同期アップロード失敗時、ローカルパスがDBに登録される
    @pytest.mark.asyncio
    async def test_async_upload_failure_registers_local_path(self, coordinator_with_uploader, tmp_path):
        coordinator = coordinator_with_uploader

        # ログファイルを作成
        log_file = tmp_path / "test.log"
        log_file.write_text("test content")

        # アップロード失敗をシミュレート
        coordinator.log_uploader.upload = AsyncMock(return_value=None)

        upload_info = MagicMock()
        upload_info.log_file_path = str(log_file)
        upload_info.execution_log_id = "exec_001"
        upload_info.agent_id = "agt_123"
        upload_info.task_id = "task_789"
        upload_info.project_id = "proj_456"

        await coordinator._upload_log_async(upload_info)

        # ローカルパスがMCP経由で登録された
        coordinator.mcp_client.register_execution_log_file.assert_called_once_with(
            agent_id="agt_123",
            task_id="task_789",
            log_file_path=str(log_file)
        )

        # ファイルは削除されていない（フォールバック）
        assert log_file.exists()

    # TEST 4: 非同期アップロードが次のタスク割当をブロックしない
    @pytest.mark.asyncio
    async def test_async_upload_does_not_block(self, coordinator_with_uploader, tmp_path):
        coordinator = coordinator_with_uploader

        # 時間のかかるアップロードをシミュレート
        async def slow_upload(*args, **kwargs):
            await asyncio.sleep(5)  # 5秒かかる
            return "/project/.ai-pm/logs/test.log"

        coordinator.log_uploader.upload = slow_upload

        # ログファイルを作成
        log_file = tmp_path / "test.log"
        log_file.write_text("test content")

        mock_process = MagicMock()
        mock_process.poll.return_value = 0

        key = AgentInstanceKey("agt_123", "proj_456")
        info = AgentInstanceInfo(
            key=key,
            process=mock_process,
            working_directory="/tmp",
            provider="claude",
            model="opus",
            started_at=datetime.now(),
            log_file_handle=MagicMock(),
            task_id="task_789",
            log_file_path=str(log_file),
            execution_log_id="exec_001",
            mcp_config_file=None
        )
        coordinator._instances[key] = info

        # 時間計測
        start = asyncio.get_event_loop().time()
        finished = coordinator._cleanup_finished()
        elapsed = asyncio.get_event_loop().time() - start

        # 即座に完了する（5秒待たない）
        assert elapsed < 0.1
        assert len(finished) == 1

        # アップロードはバックグラウンドで進行中
        assert len(coordinator._pending_uploads) == 1
```

#### GREEN: 実装

**ファイル**: `runner/src/aiagent_runner/coordinator.py`

設計書の実装コード参照

---

## Phase 3: 統合テスト（UC001拡張）

**方針**: 新規テストを作成せず、既存のUC001統合テストを拡張してログ転送機能を検証する。

### 3.1 テスト設計

**拡張対象**: `web-ui/e2e/run-uc001-test.sh`

**検証シナリオ**: UC001のタスク完了フローにおいて、Coordinatorが生成したログがプロジェクトの`.ai-pm/logs/{agentId}/`に転送されることを確認。

#### ディレクトリ構成（既存）

UC001テストでは以下のディレクトリが分離されている：

- **Coordinatorログディレクトリ**: `/tmp/coordinator_logs_uc001_webui/`
- **プロジェクトWorkingDirectory**: `/tmp/uc001_webui_work/`

この構成により、マルチデバイス環境をシミュレートできる。

### 3.2 run-uc001-test.sh への変更

#### Step 4: Coordinator設定に `log_upload` セクション追加

```bash
# Step 4: Coordinatorの設定を生成
cat > /tmp/uc001_coordinator.yaml << EOF
polling_interval: 2
max_concurrent: 1
mcp_socket_path: "http://localhost:\${REST_PORT}/mcp"
coordinator_token: "${TEST_TOKEN}"
log_directory: /tmp/coordinator_logs_uc001_webui

# ログ転送設定（新規追加）
log_upload:
  enabled: true
  endpoint: "http://localhost:\${REST_PORT}/api/v1/execution-logs/upload"
  max_file_size_mb: 10
  retry_count: 3
  retry_delay_seconds: 1.0

ai_providers:
  test:
    cli_command: echo
    cli_args: ["Task completed successfully"]

agents:
  \${WORKER_AGENT_ID}:
    passkey: test_passkey
EOF
```

#### Step 8: ログ転送の検証を追加

```bash
# Step 8: 結果を検証（既存）
echo "Step 8: Verifying test results..."

# 既存の検証（タスク完了確認）
COMPLETED_TASKS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tasks WHERE status = 'done';")
if [ "$COMPLETED_TASKS" -lt 1 ]; then
    echo "ERROR: No completed tasks found"
    exit 1
fi

# ====== ログ転送検証（新規追加） ======
echo "Verifying log transfer..."

# 8.1: execution_logsテーブルにlog_file_pathが設定されているか確認
LOG_FILE_PATH=$(sqlite3 "$DB_PATH" "
    SELECT log_file_path
    FROM execution_logs
    WHERE status = 'completed'
    ORDER BY completed_at DESC
    LIMIT 1;
")

if [ -z "$LOG_FILE_PATH" ]; then
    echo "ERROR: No log_file_path found in execution_logs"
    exit 1
fi

# 8.2: パスがプロジェクトの.ai-pm/logs/配下になっているか確認
EXPECTED_PATH_PATTERN="/tmp/uc001_webui_work/.ai-pm/logs/${WORKER_AGENT_ID}/"
if [[ "$LOG_FILE_PATH" != ${EXPECTED_PATH_PATTERN}* ]]; then
    echo "ERROR: log_file_path is not in expected directory"
    echo "  Expected pattern: ${EXPECTED_PATH_PATTERN}*"
    echo "  Actual: $LOG_FILE_PATH"
    exit 1
fi

# 8.3: ファイルが実際に存在するか確認
if [ ! -f "$LOG_FILE_PATH" ]; then
    echo "ERROR: Log file does not exist at: $LOG_FILE_PATH"
    exit 1
fi

# 8.4: ファイル内容が空でないか確認
if [ ! -s "$LOG_FILE_PATH" ]; then
    echo "ERROR: Log file is empty: $LOG_FILE_PATH"
    exit 1
fi

echo "Log transfer verification: PASSED"
echo "  - Log file path: $LOG_FILE_PATH"
echo "  - File size: $(wc -c < "$LOG_FILE_PATH") bytes"
```

### 3.3 Playwrightテストへの変更

**ファイル**: `web-ui/e2e/integration/task-completion.spec.ts`

Playwrightテスト自体の変更は不要。ログ転送はバックグラウンドで実行され、ファイルシステムレベルの検証はシェルスクリプト（Step 8）で実施する。

UIからログファイルパスを確認するテストが必要な場合は、将来的に拡張可能。

---

## 実装順序

### Step 1: サーバー側（Swift）
1. `ProjectDirectoryManagerTests` を書く（RED）
2. `getOrCreateLogDirectory` を実装（GREEN）
3. `LogUploadEndpointTests` を書く（RED）
4. `handleLogUpload` を実装（GREEN）
5. リファクタリング

### Step 2: Coordinator側（Python）
1. `test_log_uploader.py` を書く（RED）
2. `LogUploader` を実装（GREEN）
3. `test_coordinator_log_upload.py` を書く（RED）
4. Coordinator変更を実装（GREEN）
5. リファクタリング

### Step 3: 統合テスト
1. E2Eテストを書く（RED）
2. 全コンポーネントを結合（GREEN）
3. パフォーマンス最適化

---

## チェックリスト

### Phase 1 完了条件
- [ ] `ProjectDirectoryManagerTests` 全テストパス
- [ ] `LogUploadEndpointTests` 全テストパス
- [ ] `.gitignore` に `logs/` 追加

### Phase 2 完了条件
- [ ] `test_log_uploader.py` 全テストパス
- [ ] `test_coordinator_log_upload.py` 全テストパス
- [ ] `coordinator.yaml` サンプル更新

### Phase 3 完了条件
- [ ] `run-uc001-test.sh` Step 4 に `log_upload` 設定追加
- [ ] `run-uc001-test.sh` Step 8 にログ転送検証追加
- [ ] UC001統合テスト実行成功（`./run-uc001-test.sh`）
- [ ] ログファイルがプロジェクトWD配下に存在することを確認
- [ ] ドキュメント更新（本ファイル）
