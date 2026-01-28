# セッション起動アーキテクチャ設計

## 概要

エージェントセッションの起動における重複スポーン防止を `project_agents.spawn_started_at` で管理する。
専用テーブルを廃止し、最小限の構成で目的を達成する。

## 設計原則

### Coordinator と MCPServer の役割分担

| コンポーネント | 責務 |
|----------------|------|
| **Coordinator** | エージェント単位でポーリング・スポーン（purpose 区別なし） |
| **MCPServer (getAgentAction)** | 起動判定 + 重複スポーン防止 |
| **MCPServer (authenticate)** | セッション生成（現在の状態に基づいて purpose を決定） |

**意図的な分散判定**: 両者の判定が厳密に一致する必要はない。順次処理で時間幅を持って見たときに、最終的にセッション生成まで進むことを保証する。

### pending の責務（最小化）

**唯一の責務**: 起動〜認証の間の重複スポーンを防ぐ

これだけ。セッション自体が生成されれば、その状態で判断可能。

### 共通ロジックの原則

**WorkDetectionService**: `getAgentAction` と `authenticate` で同一の仕事判定ロジックを使用

- チャットの仕事がないのにチャットセッションを作成しない
- タスクの仕事がないのにタスクセッションを作成しない
- 両者の判定一貫性を保証

## データ構造

### project_agents テーブル（変更）

```sql
project_agents:
  - project_id       -- PK
  - agent_id         -- PK
  - assigned_at
  - spawn_started_at -- NEW: スポーン開始時刻（NULL = スポーン中でない）
```

**`pending_agent_purposes` テーブルは廃止**

### spawn_started_at の役割

| 状態 | spawn_started_at | 意味 |
|------|------------------|------|
| 起動待ち | NULL | スポーン可能 |
| スポーン中 | 設定済み（120秒以内） | スポーン不可（重複防止） |
| スポーン失敗 | 設定済み（120秒超過） | タイムアウト、再スポーン可能 |

## フローの全体像

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Coordinator (ポーリング)                                     │
│    get_agent_action(agent_id, project_id)                       │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 2. getAgentAction (起動判定)                                    │
│    - hasWork を判定（chat / task 別メソッド）                    │
│    - spawnInProgress を判定                                     │
│    - hasWork && !spawnInProgress → spawn_started_at 設定、start │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 3. Coordinator (スポーン)                                       │
│    spawn_agent(agent_id, project_id, ...)                       │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 4. authenticate (セッション生成)                                │
│    - 現在の状態に基づいて適切なセッションを生成                  │
│    - 成功/失敗に関わらず spawn_started_at をクリア              │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 5. 次のポーリング                                               │
│    - まだ仕事があれば再度スポーン（自然な繰り返し）             │
└─────────────────────────────────────────────────────────────────┘
```

## WorkDetectionService（共通ロジック）

`getAgentAction` と `authenticate` で使用する共通の仕事判定サービス。

### 設計意図

- **一貫性**: 両者で同じ判定ロジックを使用し、不一致を防止
- **責務分離**: 仕事判定ロジックを独立したサービスとして切り出し
- **テスト容易性**: 共通ロジックを単体でテスト可能

### インターフェース

```swift
// Sources/UseCase/WorkDetectionService.swift
public struct WorkDetectionService: Sendable {
    private let chatRepository: any ChatRepositoryProtocol
    private let sessionRepository: any AgentSessionRepositoryProtocol
    private let taskRepository: any TaskRepositoryProtocol
    private let agentRepository: any AgentRepositoryProtocol

    /// チャットの仕事があるか判定
    public func hasChatWork(agentId: AgentID, projectId: ProjectID) throws -> Bool {
        let hasUnread = try chatRepository.hasUnreadMessages(projectId: projectId, agentId: agentId)
        let sessions = try sessionRepository.findByAgentIdAndProjectId(agentId, projectId: projectId)
        let hasActiveChat = sessions.contains { $0.purpose == .chat && !$0.isExpired }
        return hasUnread && !hasActiveChat
    }

    /// タスクの仕事があるか判定（基本条件のみ）
    public func hasTaskWork(agentId: AgentID, projectId: ProjectID) throws -> Bool {
        let inProgressTask = try taskRepository.findByProject(projectId, status: .inProgress)
            .first { $0.assigneeId == agentId }
        let sessions = try sessionRepository.findByAgentIdAndProjectId(agentId, projectId: projectId)
        let hasActiveTask = sessions.contains { $0.purpose == .task && !$0.isExpired }
        return inProgressTask != nil && !hasActiveTask
    }
}
```

### 利用箇所

| コンポーネント | 使用メソッド | 追加条件 |
|----------------|--------------|----------|
| **getAgentAction** | `hasChatWork`, `hasTaskWork` | 階層タイプ別条件（マネージャー待機等） |
| **authenticate** | `hasChatWork`, `hasTaskWork` | なし（共通ロジックのみ） |

## getAgentAction の実装

### メイン構造

```swift
func getAgentAction(agentId: String, projectId: String) -> Action {
    let workService = WorkDetectionService(...)

    // 共通ロジックで基本判定
    let hasWorkForChat = workService.hasChatWork(agentId, projectId)
    let hasWorkForTask = checkTaskWorkWithHierarchy(agentId, projectId, workService)

    let hasWork = hasWorkForChat || hasWorkForTask
    let spawnInProgress = checkSpawnInProgress(agentId, projectId)

    if hasWork && !spawnInProgress {
        markSpawnStarted(agentId, projectId)
        return .start
    }
    return .hold
}
```

### checkSpawnInProgress

```swift
func checkSpawnInProgress(agentId: String, projectId: String) -> Bool {
    let assignment = projectAgentRepo.find(agentId, projectId)
    guard let startedAt = assignment.spawnStartedAt else {
        return false  // NULL = スポーン中でない
    }

    let elapsed = now.timeIntervalSince(startedAt)
    if elapsed > 120 {
        return false  // タイムアウト = 再スポーン可能
    }
    return true  // スポーン中
}
```

### checkTaskWorkWithHierarchy（階層タイプ別条件）

```swift
func checkTaskWorkWithHierarchy(agentId: String, projectId: String, workService: WorkDetectionService) -> Bool {
    // 基本条件（共通ロジック）
    guard workService.hasTaskWork(agentId, projectId) else {
        return false
    }

    // 階層タイプ別の追加条件
    let agent = agentRepo.findById(agentId)

    switch agent.hierarchyType {
    case .manager:
        return checkManagerTaskWork(agentId, projectId)
    case .worker:
        return true  // 基本条件のみ
    case .owner:
        return false  // オーナーはタスク実行しない
    }
}

