# セッション起動アーキテクチャ設計

## 概要

エージェントセッションの起動を `pending_agent_purposes` テーブルで一元管理し、チャットとタスクの両方で統一された仕組みを提供する。

## 現状の問題点

### 1. チャットとタスクで異なる起動判定

| | チャット | タスク |
|---|---|---|
| 起動トリガー | pending_agent_purposes | in_progressタスクの有無 |
| 重複起動防止 | started_at で追跡 | なし（activeTaskSessionsのみ） |
| purpose判定 | pendingから取得 | デフォルトで task |

### 2. 認証時のpurpose判定問題

```swift
// AuthenticateUseCase
var purpose: AgentPurpose = .task  // デフォルト
if let pending = pendingRepo.find(...) {
    purpose = pending.purpose      // pendingがあればそこから取得
}
```

タスクはpendingを経由しないため、認証時にチャットとタスクの区別がつかない。

### 3. タスクの重複起動リスク

```
1. Coordinator → getAgentAction → start (in_progressタスクあり)
2. スポーン開始（数秒かかる）
3. 同じCoordinator → getAgentAction → start (まだセッションなし)
4. 複数エージェントが起動
```

チャットは `started_at` で追跡しているが、タスクにはこの仕組みがない。

## 設計方針

### pending_agent_purposes の責務

**単一責務**: セッション起動のキュー管理

```
起動が必要な処理発生 → pending作成
         ↓
Coordinator → getAgentAction → pendingあれば start
         ↓
エージェント起動 → authenticate → セッション作成
         ↓
pending削除
```

### ライフサイクル

```
┌─────────────────────────────────────────────────────────────────┐
│                    pending_agent_purposes                        │
├─────────────────────────────────────────────────────────────────┤
│ 作成: チャットメッセージ送信 / タスクが in_progress になった時   │
│ 更新: getAgentAction で start を返す時に started_at を設定      │
│ 削除: セッション作成成功時 / TTL超過時                           │
└─────────────────────────────────────────────────────────────────┘
```

### started_at の役割

`started_at` は「スポーン開始〜セッション作成」の間の不確実性を扱う：

| 状態 | started_at | 動作 |
|------|------------|------|
| 起動待ち | NULL | start を返す + started_at を設定 |
| スポーン中 | 設定済み（120秒以内） | hold を返す |
| スポーン失敗 | 設定済み（120秒超過） | started_at クリア + start を返す |

```
pending作成 ─→ start ─→ スポーン ─→ 認証 ─→ セッション作成 ─→ pending削除
              │                              │
              └── started_at で追跡 ─────────┘
```

## 統一設計

### getAgentAction のロジック

```swift
func getAgentAction(agentId, projectId) -> Action {
    // 1. アクティブセッションのチェック（purpose別）
    let activeChatSessions = sessions.filter { $0.purpose == .chat && !$0.isExpired }
    let activeTaskSessions = sessions.filter { $0.purpose == .task && !$0.isExpired }

    // 2. pendingの確認
    let pending = pendingRepo.find(agentId, projectId)

    if let pending = pending {
        // 同じpurposeのセッションが既にあれば hold
        if pending.purpose == .chat && !activeChatSessions.isEmpty {
            return .hold(reason: "chat_session_exists")
        }
        if pending.purpose == .task && !activeTaskSessions.isEmpty {
            return .hold(reason: "task_session_exists")
        }

        // started_at チェック（重複起動防止）
        if let startedAt = pending.startedAt {
            if timeSince(startedAt) > 120 {
                // タイムアウト → 再スポーン許可
                pendingRepo.clearStartedAt(pending)
                return .start(purpose: pending.purpose)
            } else {
                // スポーン中 → hold
                return .hold(reason: "spawning")
            }
        }

        // 新規起動
        pendingRepo.markAsStarted(pending, startedAt: now)
        return .start(purpose: pending.purpose)
    }

    // 3. フォールバック: in_progressタスクがあればpendingを作成
    if let task = tasks.first(where: { $0.status == .inProgress }) {
        if activeTaskSessions.isEmpty {
            let newPending = PendingAgentPurpose(
                agentId: agentId,
                projectId: projectId,
                purpose: .task
            )
            pendingRepo.save(newPending)
            pendingRepo.markAsStarted(newPending, startedAt: now)
            return .start(purpose: .task, taskId: task.id)
        }
    }

    // 4. 起動不要
    return .hold(reason: "no_pending_work")
}
```

### authenticate のロジック

```swift
func authenticate(agentId, passkey, projectId) -> Result {
    // ... 認証処理 ...

    // pendingからpurposeを取得
    let pending = pendingRepo.find(agentId, projectId)
    let purpose = pending?.purpose ?? .task

    // purpose別の重複チェック
    let existingSessions = sessionRepo.find(agentId, projectId)
        .filter { !$0.isExpired && $0.purpose == purpose }

    if !existingSessions.isEmpty {
        return .failure("Session already exists for this purpose")
    }

    // セッション作成
    let session = AgentSession(agentId, projectId, purpose)
    sessionRepo.save(session)

    // pending削除
    if let pending = pending {
        pendingRepo.delete(pending)
    }

    return .success(session)
}
```

### タスクステータス変更時のpending作成

```swift
func updateTaskStatus(taskId, newStatus) {
    let task = taskRepo.find(taskId)

    if newStatus == .inProgress && task.status != .inProgress {
        // in_progressになった時点でpendingを作成
        let existing = pendingRepo.find(task.assigneeId, task.projectId, purpose: .task)
        if existing == nil {
            let pending = PendingAgentPurpose(
                agentId: task.assigneeId,
                projectId: task.projectId,
                purpose: .task
            )
            pendingRepo.save(pending)
        }
    }

    task.status = newStatus
    taskRepo.save(task)
}
```

## フォールバックによる堅牢性

タスクの場合、`in_progress` 状態がソースオブトゥルースとして機能する：

```
通常フロー:
  タスク in_progress → pending作成 → getAgentAction → start

フォールバック（pending作成漏れの場合）:
  タスク in_progress → getAgentAction → pendingなし
                                      → in_progressタスク検出
                                      → pending自動作成 → start
```

これにより：
- pending作成漏れがあってもタスクは実行される
- 重複起動防止（started_at）の恩恵を受けられる

## UIステータス表示

pendingの有無ではなく、セッションの状態で判断する：

| 表示 | 判定条件 |
|------|----------|
| connected | アクティブなセッションあり |
| connecting | セッションの state が initializing |
| disconnected | セッションなし |

これにより pending を内部実装の詳細として隠蔽できる。

## 移行計画

### Phase 1: タスクのpending経由化

1. タスクが `in_progress` になった時に pending を作成する処理を追加
2. getAgentAction のフォールバックロジックを追加（後方互換性）
3. テストで動作確認

### Phase 2: authenticate の purpose別チェック

1. authenticate で purpose 別のセッション重複チェックを実装
2. 既存の「全セッションブロック」ロジックを削除
3. UC019（チャット+タスク同時実行）のテストで確認

### Phase 3: UIステータス表示の変更

1. RESTServer の chatStatus 判定を セッション状態ベースに変更
2. 既存のpending依存ロジックを削除

## 関連ドキュメント

- [CHAT_FEATURE.md](./CHAT_FEATURE.md) - チャット機能の設計
- [SPAWN_ERROR_PROTECTION.md](./SPAWN_ERROR_PROTECTION.md) - スポーンエラー保護
