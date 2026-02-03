# マネージャー状態遷移 設計書 V2

## 概要

本ドキュメントは、マネージャーエージェントの状態遷移を再設計したものである。
現行実装の問題点を解決し、マネージャーに適切な判断権限を委譲することを目的とする。

## 背景と問題点

### 現行実装の問題

現行のマネージャー実装では、`get_next_action` が返す指示に従うだけの「状態機械の奴隷」となっている。

#### 問題1: タスク開始の決定権がない

```
現行: get_next_action → start_task { next_subtask: "tsk_001" }
```

- システムが「どのタスクを開始するか」を1件指定
- マネージャーに選択の余地がない
- 優先順位の判断、リソース状況の考慮ができない

#### 問題2: 復帰時に状況把握の機会がない

```
現行フロー:
  waiting_for_workers (exit)
    ↓
  [Worker完了]
    ↓
  再起動 → get_next_action → start_task (即座に次タスク開始)
```

- ワーカーの成果をレビューする機会がない
- 何が完了し、何が残っているか俯瞰できない
- 計画の修正やタスクの振り直しを検討する機会がない

#### 問題3: マネージャーが使用していないツール

| ツール | 用途 | 呼び出し回数 |
|--------|------|-------------|
| `list_subordinates` | ワーカーの状態確認 | 0 |
| `list_tasks` | タスク進捗の俯瞰 | 0 |
| `get_task` | 完了タスクの成果確認 | 0 |
| `get_subordinate_profile` | ワーカーのスキル確認 | 0 |

これらは `get_next_action` が指示しないため呼ばれない。

### 参考: 調査記録

- Issue: `docs/issues/MANAGER_AUTONOMY_AND_SITUATIONAL_AWARENESS.md`

---

## 新設計

### 設計方針

1. **状態遷移の構造は維持** - 既存の構造を大きく変えない
2. **判断権限をマネージャーに委譲** - 何をするかはマネージャーが決める
3. **状況把握を中核に据える** - 常に状況を把握した上で判断
4. **確実性の担保** - 割り当てと実行開始は責務として明示
5. **状況は自分で確認** - システムは状況を直接提供せず、確認を促す

### 状態一覧

| # | 状態 | 条件 | 概要 |
|---|------|------|------|
| 1 | `create_subtasks` | サブタスクなし | サブタスク作成（現行維持） |
| 2 | `situational_awareness` | サブタスクあり | **状況把握を促す（新規・中核）** |
| 3 | `start` | マネージャー選択 | **タスク開始（割当+開始統合）** |
| 4 | `adjust` | マネージャー選択 | **調整（新規）** |
| 5 | `wait` | マネージャー選択 | ワーカー待機（exitから改名） |
| 6 | `needs_completion` | 全完了 | 完了報告（現行維持） |
| 7 | `review_blocks` | ブロックのみ残存 | ブロック対処（現行維持） |

### 状態遷移図

```
開始 (authenticate)
    │
    ▼
get_next_action
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│                         状態判定                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ サブタスクなし        → create_subtasks                 │    │
│  │ 全完了                → needs_completion                │    │
│  │ ブロックのみ残存      → review_blocks                   │    │
│  │ それ以外              → situational_awareness           │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
    │
    ├─────────────────────────────────────────────────────────────┐
    │                                                             │
    ▼                                                             │
┌─────────────────┐                                               │
│ create_subtasks │                                               │
│ (サブタスク作成) │                                               │
└────────┬────────┘                                               │
         │                                                        │
         │ get_next_action                                        │
         ▼                                                        │
┌──────────────────────────────────────┐                          │
│       situational_awareness          │ ←────────────────────────┤
│           (状況把握)                  │                          │
│                                      │                          │
│  マネージャーが:                      │                          │
│  1. ツールで状況を確認               │                          │
│  2. select_action で次を選択         │                          │
└──────────────────┬───────────────────┘                          │
                   │                                              │
                   │ select_action                                │
                   │                                              │
     ┌─────────────┼─────────────┐                                │
     │             │             │                                │
     ▼             ▼             ▼                                │
┌─────────┐  ┌─────────┐  ┌─────────┐                             │
│  start  │  │ adjust  │  │  wait   │                             │
│         │  │         │  │         │                             │
│割当+開始│  │調整全般 │  │Worker待機│                             │
└────┬────┘  └────┬────┘  └────┬────┘                             │
     │            │            │                                  │
     │            │            │ logout                           │
     │            │            ▼                                  │
     │            │     [Worker完了]                              │
     │            │            │                                  │
     └────────────┴────────────┴──────────────────────────────────┘
                               │
                               │ (終了条件を満たした場合)
                               ▼
                  ┌─────────────────────────┐
                  │    needs_completion     │
                  │    (全完了 → 報告)      │
                  └────────────┬────────────┘
                               │
                               ▼
                  ┌─────────────────────────┐
                  │     review_blocks       │
                  │  (ブロックのみ → 対処)  │
                  └────────────┬────────────┘
                               │
                               ▼
                             終了
```

