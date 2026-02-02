# Web UI 機能拡張プラン（改訂版）

## 概要

macOSアプリ（AIAgentPM）の機能をweb-uiに展開するための実装計画。
**macOSアプリの挙動を正確に再現**し、適切な**権限モデル**を実装する。

---

## 設計原則

### 1. macOSアプリとの整合性

web-uiはmacOSアプリと**同一の挙動**を提供する。独自機能の追加は行わない。

| 機能 | macOSアプリ | web-ui（実装目標） |
|------|------------|-------------------|
| タスクカードタップ | 詳細画面へ遷移 | 詳細パネル表示 |
| タスクドラッグ | ステータス変更 | ステータス変更 |
| タスクカードメニュー | **なし** | **なし**（削除） |
| ステータス変更 | ピッカーで選択 | ピッカーで選択 |
| タスク削除 | **なし**（cancelledへ変更） | **なし**（ピッカーでcancelled選択） |
| 編集ボタン | TaskDetailViewツールバー | TaskDetailPanelヘッダー |
| Handoffボタン | TaskDetailViewツールバー | TaskDetailPanelヘッダー |

### 2. 権限モデル

**ユーザー＝ログインエージェント**として扱い、以下の権限ルールを適用する。

#### ステータス変更権限

参照: `UpdateTaskStatusUseCase.validateStatusChangePermission()`

```
statusChangedByAgentId が...
  - 未設定 → 許可（後方互換性）
  - 自分自身 → 許可
  - 自分の下位エージェント → 許可
  - 上記以外 → 拒否（403 Forbidden）
```

#### 担当者変更制限

参照: `AssignTaskUseCase`

```
タスクステータスが...
  - in_progress → 担当者変更不可（作業コンテキスト破棄防止）
  - blocked → 担当者変更不可
  - その他 → 担当者変更可能
```

#### ステータス遷移制限

参照: `UpdateTaskStatusUseCase.canTransition()`

```
有効な遷移のみ許可（ホワイトリスト方式）
backlog → todo → in_progress → done
                      ↓
                  cancelled（任意のステータスから）
                  blocked（in_progressから）
```

---

## Phase 1: タスクカード修正 🔴 要対応

### 現状の問題

- ❌ メニューボタンを追加（macOSアプリにはない）
- ❌ 削除確認ダイアログを実装（不要）
- ❌ DELETE API直接呼び出し（macOSアプリは使用しない）

### 修正内容

**TaskCard.tsx**:
```tsx
// 削除: メニューボタン、削除確認ダイアログ
// 維持: タップで詳細表示、ドラッグでステータス変更
export function TaskCard({ task, onClick }: TaskCardProps) {
  return (
    <div onClick={() => onClick?.(task.id)}>
      <h4>{task.title}</h4>
      <PriorityBadge priority={task.priority} />
      {task.assigneeName && <span>{task.assigneeName}</span>}
    </div>
  )
}
```

**TaskBoard.tsx**:
- ドラッグ&ドロップは維持
- 遷移失敗時はAPIエラーをトースト表示

### テスト修正

**task-board.spec.ts**:
- ❌ 削除テストを削除
- ✅ ドラッグ&ドロップでの無効な遷移をテスト

---

## Phase 2: REST API 権限チェック追加 🔴 要対応

### 現状の問題

`RESTServer.swift` の `updateTask()`:
- ❌ 権限チェックなし
- ❌ ステータス遷移検証なし
- ❌ 担当者変更制限なし

### 修正内容

**RESTServer.swift**:

```swift
private func updateTask(request: Request, context: AuthenticatedContext) async throws -> Response {
    let loggedInAgentId = context.agentId  // ログイン中のエージェント

    guard var task = try taskRepository.findById(taskId) else {
        return errorResponse(status: .notFound, message: "Task not found")
    }

    // ステータス変更時の権限チェック
    if let newStatusStr = updateRequest.status,
       let newStatus = TaskStatus(rawValue: newStatusStr) {

        // 1. 遷移検証
        guard UpdateTaskStatusUseCase.canTransition(from: task.status, to: newStatus) else {
            return errorResponse(status: .badRequest,
                message: "Invalid transition: \(task.status.rawValue) -> \(newStatus)")
        }

        // 2. 権限検証（自分または下位エージェントのみ）
        if let lastChangedBy = task.statusChangedByAgentId {
            let subordinates = try agentRepository.findByParent(loggedInAgentId)
            let canChange = lastChangedBy == loggedInAgentId ||
                           subordinates.contains { $0.id == lastChangedBy }
            guard canChange else {
                return errorResponse(status: .forbidden,
                    message: "Cannot change status. Last changed by \(lastChangedBy.value)")
            }
        }

        task.status = newStatus
        task.statusChangedByAgentId = loggedInAgentId
        task.statusChangedAt = Date()
    }

    // 担当者変更時の制限チェック
    if let newAssigneeId = updateRequest.assigneeId,
       task.assigneeId?.value != newAssigneeId {
        guard task.status != .inProgress && task.status != .blocked else {
            return errorResponse(status: .badRequest,
                message: "Cannot reassign task in \(task.status.rawValue) status")
        }
    }

    // ... 以降の更新処理
}
```

### 新規API

**GET /api/tasks/:taskId/permissions**

ログイン中のエージェントがそのタスクに対して持つ権限を返す。

```json
{
  "canEdit": true,
  "canChangeStatus": true,
  "canReassign": false,
  "validStatusTransitions": ["done", "blocked", "cancelled"],
  "reason": "Task is in_progress, reassignment disabled"
}
```

---

## Phase 3: TaskDetailPanel 実装

### 概要

macOSアプリの`TaskDetailView`に相当するコンポーネント。

### 実装内容

**TaskDetailPanel.tsx**:

```tsx
export function TaskDetailPanel({ taskId, onClose }: Props) {
  const { data: task } = useQuery(['task', taskId], () => getTask(taskId))
  const { data: permissions } = useQuery(['task-permissions', taskId],
    () => getTaskPermissions(taskId))

  return (
    <Panel>
      <Header>
        <Title>{task.title}</Title>
        <Actions>
          <Button onClick={openEditForm} disabled={!permissions?.canEdit}>
            <PencilIcon /> Edit
          </Button>
          <Button onClick={openHandoff}>
            <ArrowsIcon /> Handoff
          </Button>
        </Actions>
      </Header>

      <Content>
        {/* ステータスピッカー（有効な遷移のみ表示） */}
        <StatusPicker
          value={task.status}
          validTransitions={permissions?.validStatusTransitions}
          disabled={!permissions?.canChangeStatus}
          onChange={handleStatusChange}
        />

        {/* ブロック理由（blocked時のみ） */}
        {task.status === 'blocked' && (
          <BlockedReasonField value={task.blockedReason} />
        )}

        {/* その他の詳細 */}
        <Field label="Priority">{task.priority}</Field>
        <Field label="Assignee">{task.assigneeName}</Field>
        <Field label="Description">{task.description}</Field>

        {/* 依存関係 */}
        <DependencyList
          dependencies={task.dependencies}
          dependentTasks={task.dependentTasks}
        />

        {/* 時間追跡 */}
        <TimeTracking
          estimated={task.estimatedMinutes}
          actual={task.actualMinutes}
        />
      </Content>
    </Panel>
  )
}
```

### UI要素

| 要素 | 編集可否 | 備考 |
|------|---------|------|
| ステータスピッカー | ✅ | 有効な遷移のみ表示、権限チェック |
| ブロック理由 | ✅ | blocked時のみ表示 |
| 優先度 | ❌ | 表示のみ（編集フォームで変更） |
| 担当者 | ❌ | 表示のみ（編集フォームで変更） |
| 説明 | ❌ | 表示のみ（編集フォームで変更） |
| 依存関係 | ❌ | 表示のみ（編集フォームで変更） |
| 時間追跡 | ❌ | 表示のみ（編集フォームで変更） |

---

## Phase 4: 編集フォーム実装

### TaskEditForm.tsx

macOSアプリの`TaskFormView`に相当。

