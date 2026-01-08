# State-Driven Workflow Control

Agent Instance のワークフローをアプリ側で制御するための設計ドキュメント。

## 概要

Agent Instance（Claude Code等のLLM）に対して、プロンプトで全ての指示を与えるのではなく、
`get_next_action` MCP ツールを通じて状態に応じた指示を都度返す。

### メリット
- アプリ側がワークフローを完全に制御
- LLM のコンテキストに依存しない
- 役割や状態に応じた柔軟な指示が可能

---

## プロンプト構成

Agent Instance に渡すプロンプトは2つの要素で構成される:

### 1. ユーザー設定プロンプト（system_prompt）

エージェントの役割や振る舞いを定義。DBの `agents.system_prompt` に保存。

```
あなたはバックエンドエンジニアです。
Python と FastAPI を使用してAPIを実装してください。
コードは必ずテストを書いてください。
```

### 2. 制御指示プロンプト（Coordinator が生成）

ワークフロー制御に必要な最小限の指示。

```
## 認証
authenticate を呼び出してください。
- agent_id: "agt_xxx"
- passkey: "xxx"
- project_id: "prj_xxx"

## ワークフロー
認証後、get_next_action を呼び出し、返された instruction に従ってください。
作業が完了するまでこれを繰り返してください。
```

### プロンプト統合

最終的なプロンプト = 制御指示 + ユーザー設定プロンプト

```
[制御指示プロンプト]

---

[ユーザー設定プロンプト（system_prompt）]
```

---

## 共通ワークフロー: サブタスク分解

**全てのエージェント（Worker・Manager 共通）** は、割り当てられたタスクをサブタスクに分解する。

### 共通フロー

```
1. authenticate
2. get_next_action → "get_task"
3. get_my_task → タスク詳細取得
4. get_next_action → "create_subtasks"
5. create_task × N → サブタスク作成（2〜5個）
6. （以降、hierarchy_type によって異なる）
```

---

## 階層ベースの制御

エージェントには `hierarchy_type`（AgentHierarchyType）があり、
**サブタスク作成後の行動** が異なる。

※ `role_type`（AgentRoleType: developer, reviewer, tester 等）は役割の専門性を表し、
  `hierarchy_type` はタスク管理の権限を表す。

### HierarchyType 一覧

| hierarchy_type | 説明 | サブタスク作成後の行動 |
|----------------|------|------------------------|
| worker | 実作業を行う | サブタスクを **自分で順番に実行** |
| manager | 作業を分割・委譲 | サブタスクを **Worker に割り当て**（自分では実行しない） |

### Worker のワークフロー

```
1. authenticate
2. get_next_action → "get_task"
3. get_my_task → タスク詳細取得
4. get_next_action → "create_subtasks"
5. create_task × N → サブタスク作成
6. get_next_action → "execute_subtask"
7. サブタスクを実行 → update_task_status で done に
8. get_next_action → "execute_subtask"（次のサブタスク）
   ... 繰り返し ...
9. get_next_action → "report_completion"（全サブタスク完了後）
10. report_completed
```

Worker は **サブタスクを作成し、自分で順番に実行する**。

### Manager のワークフロー

```
1. authenticate
2. get_next_action → "get_task"
3. get_my_task → タスク詳細取得
4. get_next_action → "create_subtasks"
5. create_task × N → サブタスク作成
6. get_next_action → "delegate"
7. サブタスクを Worker に割り当て
8. get_next_action → "wait"（Worker の完了を待つ）
   ... Worker が実行 ...
9. get_next_action → "report_completion"（全サブタスク完了後）
10. report_completed
```

Manager は **サブタスクを作成し、Worker に割り当てる**。
**Manager 自身は実作業を行わない。**

---

## get_next_action の状態判断

### 入力
- session_token（認証済みセッション）

### 判断に使用する DB 情報

| 情報 | 取得元 | 用途 |
|------|--------|------|
| agent.hierarchy_type | agents テーブル | Worker か Manager かの判断 |
| メインタスク | tasks (assignee_id, status, parent_task_id=NULL) | 現在のタスク |
| サブタスク | tasks (parent_task_id=メインタスク) | 作成済みサブタスク |
| Context | contexts (task_id) | ワークフローフェーズの記録 |

### ワークフローフェーズの追跡

`get_my_task` を呼んだかどうかなど、DB状態からは直接判断できない情報は
**Context に記録** して追跡する。

```
Context.progress に以下を記録:
- "workflow:task_fetched" - get_my_task を呼んだ
- "workflow:subtasks_created" - サブタスク作成完了
- "workflow:executing" - 実行中
```

### 状態判断ロジック

```
function getNextAction(agentId, projectId):
    agent = getAgent(agentId)
    mainTask = getInProgressTask(agentId, projectId, parentTaskId=NULL)
    latestContext = getLatestContext(mainTask.id)

    # 1. タスク詳細を取得していない
    if latestContext == NULL or not latestContext.progress.startsWith("workflow:"):
        return {
            action: "get_task",
            instruction: "get_my_task を呼び出してタスク詳細を取得してください"
        }

    # 2. 階層に応じた分岐
    if agent.hierarchyType == "worker":
        return getWorkerNextAction(mainTask, latestContext)
    else if agent.hierarchyType == "manager":
        return getManagerNextAction(mainTask, latestContext)
```