---

## 新規ツール設計

### 概要

| ツール | 用途 | 優先度 |
|--------|------|--------|
| `select_action` | 次のアクション（状態）を選択 | **必須** |
| `get_recent_completions` | 最近完了したタスクの確認 | **必須** |
| `update_task` | タスク内容の修正 | 高 |
| `cancel_task` | タスクのキャンセル | 高 |
| `block_task` | タスクのブロック | 高 |
| `update_task_dependencies` | 依存関係の変更 | 中 |

---

### select_action - 次のアクション選択

**用途**: マネージャーが次の状態（start/adjust/wait）を明示的に選択

```json
{
  "name": "select_action",
  "description": "次のアクションを選択します。状況を確認した上で、start（開始）、adjust（調整）、wait（待機）のいずれかを選択してください。",
  "inputSchema": {
    "type": "object",
    "properties": {
      "action": {
        "type": "string",
        "enum": ["start", "adjust", "wait"],
        "description": "選択するアクション。start: タスクを開始する、adjust: 調整を行う、wait: ワーカー完了を待機する"
      },
      "reason": {
        "type": "string",
        "description": "選択理由（任意）"
      }
    },
    "required": ["action"]
  }
}
```

**レスポンス例**:
```json
{
  "success": true,
  "selected_action": "start",
  "message": "アクション 'start' が選択されました。get_next_action を呼び出して詳細指示を取得してください。"
}
```

---

### get_recent_completions - 最近の完了タスク確認

**用途**: 最近完了したサブタスクの一覧と成果サマリーを取得

```json
{
  "name": "get_recent_completions",
  "description": "最近完了したサブタスクの一覧を取得します。成果サマリーを含みます。",
  "inputSchema": {
    "type": "object",
    "properties": {
      "parent_task_id": {
        "type": "string",
        "description": "親タスクのID（省略時は現在のメインタスク）"
      },
      "since": {
        "type": "string",
        "description": "この日時以降の完了タスク（ISO8601形式、省略時は前回セッション終了以降）"
      },
      "limit": {
        "type": "integer",
        "description": "取得件数上限（デフォルト: 10）"
      }
    },
    "required": []
  }
}
```

**レスポンス例**:
```json
{
  "completions": [
    {
      "task_id": "tsk_001",
      "title": "API実装",
      "assignee_id": "worker-01",
      "completed_at": "2026-02-03T15:30:00Z",
      "result": "success",
      "summary": "REST API 5エンドポイント実装完了"
    }
  ],
  "total": 1,
  "since": "2026-02-03T14:00:00Z"
}
```

---

### update_task - タスク内容の修正

**用途**: タスクのtitle、description、priorityを修正

```json
{
  "name": "update_task",
  "description": "タスクの内容を更新します。title, description, priority を変更できます。",
  "inputSchema": {
    "type": "object",
    "properties": {
      "task_id": {
        "type": "string",
        "description": "更新するタスクのID"
      },
      "title": {
        "type": "string",
        "description": "新しいタイトル（省略時は変更なし）"
      },
      "description": {
        "type": "string",
        "description": "新しい説明（省略時は変更なし）"
      },
      "priority": {
        "type": "string",
        "enum": ["low", "medium", "high", "critical"],
        "description": "新しい優先度（省略時は変更なし）"
      }
    },
    "required": ["task_id"]
  }
}
```

