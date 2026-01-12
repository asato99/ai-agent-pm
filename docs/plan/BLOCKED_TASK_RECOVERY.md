# Blocked Task Recovery Feature

## 概要

blockedステータスのタスクをin_progressに復帰させる際の条件付き制御機能。
自己ブロックまたは下位ワーカーによるブロックの場合のみ、再開を許可する。

## 背景

### 問題

Worker workflowにおいて、AIがサブタスクを依存関係なしで作成した場合:
1. `get_next_action`が任意の順序でサブタスクを返す
2. AIが実行順序の問題に気づき、自己判断でタスクをblockedに設定
3. このblocked状態からの復帰方法が明確でない

### UC003での具体例

```
1. Worker がサブタスクを作成（依存関係なし）
2. get_next_action → 「ファイル確認」タスクを返す（本来は「ファイル作成」が先）
3. AIが実行 → ファイルが存在しないことを発見
4. AIが自己判断で update_task_status(確認タスク, blocked) を呼び出し
5. タスクがblocked状態で停滞
```

## 設計

### 基本原則

1. **ステータス更新者の常時記録**: blocked に限らず、すべてのステータス変更で更新者を記録
2. **blocked → in_progress 遷移の条件付き制御**: 更新者が「自身」または「自身の下位ワーカー」の場合のみ許可

### ステータス更新者の追跡

**設計方針**: Task エンティティに汎用的な更新者追跡フィールドを追加

理由:
1. StateChangeEvent は監査用途、Task フィールドは即時判定用途（役割分離）
2. blocked 以外のステータスでも更新者情報は有用（誰が完了させたか等）
3. 判定時のクエリが単純化される

### エンティティ変更

```swift
// Task.swift に追加
public var statusChangedByAgentId: AgentID?  // 最後にステータスを変更したエージェント
public var statusChangedAt: Date?            // ステータス変更日時

// blocked 専用（任意）
public var blockedReason: String?            // ブロック理由
```

### ステータス遷移ロジック変更

```swift
// UpdateTaskStatusUseCase.swift

public func execute(...) throws -> Task {
    // ... 既存のバリデーション ...

    // blocked → inProgress の遷移時に追加チェック
    if previousStatus == .blocked && newStatus == .inProgress {
        try validateUnblockPermission(task: task, requestingAgentId: agentId)
    }

    // ステータス変更
    task.status = newStatus
    task.updatedAt = Date()

    // 更新者情報を記録（常時）
    task.statusChangedByAgentId = agentId
    task.statusChangedAt = Date()

    // blocked の場合は理由もクリアまたは設定
    if newStatus != .blocked {
        task.blockedReason = nil
    }

    // ... 保存処理 ...
}

private func validateUnblockPermission(task: Task, requestingAgentId: AgentID?) throws {
    guard let lastChangedBy = task.statusChangedByAgentId else {
        // statusChangedByAgentId が未設定の場合は許可（後方互換性）
        return
    }

    guard let requestingAgent = requestingAgentId else {
        throw UseCaseError.validationFailed("Agent ID required to unblock task")
    }

    // 1. 自己変更の場合 → 許可
    if lastChangedBy == requestingAgent {
        return
    }

    // 2. 変更者が自身の下位ワーカーの場合 → 許可
    let subordinates = try agentRepository.findByParent(requestingAgent)
    if subordinates.contains(where: { $0.id == lastChangedBy }) {
        return
    }

    // 3. それ以外 → 拒否
    throw UseCaseError.validationFailed(
        "Cannot unblock task. Last status change by \(lastChangedBy.value). Only self or subordinate workers can unblock."
    )
}
```

### 完了時チェック（Completion Gate）

親タスクの完了報告時に、blocked サブタスクの有無をチェックし、自己ブロックの場合は再開を促す:

```swift
// getWorkerNextAction / getManagerNextAction の report_completion 判定部分を修正

// 全サブタスク完了チェック（既存）
if completedSubTasks.count == subTasks.count {
    return ["action": "report_completion", ...]
}

// ↓ 以下を追加 ↓

// blocked サブタスクがある場合の処理
let blockedSubTasks = subTasks.filter { $0.status == .blocked }
if !blockedSubTasks.isEmpty {
    // 自己ブロック（または下位ワーカーによるブロック）をチェック
    let selfBlockedTasks = blockedSubTasks.filter { task in
        guard let changedBy = task.statusChangedByAgentId else { return true }  // 後方互換
        return changedBy == mainTask.assigneeId  // Worker の場合
        // Manager の場合は subordinates チェックも追加
    }

    if let blockedTask = selfBlockedTasks.first {
        return [
            "action": "unblock_and_continue",
            "instruction": """
                完了できません。ブロック中のサブタスクがあります。
                '\(blockedTask.title)' は以前あなた自身がブロックしました。
                update_task_status で '\(blockedTask.id.value)' を 'in_progress' に変更し、
                作業を再開してください。
                """,
            "state": "has_self_blocked_subtask",
            "blocked_subtask": [
                "id": blockedTask.id.value,
                "title": blockedTask.title,
                "blocked_reason": blockedTask.blockedReason ?? "unknown"
            ]
        ]
    } else {
        // 他者によるブロック → 完了不可、待機を指示
        return [
            "action": "wait_for_unblock",
            "instruction": "他のエージェントによってブロックされたサブタスクがあります。解除を待ってください。",
            "state": "has_external_blocked_subtask",
            "blocked_subtasks": blockedSubTasks.map { ["id": $0.id.value, "title": $0.title] }
        ]
    }
}
```

### pendingSubTasks の依存関係フィルタリング

`get_next_action` で次のサブタスクを選択する際、依存関係が満たされていないタスクを除外する:

