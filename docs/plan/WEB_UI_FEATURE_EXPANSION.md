# Web UI 機能拡張プラン

## 概要

macOSアプリ（AIAgentPM）の機能をweb-uiに展開するための実装計画。
REST APIエンドポイントとReactコンポーネントの追加を行う。

---

## スコープ

### 対象機能

| # | 機能 | 優先度 | 依存関係 |
|---|------|--------|----------|
| 1 | タスク削除 | 高 | なし |
| 2 | タスク詳細（時間追跡） | 高 | なし |
| 3 | タスク詳細（ブロック状態） | 高 | なし |
| 4 | タスク詳細（依存関係） | 中 | なし |
| 5 | ハンドオフ | 中 | 依存関係 |
| 6 | チャット | 中 | なし |
| 7 | ワークフローテンプレート | 低 | なし |

### 対象外

- プロジェクト管理（作成/削除/更新）
- エージェント一覧管理

---

## Phase 1: タスク削除 ✅

### 概要

タスクを削除（cancelled状態に変更）する機能。

### REST API

```
DELETE /api/tasks/:taskId
```

**レスポンス**: 204 No Content

**実装場所**: `Sources/RESTServer/RESTServer.swift`

```swift
// Routes/TaskRoutes
taskRouter.delete(":taskId") { [self] request, context in
    try await deleteTask(request: request, context: context)
}
```

### 実装状況

- ✅ DELETE `/api/tasks/:taskId` 実装完了
- ✅ Web UI（TaskCard削除メニュー）実装完了 (2026-01-19)

### Web UI

**コンポーネント**: `TaskBoardCard.tsx`

```tsx
// 削除ボタン追加
<DropdownMenuItem onClick={handleDelete}>
  <Trash2 className="h-4 w-4 mr-2" />
  Delete
</DropdownMenuItem>
```

**実装内容**:
1. TaskBoardCardに削除メニュー追加
2. 確認ダイアログ表示
3. API呼び出し
4. 状態更新（React Query invalidation）

---

## Phase 2: タスク詳細（時間追跡） ✅

### 概要

タスクの見積もり時間と実績時間を表示・編集する機能。

### 実装状況

- ✅ TaskDTO拡張（estimatedMinutes, actualMinutes）
- ✅ PATCH `/api/tasks/:taskId` 拡張完了
- ✅ GET `/api/tasks/:taskId` 実装完了
- ⬜ Web UI（TaskDetailPanel）

### データモデル

| フィールド | 型 | 説明 |
|-----------|-----|------|
| estimatedMinutes | Int? | 見積もり時間（分） |
| actualMinutes | Int? | 実績時間（分） |

### REST API

**GET /api/tasks/:taskId** レスポンス拡張:

```json
{
  "id": "task_001",
  "estimatedMinutes": 120,
  "actualMinutes": 90,
  ...
}
```

**PATCH /api/tasks/:taskId** リクエスト拡張:

```json
{
  "estimatedMinutes": 120,
  "actualMinutes": 90
}
```

### Web UI

**コンポーネント**: `TaskDetailPanel.tsx` (新規)

```tsx
<div className="space-y-4">
  <div>
    <Label>Estimated Time</Label>
    <TimeInput value={task.estimatedMinutes} onChange={...} />
  </div>
  <div>
    <Label>Actual Time</Label>
    <TimeInput value={task.actualMinutes} onChange={...} />
  </div>
</div>
```

---

## Phase 3: タスク詳細（ブロック状態） ✅

### 概要

タスクのブロック状態と理由を表示・編集する機能。

### 実装状況

- ✅ TaskDTO拡張（blockedReason）
- ✅ PATCH `/api/tasks/:taskId` 拡張完了（blockedReasonサポート）
- ⬜ Web UI（TaskBoardCardツールチップ、TaskDetailPanel）

### データモデル

| フィールド | 型 | 説明 |
|-----------|-----|------|
| blockReason | String? | ブロック理由 |

### REST API

**PATCH /api/tasks/:taskId** リクエスト拡張:

```json
{
  "status": "blocked",
  "blockReason": "Waiting for API specification"
}
```

### Web UI

**TaskBoardCard.tsx** 修正:
- ブロック状態の場合、理由をツールチップで表示

**TaskDetailPanel.tsx** 追加:
- ステータスがblockedの場合、理由入力フィールド表示

