# UI修正点リスト

現状の実装と要件定義の差分をまとめる。

---

## 1. エージェント (Agent)

### 現状
```swift
Agent
├─ projectId: ProjectID    // プロジェクトに所属
├─ name, role, type
├─ roleType: AgentRoleType
├─ capabilities: [String]
├─ systemPrompt: String?
└─ status: AgentStatus
```

### 要件との差分

| 項目 | 現状 | 要件 | 対応 |
|------|------|------|------|
| 所属 | プロジェクトに紐付く | トップレベル（独立） | **削除**: `projectId` |
| プロジェクト参加 | 1:1 | 多:多 | **新規**: 中間テーブル `ProjectAgent` |
| 親子関係 | なし | ツリー構造 | **追加**: `parentAgentId: AgentID?` |
| 並列実行数 | なし | あり | **追加**: `maxParallelTasks: Int` |
| 紐付け先 | type で AI/Human 区別 | AI種別を詳細化？ | 要検討 |

### UI修正

- [ ] エージェント一覧: プロジェクト横断で表示
- [ ] エージェント作成フォーム: `parentAgentId`, `maxParallelTasks` 追加
- [ ] エージェント詳細: 親エージェント表示、子エージェント一覧

---

## 2. タスク (Task)

### 現状
```swift
Task
├─ projectId, title, description
├─ status: TaskStatus (backlog/todo/inProgress/inReview/blocked/done/cancelled)
├─ priority: TaskPriority
├─ assigneeId: AgentID?
├─ parentTaskId: TaskID?    // サブタスク用
├─ dependencies: [TaskID]
└─ estimatedMinutes, actualMinutes
```

### 要件との差分

| 項目 | 現状 | 要件 | 対応 |
|------|------|------|------|
| サブタスク | `parentTaskId` あり | 不要 | **削除**: `parentTaskId` |
| Subtaskエンティティ | 存在する | 不要 | **削除**: `Subtask.swift` |
| ステータス | inReview あり | 不要 | **削除**: `inReview` |
| ステータス | blocked あり | 依存から導出 | 要検討 |
| 依存関係ブロック | なし | あり | **追加**: 状態遷移時チェック |
| リソースブロック | なし | あり | **追加**: in_progress時チェック |

### ステータス整理

```
現状: backlog / todo / inProgress / inReview / blocked / done / cancelled
要件: backlog / todo / in_progress / done / cancelled

削除: inReview
検討: blocked（依存から導出 or 明示的ステータス）
```

### UI修正

- [ ] タスクボード: `inReview` カラム削除
- [ ] タスク詳細: サブタスクセクション削除
- [ ] タスク作成/編集フォーム: 依存関係設定UI追加
- [ ] 状態変更: ブロック時のエラー表示

---

## 3. プロジェクト (Project)

### 現状
```swift
Project
├─ name, description
└─ status: ProjectStatus (active/archived/completed)
```

### 要件との差分

| 項目 | 現状 | 要件 | 対応 |
|------|------|------|------|
| ステータス | completed あり | active/archived のみ | **削除**: `completed` |
| エージェント | 直接所属 | 割り当て | 中間テーブル |

### UI修正

- [ ] プロジェクト一覧: 変更なし
- [ ] プロジェクト詳細: エージェント割り当てUI追加

---

## 4. 監査チーム (AuditTeam) - 新規

### 新規追加

```swift
AuditTeam
├─ id: AuditTeamID
├─ name: String
├─ description: String
└─ status: active/archived
```

### UI新規

- [ ] サイドバー: 監査チームセクション追加
- [ ] 監査チーム一覧画面
- [ ] 監査チーム作成/編集フォーム
- [ ] ロック操作UI（タスクロック、エージェントロック）

---

## 5. 履歴 (History) - 新規/強化

### 新規追加

```swift
HistoryEntry
├─ id: HistoryID
├─ timestamp: Date
├─ actorId: AgentID
├─ actionType: String
├─ targetType: String (task/agent/project)
├─ targetId: String
├─ beforeState: JSON?
├─ afterState: JSON?
└─ relatedTaskId: TaskID?
```

### UI新規

- [ ] 履歴一覧画面（タイムライン形式）
- [ ] フィルタリング（エージェント別、タスク別）

---

## 6. ContentView / ナビゲーション

### 現状
```
サイドバー: プロジェクトリスト
コンテンツ: タスクボード
詳細: タスク詳細 / エージェント詳細
```

### 要件との差分

| 項目 | 現状 | 要件 | 対応 |
|------|------|------|------|
| サイドバー構成 | プロジェクトのみ | プロジェクト + エージェント + 監査チーム | 再構成 |
| エージェント一覧 | プロジェクト内 | トップレベル | 移動 |

### UI修正

- [ ] サイドバー再構成
  ```
  サイドバー
  ├─ プロジェクト
  ├─ エージェント（全体）
  ├─ 監査チーム
  └─ 履歴
  ```

---

## 7. 削除対象

| ファイル/機能 | 理由 |
|--------------|------|
| `Subtask.swift` | サブタスク不要 |
| `SubtaskRepository` | 同上 |
| タスク詳細のサブタスクセクション | 同上 |
| `TaskStatus.inReview` | 不要 |
| `ProjectStatus.completed` | 不要 |

---

## 優先度

### P1 (コア機能)
1. エージェントをトップレベルに分離
2. エージェント親子関係追加
3. タスク依存関係ブロック実装
4. リソース可用性ブロック実装

### P2 (構造変更)
5. サブタスク削除
6. ステータス整理
7. サイドバー再構成

### P3 (新機能)
8. 監査チーム実装
9. 履歴機能実装
10. ロック機能実装
