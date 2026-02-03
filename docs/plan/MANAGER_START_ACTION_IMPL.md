# assign + start_task 統合実装計画

## 概要

現行の `assign` アクションと `start_task` アクションを `start` アクションに統合する。
段階的にパイロットテストで動作確認しながら進める。

## 現行実装の分析

### 現行フロー

```
Phase 1: 未割り当てタスクがある場合
  → action: "assign"
  → 1件指定（next_subtask）
  → マネージャーが assign_task を実行
  → get_next_action

Phase 2: 実行可能タスクがある場合（割り当て済み + 依存クリア）
  → action: "start_task"
  → 1件指定（next_subtask）
  → マネージャーが update_task_status(in_progress) を実行
  → get_next_action
```

### 問題点

1. 2段階に分かれている（assign → start_task）
2. システムが1件を指定（マネージャーに選択権なし）
3. 開始に必要なタスクにのみ割り当てればよいのに、全タスクに事前割り当て

### 該当コード

- `MCPServer.swift:3614-3674` - assign アクション
- `MCPServer.swift:3677-3702` - start_task アクション

---

## 実装計画

### Step 1: ベースライン確認

**目的**: 現行動作の確認とログ収集

**作業**:
1. パイロットテスト実行（hello-world または weather-app-complete）
2. マネージャーのログで `assign` → `start_task` の流れを確認
3. 現行動作のスクリーンショット/ログを保存

**確認ポイント**:
- `assign` アクションが返される回数
- `start_task` アクションが返される回数
- 各アクションでの指示内容

**所要時間目安**: 30分

---

### Step 2: start アクション導入

**目的**: assign と start_task を start に統合

**変更内容**:

```swift
// 変更前: Phase 1 (assign) と Phase 2 (start_task) が分離

// 変更後: startable タスクがある場合に start を返す
// startable = 未割り当て OR (割り当て済み + 依存クリア)

if !unassignedSubTasks.isEmpty || !executableSubTasks.isEmpty {
    // startable タスクを収集
    let startableSubTasks = (unassignedSubTasks + executableSubTasks).map { task in
        [
            "id": task.id.value,
            "title": task.title,
            "assignee_id": task.assigneeId?.value as Any,  // null or worker-id
            "deps_met": executableSubTasks.contains { $0.id == task.id }
        ] as [String: Any]
    }

    return [
        "action": "start",
        "state": "start",
        "instruction": """
            タスクを開始してください。

            ■ 手順
            1. 開始するタスクを選択（優先度、Worker負荷を考慮）
            2. 未割り当ての場合: assign_task で割り当て
            3. update_task_status で in_progress に変更

            どのタスクを誰に割り当てるかはマネージャーの裁量で判断してください。
            完了後、get_next_action を呼び出してください。
            """,
        "startable_subtasks": startableSubTasks,
        "available_workers": subordinates.map { ... },
        "progress": [...]
    ]
}
```

**具体的な変更ステップ**:

1. `getManagerNextAction` 関数内の Phase 1（assign）を修正
2. Phase 2（start_task）を削除し、Phase 1 に統合
3. アクション名を `assign` → `start` に変更
4. 指示文を更新（マネージャーの裁量を強調）

**所要時間目安**: 1時間

---

### Step 3: パイロットテストで動作確認

**目的**: 統合後の動作確認

**作業**:
1. パイロットテスト実行
2. マネージャーのログで `start` アクションの動作を確認
3. マネージャーが正しく割り当て + 開始を行うか確認

**確認ポイント**:
- `start` アクションが返されるか
- マネージャーが `assign_task` と `update_task_status` を適切に呼ぶか
- ワークフロー全体が正常に完了するか

**所要時間目安**: 1時間

---

### Step 4: 問題対応（必要に応じて）

**目的**: 発見された問題の修正

**想定される問題**:
1. マネージャーが指示を正しく解釈しない
2. 割り当てと開始の順序が混乱
3. 複数タスクの同時開始で問題

**対応方針**:
- 指示文の調整
- 必要に応じて段階的な指示に分割

---

## 変更対象ファイル

| ファイル | 変更内容 |
|----------|----------|
| `Sources/MCPServer/MCPServer.swift` | `getManagerNextAction` 関数の修正 |

## 後方互換性

- 既存のテストへの影響: なし（マネージャーの動作変更のみ）
- クライアント側の変更: 不要（get_next_action のレスポンス形式は維持）

---

## リスクと対策

| リスク | 対策 |
|--------|------|
| マネージャーが指示を理解しない | 指示文を明確化、必要に応じて段階的に |
| テストが通らなくなる | パイロットテストで事前確認 |
| 既存ワークフローとの非互換 | 小さな変更から段階的に |

---

## 成功基準

1. パイロットテストが正常に完了
2. マネージャーが `start` アクションで割り当て + 開始を行う
3. ワーカーが正常にタスクを実行

---

## 次のステップ（本計画完了後）

1. `situational_awareness` 状態の実装
2. `select_action` ツールの実装
3. 調整用ツール（update_task, block_task 等）の実装
