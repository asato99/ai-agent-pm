# セッション起動アーキテクチャ実装計画

テストファースト（TDD）で実装するための計画。

**参照**: [SESSION_SPAWN_ARCHITECTURE.md](../design/SESSION_SPAWN_ARCHITECTURE.md)

## 前提条件

- 現在のUC019テストは失敗している（チャット+タスク同時実行ができない）
- 実装完了後、UC019テストがパスすることが最終的な成功基準

## Phase 1: authenticate の状態ベース判定

### 1.1 テスト作成（RED）

**ファイル**: `Tests/UseCaseTests/AuthenticateUseCaseTests.swift`（新規または追加）

```swift
// テスト1: タスクセッション作成
func testAuthenticate_WithInProgressTask_CreatesTaskSession() {
    // Given
    // - activeTaskSession: なし
    // - activeChatSession: なし
    // - inProgressTask: あり（assignee = テスト対象エージェント）
    // - chatPending: なし

    // When
    let result = authenticate(agentId, passkey, projectId)

    // Then
    XCTAssertTrue(result.success)
    XCTAssertEqual(result.session.purpose, .task)
}

// テスト2: チャットセッション作成
func testAuthenticate_WithChatPending_CreatesChatSession() {
    // Given
    // - activeTaskSession: なし
    // - activeChatSession: なし
    // - inProgressTask: なし
    // - chatPending: あり

    // When
    let result = authenticate(agentId, passkey, projectId)

    // Then
    XCTAssertTrue(result.success)
    XCTAssertEqual(result.session.purpose, .chat)
}

// テスト3: タスク優先
func testAuthenticate_WithBothTaskAndChat_PrefersTask() {
    // Given
    // - activeTaskSession: なし
    // - activeChatSession: なし
    // - inProgressTask: あり
    // - chatPending: あり

    // When
    let result = authenticate(agentId, passkey, projectId)

    // Then
    XCTAssertTrue(result.success)
    XCTAssertEqual(result.session.purpose, .task)
}

// テスト4: タスクセッション既存時はチャット作成
func testAuthenticate_WithExistingTaskSession_CreatesChatSession() {
    // Given
    // - activeTaskSession: あり
    // - activeChatSession: なし
    // - inProgressTask: あり
    // - chatPending: あり

    // When
    let result = authenticate(agentId, passkey, projectId)

    // Then
    XCTAssertTrue(result.success)
    XCTAssertEqual(result.session.purpose, .chat)
}

// テスト5: 両セッション既存時は失敗
func testAuthenticate_WithBothSessionsExisting_Fails() {
    // Given
    // - activeTaskSession: あり
    // - activeChatSession: あり

    // When
    let result = authenticate(agentId, passkey, projectId)

    // Then
    XCTAssertFalse(result.success)
}

// テスト6: 何も該当しない場合は失敗
func testAuthenticate_WithNoPurpose_Fails() {
    // Given
    // - activeTaskSession: なし
    // - activeChatSession: なし
    // - inProgressTask: なし
    // - chatPending: なし

    // When
    let result = authenticate(agentId, passkey, projectId)

    // Then
    XCTAssertFalse(result.success)
}

// テスト7: task pending削除
func testAuthenticate_CreatingTaskSession_DeletesTaskPending() {
    // Given
    // - inProgressTask: あり
    // - taskPending: あり

    // When
    authenticate(agentId, passkey, projectId)

    // Then
    let taskPending = pendingRepo.find(agentId, projectId, purpose: .task)
    XCTAssertNil(taskPending)
}

// テスト8: chat pending削除
func testAuthenticate_CreatingChatSession_DeletesChatPending() {
    // Given
    // - chatPending: あり

    // When
    authenticate(agentId, passkey, projectId)

    // Then
    let chatPending = pendingRepo.find(agentId, projectId, purpose: .chat)
    XCTAssertNil(chatPending)
}
```

### 1.2 実装（GREEN）

**ファイル**: `Sources/UseCase/AuthenticationUseCases.swift`

1. `AuthenticateUseCase` に以下のリポジトリを追加:
   - `taskRepository: TaskRepositoryProtocol`
   - `sessionRepository` の検索メソッド拡張（purpose別）