**レスポンス例**:
```json
{
  "success": true,
  "task_id": "tsk_001",
  "updated_fields": ["title", "priority"],
  "message": "タスクが更新されました"
}
```

---

### cancel_task - タスクのキャンセル

**用途**: 不要になったタスクをキャンセル

```json
{
  "name": "cancel_task",
  "description": "タスクをキャンセルします。cancelled ステータスに変更されます。",
  "inputSchema": {
    "type": "object",
    "properties": {
      "task_id": {
        "type": "string",
        "description": "キャンセルするタスクのID"
      },
      "reason": {
        "type": "string",
        "description": "キャンセル理由"
      }
    },
    "required": ["task_id", "reason"]
  }
}
```

**レスポンス例**:
```json
{
  "success": true,
  "task_id": "tsk_002",
  "previous_status": "todo",
  "new_status": "cancelled",
  "reason": "方針変更により不要"
}
```

---

### block_task - タスクのブロック

**用途**: タスクをブロック状態にする

```json
{
  "name": "block_task",
  "description": "タスクをブロック状態にします。外部依存や問題発生時に使用します。",
  "inputSchema": {
    "type": "object",
    "properties": {
      "task_id": {
        "type": "string",
        "description": "ブロックするタスクのID"
      },
      "reason": {
        "type": "string",
        "description": "ブロック理由"
      }
    },
    "required": ["task_id", "reason"]
  }
}
```

**レスポンス例**:
```json
{
  "success": true,
  "task_id": "tsk_003",
  "previous_status": "in_progress",
  "new_status": "blocked",
  "reason": "外部APIの仕様変更待ち"
}
```

---

### update_task_dependencies - 依存関係の変更

**用途**: タスク間の依存関係を追加/削除

```json
{
  "name": "update_task_dependencies",
  "description": "タスクの依存関係を更新します。",
  "inputSchema": {
    "type": "object",
    "properties": {
      "task_id": {
        "type": "string",
        "description": "更新するタスクのID"
      },
      "add_dependencies": {
        "type": "array",
        "items": { "type": "string" },
        "description": "追加する依存タスクIDのリスト"
      },
      "remove_dependencies": {
        "type": "array",
        "items": { "type": "string" },
        "description": "削除する依存タスクIDのリスト"
      }
    },
    "required": ["task_id"]
  }
}
```

**レスポンス例**:
```json
{
  "success": true,
  "task_id": "tsk_004",
  "dependencies": ["tsk_001", "tsk_002"],
  "added": ["tsk_002"],
  "removed": []
}
```

---

## 各状態の詳細

### 状態1: create_subtasks（現行維持）

**条件**: サブタスクが存在しない

**レスポンス**:
```json
{
  "action": "create_subtasks",
  "instruction": "タスクを2〜5個のサブタスクに分解してください。...",
  "state": "needs_subtask_creation",
  "task": {
    "id": "tsk_main",
    "title": "メインタスク",
    "description": "..."
  }
}
```

**マネージャーの行動**:
1. `create_tasks_batch` でサブタスク作成
2. `get_next_action` 呼び出し

---

### 状態2: situational_awareness（新規・中核）

**条件**: サブタスクが存在する（全完了・ブロックのみ以外）

**目的**: マネージャーに状況確認を促し、次のアクションを選択させる