```swift
// getWorkerNextAction / getManagerNextAction の pendingSubTasks 定義を修正

// 現在の実装（依存関係を考慮しない）
let pendingSubTasks = subTasks.filter { $0.status == .todo || $0.status == .backlog }

// ↓ 修正後 ↓

// 依存関係が満たされたタスクのみを pending として扱う
let pendingSubTasks = subTasks.filter { task in
    // ステータスが todo または backlog
    guard task.status == .todo || task.status == .backlog else { return false }

    // 依存関係がない場合は即座に実行可能
    guard !task.dependencies.isEmpty else { return true }

    // 全ての依存タスクが done であることを確認
    return task.dependencies.allSatisfy { depId in
        subTasks.first(where: { $0.id == depId })?.status == .done
    }
}
```

**効果**:
1. 依存関係が設定されている場合、先行タスク完了まで後続タスクは選択されない
2. AIが依存関係を正しく設定すれば、実行順序が保証される
3. AIが依存関係を設定しなかった場合でも、既存動作（任意順序）は維持される

## DBマイグレーション (v25)

```sql
-- Migration v25: Add status change tracking fields
ALTER TABLE tasks ADD COLUMN status_changed_by_agent_id TEXT REFERENCES agents(id);
ALTER TABLE tasks ADD COLUMN status_changed_at DATETIME;
ALTER TABLE tasks ADD COLUMN blocked_reason TEXT;

-- Index for blocked task queries
CREATE INDEX idx_tasks_status_changed_by ON tasks(status_changed_by_agent_id);
```

## 実装ファイル一覧

| ファイル | 操作 | 説明 |
|---------|------|------|
| `Sources/Domain/Entities/Task.swift` | 修正 | statusChangedByAgentId, statusChangedAt, blockedReason 追加 |
| `Sources/UseCase/TaskUseCases.swift` | 修正 | validateUnblockPermission 追加、全ステータス変更時に更新者記録 |
| `Sources/Infrastructure/Database/DatabaseSetup.swift` | 修正 | v25マイグレーション追加 |
| `Sources/Infrastructure/Repositories/TaskRepository.swift` | 修正 | 新フィールドの永続化対応 |
| `Sources/MCPServer/MCPServer.swift` | 修正 | (1) pendingSubTasks の依存関係フィルタリング (2) 完了時の blocked チェック |

## 実装順序

1. **Phase 1: ブロック対応（補完機能）**
   - 1-1: Task エンティティにフィールド追加（statusChangedByAgentId, statusChangedAt, blockedReason）
   - 1-2: DBマイグレーション v25 実装
   - 1-3: TaskRepository の永続化対応
   - 1-4: UpdateTaskStatusUseCase で更新者記録 + 権限チェック
   - 1-5: get_next_action に完了時チェック（Completion Gate）追加

2. **Phase 1 検証: UC003 統合テスト実行**
   - UC003 統合テストを実行
   - 結果を報告（成功/失敗、ログ確認）
   - Phase 2 への進行可否を判断

3. **Phase 2: 依存関係フィルタリング（直接的な解決）**
   - `pendingSubTasks` の定義を修正
   - 依存タスクが done でないタスクを除外
   - UC003 の根本原因を解消

## テスト計画

### Phase 1: ブロック対応のテスト

1. **statusChangedByAgentId 記録テスト**
   - ステータス変更時に更新者IDが記録される
   - ステータス変更時に更新日時が記録される
   - blocked 以外への遷移時に blockedReason がクリアされる

2. **ステータス変更権限テスト**
   - 自己変更 → 許可
   - 下位ワーカー変更 → 許可
   - 上位マネージャー変更 → 拒否
   - 別系統エージェント変更 → 拒否
   - statusChangedByAgentId が NULL → 許可（後方互換）

3. **完了ゲートテスト**
   - 全サブタスク done → report_completion 返却
   - 自己 blocked サブタスクあり → unblock_and_continue 返却
   - 外部 blocked サブタスクあり → wait_for_unblock 返却
   - pending サブタスクあり → 次タスクを返却（完了不可）

### Phase 2: 依存関係フィルタリングのテスト

1. **pendingSubTasks フィルタリングテスト**
   - 依存関係なし → 全て pending として返る
   - 依存関係あり + 依存タスク未完了 → pending から除外
   - 依存関係あり + 依存タスク完了 → pending に含まれる
   - 複数依存 + 一部完了 → pending から除外
   - 複数依存 + 全て完了 → pending に含まれる

2. **get_next_action 依存関係テスト**
   - サブタスク A→B の依存関係で、A が pending、B が pending → A のみ返る
   - A 完了後 → B が返る

### 統合テスト (UC003拡張)

**シナリオ A: 依存関係フィルタリングによる順序制御**
1. Worker がサブタスク作成（依存関係あり: 作成→確認）
2. get_next_action → 「作成」タスクのみ返る
3. 「作成」完了
4. get_next_action → 「確認」タスクが返る
5. 「確認」完了
6. 全タスク完了

**シナリオ B: 自己ブロックからの復帰**
1. Worker がサブタスク作成（依存関係なし）
2. 「確認」タスクが先に選択される
3. AI が自己判断で blocked に設定
4. 「作成」タスクを完了
5. 完了報告試行 → unblock_and_continue が返る
6. Worker が unblock して再開
7. 全タスク完了

## 後方互換性

- `statusChangedByAgentId` が NULL の既存タスクは、無条件でunblock許可（従来動作維持）
- 全ステータス変更で更新者を記録（blocked に限らない）

## 将来拡張

1. **ブロック理由の分類**: `blockedReason` を enum 化（dependency, resource, external, manual）
2. **自動unblock**: 依存完了時に自動的にunblockするオプション
3. **ブロック通知**: 上位マネージャーへの通知機能
