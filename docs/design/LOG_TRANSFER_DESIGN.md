# ログ転送方式 詳細設計

## 概要

マルチデバイス環境において、各Coordinatorで生成された実行ログを中央サーバーに転送し、プロジェクトワーキングディレクトリ基準で一元管理する仕組みの設計。

## 背景・課題

### 現状の問題

```
┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
│ Device A            │     │ Device B            │     │ Central Server      │
│ (Coordinator)       │     │ (Coordinator)       │     │ (App + DB + UI)     │
├─────────────────────┤     ├─────────────────────┤     ├─────────────────────┤
│ ログ出力先:          │     │ ログ出力先:          │     │ DB登録パス:          │
│ /home/a/proj/       │     │ /home/b/proj/       │     │ /home/a/proj/...    │
│  .aiagent/logs/...  │     │  .aiagent/logs/...  │     │ /home/b/proj/...    │
│                     │     │                     │     │                     │
│ (ローカルに存在)     │     │ (ローカルに存在)     │     │ (アクセス不可!)      │
└─────────────────────┘     └─────────────────────┘     └─────────────────────┘
```

1. 各Coordinatorはローカルパスにログを保存
2. そのローカルパスがDBに登録される
3. 中央サーバー（UI）からログファイルにアクセスできない

### 解決方針

**ログ転送方式（Push型）**: Coordinatorがログファイルを中央サーバーにアップロードし、サーバーがプロジェクトワーキングディレクトリ配下に保存。

---

## アーキテクチャ

### 全体フロー

```
┌─────────────────────┐                    ┌─────────────────────────────────┐
│ Coordinator         │                    │ Central Server                  │
│ (任意のデバイス)     │                    │                                 │
├─────────────────────┤                    ├─────────────────────────────────┤
│                     │                    │                                 │
│ 1. エージェント実行  │                    │                                 │
│    ↓                │                    │                                 │
│ 2. ログを一時保存    │                    │                                 │
│    /tmp/aiagent/    │                    │                                 │
│    {execution_id}.log                    │                                 │
│    ↓                │                    │                                 │
│ 3. 実行完了検知      │                    │                                 │
│    (poll() → exit)  │                    │                                 │
│    ↓                │                    │                                 │
│ 4. ログファイル      │                    │                                 │
│    クローズ          │                    │                                 │
│    ↓                │                    │                                 │
│ 5. 非同期アップロード │     HTTP POST      │                                 │
│    開始（即時復帰）  │ ─────────────────→ │ 6. ログ受信                     │
│    ↓                │   multipart/form   │    ↓                            │
│ 6. 次タスク割当可能  │                    │ 7. プロジェクトWD配下に保存      │
│                     │ ←───────────────── │    {project.workingDirectory}/  │
│    (バックグラウンド) │   保存パスを返却    │    .ai-pm/logs/{agent_id}/      │
│ 7. 一時ファイル削除  │                    │    {timestamp}.log              │
│                     │                    │    ↓                            │
│                     │                    │ 8. ExecutionLog.logFilePath更新 │
└─────────────────────┘                    └─────────────────────────────────┘
```

### タイミング管理（非同期アップロード）

#### ログ書き込み完了の検知

Coordinatorがログファイルハンドルを所有しているため、確実に完了を検知できる:

```
Coordinator                          Agent Process
    |                                      |
    |-- log_f = open("file.log") -------->|
    |-- Popen(stdout=log_f) ------------->| プロセス起動
    |                                      |
    |   (polling loop)                     | 実行中...stdout出力
    |   poll() → None                      |
    |   poll() → None                      |
    |   poll() → exit_code  ←-- プロセス終了
    |                                      |
    |-- log_f.close() ------------------->| ← 書き込み完了確定
    |                                      |
    |-- asyncio.create_task(upload) ----->| 非同期アップロード開始
    |                                      |
    |-- (即座に次の処理へ)                  |
```

#### 非同期アップロードフロー

```python
# _cleanup_finished() 内の処理フロー
for key, info in self._instances.items():
    retcode = info.process.poll()
    if retcode is not None:
        # 1. ログファイルをクローズ（書き込み完了を保証）
        info.log_file_handle.close()

        # 2. 非同期アップロードを開始（ブロックしない）
        asyncio.create_task(
            self._upload_log_async(key, info)
        )

        # 3. インスタンス情報はキューに追加後、即座に削除
        #    → 次のタスク割り当てを妨げない
```

