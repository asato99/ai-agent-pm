# セッション起動アーキテクチャ実装計画

テストファースト（TDD）で実装するための計画。

**参照**: [SESSION_SPAWN_ARCHITECTURE.md](../design/SESSION_SPAWN_ARCHITECTURE.md)

## 変更概要

- `pending_agent_purposes` テーブル廃止
- `project_agents.spawn_started_at` 列追加
- `WorkDetectionService` 共通ロジック追加
- `getAgentAction` を共通ロジック + 階層条件に分離
- `authenticate` で共通ロジックを使用し `spawn_started_at` クリア

## Phase 1: スキーマ変更

### 1.1 マイグレーション

```sql
-- project_agents に列追加
ALTER TABLE project_agents ADD COLUMN spawn_started_at TEXT;
```

### 1.2 リポジトリ変更

**ファイル**: `Sources/Infrastructure/Repositories/ProjectAgentRepository.swift`

```swift
// 追加メソッド
func updateSpawnStartedAt(agentId: AgentID, projectId: ProjectID, startedAt: Date?) throws
func findAssignment(agentId: AgentID, projectId: ProjectID) throws -> ProjectAgentAssignment?
```

**ファイル**: `Sources/Domain/Entities/ProjectAgentAssignment.swift`

```swift
// spawn_started_at プロパティ追加
public struct ProjectAgentAssignment {
    public let projectId: ProjectID
    public let agentId: AgentID
    public let assignedAt: Date
    public let spawnStartedAt: Date?  // NEW
}
```

## Phase 2: WorkDetectionService 実装

### 2.1 テスト作成（RED）

**ファイル**: `Tests/UseCaseTests/WorkDetectionServiceTests.swift`

```swift
// テスト1: チャットワークあり
func testHasChatWork_WithUnreadMessages_ReturnsTrue() {
    // Given
    // - 未読チャットメッセージあり
    // - アクティブチャットセッションなし

    // When
    let result = workService.hasChatWork(agentId: id, projectId: projId)

    // Then
    XCTAssertTrue(result)
}

// テスト2: チャットワークなし（既存セッションあり）
func testHasChatWork_WithActiveSession_ReturnsFalse() {
    // Given
    // - 未読チャットメッセージあり
    // - アクティブチャットセッションあり

    // When
    let result = workService.hasChatWork(agentId: id, projectId: projId)

    // Then
    XCTAssertFalse(result)
}

// テスト3: タスクワークあり
func testHasTaskWork_WithInProgressTask_ReturnsTrue() {
    // Given
    // - in_progress タスクあり（assignee = テスト対象エージェント）
    // - アクティブタスクセッションなし

    // When
    let result = workService.hasTaskWork(agentId: id, projectId: projId)

    // Then
    XCTAssertTrue(result)
}

// テスト4: タスクワークなし（既存セッションあり）
func testHasTaskWork_WithActiveSession_ReturnsFalse() {
    // Given
    // - in_progress タスクあり
    // - アクティブタスクセッションあり

    // When
    let result = workService.hasTaskWork(agentId: id, projectId: projId)

    // Then
    XCTAssertFalse(result)
}
```

### 2.2 実装（GREEN）

**ファイル**: `Sources/UseCase/WorkDetectionService.swift`

```swift
public struct WorkDetectionService: Sendable {
    private let chatRepository: any ChatRepositoryProtocol
    private let sessionRepository: any AgentSessionRepositoryProtocol
    private let taskRepository: any TaskRepositoryProtocol

    public init(
        chatRepository: any ChatRepositoryProtocol,
        sessionRepository: any AgentSessionRepositoryProtocol,
        taskRepository: any TaskRepositoryProtocol
    ) {
        self.chatRepository = chatRepository
        self.sessionRepository = sessionRepository
        self.taskRepository = taskRepository
    }

    public func hasChatWork(agentId: AgentID, projectId: ProjectID) throws -> Bool {
        let hasUnread = try chatRepository.hasUnreadMessages(projectId: projectId, agentId: agentId)
        let sessions = try sessionRepository.findByAgentIdAndProjectId(agentId, projectId: projectId)
        let hasActiveChat = sessions.contains { $0.purpose == .chat && !$0.isExpired }
        return hasUnread && !hasActiveChat
    }

    public func hasTaskWork(agentId: AgentID, projectId: ProjectID) throws -> Bool {
        let inProgressTask = try taskRepository.findByProject(projectId, status: .inProgress)
            .first { $0.assigneeId == agentId }
        let sessions = try sessionRepository.findByAgentIdAndProjectId(agentId, projectId: projectId)
        let hasActiveTask = sessions.contains { $0.purpose == .task && !$0.isExpired }
        return inProgressTask != nil && !hasActiveTask
    }
}
```

