# タスク実行ログ表示機能 設計書

## 概要

Web-UIでタスクの実行ログを表示する機能を追加する。エージェントがタスクを実行した際のログファイル内容、実行ステータス、コンテキスト（進捗・発見・ブロッカー・次のステップ）を閲覧可能にする。

## 現状分析

### 既存のデータ構造

#### execution_logs テーブル
| カラム | 型 | 説明 |
|--------|------|------|
| id | TEXT PK | 実行ログID |
| task_id | TEXT | タスクID |
| agent_id | TEXT | エージェントID |
| status | TEXT | `running`, `completed`, `failed` |
| started_at | DATETIME | 開始日時 |
| completed_at | DATETIME | 完了日時 |
| exit_code | INTEGER | 終了コード |
| duration_seconds | DOUBLE | 実行時間（秒） |
| log_file_path | TEXT | ログファイルパス |
| error_message | TEXT | エラーメッセージ |
| reported_provider | TEXT | モデルプロバイダー |
| reported_model | TEXT | モデルID |

#### contexts テーブル
| カラム | 型 | 説明 |
|--------|------|------|
| id | TEXT PK | コンテキストID |
| task_id | TEXT | タスクID |
| session_id | TEXT | セッションID |
| agent_id | TEXT | エージェントID |
| progress | TEXT | 進捗状況 |
| findings | TEXT | 発見事項 |
| blockers | TEXT | ブロッカー |
| next_steps | TEXT | 次のステップ |

### 現状のギャップ

1. **REST APIが未実装**: 実行ログ取得用のエンドポイントがない
2. **TaskDTOが不完全**: contextsフィールドがシリアライズされていない
3. **Web-UI型定義が不足**: ExecutionLog型が未定義

## 設計

### 1. 表示するデータ

#### 実行ログ一覧（TaskDetailPanel内）
- 実行日時（started_at）
- エージェント名
- ステータス（running/completed/failed）
- 実行時間（duration_seconds）
- 終了コード（exit_code）
- エラーメッセージ（あれば）

#### ログ詳細（展開時/モーダル）
- ログファイル内容（log_file_path から読み込み）
- 使用モデル情報（reported_provider, reported_model）

#### コンテキスト履歴
- 進捗（progress）
- 発見事項（findings）
- ブロッカー（blockers）
- 次のステップ（next_steps）
- 更新日時

### 2. REST API設計

#### 2.1 実行ログ一覧取得
```
GET /api/tasks/{taskId}/execution-logs
```

**Response:**
```json
{
  "executionLogs": [
    {
      "id": "log-123",
      "taskId": "task-1",
      "agentId": "worker-1",
      "agentName": "Worker 1",
      "status": "completed",
      "startedAt": "2024-01-15T10:00:00Z",
      "completedAt": "2024-01-15T10:05:30Z",
      "exitCode": 0,
      "durationSeconds": 330.5,
      "hasLogFile": true,
      "errorMessage": null,
      "reportedProvider": "anthropic",
      "reportedModel": "claude-3-5-sonnet"
    }
  ]
}
```

#### 2.2 ログファイル内容取得
```
GET /api/execution-logs/{logId}/content
```

**Response:**
```json
{
  "content": "... log file text content ...",
  "filename": "execution.log",
  "fileSize": 12345
}
```

**注意**: 大きなファイルはストリーミングまたはページネーションを検討

#### 2.3 コンテキスト履歴取得
```
GET /api/tasks/{taskId}/contexts
```

**Response:**
```json
{
  "contexts": [
    {
      "id": "ctx-123",
      "agentId": "worker-1",
      "agentName": "Worker 1",
      "sessionId": "session-456",
      "progress": "APIエンドポイントの実装を開始",
      "findings": "既存のauth middlewareを再利用可能",
      "blockers": null,
      "nextSteps": "ユニットテストの追加",
      "createdAt": "2024-01-15T10:00:00Z",
      "updatedAt": "2024-01-15T10:05:30Z"
    }
  ]
}
```

### 3. Web-UI型定義

```typescript
// web-ui/src/types/executionLog.ts

export type ExecutionLogStatus = 'running' | 'completed' | 'failed'

export interface ExecutionLog {
  id: string
  taskId: string
  agentId: string
  agentName: string
  status: ExecutionLogStatus
  startedAt: string
  completedAt: string | null
  exitCode: number | null
  durationSeconds: number | null
  hasLogFile: boolean
  errorMessage: string | null
  reportedProvider: string | null
  reportedModel: string | null
}

export interface ExecutionLogContent {
  content: string
  filename: string
  fileSize: number
}

export interface TaskContext {
  id: string
  agentId: string
  agentName: string
  sessionId: string
  progress: string | null
  findings: string | null
  blockers: string | null
  nextSteps: string | null
  createdAt: string
  updatedAt: string
}
```

### 4. UIコンポーネント設計

#### 4.1 TaskDetailPanel タブ構成

```
┌──────────────────────────────────────┐
│ タスクタイトル                  [×] │
├──────────────────────────────────────┤
│ [詳細]  [履歴]                       │  ← タブ切り替え
├──────────────────────────────────────┤
```