#### タイムライン比較

**同期方式（採用しない）**:
```
プロセス終了 → アップロード(30秒) → 次タスク割当
              ^^^^^^^^^^^^^^^^
              この間ブロック
```

**非同期方式（採用）**:
```
プロセス終了 → 次タスク割当（即時）
           ↘
            アップロード(バックグラウンド)
```

#### 非同期アップロードの状態管理

アップロード中のログを追跡するための軽量キュー:

```python
@dataclass
class PendingLogUpload:
    """アップロード待ちログの情報"""
    log_file_path: str
    execution_log_id: str
    agent_id: str
    task_id: str
    project_id: str
    created_at: datetime
    retry_count: int = 0

class Coordinator:
    def __init__(self, ...):
        # 進行中のアップロードを追跡（メモリ内）
        self._pending_uploads: dict[str, PendingLogUpload] = {}
```

#### 失敗時のリカバリ

```
アップロード開始
    ↓
[成功] → pending_uploadsから削除 → 一時ファイル削除
    ↓
[失敗] → retry_count++
    ↓
[retry_count < max] → 再試行キューに追加
    ↓
[retry_count >= max] → ローカルパスをDB登録（フォールバック）
                      → pending_uploadsから削除
                      → 一時ファイルは保持
```

### ディレクトリ構造

**サーバー側（保存先）**:
```
{project.workingDirectory}/
└── .ai-pm/
    ├── .gitignore
    ├── agents/
    │   └── {agent_id}/
    │       └── chat.jsonl          # 既存: チャットログ
    └── logs/                        # 新規: 実行ログ
        └── {agent_id}/
            ├── 20260125_143022.log
            ├── 20260125_150135.log
            └── ...
```

**Coordinator側（一時保存）**:
```
/tmp/aiagent-coordinator/
└── {execution_log_id}.log          # アップロード後に削除
```

---

## API設計

### エンドポイント

#### POST /api/v1/execution-logs/upload

実行ログファイルをアップロードし、プロジェクトワーキングディレクトリに保存する。

**認証**: Coordinator Token（Bearer認証）

**Request**:
```
Content-Type: multipart/form-data

Fields:
- execution_log_id: string (required) - ExecutionLogのID
- agent_id: string (required) - エージェントID
- task_id: string (required) - タスクID
- project_id: string (required) - プロジェクトID
- log_file: file (required) - ログファイル（.log）
- original_filename: string (optional) - 元のファイル名（タイムスタンプ等）
```

**Response (200 OK)**:
```json
{
  "success": true,
  "execution_log_id": "exec_xxx",
  "log_file_path": "/path/to/project/.ai-pm/logs/agent_id/20260125_143022.log",
  "file_size": 12345
}
```

**Response (400 Bad Request)**:
```json
{
  "success": false,
  "error": "Missing required field: execution_log_id"
}
```

**Response (404 Not Found)**:
```json
{
  "success": false,
  "error": "Project working directory not configured"
}
```

**Response (413 Payload Too Large)**:
```json
{
  "success": false,
  "error": "Log file exceeds maximum size (10MB)"
}
```

### 認証

既存のCoordinator Token認証を使用:

```
Authorization: Bearer {coordinator_token}
```

- `coordinator_token` は `coordinator.yaml` および `AppSettings` で管理
- 既存のMCP HTTP Transport認証と同じ仕組み

---

## データモデル変更

### ExecutionLog（変更なし）

既存の `logFilePath` フィールドをそのまま使用。サーバー側で保存したパスを格納。

```swift
public struct ExecutionLog {
    // ... 既存フィールド ...
    public private(set) var logFilePath: String?  // サーバー側の絶対パス
}
```

### 設定（coordinator.yaml）

```yaml
# 既存設定
mcp_socket_path: http://192.168.11.10:8080/mcp
coordinator_token: xxx

# 新規設定
log_upload:
  enabled: true                                    # ログアップロード有効化
  endpoint: http://192.168.11.10:8080/api/v1/execution-logs/upload
  max_file_size_mb: 10                             # 最大ファイルサイズ
  retry_count: 3                                   # リトライ回数
  retry_delay_seconds: 5                           # リトライ間隔
```

---

## 実装詳細

### サーバー側（Swift）

#### 1. ログアップロードハンドラ

**ファイル**: `Sources/RESTServer/RESTServer.swift`