## Phase 3: getAgentAction リファクタリング

### 3.1 テスト作成（RED）

**ファイル**: `Tests/MCPServerTests/GetAgentActionTests.swift`

```swift
// テスト1: チャットワークあり → start
func testGetAgentAction_WithChatWork_ReturnsStart() {
    // Given
    // - 未読チャットメッセージあり
    // - アクティブチャットセッションなし
    // - spawn_started_at = nil

    // When
    let result = getAgentAction(agentId, projectId)

    // Then
    XCTAssertEqual(result["action"], "start")
}

// テスト2: タスクワークあり → start
func testGetAgentAction_WithTaskWork_ReturnsStart() {
    // Given
    // - in_progress タスクあり（assignee = テスト対象エージェント）
    // - アクティブタスクセッションなし
    // - spawn_started_at = nil

    // When
    let result = getAgentAction(agentId, projectId)

    // Then
    XCTAssertEqual(result["action"], "start")
}

// テスト3: スポーン中 → hold
func testGetAgentAction_WithSpawnInProgress_ReturnsHold() {
    // Given
    // - 仕事あり
    // - spawn_started_at = 10秒前

    // When
    let result = getAgentAction(agentId, projectId)

    // Then
    XCTAssertEqual(result["action"], "hold")
}

// テスト4: スポーンタイムアウト → start
func testGetAgentAction_WithSpawnTimeout_ReturnsStart() {
    // Given
    // - 仕事あり
    // - spawn_started_at = 130秒前

    // When
    let result = getAgentAction(agentId, projectId)

    // Then
    XCTAssertEqual(result["action"], "start")
}

// テスト5: 仕事なし → hold
func testGetAgentAction_WithNoWork_ReturnsHold() {
    // Given
    // - 未読チャットなし
    // - in_progress タスクなし

    // When
    let result = getAgentAction(agentId, projectId)

    // Then
    XCTAssertEqual(result["action"], "hold")
}

// テスト6: マネージャー + 部下が仕事中 → hold
func testGetAgentAction_ManagerWithBusySubordinates_ReturnsHold() {
    // Given
    // - マネージャーエージェント
    // - in_progress タスクあり
    // - アクティブタスクセッションなし
    // - 部下にアクティブタスクセッションあり

    // When
    let result = getAgentAction(agentId, projectId)

    // Then
    XCTAssertEqual(result["action"], "hold")
}

// テスト7: マネージャー + 部下が待機中 → start
func testGetAgentAction_ManagerWithIdleSubordinates_ReturnsStart() {
    // Given
    // - マネージャーエージェント
    // - in_progress タスクあり
    // - アクティブタスクセッションなし
    // - 部下にアクティブタスクセッションなし

    // When
    let result = getAgentAction(agentId, projectId)

    // Then
    XCTAssertEqual(result["action"], "start")
}
```

### 3.2 実装（GREEN）

**ファイル**: `Sources/MCPServer/MCPServer.swift`

