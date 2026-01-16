# エージェント実行ログ閲覧機能

エージェントが実行時に出力したログを効率的に閲覧するための機能設計。

---

## 背景と目的

### 課題

現状、エージェントがタスクを実行した際の詳細なログを確認する手段がない。

- エージェントがなぜ `blocked` を報告したのか分からない
- タスク実行中に何が起きたのか追跡できない
- 問題発生時の調査が困難

### 目的

エージェントが出力した**実際のログファイル**を、いつ・何のタスクに対するものか把握しやすい形で閲覧できるようにする。

---

## 機能概要

| 項目 | 内容 |
|------|------|
| 対象 | エージェント実行時の stdout/stderr 出力 |
| 単位 | 1回のタスク実行（ExecutionLog）ごと |
| アクセス | エージェント詳細画面 > 実行履歴 |

---

## システム連携設計

### 全体フロー

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│ Coordinator │    │   Agent     │    │ MCPServer   │    │     DB      │
│  (Python)   │    │ (Claude等)  │    │  (Swift)    │    │   (SQLite)  │
└──────┬──────┘    └──────┬──────┘    └──────┬──────┘    └──────┬──────┘
       │                  │                  │                  │
       │ ① spawn process  │                  │                  │
       │    stdout→log_file                  │                  │
       │─────────────────>│                  │                  │
       │                  │                  │                  │
       │                  │ ② get_my_task    │                  │
       │                  │─────────────────>│ ExecutionLog作成 │
       │                  │                  │─────────────────>│
       │                  │                  │  (logFilePath=NULL)
       │                  │                  │                  │
       │                  │ ③ タスク実行      │                  │
       │                  │    stdout/stderr │                  │
       │<- - - - - - - - -│    →log_file    │                  │
       │                  │                  │                  │
       │                  │ ④ report_completed                  │
       │                  │─────────────────>│                  │
       │                  │                  │                  │
       │ ⑤ process終了検知 │                  │                  │
       │                  │                  │                  │
       │ ⑥ register_execution_log_file       │                  │
       │────────────────────────────────────>│ logFilePath保存  │
       │                  │                  │─────────────────>│
       │                  │                  │                  │
       │ ⑦ invalidate_session                │                  │
       │────────────────────────────────────>│                  │
       │                  │                  │                  │
```

### Coordinator側の処理

#### ログファイル保存場所

プロジェクトのワーキングディレクトリを基準にする。

```
{project.working_directory}/.aiagent/logs/{agent_id}/
  └── {timestamp}.log
```

例:
```
/Users/dev/my-project/.aiagent/logs/
  └── agt_worker01/
      ├── 20260116_005934.log
      ├── 20260116_003000.log
      └── 20260115_230000.log
```

**フォールバック**: ワーキングディレクトリ未設定時
```
~/Library/Application Support/AIAgentPM/agent_logs/{agent_id}/
  └── {timestamp}.log
```

#### 実装変更（coordinator.py）

```python
def _get_log_directory(self, working_dir: Optional[str], agent_id: str) -> Path:
    """Get log directory for an agent.

    Args:
        working_dir: Project working directory (None if not set)
        agent_id: Agent ID

    Returns:
        Path to log directory
    """
    if working_dir:
        # プロジェクトのワーキングディレクトリ基準
        log_dir = Path(working_dir) / ".aiagent" / "logs" / agent_id
    else:
        # フォールバック: アプリ管轄ディレクトリ
        log_dir = (
            Path.home()
            / "Library" / "Application Support" / "AIAgentPM"
            / "agent_logs" / agent_id
        )

    log_dir.mkdir(parents=True, exist_ok=True)
    return log_dir

def _spawn_instance(self, ..., working_dir: str, ...):
    # ログファイルパス生成
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_dir = self._get_log_directory(working_dir, agent_id)
    log_file = log_dir / f"{timestamp}.log"

    # プロセス起動（stdout/stderrをログファイルにリダイレクト）
    log_f = open(log_file, "w")
    process = subprocess.Popen(
        cmd,
        cwd=working_dir,
        stdout=log_f,
        stderr=subprocess.STDOUT,
        ...
    )
```

#### ワーキングディレクトリの取得

Coordinatorは `list_active_projects_with_agents` MCPツールからワーキングディレクトリを取得済み。

```python
projects = await self.mcp_client.list_active_projects_with_agents()
# project.working_directory が含まれる
```

### App側の処理

#### ExecutionLogへのパス登録

Coordinatorがプロセス終了後に `register_execution_log_file` MCPツールを呼び出す。

```python
# coordinator.py - _cleanup_finished() 内
await self.mcp_client.register_execution_log_file(
    agent_id=key.agent_id,
    task_id=info.task_id,
    log_file_path=str(info.log_file_path)
)
```

#### MCPツール（既存）

```swift
// MCPServer.swift
private func registerExecutionLogFile(agentId: String, taskId: String, logFilePath: String) throws -> [String: Any] {
    // 最新のExecutionLogを取得
    guard var log = try executionLogRepository.findLatestByAgentAndTask(agentId: agId, taskId: tId) else {
        return ["success": false, "error": "execution_log_not_found"]
    }

    // ログファイルパスを設定して保存
    log.setLogFilePath(logFilePath)
    try executionLogRepository.save(log)

    return ["success": true, ...]
}
```

---

## UI設計

### エージェント詳細画面 > 実行履歴タブ

```
┌─────────────────────────────────────────────────────┐
│ Agent: worker01                                      │
│ Role: 開発担当  Status: ● Active                    │
├─────────────────────────────────────────────────────┤
│ [プロファイル] [実行履歴]                              │
├─────────────────────────────────────────────────────┤
│                                                      │
│ ┌─ フィルタ ─────────────────────────────────────┐  │
│ │ プロジェクト: [All ▼]  結果: [All ▼]            │  │
│ └───────────────────────────────────────────────┘  │
│                                                      │
│ ┌─ 実行履歴 ────────────────────────────────────┐  │
│ │                                                │  │
│ │ ▼ 2026-01-16 00:59:34 - 01:00:02 (28秒)       │  │
│ │   プロジェクト: Project A                      │  │
│ │   タスク: tsk_95a81277 ユーザー認証機能の実装    │  │
│ │   結果: ⚠️ blocked                            │  │
│ │   [ログを開く]                                  │  │
│ │                                                │  │
│ │ ▶ 2026-01-16 00:30:00 - 00:45:12 (15分)       │  │
│ │   プロジェクト: Project A                      │  │
│ │   タスク: tsk_62bcea1c API設計                  │  │
│ │   結果: ✅ success                             │  │
│ │   [ログを開く]                                  │  │
│ │                                                │  │
│ │ ▶ 2026-01-15 23:00:00 - 23:42:18 (42分)       │  │
│ │   プロジェクト: Project B                      │  │
│ │   タスク: tsk_a04e4203 DB設計                  │  │
│ │   結果: ✅ success                             │  │
│ │   [ログを開く]                                  │  │
│ │                                                │  │
│ └────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