```swift
// MARK: - Execution Log Upload

/// POST /api/v1/execution-logs/upload
/// Coordinatorからのログファイルアップロードを受け付け、プロジェクトWD配下に保存
private func handleLogUpload(request: Request, context: Context) async throws -> Response {
    // 1. Coordinator Token認証
    guard let authHeader = request.headers[.authorization].first,
          authHeader.hasPrefix("Bearer ") else {
        return errorResponse(status: .unauthorized, message: "Missing authorization")
    }
    let token = String(authHeader.dropFirst(7))
    let settings = try appSettingsRepository.get()
    guard token == settings.coordinatorToken else {
        return errorResponse(status: .unauthorized, message: "Invalid coordinator token")
    }

    // 2. multipart/form-dataパース
    let formData = try await request.decodeMultipartFormData()
    guard let executionLogId = formData.getString("execution_log_id"),
          let agentId = formData.getString("agent_id"),
          let taskId = formData.getString("task_id"),
          let projectId = formData.getString("project_id"),
          let logFileData = formData.getFile("log_file") else {
        return errorResponse(status: .badRequest, message: "Missing required fields")
    }

    // 3. プロジェクトワーキングディレクトリ取得
    guard let project = try projectRepository.findById(ProjectID(value: projectId)),
          let workingDir = project.workingDirectory else {
        return errorResponse(status: .notFound, message: "Project working directory not configured")
    }

    // 4. 保存先ディレクトリ作成
    let logDir = try directoryManager.getOrCreateLogDirectory(
        workingDirectory: workingDir,
        agentId: AgentID(value: agentId)
    )

    // 5. ファイル名決定（元のファイル名 or タイムスタンプ）
    let filename = formData.getString("original_filename")
        ?? "\(ISO8601DateFormatter().string(from: Date())).log"
    let logFilePath = logDir.appendingPathComponent(filename)

    // 6. ファイル保存
    try logFileData.write(to: logFilePath)

    // 7. ExecutionLog更新
    if var log = try executionLogRepository.findById(ExecutionLogID(value: executionLogId)) {
        log.setLogFilePath(logFilePath.path)
        try executionLogRepository.save(log)
    }

    // 8. レスポンス
    return jsonResponse([
        "success": true,
        "execution_log_id": executionLogId,
        "log_file_path": logFilePath.path,
        "file_size": logFileData.count
    ])
}
```

#### 2. ProjectDirectoryManager拡張

**ファイル**: `Sources/Infrastructure/FileStorage/ProjectDirectoryManager.swift`

```swift
/// 実行ログディレクトリを取得（なければ作成）
/// - Parameters:
///   - workingDirectory: プロジェクトの作業ディレクトリ
///   - agentId: エージェントID
/// - Returns: ログディレクトリのURL
public func getOrCreateLogDirectory(workingDirectory: String?, agentId: AgentID) throws -> URL {
    let appDirURL = try getOrCreateAppDirectory(workingDirectory: workingDirectory)
    let logsDirURL = appDirURL.appendingPathComponent("logs")
    try createDirectoryIfNeeded(at: logsDirURL)
    let agentLogDirURL = logsDirURL.appendingPathComponent(agentId.value)
    try createDirectoryIfNeeded(at: agentLogDirURL)
    return agentLogDirURL
}
```

#### 3. .gitignore更新

```swift
private static let gitignoreContent = """
    # AI Agent PM - auto-generated
    chat.jsonl
    context.md
    logs/
    """
```

### Coordinator側（Python）

#### 1. 設定モデル拡張

**ファイル**: `runner/src/aiagent_runner/coordinator_config.py`

```python
@dataclass
class LogUploadConfig:
    """Log upload configuration."""
    enabled: bool = False
    endpoint: Optional[str] = None
    max_file_size_mb: int = 10
    retry_count: int = 3
    retry_delay_seconds: int = 5

@dataclass
class CoordinatorConfig:
    # ... 既存フィールド ...
    log_upload: Optional[LogUploadConfig] = None
```

#### 2. ログアップロードクライアント

**ファイル**: `runner/src/aiagent_runner/log_uploader.py`（新規）