```swift
private let workDetectionService: WorkDetectionService

private func getAgentAction(agentId: String, projectId: String) throws -> [String: Any] {
    let id = AgentID(value: agentId)
    let projId = ProjectID(value: projectId)

    // 共通ロジックで仕事の有無を判定
    let hasWorkForChat = try workDetectionService.hasChatWork(agentId: id, projectId: projId)
    let hasWorkForTask = try checkTaskWorkWithHierarchy(agentId: id, projectId: projId)
    let hasWork = hasWorkForChat || hasWorkForTask

    // スポーン中か判定
    let spawnInProgress = try checkSpawnInProgress(agentId: id, projectId: projId)

    if hasWork && !spawnInProgress {
        try markSpawnStarted(agentId: id, projectId: projId)
        return ["action": "start", "reason": hasWorkForTask ? "has_task_work" : "has_chat_work"]
    }

    return ["action": "hold", "reason": "no_work_or_spawn_in_progress"]
}

private func checkTaskWorkWithHierarchy(agentId: AgentID, projectId: ProjectID) throws -> Bool {
    // 基本条件（共通ロジック）
    guard try workDetectionService.hasTaskWork(agentId: agentId, projectId: projectId) else {
        return false
    }

    // 階層タイプ別の追加条件
    guard let agent = try agentRepository.findById(agentId) else {
        return false
    }

    switch agent.hierarchyType {
    case .manager:
        return try checkManagerTaskWork(agentId: agentId, projectId: projectId)
    case .worker:
        return true  // 基本条件のみ
    case .owner:
        return false  // オーナーはタスク実行しない
    }
}

private func checkManagerTaskWork(agentId: AgentID, projectId: ProjectID) throws -> Bool {
    // 部下が仕事中かチェック
    let allAgents = try agentRepository.findAll()
    let subordinates = allAgents.filter { $0.parentAgentId == agentId }

    for sub in subordinates {
        let hasActiveSession = try agentSessionRepository
            .findByAgentIdAndProjectId(sub.id, projectId: projectId)
            .contains { $0.purpose == .task && !$0.isExpired }
        if hasActiveSession {
            return false  // 部下が仕事中
        }
    }

    return true
}

private func checkSpawnInProgress(agentId: AgentID, projectId: ProjectID) throws -> Bool {
    guard let assignment = try projectAgentAssignmentRepository
        .findAssignment(agentId: agentId, projectId: projectId) else {
        return false
    }

    guard let startedAt = assignment.spawnStartedAt else {
        return false
    }

    let elapsed = Date().timeIntervalSince(startedAt)
    return elapsed <= 120  // 120秒以内ならスポーン中
}

private func markSpawnStarted(agentId: AgentID, projectId: ProjectID) throws {
    try projectAgentAssignmentRepository.updateSpawnStartedAt(
        agentId: agentId,
        projectId: projectId,
        startedAt: Date()
    )
}
```

## Phase 4: authenticate 変更

### 4.1 テスト作成（RED）

**ファイル**: `Tests/UseCaseTests/AuthenticateUseCaseTests.swift`

```swift
// テスト1: 成功時に spawn_started_at クリア
func testAuthenticate_Success_ClearsSpawnStartedAt() {
    // Given
    // - spawn_started_at 設定済み
    // - 有効な認証情報
    // - 仕事あり

    // When
    let result = authenticate(agentId, passkey, projectId)

    // Then
    XCTAssertTrue(result.success)
    let assignment = projectAgentRepo.findAssignment(agentId, projectId)
    XCTAssertNil(assignment.spawnStartedAt)
}

// テスト2: 失敗時も spawn_started_at クリア
func testAuthenticate_Failure_ClearsSpawnStartedAt() {
    // Given
    // - spawn_started_at 設定済み
    // - 有効な認証情報
    // - 仕事なし（セッション作成理由なし）

    // When
    let result = authenticate(agentId, passkey, projectId)

    // Then
    XCTAssertFalse(result.success)
    let assignment = projectAgentRepo.findAssignment(agentId, projectId)
    XCTAssertNil(assignment.spawnStartedAt)
}

// テスト3: タスク優先でセッション作成（共通ロジック使用）
func testAuthenticate_WithBothTaskAndChat_CreatesTaskSession() {
    // Given
    // - in_progress タスクあり
    // - 未読チャットあり

    // When
    let result = authenticate(agentId, passkey, projectId)

    // Then
    XCTAssertEqual(result.session.purpose, .task)
}

// テスト4: タスクセッション既存時はチャットセッション作成
func testAuthenticate_WithExistingTaskSession_CreatesChatSession() {
    // Given
    // - アクティブタスクセッションあり
    // - 未読チャットあり

    // When
    let result = authenticate(agentId, passkey, projectId)

    // Then
    XCTAssertEqual(result.session.purpose, .chat)
}
```

### 4.2 実装（GREEN）

**ファイル**: `Sources/UseCase/AuthenticationUseCases.swift`