### ビジネスロジック（UC008準拠）

- ブロック時のカスケード処理（サブタスクも連動）
- エージェントセッション無効化

---

## Phase 4: タスク詳細（依存関係） ✅

### 概要

タスク間の依存関係を表示・編集する機能。

### 実装状況

- ✅ TaskDTO拡張（dependentTasks追加）
- ✅ GET `/api/projects/:projectId/tasks` 拡張（逆依存関係含む）
- ✅ GET `/api/tasks/:taskId` 実装（逆依存関係含む）
- ✅ PATCH `/api/tasks/:taskId` 拡張（循環依存・自己参照チェック）
- ⬜ Web UI（DependencySelector、TaskList）

### REST API

**GET /api/projects/:projectId/tasks** レスポンス拡張:

```json
{
  "id": "task_001",
  "dependencies": ["task_000"],
  "dependentTasks": ["task_002", "task_003"],
  ...
}
```

**PATCH /api/tasks/:taskId** リクエスト拡張:

```json
{
  "dependencies": ["task_000", "task_001"]
}
```

### Web UI

**TaskDetailPanel.tsx** 追加:

```tsx
<div>
  <Label>Dependencies</Label>
  <DependencySelector
    currentDependencies={task.dependencies}
    availableTasks={allTasks}
    onChange={handleDependenciesChange}
  />
</div>

<div>
  <Label>Dependent Tasks</Label>
  <TaskList tasks={dependentTasks} readonly />
</div>
```

**バリデーション**:
- 循環依存チェック
- 自己参照禁止

---

## Phase 5: ハンドオフ

### 概要

in_progress/blockedタスクを別エージェントに正式に委任する機能。

### データモデル

**Handoff**:

| フィールド | 型 | 説明 |
|-----------|-----|------|
| id | HandoffID | 一意識別子 |
| taskId | TaskID | 対象タスク |
| fromAgentId | AgentID | 委任元 |
| toAgentId | AgentID | 委任先 |
| context | String | 引き継ぎコンテキスト |
| createdAt | Date | 作成日時 |

### REST API

```
POST /api/tasks/:taskId/handoff
```

**リクエスト**:
```json
{
  "toAgentId": "agent_002",
  "context": "API implementation completed, needs testing"
}
```

**レスポンス**: 201 Created

### Web UI

**TaskDetailPanel.tsx** 追加:

```tsx
{(task.status === 'in_progress' || task.status === 'blocked') && (
  <Button onClick={() => setShowHandoffDialog(true)}>
    Handoff to another agent
  </Button>
)}

<HandoffDialog
  open={showHandoffDialog}
  task={task}
  assignableAgents={agents}
  onSubmit={handleHandoff}
/>
```

---

## Phase 6: チャット（UC009準拠）

### 概要

ユーザーがエージェントにチャットでメッセージを送信し、応答を受け取る機能。

### REST API

```
GET /api/projects/:projectId/agents/:agentId/chat
POST /api/projects/:projectId/agents/:agentId/chat
```

**GET レスポンス**:
```json
{
  "messages": [
    {
      "id": "msg_001",
      "sender": "user",
      "content": "あなたの名前を教えてください",
      "createdAt": "2026-01-19T10:00:00Z"
    },
    {
      "id": "msg_002",
      "sender": "agent",
      "content": "私の名前はbackend-devです",
      "createdAt": "2026-01-19T10:00:30Z"
    }
  ]
}
```

**POST リクエスト**:
```json
{
  "content": "あなたの名前を教えてください"
}
```

### Web UI

**AgentChatPanel.tsx** (新規):

```tsx
export function AgentChatPanel({ projectId, agentId }) {
  const { data: messages } = useQuery(['chat', projectId, agentId], fetchMessages);
  const sendMessage = useMutation(postMessage);

  return (
    <div className="flex flex-col h-full">
      <ChatMessageList messages={messages} />
      <ChatInput onSend={(content) => sendMessage.mutate({ content })} />
    </div>
  );
}
```

**アクセス方法**:
- TaskBoardヘッダーのエージェントアバタークリック
- 第3カラムにAgentChatPanelを表示

### バックエンド実装

**ファイルベース（UC009準拠）**:
- `{workingDirectory}/.ai-pm/agents/{agentId}/chat.jsonl`
- POSTでメッセージ追記 + `pending_agent_purposes` に `purpose="chat"` 記録

