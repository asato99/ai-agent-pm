# MCP Agent Control Analysis

Agent制御機構、特に `get_next_action` 周辺の実装調査レポート。

## 調査日

2026-01-17

## 調査背景

UC006/UC007統合テストの失敗分析において、Worker（特にJA Worker）が無限タスク分解ループに陥る問題を発見。
MCP Agent制御機構の詳細調査を実施。

---

## システムアーキテクチャ

### 全体構成

```
┌─────────────────────────────────────────────────────────────────┐
│                        Coordinator                               │
│  (Python: runner/src/aiagent_runner/coordinator.py)             │
│                                                                  │
│  - ポーリングループで全エージェントを監視                           │
│  - get_agent_action API でエージェント起動判断                     │
│  - Claude CLI等を子プロセスとして起動                              │
└───────────────────────┬─────────────────────────────────────────┘
                        │ Unix Socket (MCP Protocol)
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                       MCP Server                                 │
│  (Swift: Sources/MCPServer/MCPServer.swift)                     │
│                                                                  │
│  - get_agent_action: Coordinator→起動判断                        │
│  - get_next_action: Agent Instance→次のアクション指示            │
│  - authenticate, get_my_task, create_task, etc.                 │
└─────────────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Agent Instance (Claude Code)                   │
│                                                                  │
│  1. authenticate → セッション確立                                │
│  2. get_next_action → 次の指示を取得                             │
│  3. 指示に従って作業 → get_next_action を繰り返し                 │
│  4. report_completed → 完了報告                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 2つのAction API

| API | 呼び出し元 | 目的 | ファイル位置 |
|-----|-----------|------|-------------|
| `get_agent_action` | Coordinator | エージェント起動判断 | MCPServer.swift:1184 |
| `get_next_action` | Agent Instance | 次のワークフロー指示 | MCPServer.swift:1861 |

---

## get_agent_action（Coordinator用）

### 概要

Coordinatorが各エージェントを起動すべきか判断するためのAPI。

**ファイル**: `Sources/MCPServer/MCPServer.swift:1184-1455`

### 返却値

| action | 意味 |
|--------|------|
| `start` | エージェントを起動すべき |
| `hold` | 起動不要（現状維持） |
| `stop` | 停止すべき（将来用） |

### 判断ロジック（順序）

```
1. プロジェクト一時停止チェック
   - project.status == .paused → hold (project_paused)

2. エージェント割り当てチェック
   - isAgentAssignedToProject == false → hold (agent_not_assigned)

3. blockedタスクチェック
   - blockedタスクあり かつ in_progressなし → hold (blocked_without_in_progress)

4. アクティブセッションチェック
   - 有効期限内のセッションあり → hold (already_running)

5. Manager待機状態チェック（hierarchyType == manager の場合）
   - progress == "workflow:worker_blocked" → start (worker_blocked)
   - progress == "workflow:handled_blocked" → hold (handled_blocked)
   - progress == "workflow:waiting_for_workers"
     - まだWorkerが実行中 → hold (waiting_for_workers)
     - 全Worker完了 → start

6. Pending Purpose チェック（チャット機能用）
   - pending_agent_purposesテーブルにレコードあり → start (has_pending_purpose)
   - TTL超過 → hold + チャットにエラーメッセージ

7. in_progressタスクチェック
   - in_progressタスクあり → start (has_in_progress_task)
   - なし → hold (no_in_progress_task)