2. `execute` メソッドを書き換え:
   ```swift
   public func execute(agentId: String, passkey: String, projectId: String) throws -> AuthenticateResult {
       // パスキー検証（既存ロジック維持）

       // 状態取得
       let activeTaskSession = findActiveTaskSession(agentId, projectId)
       let activeChatSession = findActiveChatSession(agentId, projectId)
       let inProgressTask = findInProgressTask(agentId, projectId)
       let chatPending = pendingRepo.find(agentId, projectId, purpose: .chat)

       // タスクセッション判定
       if activeTaskSession == nil && inProgressTask != nil {
           // タスクセッション作成
           // task pending削除
           return .success(...)
       }

       // チャットセッション判定
       if activeChatSession == nil && chatPending != nil {
           // チャットセッション作成
           // chat pending削除
           return .success(...)
       }

       return .failure("No valid purpose")
   }
   ```

### 1.3 MCPServer の authenticate 更新

**ファイル**: `Sources/MCPServer/MCPServer.swift`

1. `authenticate` メソッドの重複セッションチェックを削除（Lines 3629-3639）
2. `AuthenticateUseCase` に必要なリポジトリを渡す

## Phase 2: getAgentAction の判定ロジック統一

### 2.1 テスト作成（RED）

**ファイル**: `Tests/MCPServerTests/GetAgentActionTests.swift`（新規または追加）

```swift
// テスト1: タスク起動（pendingなし → 自動作成）
func testGetAgentAction_WithInProgressTask_NoPending_CreatesAndStarts() {
    // Given
    // - activeTaskSession: なし
    // - inProgressTask: あり
    // - taskPending: なし

    // When
    let result = getAgentAction(agentId, projectId)

    // Then
    XCTAssertEqual(result["action"], "start")
    // task pendingが作成されていること
    let taskPending = pendingRepo.find(agentId, projectId, purpose: .task)
    XCTAssertNotNil(taskPending)
    XCTAssertNotNil(taskPending?.startedAt)
}

// テスト2: タスク起動（pending未起動）
func testGetAgentAction_WithTaskPending_NotStarted_Starts() {
    // Given
    // - activeTaskSession: なし
    // - inProgressTask: あり
    // - taskPending: あり（startedAt = nil）

    // When
    let result = getAgentAction(agentId, projectId)

    // Then
    XCTAssertEqual(result["action"], "start")
    // startedAtが設定されていること
    let taskPending = pendingRepo.find(agentId, projectId, purpose: .task)
    XCTAssertNotNil(taskPending?.startedAt)
}

// テスト3: タスクスポーン中 → チャット起動
func testGetAgentAction_WithTaskSpawning_ChatPending_StartsChatInstead() {
    // Given
    // - activeTaskSession: なし
    // - activeChatSession: なし
    // - inProgressTask: あり
    // - taskPending: あり（startedAt = 10秒前）
    // - chatPending: あり（startedAt = nil）

    // When
    let result = getAgentAction(agentId, projectId)

    // Then
    XCTAssertEqual(result["action"], "start")
    // chatPendingのstartedAtが設定されていること
    let chatPending = pendingRepo.find(agentId, projectId, purpose: .chat)
    XCTAssertNotNil(chatPending?.startedAt)
}

// テスト4: 両方スポーン中 → hold
func testGetAgentAction_WithBothSpawning_ReturnsHold() {
    // Given
    // - activeTaskSession: なし
    // - activeChatSession: なし
    // - inProgressTask: あり
    // - taskPending: あり（startedAt = 10秒前）
    // - chatPending: あり（startedAt = 10秒前）

    // When
    let result = getAgentAction(agentId, projectId)

    // Then
    XCTAssertEqual(result["action"], "hold")
}

// テスト5: タスクセッション既存 → チャット起動
func testGetAgentAction_WithExistingTaskSession_StartsChat() {
    // Given
    // - activeTaskSession: あり
    // - activeChatSession: なし
    // - inProgressTask: あり
    // - chatPending: あり（startedAt = nil）

    // When
    let result = getAgentAction(agentId, projectId)

    // Then
    XCTAssertEqual(result["action"], "start")
    // chatPendingのstartedAtが設定されていること
}

// テスト6: スポーンタイムアウト → 再起動
func testGetAgentAction_WithTaskPendingTimedOut_Restarts() {
    // Given
    // - activeTaskSession: なし
    // - inProgressTask: あり
    // - taskPending: あり（startedAt = 130秒前）

    // When
    let result = getAgentAction(agentId, projectId)

    // Then
    XCTAssertEqual(result["action"], "start")
    // startedAtが更新されていること
}

// テスト7: 起動理由なし → hold
func testGetAgentAction_WithNoPurpose_ReturnsHold() {
    // Given
    // - activeTaskSession: なし
    // - activeChatSession: なし
    // - inProgressTask: なし
    // - chatPending: なし

    // When
    let result = getAgentAction(agentId, projectId)

    // Then
    XCTAssertEqual(result["action"], "hold")
}
```