---

## Phase 7: ワークフローテンプレート

### 概要

一連のタスクをテンプレートとして定義し、繰り返し適用できる機能。

### REST API

```
GET    /api/projects/:projectId/templates
POST   /api/projects/:projectId/templates
GET    /api/projects/:projectId/templates/:templateId
PATCH  /api/projects/:projectId/templates/:templateId
DELETE /api/projects/:projectId/templates/:templateId
POST   /api/projects/:projectId/templates/:templateId/instantiate
```

**インスタンス化リクエスト**:
```json
{
  "variables": {
    "feature_name": "ログイン機能",
    "module": "認証"
  },
  "assignments": {
    "1": "agent_001",
    "2": "agent_002"
  }
}
```

### Web UI

**TemplateListPanel.tsx** (新規):
- テンプレート一覧表示
- 新規作成、編集、アーカイブ、インスタンス化

**TemplateFormDialog.tsx** (新規):
- テンプレート名、説明、変数定義
- タスク一覧（ドラッグ&ドロップ順序変更）

**InstantiateDialog.tsx** (新規):
- 変数入力フォーム
- プレビュー表示
- エージェントアサイン

---

## 実装優先順位

### Sprint 1（高優先度）

1. ✅ タスク削除 API ~~+ UI~~ (API完了 2026-01-19)
2. ✅ タスク詳細（時間追跡） API ~~+ UI~~ (API完了 2026-01-19)
3. ✅ タスク詳細（ブロック状態） API ~~+ UI~~ (API完了 2026-01-19)

### Sprint 2（中優先度）

4. ✅ タスク詳細（依存関係） API ~~+ UI~~ (API完了 2026-01-19)
5. ハンドオフ API + UI
6. チャット API + UI

### Sprint 3（低優先度）

7. ワークフローテンプレート API + UI

---

## ファイル構成

### REST API（Swift）

```
Sources/RESTServer/
├── RESTServer.swift           # 既存（拡張）
├── Routes/
│   ├── TaskRoutes.swift       # 新規
│   ├── HandoffRoutes.swift    # 新規
│   ├── ChatRoutes.swift       # 新規
│   └── TemplateRoutes.swift   # 新規
└── DTOs/
    ├── TaskDTO.swift          # 既存（拡張）
    ├── HandoffDTO.swift       # 新規
    ├── ChatDTO.swift          # 新規
    └── TemplateDTO.swift      # 新規
```

### Web UI（React）

```
web-ui/src/
├── components/
│   ├── task/
│   │   ├── TaskDetailPanel.tsx    # 新規
│   │   ├── DependencySelector.tsx # 新規
│   │   └── TimeInput.tsx          # 新規
│   ├── chat/
│   │   ├── AgentChatPanel.tsx     # 新規
│   │   ├── ChatMessageList.tsx    # 新規
│   │   └── ChatInput.tsx          # 新規
│   ├── handoff/
│   │   └── HandoffDialog.tsx      # 新規
│   └── template/
│       ├── TemplateListPanel.tsx  # 新規
│       ├── TemplateFormDialog.tsx # 新規
│       └── InstantiateDialog.tsx  # 新規
├── api/
│   ├── tasks.ts               # 既存（拡張）
│   ├── chat.ts                # 新規
│   ├── handoff.ts             # 新規
│   └── templates.ts           # 新規
└── types/
    └── index.ts               # 拡張
```

---

## 参考ドキュメント

| 機能 | 参考 |
|------|------|
| タスク仕様 | docs/requirements/TASKS.md |
| ブロック | docs/usecase/UC008_TaskBlocking.md |
| 依存関係 | docs/usecase/UC007_DependentTaskExecution.md |
| チャット | docs/usecase/UC009_ChatCommunication.md |
| ワークフローテンプレート | docs/requirements/WORKFLOW_TEMPLATES.md |

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-01-19 | 初版作成 |
| 2026-01-19 | Internal Auditをスコープから除外 |
| 2026-01-19 | Phase 1-4 REST API実装完了（タスク削除、時間追跡、ブロック状態、依存関係） |
| 2026-01-19 | Phase 1-4 リポジトリ層テスト追加（12テストケース） |
| 2026-01-19 | Phase 1 Web UI実装完了（タスク削除メニュー、E2Eテスト追加） |
