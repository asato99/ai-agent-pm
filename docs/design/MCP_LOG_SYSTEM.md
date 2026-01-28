# MCP Log System Design

MCPサーバーのログシステム設計書。ログローテーションと構造化ログの導入により、運用性と可読性を向上させる。

## 背景と課題

### 現状の問題点

| 問題 | 影響 |
|------|------|
| **ログファイルの肥大化** | `mcp-server.log` が16MB以上に成長、ディスク圧迫 |
| **ローテーションなし** | 古いログが無期限に蓄積 |
| **healthCheckの大量出力** | 2秒ごとに出力され、ログの大部分を占める |
| **DEBUGログの冗長性** | テーブル全体がダンプされる |
| **非構造化フォーマット** | 文字列マッチでしかフィルタできない |

### 現在のログ形式

```
[2026-01-28T00:21:29Z] [MCP] getAgentAction called for agent: 'agt_801b2cc6-c7f', project: 'prj_1f85f0fd-616'
[2026-01-28T00:21:29Z] [MCP] DEBUG: All pending_agent_purposes rows: [{"project_id": "prj_e6c3df56-b06", ...}]
```

- タイムスタンプ + プレーンテキスト
- ログレベルの概念がない
- カテゴリ分類なし

---

## 設計

### 1. ログローテーション

#### 1.1 方式

**日数ベースローテーション**を採用する。

| 項目 | 設定値 |
|------|--------|
| 保持期間 | 7日（デフォルト） |
| チェックタイミング | デーモン起動時 |
| ファイル命名規則 | `mcp-server-YYYY-MM-DD.log` |

#### 1.2 動作フロー

```
デーモン起動時:
1. logs/ ディレクトリ内のログファイルをスキャン
2. ファイル名から日付を抽出
3. 保持期間を超えたファイルを削除
4. 現在日付のログファイルを開く（なければ作成）
```

#### 1.3 ファイル構造

```
~/Library/Application Support/AIAgentPM/
├── logs/
│   ├── mcp-server-2026-01-28.log  ← 今日
│   ├── mcp-server-2026-01-27.log
│   ├── mcp-server-2026-01-26.log
│   └── ... (7日分)
├── mcp-daemon.log  ← 既存（将来的に統合検討）
└── webserver.log   ← 既存（将来的に統合検討）
```

#### 1.4 設定

```swift
struct LogRotationConfig {
    /// ログ保持日数（デフォルト: 7日）
    var retentionDays: Int = 7

    /// ローテーションを有効にするか
    var enabled: Bool = true
}
```

環境変数でのオーバーライド:
- `MCP_LOG_RETENTION_DAYS`: 保持日数

---

### 2. 構造化ログ

#### 2.1 JSON形式

```json
{
  "timestamp": "2026-01-28T00:21:29.123Z",
  "level": "INFO",
  "category": "agent",
  "operation": "getAgentAction",
  "agent_id": "agt_801b2cc6-c7f",
  "project_id": "prj_1f85f0fd-616",
  "message": "Action determined",
  "details": {
    "action": "hold",
    "elapsed_seconds": 35
  },
  "duration_ms": 5
}
```

#### 2.2 フィールド定義

| フィールド | 型 | 必須 | 説明 |
|------------|-----|------|------|
| `timestamp` | string (ISO8601) | ✓ | ミリ秒精度のタイムスタンプ |
| `level` | string | ✓ | ログレベル |
| `category` | string | ✓ | カテゴリ |
| `operation` | string |  | 操作名（ツール名など） |
| `agent_id` | string |  | 関連エージェントID |
| `project_id` | string |  | 関連プロジェクトID |
| `task_id` | string |  | 関連タスクID |
| `session_id` | string |  | セッションID |
| `message` | string | ✓ | 人間可読なメッセージ |
| `details` | object |  | 追加の詳細情報 |
| `duration_ms` | number |  | 処理時間（ミリ秒） |
| `error` | object |  | エラー情報 |

#### 2.3 ログレベル

| レベル | 値 | 用途 |
|--------|-----|------|
| `TRACE` | 0 | 全て（healthCheck含む） |
| `DEBUG` | 1 | デバッグ情報、詳細なフロー |
| `INFO` | 2 | 主要な操作（デフォルト） |
| `WARN` | 3 | 警告、非推奨の使用 |
| `ERROR` | 4 | エラー、例外 |

**デフォルト**: `INFO`

環境変数でのオーバーライド:
- `MCP_LOG_LEVEL`: `TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`

#### 2.4 カテゴリ

| カテゴリ | 説明 | 主な操作 |
|----------|------|----------|
| `system` | システム全般 | 起動、シャットダウン |
| `health` | ヘルスチェック | healthCheck |
| `auth` | 認証・セッション | authenticate, validateSession |
| `agent` | エージェント操作 | getAgentAction, getAgentProfile |
| `task` | タスク操作 | requestTask, completeTask |
| `chat` | チャット機能 | sendMessage, getMessages |
| `project` | プロジェクト操作 | getProject, listProjects |
| `error` | エラー | reportAgentError |