**レスポンス**:
```json
{
  "action": "situational_awareness",
  "state": "situational_awareness",

  "instruction": "現在の状況を確認し、次のアクションを選択してください。\n\n■ 状況確認ツール\n  - list_tasks: サブタスクの全体状況を確認\n  - get_recent_completions: 最近完了したタスクと成果を確認\n  - get_task: 特定タスクの詳細を確認\n  - list_subordinates: ワーカーの状況を確認\n\n■ 次のアクション選択\n状況を把握した上で、select_action ツールで次のアクションを選択してください:\n  - start: タスクを開始する（割当+開始）\n  - adjust: 調整を行う（振り直し、修正、ブロック対処等）\n  - wait: ワーカー完了を待機する\n\n選択後、get_next_action を呼び出して詳細指示を取得してください。"
}
```

**マネージャーの行動**:
1. `list_tasks` でサブタスクの状況を確認
2. `get_recent_completions` で完了タスクの成果を確認（任意）
3. `list_subordinates` でワーカーの状況を確認（任意）
4. `select_action` で次のアクションを選択（start/adjust/wait）
5. `get_next_action` 呼び出し

---

### 状態3: start（新規 - assign + start_task 統合）

**条件**: マネージャーが `select_action(action: "start")` を選択

**目的**: タスクの割り当てと開始を一体で行う

**レスポンス**:
```json
{
  "action": "start",
  "state": "start",

  "instruction": "タスクを開始してください。\n\n■ 手順\n1. list_tasks で開始可能なタスクを確認\n2. 未割り当ての場合: assign_task で割り当て\n3. update_task_status で in_progress に変更\n\nどのタスクを誰に割り当てるかは、内容・優先度・Worker負荷を考慮して判断してください。\n完了後、get_next_action を呼び出してください。"
}
```

**マネージャーの行動**:
1. `list_tasks` で開始可能なタスクを確認
2. 開始するタスクを選択（マネージャーの裁量）
3. 未割り当てなら `assign_task` で割り当て
4. `update_task_status` で `in_progress` に変更
5. `get_next_action` 呼び出し

---

### 状態4: adjust（新規）

**条件**: マネージャーが `select_action(action: "adjust")` を選択

**目的**: 振り直し、修正、ブロック対処等の調整作業

**レスポンス**:
```json
{
  "action": "adjust",
  "state": "adjust",

  "instruction": "必要な調整を行ってください。\n\n■ 調整用ツール\n  - assign_task: 担当者変更・振り直し\n  - update_task: タスク内容の修正（title, description, priority）\n  - update_task_status: ステータス変更\n  - update_task_dependencies: 依存関係の変更\n  - block_task: タスクをブロック状態にする\n  - cancel_task: タスクをキャンセル\n  - create_tasks_batch: 追加タスク作成\n\n■ 確認用ツール\n  - list_tasks: 全体状況確認\n  - get_task: 詳細確認\n\n調整完了後、get_next_action を呼び出してください。"
}
```

**マネージャーの行動**:
1. 必要な調整を実施
2. `get_next_action` 呼び出し

---

### 状態5: wait（exitから改名）

**条件**: マネージャーが `select_action(action: "wait")` を選択

**目的**: ワーカー完了を待機

**レスポンス**:
```json
{
  "action": "wait",
  "state": "waiting_for_workers",

  "instruction": "Worker の完了を待つため、プロセスを終了してください。\nWorker 完了後に自動的に再起動されます。\nlogout を呼び出してください。"
}
```

**マネージャーの行動**:
1. `logout` 呼び出し
2. プロセス終了
3. [Worker完了後] 再起動 → `situational_awareness` へ

---

### 状態6: needs_completion（現行維持）

**条件**: 全サブタスク完了

**レスポンス**:
```json
{
  "action": "report_completion",
  "state": "needs_completion",

  "instruction": "全てのサブタスクが完了しました。\nreport_completed を呼び出してメインタスクを完了してください。",

  "task": {
    "id": "tsk_main",
    "title": "メインタスク"
  }
}
```

---

### 状態7: review_blocks（現行維持）

**条件**: ブロックタスクのみ残存（pending=0, in_progress=0）

**レスポンス**:
```json
{
  "action": "review_and_resolve_blocks",
  "state": "needs_review",

  "instruction": "ブロック状態のサブタスクがあります。対処を検討してください。\n\n■ 確認\n  - list_tasks でブロック中のタスクを確認\n  - get_task で詳細とブロック理由を確認\n\n■ 対処\n  - 解除可能: update_task_status で todo に変更\n  - 対処不可: report_completed で blocked として報告"
}
```