### 実行履歴の表示項目

| 項目 | 説明 |
|------|------|
| 実行期間 | 開始日時 - 終了日時（所要時間） |
| プロジェクト | 対象プロジェクト名 |
| タスク | タスクID + タイトル |
| 結果 | success / failed / blocked |
| ログを開く | ログビューアを開くボタン |

---

### ログビューア（モーダル or シート）

```
┌─────────────────────────────────────────────────────┐
│ 実行ログ                                   [× 閉じる]│
├─────────────────────────────────────────────────────┤
│ エージェント: worker01                               │
│ タスク: tsk_95a81277 ユーザー認証機能の実装          │
│ 実行期間: 2026-01-16 00:59:34 - 01:00:02 (28秒)     │
│ 結果: blocked                                        │
├─────────────────────────────────────────────────────┤
│ 🔍 [検索_______________]           [折り返し: ON]   │
├─────────────────────────────────────────────────────┤
│ $ claude-code --task "ユーザー認証機能の実装"        │
│                                                      │
│ [INFO] Starting task execution...                   │
│ [INFO] Reading project context...                   │
│ [DEBUG] Found 3 related files                       │
│ [INFO] Analyzing dependencies...                    │
│ [WARN] Dependency tsk_abc123 not completed          │
│ [WARN] Dependency tsk_def456 not completed          │
│ [INFO] Cannot proceed - reporting blocked           │
│ [INFO] Reason: 依存タスクが未完了のため実行不可        │
│ [INFO] Task completed with result: blocked          │
│                                                      │
│ --- End of log ---                                  │
│                                                      │
│                                                      │
│                                                      │
└─────────────────────────────────────────────────────┘
```

### ログビューアの機能

| 機能 | 説明 |
|------|------|
| ヘッダー情報 | エージェント、タスク、期間、結果を表示 |
| テキスト検索 | ログ内のキーワード検索 |
| 折り返し表示 | 長い行の折り返し ON/OFF |
| スクロール | 大きなログファイルのスクロール閲覧 |

---

## データモデル

### 既存: ExecutionLog

現在の `ExecutionLog` エンティティを活用する。

```swift
public struct ExecutionLog {
    public let id: ExecutionLogID
    public let taskId: TaskID
    public let agentId: AgentID
    public private(set) var status: ExecutionStatus  // running/completed/failed
    public let startedAt: Date
    public private(set) var completedAt: Date?
    public private(set) var exitCode: Int?
    public private(set) var durationSeconds: Double?
    public private(set) var logFilePath: String?     // ← ログファイルパス
    public private(set) var errorMessage: String?
    // ...
}
```

---

## 実装要件

### 1. Coordinator側（Python）

| 要件 | 説明 |
|------|------|
| ログ保存場所 | `{working_dir}/.aiagent/logs/{agent_id}/{timestamp}.log` |
| フォールバック | ワーキングディレクトリ未設定時はApp Support配下 |
| キャプチャ対象 | エージェントプロセスの stdout/stderr |
| パス登録 | プロセス終了後に `register_execution_log_file` 呼び出し |

### 2. App側（Swift）

| 画面 | 実装内容 |
|------|----------|
| エージェント詳細 | 実行履歴タブの追加 |
| 実行履歴一覧 | ExecutionLog のリスト表示 |
| ログビューア | ログファイル内容の表示 |

### 3. 必要なリポジトリメソッド

```swift
// ExecutionLogRepository に追加
func findByAgentId(_ agentId: AgentID, limit: Int?, offset: Int?) throws -> [ExecutionLog]
```

---

## 制約事項

| 項目 | 制約 |
|------|------|
| ログサイズ | 大きなログファイルは部分読み込みを検討 |
| 保持期間 | 古いログの自動削除は将来検討 |
| リアルタイム | 実行中のログのリアルタイム表示は対象外（将来検討） |
| .gitignore | プロジェクトの .gitignore に `.aiagent/` を追加推奨 |

---

## 関連ドキュメント

- [エージェント管理画面](../ui/03_agent_management.md)
- [Phase 3 実行ログ](../plan/PHASE3_PULL_ARCHITECTURE.md)
- [Phase 4 Coordinator設計](../plan/PHASE4_COORDINATOR_ARCHITECTURE.md)

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-01-16 | 初版作成 |
| 2026-01-16 | Coordinator-App連携設計を追加、ログ保存場所をワーキングディレクトリ基準に変更 |
