# 実装プラン: get_my_task_progress ツールと update_task_status 改善

## 背景

### 問題
エージェントがサブタスクを作成後、サブタスクを実行せずに親タスクを`done`にしてしまう問題が発生。

### 原因
1. `update_task_status`の戻り値に次アクションの指示がない
2. エージェントが状況を確認せずに親タスクを完了にできてしまう
3. `get_my_task`はログ書き込みなど副作用があり、状況確認用途には不適切

## 解決策

### 1. 新規ツール `get_my_task_progress`

自分に割り当てられたタスクの進行状況を構造的に確認する読み取り専用ツール。

### 2. `update_task_status` の改善

`done`への更新時に、残タスクの有無に応じた指示を返す。

---

## 新規ツール: `get_my_task_progress`

### 仕様

| 項目 | 値 |
|------|-----|
| ツール名 | `get_my_task_progress` |
| 認証 | 必須（session_token） |
| 副作用 | なし（読み取り専用） |
| 用途 | タスク進行状況の確認 |

### 入力パラメータ

```json
{
  "session_token": "string (required)"
}
```

### 戻り値

```json
{
  "tasks": [
    {
      "id": "tsk_main",
      "title": "ショッピングカートのテスト",
      "status": "in_progress",
      "subtasks": [
        { "id": "tsk_sub1", "title": "商品追加テスト", "status": "done" },
        { "id": "tsk_sub2", "title": "合計計算テスト", "status": "done" },
        { "id": "tsk_sub3", "title": "カートクリアテスト", "status": "todo" },
        { "id": "tsk_sub4", "title": "永続性テスト", "status": "todo" },
        { "id": "tsk_sub5", "title": "レポート作成", "status": "todo" }
      ]
    }
  ]
}
```

### 設計方針

- **事実のみを返す**: 指示やnext_actionは含めない
- **構造的表示**: 親子関係を階層で表現
- **シンプル**: 必要最小限の情報のみ

---

## 変更: `update_task_status` の戻り値

### 現状

```swift
return [
    "success": true,
    "task": [
        "id": ...,
        "title": ...,
        "previous_status": ...,
        "new_status": ...
    ]
]
```

### 変更後（status=done の場合）

```swift
// 残タスクがない場合
return [
    "success": true,
    "task": [...],
    "instruction": "担当タスクが全て完了しました。report_completed を呼び出してください。"
]

// 残タスクがある場合
return [
    "success": true,
    "task": [...],
    "instruction": "get_my_task_progress で残りのタスク状況を確認し、必要な作業を続けてください。"
]
```

### 残タスクの判定ロジック

```swift
// 同一プロジェクト内で、自分に割り当てられた未完了タスク
let remainingTasks = allAssignedTasks.filter { task in
    task.projectId == projectId &&
    task.status != .done &&
    task.status != .cancelled
}
```

---

## 実装タスク

### Phase 1: `get_my_task_progress` ツール追加

1. **ToolDefinitions.swift**
   - ツール定義 `getMyTaskProgress` を追加
   - `allTools` リストに追加

2. **MCPServer.swift**
   - `case "get_my_task_progress":` ハンドラ追加
   - `private func getMyTaskProgress(session:)` 実装

### Phase 2: `update_task_status` 改善

1. **MCPServer.swift**
   - `updateTaskStatus` 関数の戻り値を変更
   - `done` への更新時に残タスクをチェック
   - 適切な `instruction` を返す

---

## ファイル変更一覧

| ファイル | 変更内容 |
|----------|----------|
| `Sources/MCPServer/Tools/ToolDefinitions.swift` | ツール定義追加 |
| `Sources/MCPServer/MCPServer.swift` | ハンドラ追加、update_task_status修正、getWorkerNextAction修正 |

---

## 変更: `getWorkerNextAction` の指示文

### 不要になる記述

`update_task_status`の戻り値で次アクションを指示するため、以下の「get_next_action を呼び出してください」の記述が不要になる。

#### action: work（3018-3023行）

**現状**:
```swift
"instruction": """
    このタスクを直接実行してください。
    タスクの内容に従って作業を行い、完了したら
    update_task_status で status を 'done' に変更してください。
    その後 get_next_action を呼び出してください。
    """
```

**変更後**:
```swift
"instruction": """
    このタスクを直接実行してください。
    タスクの内容に従って作業を行い、完了したら
    update_task_status で status を 'done' に変更してください。
    """
```

#### action: execute_subtask（3121-3125行）

**現状**:
```swift
"instruction": """
    現在のサブタスクを実行してください。
    完了したら update_task_status で status を 'done' に変更し、
    get_next_action を呼び出してください。
    """
```

**変更後**:
```swift
"instruction": """
    現在のサブタスクを実行してください。
    完了したら update_task_status で status を 'done' に変更してください。
    """
```

### 理由

`update_task_status`の戻り値に`instruction`が含まれるようになるため、エージェントはその指示に従えばよい。明示的に`get_next_action`を呼ぶ指示は不要。

---

## 期待される動作フロー

```
1. エージェントがサブタスクを完了
   ↓
2. update_task_status(subtask_id, "done") を呼び出す
   ↓
3. 戻り値に「get_my_task_progress で確認してください」の指示
   ↓
4. エージェントが get_my_task_progress を呼び出す
   ↓
5. 残りのサブタスクを確認
   ↓
6. 次のサブタスクを実行（繰り返し）
   ↓
7. 全サブタスク完了後、親タスクを完了
   ↓
8. update_task_status 戻り値に「report_completed を呼び出してください」
   ↓
9. report_completed でセッション終了
```
