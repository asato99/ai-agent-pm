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
// AuthenticateUseCase（現状）
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

### 4. ゾンビpendingによるブロックリスク

現状の `find(agentId, projectId)` は1レコードしか返さない（purpose指定なし）。
chat と task の両方の pending がある場合、片方しか見えない。

**シナリオ: ゾンビ chat pending がタスクをブロック**
```
1. チャット送信 → chat pending 作成
2. getAgentAction → start + markAsStarted
3. スポーン失敗（認証まで到達しない）
4. chat pending がゾンビとして残る（started_at あり）
5. タスクが in_progress → task pending 作成
6. getAgentAction → find() → chat pending が返される（started_at優先）
7. started_at チェック → 120秒以内なら hold
8. タスクがブロックされる
```

## 設計方針

### pending_agent_purposes の責務

| フェーズ | task pending | chat pending |
|----------|--------------|--------------|
| getAgentAction | started_at で重複起動防止 | started_at で重複起動防止 |
| authenticate | 不要（in_progressタスクで判定） | purpose判定に使用 |

**タスク**: in_progressタスクがソースオブトゥルース（堅牢）
**チャット**: chat pendingがソースオブトゥルース

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

**重要**: getAgentAction と authenticate の判断基準を一致させる。
タスク優先で判定し、該当するpurposeのpendingのみにmarkAsStartedする。

```swift
func getAgentAction(agentId: String, projectId: String) -> Action {
    // 状態取得
    let activeTaskSession = findActiveTaskSession(agentId, projectId)
    let activeChatSession = findActiveChatSession(agentId, projectId)
    let inProgressTask = findInProgressTask(assignee: agentId, projectId: projectId)
    let taskPending = pendingRepo.find(agentId, projectId, purpose: .task)
    let chatPending = pendingRepo.find(agentId, projectId, purpose: .chat)

    // ==========================================
    // タスク判定（認証と同じロジック）
    // 条件: activeTaskSession == nil AND inProgressTask != nil
    // ==========================================
    if activeTaskSession == nil && inProgressTask != nil {
        // タスクセッションが必要
        var currentTaskPending = taskPending

        // フォールバック: task pending がなければ作成
        if currentTaskPending == nil {
            currentTaskPending = PendingAgentPurpose(
                agentId: agentId,
                projectId: projectId,
                purpose: .task
            )
            pendingRepo.save(currentTaskPending)
        }

        // started_at チェック
        if currentTaskPending.startedAt == nil {
            // 未起動 → start
            pendingRepo.markAsStarted(currentTaskPending, startedAt: now)
            return .start
        } else if timedOut(currentTaskPending.startedAt, timeout: 120) {
            // タイムアウト → 再スポーン許可
            pendingRepo.clearStartedAt(currentTaskPending)
            pendingRepo.markAsStarted(currentTaskPending, startedAt: now)
            return .start
        }
        // else: タスク用スポーン中、続けてチャットを確認
    }

    // ==========================================
    // チャット判定
    // 条件: activeChatSession == nil AND chatPending != nil
    // ==========================================
    if activeChatSession == nil && chatPending != nil {
        // started_at チェック
        if chatPending.startedAt == nil {
            // 未起動 → start
            pendingRepo.markAsStarted(chatPending, startedAt: now)
            return .start
        } else if timedOut(chatPending.startedAt, timeout: 120) {
            // タイムアウト → 再スポーン許可
            pendingRepo.clearStartedAt(chatPending)
            pendingRepo.markAsStarted(chatPending, startedAt: now)
            return .start
        }
        // else: チャット用スポーン中
    }

    // ==========================================
    // どちらも起動不要
    // ==========================================
    return .hold
}
```

### authenticate のロジック

**重要**: purpose判定はpendingに依存せず、状態ベースで行う。

```swift
func authenticate(agentId: String, passkey: String, projectId: String) -> Result {
    // ... パスキー検証等 ...

    // 状態取得
    let activeTaskSession = findActiveTaskSession(agentId, projectId)
    let activeChatSession = findActiveChatSession(agentId, projectId)
    let inProgressTask = findInProgressTask(assignee: agentId, projectId: projectId)
    let chatPending = pendingRepo.find(agentId, projectId, purpose: .chat)

    // ==========================================
    // タスクセッション判定（優先）
    // 条件: activeTaskSession == nil AND inProgressTask != nil
    // ==========================================
    if activeTaskSession == nil && inProgressTask != nil {
        // タスクセッション作成
        let session = AgentSession(agentId, projectId, purpose: .task)
        sessionRepo.save(session)

        // task pending 削除（あれば）
        if let taskPending = pendingRepo.find(agentId, projectId, purpose: .task) {
            pendingRepo.delete(taskPending)
        }

        return .success(session)
    }

    // ==========================================
    // チャットセッション判定
    // 条件: activeChatSession == nil AND chatPending != nil
    // ==========================================
    if activeChatSession == nil && chatPending != nil {
        // チャットセッション作成
        let session = AgentSession(agentId, projectId, purpose: .chat)
        sessionRepo.save(session)

        // chat pending 削除
        pendingRepo.delete(chatPending)

        return .success(session)
    }

    // ==========================================
    // どちらにも該当しない
    // ==========================================
    return .failure("No valid purpose for authentication")
}
```

### 判定ロジックの一貫性

| 判定 | getAgentAction | authenticate |
|------|----------------|--------------|
| タスク | `activeTaskSession == nil AND inProgressTask != nil` | 同左 |
| チャット | `activeChatSession == nil AND chatPending != nil` | 同左 |

両方のメソッドで同じ条件を使用することで、getAgentActionでmarkAsStartedしたpurposeと、authenticateで作成するセッションのpurposeが一致する。

### タスクステータス変更時のpending作成

```swift
func updateTaskStatus(taskId: TaskID, newStatus: TaskStatus) {
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

## ゾンビpending対策

### 対策1: purpose別にpendingを検索

```swift
// 旧: 1レコードしか返さない
let pending = find(agentId, projectId)

// 新: purpose別に検索
let taskPending = find(agentId, projectId, purpose: .task)
let chatPending = find(agentId, projectId, purpose: .chat)
```

### 対策2: 状態ベースのpurpose判定

authenticateでは、pendingからpurposeを取得するのではなく、
`in_progressタスクの有無`で判定する。

これにより、ゾンビchat pendingがあっても：
- in_progressタスクがあれば → タスクセッション作成（正しい）
- in_progressタスクがなければ → チャットセッション作成

### 対策3: TTLによる自然消滅

- デフォルトTTL: 300秒（5分）
- 期限切れのpendingは自動削除

### 対策4: スポーンタイムアウト

- タイムアウト: 120秒
- started_atから120秒経過でstarted_atクリア → 再スポーン許可

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

### Phase 2: authenticate の状態ベース判定

1. authenticate で状態ベースのpurpose判定を実装
2. 既存の「全セッションブロック」ロジックを削除
3. purpose別にpending削除
4. UC019（チャット+タスク同時実行）のテストで確認

### Phase 3: getAgentAction の判定ロジック統一

1. purpose別にpendingを検索するよう変更
2. タスク優先の判定ロジックに変更
3. authenticateと同じ判定条件を使用

### Phase 4: UIステータス表示の変更

1. RESTServer の chatStatus 判定を セッション状態ベースに変更
2. 既存のpending依存ロジックを削除

## 関連ドキュメント

- [CHAT_FEATURE.md](./CHAT_FEATURE.md) - チャット機能の設計
- [SPAWN_ERROR_PROTECTION.md](./SPAWN_ERROR_PROTECTION.md) - スポーンエラー保護