```

### 問題点

**Coordinatorは「起動すべきか」のみ判断し、エージェントの振る舞いは制御しない。**
振る舞い制御は `get_next_action` に委譲される。

---

## get_next_action（Agent Instance用）

### 概要

Agent Instance（Claude Code等）がワークフローの次の指示を取得するためのAPI。

**ファイル**: `Sources/MCPServer/MCPServer.swift:1861-1974`

### エントリーポイント

```swift
private func getNextAction(session: AgentSession) throws -> [String: Any] {
    // 1. モデル検証チェック
    if session.modelVerified == nil {
        return ["action": "report_model", ...]
    }

    // 2. Chat機能チェック
    if session.purpose == .chat {
        return ["action": "get_pending_messages", ...] or ["action": "logout", ...]
    }

    // 3. メインタスク取得
    guard let main = mainTask else {
        return ["action": "get_task", ...]
    }

    // 4. 階層タイプに応じた分岐
    switch agent.hierarchyType {
    case .worker:
        return try getWorkerNextAction(mainTask: main, phase: phase, allTasks: allTasks)
    case .manager:
        return try getManagerNextAction(mainTask: main, phase: phase, allTasks: allTasks)
    }
}
```

### 返却されるアクション一覧

| action | 説明 | 次に呼ぶべきAPI |
|--------|------|----------------|
| `report_model` | モデル情報申告 | report_model |
| `get_task` | タスク詳細取得 | get_my_task |
| `create_subtasks` | サブタスク作成 | create_task × N |
| `start_subtask` | サブタスク開始 | update_task_status |
| `execute_subtask` | サブタスク実行 | (実作業) |
| `delegate` | Worker委譲 | assign_task |
| `exit` | 待機終了 | logout |
| `report_completion` | 完了報告 | report_completed |
| `review_and_resolve_blocks` | ブロック対処 | update_task_status |

---

## Worker ワークフロー制御

**ファイル**: `Sources/MCPServer/MCPServer.swift:1979-2210`

### 状態遷移図

```
                    get_my_task呼び出し
                          │
                          ▼
              ┌───────────────────────┐
              │ phase: task_fetched   │
              │ subTasks: empty       │
              └───────────┬───────────┘
                          │ → create_subtasks
                          ▼
              ┌───────────────────────┐
              │ phase: creating_subtasks │
              │ subTasks: creating    │
              └───────────┬───────────┘
                          │ → start_subtask
                          ▼
              ┌───────────────────────┐
              │ phase: subtasks_created  │
              │ サブタスク実行中         │
              └───────────┬───────────┘
                          │
           ┌──────────────┼──────────────┐
           │              │              │
           ▼              ▼              ▼
    execute_subtask  start_subtask  report_completion
    (in_progress有)  (pending有)    (全て完了)
```

### 判断ロジック詳細

```swift
// 1. サブタスク未作成 → 作成指示
if phase == "workflow:task_fetched" && subTasks.isEmpty {
    return ["action": "create_subtasks", ...]
}

// 2. サブタスクが存在する場合
if !subTasks.isEmpty {
    // 2a. 全完了 → 完了報告
    if completedSubTasks.count == subTasks.count {
        return ["action": "report_completion", ...]
    }

    // 2b. blockedのみ残り → 対処検討
    if !blockedSubTasks.isEmpty && pendingSubTasks.isEmpty && inProgressSubTasks.isEmpty {
        return ["action": "review_and_resolve_blocks", ...]
    }

    // 2c. 実行中あり → 続行
    if let currentSubTask = inProgressSubTasks.first {
        return ["action": "execute_subtask", ...]
    }

    // 2d. 次のサブタスク開始
    if let nextSubTask = pendingSubTasks.first {
        return ["action": "start_subtask", ...]
    }
}

// 3. 作成中フェーズ完了
if phase == "workflow:creating_subtasks" && !subTasks.isEmpty {
    return ["action": "start_subtask", ...]
}

// フォールバック
return ["action": "get_task", ...]
```

---

## Manager ワークフロー制御

**ファイル**: `Sources/MCPServer/MCPServer.swift:2215-2553`

### Workerとの違い

| 項目 | Worker | Manager |
|------|--------|---------|
| サブタスク実行 | 自分で実行 | Workerに委譲 |
| 待機 | なし | Workerの完了を待つ |
| 委譲先 | なし | 下位Worker |

### 状態遷移図

```
              ┌───────────────────────┐
              │ phase: task_fetched   │
              │ subTasks: empty       │
              └───────────┬───────────┘
                          │ → create_subtasks
                          ▼
              ┌───────────────────────┐
              │ phase: creating_subtasks │
              └───────────┬───────────┘
                          │ → delegate
                          ▼
              ┌───────────────────────┐
              │ phase: subtasks_created  │
              │ サブタスク委譲中         │
              └───────────┬───────────┘
                          │
           ┌──────────────┴──────────────┐
           │                             │
           ▼                             ▼
        delegate                        exit
    (pending有→Worker委譲)    (in_progress有→待機終了)
           │                             │
           │                             ▼
           │              ┌───────────────────────┐
           │              │ phase: waiting_for_workers │
           │              │ Workerの完了を待つ        │
           │              └───────────┬───────────┘
           │                          │
           └──────────────┬───────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │ 全サブタスク完了        │
              │ → report_completion   │
              └───────────────────────┘