```tsx
export function TaskEditForm({ taskId, onClose }: Props) {
  const { data: task } = useQuery(['task', taskId])
  const { data: permissions } = useQuery(['task-permissions', taskId])
  const { data: agents } = useQuery(['assignable-agents'])

  return (
    <Dialog>
      <Form onSubmit={handleSubmit}>
        <Field label="Title" required>
          <Input value={title} onChange={setTitle} />
        </Field>

        <Field label="Description">
          <Textarea value={description} onChange={setDescription} />
        </Field>

        <Field label="Priority">
          <PriorityPicker value={priority} onChange={setPriority} />
        </Field>

        <Field label="Assignee">
          <AgentPicker
            value={assigneeId}
            agents={agents}
            onChange={setAssigneeId}
            disabled={!permissions?.canReassign}
          />
          {!permissions?.canReassign && (
            <HelpText>
              作業中/ブロック中のタスクは担当者を変更できません
            </HelpText>
          )}
        </Field>

        <Field label="Dependencies">
          <DependencySelector
            value={dependencies}
            onChange={setDependencies}
          />
        </Field>

        <Field label="Estimated Time">
          <TimeInput value={estimatedMinutes} onChange={setEstimatedMinutes} />
        </Field>

        <Actions>
          <Button type="button" onClick={onClose}>Cancel</Button>
          <Button type="submit">Save</Button>
        </Actions>
      </Form>
    </Dialog>
  )
}
```

---

## Phase 5: Handoff実装

### HandoffDialog.tsx

```tsx
export function HandoffDialog({ taskId, onClose }: Props) {
  const { data: task } = useQuery(['task', taskId])
  const { data: agents } = useQuery(['assignable-agents'])

  return (
    <Dialog>
      <Form onSubmit={handleHandoff}>
        <Field label="委任先エージェント">
          <AgentPicker
            value={toAgentId}
            agents={agents.filter(a => a.id !== task.assigneeId)}
            onChange={setToAgentId}
          />
        </Field>

        <Field label="引き継ぎコンテキスト">
          <Textarea
            value={context}
            onChange={setContext}
            placeholder="作業の進捗や注意点を記載..."
          />
        </Field>

        <Actions>
          <Button type="button" onClick={onClose}>Cancel</Button>
          <Button type="submit">Handoff</Button>
        </Actions>
      </Form>
    </Dialog>
  )
}
```

### REST API

**POST /api/tasks/:taskId/handoff**

```json
// Request
{
  "toAgentId": "agent-2",
  "context": "API実装完了、テストが必要"
}

// Response: 201 Created
{
  "handoffId": "handoff-1",
  "taskId": "task-1",
  "fromAgentId": "agent-1",
  "toAgentId": "agent-2",
  "context": "...",
  "createdAt": "..."
}
```

---

## 実装優先順位

### Sprint 1: 修正フェーズ（必須）

1. **TaskCard修正**: メニューボタン・削除機能を削除
2. **REST API権限チェック**: ステータス変更・担当者変更の権限検証
3. **E2Eテスト修正**: 削除テストを削除、権限エラーテストを追加

### Sprint 2: 詳細画面フェーズ

4. **TaskDetailPanel**: ステータスピッカー、基本情報表示
5. **TaskEditForm**: タスク編集フォーム
6. **権限API**: GET /api/tasks/:taskId/permissions

### Sprint 3: 高度な機能

7. **Handoff**: 委任機能
8. **依存関係UI**: DependencySelector
9. **時間追跡UI**: TimeInput

---

## ファイル構成

### 削除対象

```
web-ui/src/components/task/TaskCard/
├── TaskCard.tsx  # メニュー・削除関連コードを削除
```

### 修正対象

```
Sources/RESTServer/
└── RESTServer.swift  # 権限チェック追加

web-ui/src/components/task/
├── TaskCard/TaskCard.tsx  # シンプル化
└── TaskBoard/TaskBoard.tsx  # エラーハンドリング改善

web-ui/e2e/tests/
└── task-board.spec.ts  # 削除テストを削除
```

### 新規作成

```
web-ui/src/components/task/
├── TaskDetailPanel/
│   ├── TaskDetailPanel.tsx
│   ├── StatusPicker.tsx
│   └── BlockedReasonField.tsx
├── TaskEditForm/
│   ├── TaskEditForm.tsx
│   ├── DependencySelector.tsx
│   └── TimeInput.tsx
└── HandoffDialog/
    └── HandoffDialog.tsx

web-ui/src/api/
└── tasks.ts  # getTaskPermissions追加
```

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-01-19 | 初版作成 |
| 2026-01-19 | Phase 1-4 REST API実装完了（権限チェックなし） |
| 2026-01-19 | Phase 1 Web UI実装（TaskCard削除メニュー）← **要撤回** |
| 2026-01-19 | **改訂版作成**: macOSアプリとの整合性を重視した再設計 |