---

## 現行との差分

| 現行状態 | 新設計 | 変更内容 |
|----------|--------|---------|
| `needs_assignment` | **削除** | `start` に統合 |
| `needs_start` | **削除** | `start` に統合 |
| - | `situational_awareness` | **新規追加（中核）** |
| - | `start` | **新規（割当+開始統合）** |
| - | `adjust` | **新規追加** |
| `waiting_for_workers` | `wait` | 改名、復帰時に `situational_awareness` 経由 |
| `waiting_for_dependencies` | **削除** | `wait` に統合 |
| `needs_completion` | `needs_completion` | 維持 |
| `needs_review` | `review_blocks` | 改名 |

### 新規ツール

| ツール | 用途 |
|--------|------|
| `select_action` | 次のアクション（状態）を選択 |
| `get_recent_completions` | 最近完了したタスクの確認 |
| `update_task` | タスク内容の修正 |
| `cancel_task` | タスクのキャンセル |
| `block_task` | タスクのブロック |
| `update_task_dependencies` | 依存関係の変更 |

---

## 実装への影響

### 変更対象ファイル

- `Sources/MCPServer/MCPServer.swift`
  - `getManagerNextAction` 関数の大幅修正
  - `select_action` の結果を Context に保存
  - 新状態のレスポンス生成ロジック追加

- `Sources/MCPServer/Tools/ToolDefinitions.swift`
  - 新規ツールの定義追加

- `Sources/MCPServer/Tools/ToolHandlers.swift`
  - 新規ツールのハンドラ実装

- `Sources/Domain/Entities/Task.swift`
  - 必要に応じて `priority` フィールド追加

### Context 管理

マネージャーが選択したアクションを Context に保存:

```swift
// select_action 呼び出し時
context.progress = "workflow:selected_\(action)"  // selected_start, selected_adjust, selected_wait

// get_next_action での判定
if latestContext?.progress == "workflow:selected_start" {
    return startActionResponse()
} else if latestContext?.progress == "workflow:selected_adjust" {
    return adjustActionResponse()
} else if latestContext?.progress == "workflow:selected_wait" {
    return waitActionResponse()
} else {
    return situationalAwarenessResponse()
}
```

### ワークフロー例

```
1. authenticate
2. get_next_action → situational_awareness
3. list_tasks（状況確認）
4. get_recent_completions（完了タスク確認）
5. select_action(action: "start")
6. get_next_action → start
7. list_tasks（開始可能タスク確認）
8. assign_task（割り当て）
9. update_task_status(in_progress)
10. get_next_action → situational_awareness（または wait）
...
```

---

## 期待される効果

1. **マネージャーの判断権限拡大**
   - どのタスクを誰に割り当てるかはマネージャーが決定
   - 優先順位、リソース状況を考慮した判断が可能
   - 次のアクション（start/adjust/wait）を自分で選択

2. **状況把握の機会確保**
   - 復帰時に必ず状況確認フェーズを経由
   - `get_recent_completions` で完了タスクの成果レビューが可能
   - 問題の早期発見と対処

3. **柔軟な調整**
   - `update_task` でタスク内容を修正
   - `block_task` / `cancel_task` でタスク状態を管理
   - `update_task_dependencies` で依存関係を調整
   - 状況に応じた動的な計画変更

4. **確実性の担保**
   - 状態遷移の構造により必要なアクションを保証
   - `select_action` による明示的な状態選択

---

## 関連ドキュメント

- `docs/issues/MANAGER_AUTONOMY_AND_SITUATIONAL_AWARENESS.md` - 問題の詳細調査
- `docs/plan/archive/STATE_DRIVEN_WORKFLOW.md` - 旧ワークフロー設計

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-02-03 | 初版作成 |
| 2026-02-03 | 新規ツール設計追加、situational_awareness を確認促進型に変更 |