```

### Managerの`exit`アクション

```swift
// 実行中のサブタスクがある → Worker の完了を待つ
if !inProgressSubTasks.isEmpty {
    // 待機状態を Context に記録
    let context = Context(
        progress: "workflow:waiting_for_workers"
    )
    try contextRepository.save(context)

    return [
        "action": "exit",
        "instruction": """
            サブタスクを Worker に委譲しました。
            Worker の完了を待つため、ここでプロセスを終了してください。
            Coordinator が Worker 完了後に自動的に再起動します。
            """,
        "state": "waiting_for_workers",
        "reason": "subtasks_delegated_to_workers"
    ]
}
```

**注意**: Managerは`exit`を受け取ったら`logout`を呼び、プロセスを終了する。
Coordinatorが定期的にチェックし、全Workerが完了したらManagerを再起動する。

---

## UC006失敗の根本原因分析

### 症状

- ZH Worker: 3サブタスク作成 → 全完了 → `hello_zh.txt`作成 ✅
- JA Worker: 19+サブタスク作成 → 実行されず → `hello_ja.txt`未作成 ❌

### 問題の構造

```
get_next_action → "create_subtasks" 指示
    ↓
Agent（Claude）がサブタスクを作成
    ↓
get_next_action を再度呼び出し
    ↓
【問題】phase判定でサブタスク作成完了を正しく検出できず
    ↓
再度 "create_subtasks" 指示が返される
    ↓
無限ループ
```

### 技術的原因

1. **phaseの不整合**
   - `workflow:task_fetched` の状態でサブタスクが存在しない場合のみ `create_subtasks`
   - サブタスク作成後、phaseが `workflow:creating_subtasks` に更新される
   - しかし、Agentがget_next_actionを呼ぶタイミングによっては、DB更新が反映されていない可能性

2. **非決定論的なAgent挙動**
   - 同じsystem_promptでもZHとJAで異なる結果
   - Agentが`create_subtasks`指示を受けた後の解釈のばらつき
   - 「サブタスク作成後にget_next_actionを呼ぶ」指示に従わないケース

3. **Context更新のタイミング**
   - `get_my_task`呼び出し時に `workflow:task_fetched` を記録
   - サブタスク作成完了は明示的に記録されない（create_taskハンドラ内で行うべき？）

### 推測される失敗パターン

```
JA Worker:
1. authenticate → 成功
2. get_next_action → "get_task"
3. get_my_task → タスク取得、phase = "task_fetched"
4. get_next_action → "create_subtasks"
5. create_task × 3 → サブタスク3つ作成
6. 【問題】Agent が get_next_action を呼ばず、再度 create_task を呼ぶ
7. create_task × N → 追加サブタスク作成
8. ... 繰り返し ...
```

---

## 推奨される改善策

### 短期（UC006修正）

1. **サブタスク作成上限の強制**
   ```swift
   // create_task内でチェック
   let existingSubTasks = try taskRepository.findByParentTask(parentTaskId)
   if existingSubTasks.count >= 5 {
       throw MCPError.tooManySubtasks(parentTaskId)
   }
   ```

2. **phase遷移の自動化**
   - サブタスクが1つ以上存在する場合、`workflow:creating_subtasks` → `workflow:subtasks_created` に自動遷移

3. **より明確な指示文**
   ```
   サブタスクを2〜5個作成してください。
   【重要】create_taskは最大5回まで呼んでください。
   作成完了後、必ず get_next_action を呼び出してください。
   追加のサブタスクを作成しないでください。
   ```

### 中期（アーキテクチャ改善）

1. **状態機械の厳格化**
   - 各stateからの遷移を厳密に定義
   - 不正な状態遷移を拒否

2. **Coordinator側でのガードレール**
   - サブタスク数の監視
   - 異常なタスク作成を検出してAgent停止

3. **ログ強化**
   - 各get_next_action呼び出しとレスポンスを記録
   - デバッグ時に状態遷移を追跡可能に

---

## 関連ファイル

| ファイル | 説明 |
|---------|------|
| `Sources/MCPServer/MCPServer.swift:1184-1455` | get_agent_action 実装 |
| `Sources/MCPServer/MCPServer.swift:1861-1974` | get_next_action エントリーポイント |
| `Sources/MCPServer/MCPServer.swift:1979-2210` | getWorkerNextAction |
| `Sources/MCPServer/MCPServer.swift:2215-2553` | getManagerNextAction |
| `runner/src/aiagent_runner/coordinator.py` | Coordinator ポーリングループ |
| `docs/plan/STATE_DRIVEN_WORKFLOW.md` | 状態駆動ワークフロー設計 |
| `docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md` | Coordinatorアーキテクチャ |

---

## 結論

`get_next_action` の実装は設計通りに動作しているが、**LLMの非決定論的な挙動**と**状態遷移の暗黙的な期待**の組み合わせにより、失敗パターンが発生している。

特に:
- Agentが指示に従わず追加のサブタスクを作成し続ける
- phase遷移が自動ではなく、Agentの正しい振る舞いに依存している

根本的な解決には、**サーバー側でのガードレール強化**と**状態機械の厳格化**が必要。