#### 2.5 ログレベルとカテゴリの関係

```
healthCheck → category: "health", level: "TRACE"
              （デフォルトでは出力されない）

getAgentAction → category: "agent", level: "INFO"
                 （通常操作として出力）

reportAgentError → category: "error", level: "ERROR"
                   （常に出力）
```

---

### 3. MCPLogView UI改善

#### 3.1 フィルタリング機能

```
┌─────────────────────────────────────────────────────────────┐
│ MCP Server Logs                                    [x]      │
├─────────────────────────────────────────────────────────────┤
│ Level: [TRACE ▾] [DEBUG ▾] [INFO ✓] [WARN ✓] [ERROR ✓]     │
│ Category: [All ▾]  Agent: [________]  Time: [Last 1h ▾]    │
│ Search: [________________________] [⟳] [Auto-scroll ✓]     │
├─────────────────────────────────────────────────────────────┤
│ 2026-01-28 09:21:35 ERROR [error] reportAgentError          │
│   agent: agt_801b2cc6-c7f                                   │
│   message: You have exhausted your capacity...              │
│                                                             │
│ 2026-01-28 09:21:29 INFO [agent] getAgentAction             │
│   agent: agt_801b2cc6-c7f project: prj_1f85f0fd-616         │
│   action: hold, elapsed: 35s                                │
└─────────────────────────────────────────────────────────────┘
```

#### 3.2 フィルタ項目

| フィルタ | 説明 | UI |
|----------|------|-----|
| **Level** | 表示するログレベル | チェックボックス（複数選択） |
| **Category** | カテゴリ絞り込み | ドロップダウン |
| **Agent ID** | 特定エージェント | テキスト入力 |
| **Project ID** | 特定プロジェクト | テキスト入力 |
| **Time Range** | 時間範囲 | ドロップダウン（1h/6h/24h/All） |
| **Search** | 全文検索 | テキスト入力 |

#### 3.3 表示形式

**コンパクトモード**（デフォルト）:
```
09:21:35 ERROR [error] reportAgentError - You have exhausted your capacity...
```

**詳細モード**（行クリックで展開）:
```json
{
  "timestamp": "2026-01-28T09:21:35.123Z",
  "level": "ERROR",
  "category": "error",
  "operation": "reportAgentError",
  "agent_id": "agt_801b2cc6-c7f",
  "message": "You have exhausted your capacity on this model.",
  "details": { "reset_after_seconds": 361 }
}
```

---

### 4. 実装計画

#### Phase 1: ログローテーション

| タスク | 優先度 |
|--------|--------|
| `LogRotator` クラス作成 | 高 |
| デーモン起動時のローテーション実行 | 高 |
| 日付別ファイル出力対応 | 高 |
| 設定（保持日数）対応 | 中 |

#### Phase 2: 構造化ログ基盤

| タスク | 優先度 |
|--------|--------|
| `StructuredLogger` クラス作成 | 高 |
| JSON形式での出力 | 高 |
| ログレベル制御 | 高 |
| カテゴリ付与 | 高 |
| 既存の `Self.log()` を置き換え | 中 |

#### Phase 3: MCPLogView改善

| タスク | 優先度 |
|--------|--------|
| JSONログのパース対応 | 高 |
| カテゴリフィルタUI | 高 |
| ログレベルフィルタUI | 高 |
| 時間範囲フィルタ | 中 |
| エージェント/プロジェクトフィルタ | 中 |
| 詳細表示モード | 低 |

---

### 5. 後方互換性

#### 5.1 移行期間

構造化ログ導入後も、既存のプレーンテキストログを一定期間サポートする。

```swift
// MCPLogViewでの判定
if line.starts(with: "{") {
    // JSON形式として解析
    parseStructuredLog(line)
} else {
    // レガシー形式として表示
    displayLegacyLog(line)
}
```

#### 5.2 環境変数

| 変数 | 説明 | デフォルト |
|------|------|------------|
| `MCP_LOG_FORMAT` | `json` または `text` | `json` |
| `MCP_LOG_LEVEL` | ログレベル | `INFO` |
| `MCP_LOG_RETENTION_DAYS` | 保持日数 | `7` |

---

### 6. CLIツール（将来）

```bash
# ログ検索
mcp-server-pm logs --level ERROR --since 1h

# 特定エージェントのログ
mcp-server-pm logs --agent agt_801b2cc6-c7f

# JSON出力
mcp-server-pm logs --format json | jq '.level == "ERROR"'

# リアルタイム監視
mcp-server-pm logs --follow --level INFO
```

---

## 参考

- [LOG_TRANSFER_DESIGN.md](./LOG_TRANSFER_DESIGN.md) - マルチデバイス環境でのログ転送設計
- [AGENT_EXECUTION_LOG.md](./AGENT_EXECUTION_LOG.md) - エージェント実行ログ設計