### 2.2 実装（GREEN）

**ファイル**: `Sources/MCPServer/MCPServer.swift`

1. `getAgentAction` メソッドを書き換え:
   - purpose別にpendingを検索
   - タスク優先の判定ロジック
   - authenticateと同じ条件を使用

## Phase 3: タスクステータス変更時のpending作成

### 3.1 テスト作成（RED）

**ファイル**: `Tests/UseCaseTests/TaskStatusChangeTests.swift`（新規）

```swift
// テスト1: in_progress変更時にpending作成
func testUpdateTaskStatus_ToInProgress_CreatesPending() {
    // Given
    // - task.status = .todo
    // - taskPending: なし

    // When
    updateTaskStatus(taskId, newStatus: .inProgress)

    // Then
    let pending = pendingRepo.find(task.assigneeId, task.projectId, purpose: .task)
    XCTAssertNotNil(pending)
}

// テスト2: 既存pending がある場合は作成しない
func testUpdateTaskStatus_ToInProgress_WithExistingPending_DoesNotDuplicate() {
    // Given
    // - task.status = .todo
    // - taskPending: あり

    // When
    updateTaskStatus(taskId, newStatus: .inProgress)

    // Then
    // pendingが1つだけであること
}

// テスト3: 他のステータス変更ではpending作成しない
func testUpdateTaskStatus_ToDone_DoesNotCreatePending() {
    // Given
    // - task.status = .inProgress

    // When
    updateTaskStatus(taskId, newStatus: .done)

    // Then
    // 新しいpendingが作成されていないこと
}
```

### 3.2 実装（GREEN）

タスクステータス変更箇所（複数）にpending作成ロジックを追加:
- `Sources/MCPServer/MCPServer.swift` の `updateTaskStatus`
- `Sources/RESTServer/RESTServer.swift` のタスク更新API
- ドラッグ＆ドロップでのステータス変更

## Phase 4: 統合テスト（UC019）

### 4.1 既存テストの確認

**ファイル**: `web-ui/e2e/integration/chat-task-simultaneous.spec.ts`

UC019テストが以下を検証していることを確認:
1. チャットセッション開始
2. タスクを in_progress に変更
3. タスクセッションが起動
4. 両方のセッションが同時に存在

### 4.2 実装完了確認

```bash
# UC019テスト実行
cd web-ui && npx playwright test chat-task-simultaneous.spec.ts
```

テストがパスすれば実装完了。

## 実装順序とチェックリスト

### Step 1: ユニットテスト基盤
- [ ] `AuthenticateUseCaseTests.swift` 作成
- [ ] `GetAgentActionTests.swift` 作成
- [ ] テストが RED であることを確認

### Step 2: authenticate 実装
- [ ] `AuthenticateUseCase` に `taskRepository` 追加
- [ ] 状態ベースのpurpose判定実装
- [ ] purpose別pending削除実装
- [ ] MCPServer の重複チェック削除
- [ ] ユニットテストが GREEN であることを確認

### Step 3: getAgentAction 実装
- [ ] purpose別pending検索に変更
- [ ] タスク優先の判定ロジック実装
- [ ] フォールバック（pending自動作成）実装
- [ ] ユニットテストが GREEN であることを確認

### Step 4: タスクステータス変更
- [ ] `TaskStatusChangeTests.swift` 作成
- [ ] MCPServer の `updateTaskStatus` にpending作成追加
- [ ] RESTServer のタスク更新APIにpending作成追加
- [ ] ユニットテストが GREEN であることを確認

### Step 5: 統合テスト
- [ ] UC019テスト実行
- [ ] テストが GREEN であることを確認
- [ ] 他のテスト（UC001, UC010等）が壊れていないことを確認

## リスクと対策

### リスク1: 既存機能の破壊
**対策**: 各Stepでユニットテストを実行し、既存テストがパスすることを確認

### リスク2: pending削除漏れ
**対策**:
- TTLによる自然消滅（300秒）
- テストでpending削除を明示的に検証

### リスク3: 判定ロジックの不一致
**対策**:
- getAgentActionとauthenticateで同じ条件を使用
- 条件を定数またはヘルパーメソッドとして共通化

## 完了基準

1. 全ユニットテストがパス
2. UC019（チャット+タスク同時実行）テストがパス
3. 既存の統合テスト（UC001, UC010等）がパス
4. コードレビュー完了