```python
import aiohttp
import asyncio
from pathlib import Path
from typing import Optional
import logging

logger = logging.getLogger(__name__)

class LogUploader:
    """Handles uploading execution logs to central server."""

    def __init__(self, config: LogUploadConfig, coordinator_token: str):
        self.config = config
        self.coordinator_token = coordinator_token

    async def upload(
        self,
        log_file_path: str,
        execution_log_id: str,
        agent_id: str,
        task_id: str,
        project_id: str
    ) -> Optional[str]:
        """
        Upload log file to central server.

        Returns:
            Server-side log file path if successful, None otherwise.
        """
        if not self.config.enabled or not self.config.endpoint:
            logger.debug("Log upload disabled or endpoint not configured")
            return None

        log_path = Path(log_file_path)
        if not log_path.exists():
            logger.warning(f"Log file not found: {log_file_path}")
            return None

        # Check file size
        file_size_mb = log_path.stat().st_size / (1024 * 1024)
        if file_size_mb > self.config.max_file_size_mb:
            logger.warning(
                f"Log file too large ({file_size_mb:.2f}MB > {self.config.max_file_size_mb}MB)"
            )
            return None

        # Retry loop
        for attempt in range(self.config.retry_count):
            try:
                result = await self._do_upload(
                    log_path, execution_log_id, agent_id, task_id, project_id
                )
                if result:
                    return result
            except Exception as e:
                logger.warning(f"Upload attempt {attempt + 1} failed: {e}")
                if attempt < self.config.retry_count - 1:
                    await asyncio.sleep(self.config.retry_delay_seconds)

        logger.error(f"Failed to upload log after {self.config.retry_count} attempts")
        return None

    async def _do_upload(
        self,
        log_path: Path,
        execution_log_id: str,
        agent_id: str,
        task_id: str,
        project_id: str
    ) -> Optional[str]:
        """Perform the actual upload."""
        headers = {"Authorization": f"Bearer {self.coordinator_token}"}

        async with aiohttp.ClientSession() as session:
            data = aiohttp.FormData()
            data.add_field("execution_log_id", execution_log_id)
            data.add_field("agent_id", agent_id)
            data.add_field("task_id", task_id)
            data.add_field("project_id", project_id)
            data.add_field("original_filename", log_path.name)
            data.add_field(
                "log_file",
                open(log_path, "rb"),
                filename=log_path.name,
                content_type="text/plain"
            )

            async with session.post(
                self.config.endpoint,
                headers=headers,
                data=data
            ) as response:
                if response.status == 200:
                    result = await response.json()
                    logger.info(f"Log uploaded: {result.get('log_file_path')}")
                    return result.get("log_file_path")
                else:
                    error = await response.text()
                    logger.warning(f"Upload failed ({response.status}): {error}")
                    return None
```

#### 3. Coordinator変更（非同期アップロード対応）

**ファイル**: `runner/src/aiagent_runner/coordinator.py`