```swift
public struct AuthenticateUseCaseV3: Sendable {
    private let credentialRepository: any AgentCredentialRepositoryProtocol
    private let sessionRepository: any AgentSessionRepositoryProtocol
    private let projectAgentRepository: any ProjectAgentAssignmentRepositoryProtocol
    private let workDetectionService: WorkDetectionService

    public func execute(agentId: String, passkey: String, projectId: String) throws -> AuthenticateResult {
        let agentID = AgentID(value: agentId)
        let projID = ProjectID(value: projectId)

        // パスキー検証
        guard let credential = try credentialRepository.findByAgentId(agentID),
              credential.verify(passkey: passkey) else {
            try clearSpawnStarted(agentId: agentID, projectId: projID)
            return .failure(error: "Invalid credentials")
        }

        // 共通ロジックで仕事判定
        let hasTaskWork = try workDetectionService.hasTaskWork(agentId: agentID, projectId: projID)
        let hasChatWork = try workDetectionService.hasChatWork(agentId: agentID, projectId: projID)

        // タスクセッション判定（優先）
        if hasTaskWork {
            let session = AgentSession(agentId: agentID, projectId: projID, purpose: .task)
            try sessionRepository.save(session)
            try clearSpawnStarted(agentId: agentID, projectId: projID)
            return .success(token: session.token, ...)
        }

        // チャットセッション判定
        if hasChatWork {
            let session = AgentSession(agentId: agentID, projectId: projID, purpose: .chat)
            try sessionRepository.save(session)
            try clearSpawnStarted(agentId: agentID, projectId: projID)
            return .success(token: session.token, ...)
        }

        // どちらにも該当しない
        try clearSpawnStarted(agentId: agentID, projectId: projID)
        return .failure(error: "No valid purpose for authentication")
    }

    private func clearSpawnStarted(agentId: AgentID, projectId: ProjectID) throws {
        try projectAgentRepository.updateSpawnStartedAt(
            agentId: agentId,
            projectId: projectId,
            startedAt: nil
        )
    }
}
```

## Phase 5: pending_agent_purposes 削除

### 5.1 参照箇所の削除

1. **MCPServer.swift**
   - pending 検索・作成・削除のコード削除
   - `checkPendingAndMarkStarted` メソッド削除

2. **RESTServer.swift**
   - pending 作成のコード削除

3. **AuthenticateUseCaseV2**
   - 廃止（V3 に置き換え）

4. **PendingAgentPurposeRepository**
   - ファイル削除

5. **PendingAgentPurpose エンティティ**
   - ファイル削除

### 5.2 テーブル削除

```sql
DROP TABLE pending_agent_purposes;
```

## Phase 6: 統合テスト

### 6.1 テストケース

1. **重複スポーン防止**
   - 連続で getAgentAction を呼んでも1回しか start が返らない

2. **認証失敗後の即再試行**
   - 認証失敗 → 次の getAgentAction で即 start

3. **chat + task 同時存在時の順次処理**
   - 両方ある → task で start → authenticate → task セッション
   - 再度 getAgentAction → chat で start → authenticate → chat セッション

4. **マネージャーの部下待機**
   - 部下が仕事中 → マネージャーは hold
   - 部下が完了 → マネージャーは start

5. **共通ロジック一貫性**
   - getAgentAction と authenticate が同じ判定結果を返す

## チェックリスト

### Phase 1: スキーマ ✅
- [x] マイグレーション SQL 作成 (v42_project_agents_spawn_started_at)
- [x] ProjectAgentAssignment エンティティ更新 (spawnStartedAt プロパティ追加)
- [x] ProjectAgentRepository 更新 (findAssignment, updateSpawnStartedAt)

### Phase 2: WorkDetectionService ✅
- [x] テスト作成（RED）
- [x] hasChatWork 実装
- [x] hasTaskWork 実装
- [x] テスト（GREEN）- 11テスト全てパス

### Phase 3: getAgentAction ✅
- [x] checkTaskWorkWithHierarchy 実装
- [x] checkManagerTaskWork 実装
- [x] checkSpawnInProgress 実装
- [x] markSpawnStarted 実装
- [x] WorkDetectionService 統合
- [x] ビルド成功

### Phase 4: authenticate ✅
- [x] AuthenticateUseCaseV3 実装
- [x] WorkDetectionService 統合
- [x] clearSpawnStarted 実装 (MCPServer内)
- [x] MCPServer 統合
- [x] 既存テスト（GREEN）- 8テスト全てパス

### Phase 5: 削除
- [ ] pending 関連コード削除
- [ ] テーブル削除
- [ ] 既存テスト修正

### Phase 6: 統合テスト
- [ ] 重複スポーン防止テスト
- [ ] 認証失敗再試行テスト
- [ ] chat + task 順次処理テスト
- [ ] マネージャー待機テスト
- [ ] 共通ロジック一貫性テスト

## 完了基準

1. 全ユニットテストがパス
2. 統合テストがパス
3. `pending_agent_purposes` テーブルが削除されている
4. コードレビュー完了