func checkManagerTaskWork(agentId: String, projectId: String) -> Bool {
    // マネージャー固有: 部下が仕事中なら待機
    let subordinates = agentRepo.findSubordinates(agentId)
    let anySubordinateBusy = subordinates.contains { sub in
        sessionRepo.hasActiveSession(sub.id, projectId, purpose: .task)
    }

    if anySubordinateBusy {
        return false  // 部下が仕事中 → マネージャーは仕事なし
    }

    return true

    // 将来の拡張ポイント:
    // - 全サブタスクが完了しているか
    // - 承認待ちのタスクがあるか
}
```

## authenticate の実装

`WorkDetectionService` の共通ロジックを使用してセッション目的を決定。

```swift
func authenticate(agentId: String, passkey: String, projectId: String) -> Result {
    let workService = WorkDetectionService(...)

    // パスキー検証
    guard verifyPasskey(agentId, passkey) else {
        clearSpawnStarted(agentId, projectId)  // 失敗でもクリア
        return .failure("Invalid credentials")
    }

    // 共通ロジックで仕事判定
    let hasTaskWork = workService.hasTaskWork(agentId, projectId)
    let hasChatWork = workService.hasChatWork(agentId, projectId)

    // タスクセッション判定（優先）
    if hasTaskWork {
        let session = createSession(agentId, projectId, purpose: .task)
        clearSpawnStarted(agentId, projectId)
        return .success(session)
    }

    // チャットセッション判定
    if hasChatWork {
        let session = createSession(agentId, projectId, purpose: .chat)
        clearSpawnStarted(agentId, projectId)
        return .success(session)
    }

    // どちらにも該当しない
    clearSpawnStarted(agentId, projectId)  // 失敗でもクリア
    return .failure("No valid purpose for authentication")
}
```

**重要**:
- 成功でも失敗でも `spawn_started_at` をクリア → 長期ブロック防止
- `WorkDetectionService` を使用 → `getAgentAction` と同一の判定ロジック

## 両方必要な場合の自然な解決

```
状態: in_progress タスクあり + 未読チャットあり
     ↓
getAgentAction: hasWork=true, spawnInProgress=false → "start"
     ↓
spawn → authenticate → TASK セッション生成 → spawn_started_at クリア
     ↓
次の getAgentAction:
  hasWork=true (chat がまだある), spawnInProgress=false
  → "start"
     ↓
spawn → authenticate → CHAT セッション生成 → spawn_started_at クリア
```

purpose を追跡しないことで、**残った仕事に対して自然に再スポーンが発生**する。

## 旧設計との比較

| 観点 | 旧設計 | 新設計 |
|------|--------|--------|
| 専用テーブル | `pending_agent_purposes` | なし |
| purpose 追跡 | purpose 別に pending レコード | なし（セッションで判断） |
| started_at の管理 | purpose ごとに独立 | エージェント×プロジェクトで1つ |
| 認証失敗時 | started_at 残存（120秒ブロック） | 必ずクリア（即再試行可能） |
| 複雑性 | 高（purpose 交差問題あり） | 低（シンプルなロック機構） |

## マイグレーション

### 1. スキーマ変更

```sql
-- project_agents に列追加
ALTER TABLE project_agents ADD COLUMN spawn_started_at TEXT;

-- pending_agent_purposes は後で削除（移行完了後）
```

### 2. コード変更

1. `getAgentAction` のリファクタリング
   - `checkChatWork`, `checkTaskWork` メソッド追加
   - `checkSpawnInProgress` を `project_agents` 参照に変更

2. `AuthenticateUseCaseV2` の変更
   - `spawn_started_at` クリアを追加
   - pending 削除ロジックを削除

3. pending 作成箇所の削除
   - チャット送信時の pending 作成を削除
   - タスクステータス変更時の pending 作成を削除

### 3. テスト

- 重複スポーン防止のテスト
- 認証失敗後の即再試行テスト
- chat + task 同時存在時の順次処理テスト

### 4. pending_agent_purposes 削除

```sql
DROP TABLE pending_agent_purposes;
```

## 関連ドキュメント

- [CHAT_FEATURE.md](./CHAT_FEATURE.md) - チャット機能の設計
- [SPAWN_ERROR_PROTECTION.md](./SPAWN_ERROR_PROTECTION.md) - スポーンエラー保護