```python
@dataclass
class PendingLogUpload:
    """アップロード待ちログの情報"""
    log_file_path: str
    execution_log_id: str
    agent_id: str
    task_id: str
    project_id: str
    created_at: datetime
    retry_count: int = 0


class Coordinator:
    def __init__(self, config: CoordinatorConfig):
        # ... 既存の初期化 ...

        # ログアップローダー初期化
        self.log_uploader: Optional[LogUploader] = None
        if config.log_upload and config.log_upload.enabled:
            self.log_uploader = LogUploader(
                config.log_upload,
                config.coordinator_token
            )

        # 進行中のアップロードを追跡
        self._pending_uploads: dict[str, asyncio.Task] = {}

    def _get_log_directory(self, working_dir: Optional[str], agent_id: str) -> Path:
        """Get log directory for an agent."""
        if self.log_uploader:
            # アップロードモード: 一時ディレクトリを使用
            log_dir = Path(tempfile.gettempdir()) / "aiagent-coordinator" / "logs"
        elif working_dir:
            # 従来モード: プロジェクトワーキングディレクトリ基準
            log_dir = Path(working_dir) / ".aiagent" / "logs" / agent_id
        else:
            # フォールバック
            log_dir = get_data_directory() / "agent_logs" / agent_id

        log_dir.mkdir(parents=True, exist_ok=True)
        return log_dir

    def _cleanup_finished(self) -> list[tuple[AgentInstanceKey, AgentInstanceInfo, int]]:
        """Clean up finished processes and start async log uploads."""
        finished = []
        for key, info in self._instances.items():
            retcode = info.process.poll()
            if retcode is not None:
                # 1. ログファイルをクローズ（書き込み完了を保証）
                if info.log_file_handle:
                    info.log_file_handle.close()

                # 2. 非同期アップロードを開始（ブロックしない）
                if self.log_uploader and info.log_file_path and info.task_id:
                    upload_info = PendingLogUpload(
                        log_file_path=info.log_file_path,
                        execution_log_id=info.execution_log_id,
                        agent_id=key.agent_id,
                        task_id=info.task_id,
                        project_id=key.project_id,
                        created_at=datetime.now()
                    )
                    task = asyncio.create_task(
                        self._upload_log_async(upload_info)
                    )
                    self._pending_uploads[info.execution_log_id] = task

                # 3. 終了リストに追加（即座に次タスク割当可能）
                finished.append((key, info, retcode))

        # インスタンス削除
        for key, _, _ in finished:
            del self._instances[key]

        return finished

    async def _upload_log_async(self, upload_info: PendingLogUpload) -> None:
        """バックグラウンドでログをアップロード"""
        try:
            server_log_path = await self.log_uploader.upload(
                log_file_path=upload_info.log_file_path,
                execution_log_id=upload_info.execution_log_id,
                agent_id=upload_info.agent_id,
                task_id=upload_info.task_id,
                project_id=upload_info.project_id
            )

            if server_log_path:
                # 成功: 一時ファイル削除
                try:
                    Path(upload_info.log_file_path).unlink()
                    logger.debug(f"Deleted temp log: {upload_info.log_file_path}")
                except Exception as e:
                    logger.warning(f"Failed to delete temp log: {e}")
            else:
                # 失敗: ローカルパスをDB登録（フォールバック）
                await self._fallback_register_local_path(upload_info)

        except Exception as e:
            logger.error(f"Async log upload failed: {e}")
            await self._fallback_register_local_path(upload_info)

        finally:
            # 追跡から削除
            self._pending_uploads.pop(upload_info.execution_log_id, None)

    async def _fallback_register_local_path(self, upload_info: PendingLogUpload) -> None:
        """アップロード失敗時、ローカルパスをDB登録"""
        logger.warning(
            f"Log upload failed, registering local path: {upload_info.log_file_path}"
        )
        await self.mcp_client.register_execution_log_file(
            agent_id=upload_info.agent_id,
            task_id=upload_info.task_id,
            log_file_path=upload_info.log_file_path
        )
```

---

## エラーハンドリング

### アップロード失敗時のフォールバック

```
アップロード試行
    ↓
[成功] → サーバー側パスをDBに登録、一時ファイル削除
    ↓
[失敗] → リトライ（最大3回）
    ↓
[全リトライ失敗] → ローカルパスをDBに登録（従来の動作）
                   ログ: "Log upload failed, using local path"
```

### ファイルサイズ制限

- デフォルト最大: 10MB
- 超過時: アップロードスキップ、ローカルパスを登録
- サーバー側でも検証（413 Payload Too Large）

### ネットワークエラー

- 接続タイムアウト: 30秒
- リトライ間隔: 5秒（設定可能）
- リトライ回数: 3回（設定可能）

---

## 移行計画

### Phase 1: サーバー側実装

1. `ProjectDirectoryManager` にログディレクトリ管理追加
2. REST APIエンドポイント実装
3. `.gitignore` 更新
4. 単体テスト

### Phase 2: Coordinator側実装

1. `LogUploader` クラス実装
2. `CoordinatorConfig` 拡張
3. `Coordinator` 変更（アップロード統合）
4. 単体テスト

### Phase 3: 統合テスト

1. E2Eテスト（ログ生成→アップロード→参照）
2. フォールバックテスト（アップロード失敗時）
3. パフォーマンステスト（大きなログファイル）

### Phase 4: ドキュメント・設定

1. `coordinator.yaml` サンプル更新
2. セットアップガイド更新
3. トラブルシューティングガイド

---

## セキュリティ考慮事項

1. **認証**: Coordinator Tokenによるアクセス制限
2. **ファイルサイズ制限**: DoS攻撃防止
3. **パス検証**: ディレクトリトラバーサル攻撃防止
4. **ファイルタイプ検証**: .logファイルのみ受け付け
5. **HTTPS推奨**: 本番環境ではTLS必須

---

## 今後の拡張可能性

1. **ログ圧縮**: gzip圧縮によるネットワーク帯域削減
2. **チャンク転送**: 大きなログファイルの分割アップロード
3. **ログローテーション**: 古いログの自動削除
4. **ログ検索API**: サーバー側でのログ内容検索
5. **永続キュー**: Coordinator再起動時のアップロード再開（現在はメモリ内のみ）