#### 4.2 「詳細」タブ（既存内容）

```
│ ステータス: [In Progress ▼]          │
│ 優先度: High                         │
│ 担当者: Worker 1                     │
│ 説明: REST APIエンドポイントの実装   │
│ 階層パス: API実装 > エンドポイント   │
│ 依存先: DB設計 ✅                    │
│ ...                                  │
```

#### 4.3 「履歴」タブ（実行ログ + コンテキスト統合）

```
│ ┌────────────────────────────────┐  │
│ │ 📋 01/15 10:00  Worker 1       │  │
│ │ 実行完了 ✅ 5分30秒            │  │
│ │ claude-3-5-sonnet              │  │
│ │                     [ログ表示] │  │
│ └────────────────────────────────┘  │
│ ┌────────────────────────────────┐  │
│ │ 📝 01/15 10:05  Worker 1       │  │
│ │ 進捗: APIエンドポイント実装完了│  │
│ │ 発見: auth middleware再利用可能│  │
│ │ 次: ユニットテスト追加         │  │
│ └────────────────────────────────┘  │
│ ┌────────────────────────────────┐  │
│ │ 📋 01/14 15:30  Worker 1       │  │
│ │ 実行失敗 ❌ 2分10秒            │  │
│ │ Error: API timeout             │  │
│ │                     [ログ表示] │  │
│ └────────────────────────────────┘  │
│         (時系列で統合表示)           │
└──────────────────────────────────────┘
```

#### 4.2 ログビューアモーダル

```
┌──────────────────────────────────────┐
│ 実行ログ: task-1 / Worker 1    [×]  │
├──────────────────────────────────────┤
│ 📅 2024-01-15 10:00 - 10:05:30      │
│ 🤖 claude-3-5-sonnet (anthropic)    │
│ ✅ 正常終了 (exit: 0)               │
├──────────────────────────────────────┤
│ ┌────────────────────────────────┐  │
│ │ [2024-01-15 10:00:01] Starting │  │
│ │ [2024-01-15 10:00:02] Loading  │  │
│ │ ...                            │  │
│ │ (スクロール可能なログ表示)      │  │
│ └────────────────────────────────┘  │
├──────────────────────────────────────┤
│                        [閉じる]      │
└──────────────────────────────────────┘
```

### 5. コンポーネント構成

```
web-ui/src/
├── types/
│   └── executionLog.ts          # 新規: ExecutionLog, TaskContext型
├── api/
│   └── client.ts                # 既存: 変更不要
├── hooks/
│   ├── useExecutionLogs.ts      # 新規: ログ取得フック
│   ├── useTaskContexts.ts       # 新規: コンテキスト取得フック
│   └── useTaskHistory.ts        # 新規: ログ+コンテキスト統合フック
├── components/
│   └── task/
│       ├── TaskDetailPanel/
│       │   ├── TaskDetailPanel.tsx  # 拡張: タブ構成に変更
│       │   ├── TaskDetailTab.tsx    # 新規: 詳細タブ（既存内容を分離）
│       │   ├── TaskHistoryTab.tsx   # 新規: 履歴タブ
│       │   └── index.ts
│       ├── HistoryItem/             # 新規: 履歴項目（ログ/コンテキスト共通）
│       │   ├── ExecutionLogItem.tsx
│       │   ├── ContextItem.tsx
│       │   └── index.ts
│       └── ExecutionLogViewer/      # 新規: ログ内容モーダル
│           ├── ExecutionLogViewer.tsx
│           └── index.ts
```

### 6. 実装フェーズ

#### Phase 1: バックエンドAPI（Swift）
1. ExecutionLogDTO, ContextDTO作成
2. GET /tasks/{taskId}/execution-logs 実装
3. GET /execution-logs/{logId}/content 実装
4. GET /tasks/{taskId}/contexts 実装

#### Phase 2: フロントエンド型・フック
1. executionLog.ts 型定義
2. useExecutionLogs フック
3. useTaskContexts フック
4. useExecutionLogContent フック

#### Phase 3: UIコンポーネント
1. ExecutionLogList / ExecutionLogItem
2. ExecutionLogViewer（モーダル）
3. ContextHistory / ContextItem
4. TaskDetailPanel拡張

#### Phase 4: E2Eテスト
1. MSWモックデータ追加
2. 実行ログ表示テスト
3. コンテキスト表示テスト

## 考慮事項

### パフォーマンス
- ログファイルが大きい場合のストリーミング対応
- 実行ログ一覧のページネーション（履歴が多い場合）

### セキュリティ
- ログファイルアクセスの認可確認
- パストラバーサル対策

### UX
- ログ読み込み中のローディング表示
- 長いログのスクロール・検索機能
- ステータス別の色分け表示

## 決定事項

- **TaskDetailPanel内にタブ追加** を採用
- タブ構成: 「詳細」「履歴」の2タブ
- 「履歴」タブに実行ログとコンテキストを統合表示
- ログ内容は別モーダルで表示
- アクセス制御なし（全ユーザーが閲覧可能）
- 初期実装ではページネーション不要（後で追加可能）