#### 共通: サブタスク作成判断

```
function checkSubtaskCreation(mainTask, phase, subTasks):
    # サブタスク未作成
    if phase == "workflow:task_fetched" and subTasks.isEmpty():
        return {
            action: "create_subtasks",
            instruction: "タスクを2-5個のサブタスクに分解してください。create_task を使用します。",
            task: mainTask
        }
    return null  # サブタスク作成済み or 作成中
```

#### Worker の状態判断

```
function getWorkerNextAction(mainTask, latestContext):
    phase = latestContext.progress
    subTasks = getSubTasks(mainTask.id)

    # サブタスク作成チェック（共通）
    createAction = checkSubtaskCreation(mainTask, phase, subTasks)
    if createAction != null:
        return createAction

    # サブタスク作成済み → 自分で順番に実行
    pendingSubTasks = subTasks.filter(status in [backlog, todo])
    inProgressSubTasks = subTasks.filter(status == in_progress)
    completedSubTasks = subTasks.filter(status == done)

    # 全サブタスク完了
    if completedSubTasks.count == subTasks.count and not subTasks.isEmpty():
        return {
            action: "report_completion",
            instruction: "全サブタスクが完了しました。report_completed を呼んでください"
        }

    # 実行中のサブタスクがある → 続けて実行
    if not inProgressSubTasks.isEmpty():
        return {
            action: "execute_subtask",
            instruction: "サブタスクを実行してください。完了したら update_task_status で done にしてください。",
            subtask: inProgressSubTasks[0]
        }

    # 次のサブタスクを開始
    if not pendingSubTasks.isEmpty():
        return {
            action: "start_subtask",
            instruction: "次のサブタスクを開始してください。update_task_status で in_progress にしてください。",
            subtask: pendingSubTasks[0]
        }
```

#### Manager の状態判断

```
function getManagerNextAction(mainTask, latestContext):
    phase = latestContext.progress
    subTasks = getSubTasks(mainTask.id)

    # サブタスク作成チェック（共通）
    createAction = checkSubtaskCreation(mainTask, phase, subTasks)
    if createAction != null:
        return createAction

    # サブタスク作成済み → Worker に委譲
    pendingSubTasks = subTasks.filter(status in [backlog, todo])
    inProgressSubTasks = subTasks.filter(status == in_progress)
    completedSubTasks = subTasks.filter(status == done)

    # 全サブタスク完了
    if completedSubTasks.count == subTasks.count and not subTasks.isEmpty():
        return {
            action: "report_completion",
            instruction: "全サブタスクが完了しました。report_completed を呼んでください"
        }

    # 実行中のサブタスクがある → Worker の完了を待つ
    if not inProgressSubTasks.isEmpty():
        return {
            action: "wait",
            instruction: "サブタスクが実行中です。Worker の完了を待ってください。",
            in_progress: inProgressSubTasks
        }

    # 未割り当てのサブタスクがある → Worker に委譲
    if not pendingSubTasks.isEmpty():
        return {
            action: "delegate",
            instruction: "次のサブタスクを Worker に割り当ててください",
            next_subtask: pendingSubTasks[0]
        }
```

---

## Context を使ったフェーズ記録

### 記録タイミング

| イベント | 記録する progress |
|----------|-------------------|
| get_my_task 呼び出し時 | "workflow:task_fetched" |
| create_task 完了時 | "workflow:subtasks_created" |
| 作業開始時 | "workflow:executing" |
| report_completed 呼び出し時 | "workflow:completed" |

### 実装方法

`get_my_task` ハンドラ内で自動的に Context を作成:

```swift
func getMyTask(agentId, projectId) {
    let task = findInProgressTask(agentId, projectId)

    // ワークフローフェーズを記録
    let context = Context(
        taskId: task.id,
        agentId: agentId,
        progress: "workflow:task_fetched"
    )
    contextRepository.save(context)

    return task
}
```

---

## 未解決の課題

### 1. 複数サブタスクの並列実行
- 複数の Worker が同時にサブタスクを実行する場合の調整
- Manager から複数 Worker への並列委譲

### 2. エラーハンドリング
- サブタスクが失敗した場合の親タスクへの影響
- リトライや代替エージェントへの再割り当て

### 3. サブタスクの粒度制御
- サブタスク数の適切な範囲（現在は2〜5個を推奨）
- 再帰的なサブタスク分解の可否

---

## 実装計画

### Phase 1: Worker ワークフロー
1. Context にフェーズ記録を追加
2. get_next_action で Worker 用ロジック実装
3. テスト

### Phase 2: Manager ワークフロー
1. get_next_action で Manager 用ロジック実装
2. サブタスク作成・管理のフロー
3. テスト

### Phase 3: 役割間連携
1. Manager → Worker へのサブタスク割り当て
2. Worker 完了時の Manager への通知
3. 統合テスト
