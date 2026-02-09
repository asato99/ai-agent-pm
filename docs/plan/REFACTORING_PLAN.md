# 大規模リファクタリング計画

> **作成日**: 2026-02-09
> **ステータス**: Phase 2 完了
> **目的**: レガシー化が進むコードベースの構造改善

---

## 背景

機能追加・改修を重ねる中で、以下の構造劣化が顕在化している：

- **God Object の肥大化**: MCPServer.swift（7,542行）、RESTServer.swift（2,695行）
- **単一責任原則の違反**: UseCase が複数の責務を持つ（例: UpdateTaskStatusUseCase 414行）
- **マイグレーションの集中**: DatabaseSetup.swift に51バージョン（1,257行）
- **UI View の肥大化**: 1,000行超のビューが複数存在
- **エラー型の肥大化**: UseCaseError が26ケース

一方で、以下の良好な点は維持されている：

- **Clean Architecture のレイヤー分離**: Domain → UseCase → Infrastructure → App の依存方向に違反なし
- **DI 設計**: DependencyContainer による適切な依存注入
- **リアクティブ UI**: TaskStore + @Published パターン
- **テストカバレッジ**: ユニットテスト52ファイル（24,424行）、UIテスト34ファイル（10,578行）

---

## 現状メトリクス

### ファイルサイズ（深刻度順）

| ファイル | 行数 | 深刻度 | 責務数 |
|---------|------|--------|--------|
| MCPServer.swift | ~~7,542~~ → 1,530 | ~~CRITICAL~~ → MODERATE | ~~9+~~ → 3（コア+ルーティング+enum） |
| RESTServer.swift | ~~2,695~~ → 568 | ~~CRITICAL~~ → HEALTHY | ~~5+~~ → 2（ルート登録+helpers） |
| ToolDefinitions.swift | 1,570 | MAJOR | 1（ただし60定義） |
| DatabaseSetup.swift | 1,257 | MAJOR | 51マイグレーション |
| SettingsView.swift | 1,148 | MODERATE | 4+ タブ |
| SkillManagementView.swift | 1,085 | MODERATE | 3+ |
| TaskDetailView.swift | 1,079 | MODERATE | 4+ セクション |

### 層別健全性

| 層 | ファイル数 | 総行数 | 評価 |
|----|----------|--------|------|
| Domain | 28 | 3,054 | HEALTHY |
| UseCase | 18 | 3,869 | ~~MODERATE~~ → HEALTHY（3ファイル→サブディレクトリ分割済） |
| Infrastructure | 35 | 6,863 | MODERATE |
| App | 43 | 15,559 | MAJOR |
| MCPServer | 22 | 9,625 | ~~CRITICAL~~ → MODERATE（14ファイルに分割済） |
| RESTServer | 23 | 3,150 | ~~MAJOR~~ → MODERATE（12ファイルに分割済） |

---

## フェーズ構成

```
Phase 0: MCPServer.swift 分割         [完了 ✅]
Phase 1: RESTServer.swift 分割        [完了 ✅]
Phase 2: UseCase 層の改善              [中優先]
Phase 3: Infrastructure 層の整理       [中優先]
Phase 4: App 層 View の分割            [低優先]
Phase 5: 横断的な改善                  [低優先]
```

---

## Phase 0: MCPServer.swift 分割

### 概要

| 項目 | 値 |
|------|-----|
| 対象ファイル | `Sources/MCPServer/MCPServer.swift`（7,542行） |
| 依存数 | 19リポジトリ |
| メソッド数 | 120+ |
| 推定作業量 | 大 |
| リスク | 高（MCP プロトコル全体に影響） |

### 現状の責務分析

MCPServer.swift は以下の責務を1ファイルに混在させている：

1. **MCP プロトコルハンドリング**: initialize, listTools, callTool 等
2. **認証・認可**: エージェント認証、セッション管理
3. **ツール実行（タスク系）**: create_task, update_task, get_my_task 等（~20ツール）
4. **ツール実行（エージェント系）**: register_agent, get_agent_status 等（~10ツール）
5. **ツール実行（プロジェクト系）**: create_project, list_projects 等（~8ツール）
6. **ツール実行（チャット系）**: send_message, get_messages 等（~12ツール）
7. **ツール実行（監査系）**: create_audit, submit_finding 等（~10ツール）
8. **ツール実行（その他）**: ワークフロー、通知、スキル等（~15ツール）
9. **リソース処理**: listResources, readResource
10. **プロンプト生成**: listPrompts, getPrompt
11. **データ変換**: エンティティ → MCP レスポンス変換

### 実施結果（2026-02-09 完了）

**アプローチ**: Swift extension による安全な分割

計画当初は ToolHandler プロトコル + DI 設計を想定していたが、リスク最小化のため extension ベースのファイル分割を採用。MCPServer クラスの public API は一切変更なし。

**実施前** → **実施後**:
- MCPServer.swift: 7,542行 → 1,530行（プロトコルハンドリング、プロパティ、init、ルーティング、executeToolImpl switch、BlockType/MCPError enum）
- 新規14ファイル: `Handlers/` サブディレクトリに配置

```
Sources/MCPServer/
├── MCPServer.swift              （1,530行: コア、ルーティング、enum）
├── App.swift                    （エントリーポイント）
├── Authorization/
│   └── ToolAuthorization.swift
├── Handlers/                    （★新規: ツール実行ハンドラー群）
│   ├── AgentAPI.swift           （エージェント操作: get_my_task, report_completed, logout 等）
│   ├── ChatTaskTools.swift      （チャット→タスク: start_task_from_chat, update_task_from_chat）
│   ├── ChatTools.swift          （チャット: send_message, get_pending_messages）
│   ├── ConversationTools.swift  （会話管理: start/end_conversation, delegate_to_chat_session）
│   ├── Converters.swift         （Entity→Dict変換: agentToDict, taskToDict 等）
│   ├── CoordinatorAPI.swift     （コーディネーターAPI: health_check, list_managed_agents）
│   ├── ExecutionLog.swift       （実行ログ: report_execution_start/complete）
│   ├── HelpTool.swift           （ヘルプ: executeHelp, buildToolList）
│   ├── Prompts.swift            （プロンプト: handlePromptsList, handlePromptsGet）
│   ├── Resources.swift          （リソース: handleResourcesList, handleResourcesRead）
│   ├── SelfStatusTools.swift    （自己ステータス: getMyExecutionHistory）
│   ├── SessionAuth.swift        （認証: validateSession, authenticate）
│   ├── TaskTools.swift          （タスク: createTask, assignTask, updateTaskStatus）
│   └── WorkflowControl.swift   （ワークフロー: getNextAction, getWorkerNextAction）
├── Tools/
│   └── ToolDefinitions.swift
└── Transport/
    ├── JSONRPCTypes.swift
    ├── StdioTransport.swift
    ├── Transport.swift
    └── UnixSocketTransport.swift
```

**アクセス制御変更**: `private` → `internal`（extension 間参照のため）
- プロパティ: 19個のリポジトリ依存、log/logDebug/formatResult メソッド
- BlockType enum: private → internal

**テスト結果**:
- MCPServerTests: 221テスト, 5件失敗（全て Phase 0 以前から既存、0 unexpected）
- RESTServerTests: 全テスト成功
- ビルド: MCPServer, RESTServer, AIAgentPMApp 全ターゲット成功

**残タスク（Phase 0 後半として検討）**:
- ToolHandler プロトコル導入 + DI 改善（現状は extension で十分に見通しが良いため急務ではない）
- ToolDefinitions.swift のドメイン別分割（1,570行）

---

## Phase 1: RESTServer.swift 分割

### 概要

| 項目 | 値 |
|------|-----|
| 対象ファイル | `Sources/RESTServer/RESTServer.swift`（2,695行） |
| 依存数 | 16リポジトリ |
| エンドポイント数 | 40+ |
| 推定作業量 | 中 |
| リスク | 中（REST API 全体に影響） |

### 実施結果（2026-02-09 完了）

**アプローチ**: Phase 0 同様、Swift extension による安全な分割

**実施前** → **実施後**:
- RESTServer.swift: 2,695行 → 568行（プロパティ、init、run、ルート登録、helpers）
- 新規11ファイル: `Handlers/` サブディレクトリに配置
- 新規1ファイル: `DTOs/InlineDTOs.swift`（インラインDTOを分離）

```
Sources/RESTServer/
├── RESTServer.swift             （568行: コア、ルート登録、helpers）
├── main.swift
├── RESTServer.entitlements
├── DTOs/                        （既存 + InlineDTOs.swift）
│   ├── AgentDTO.swift
│   ├── ChatDTO.swift
│   ├── ContextDTO.swift
│   ├── ExecutionLogDTO.swift
│   ├── InlineDTOs.swift         （★新規: Auth/Handoff/WorkingDirectory DTOs）
│   ├── ProjectDTO.swift
│   ├── SkillDTO.swift
│   └── TaskDTO.swift
├── Handlers/                    （★新規: エンドポイントハンドラー群）
│   ├── AgentHandlers.swift
│   ├── AuthHandlers.swift
│   ├── ChatHandlers.swift
│   ├── ExecutionLogHandlers.swift
│   ├── HandoffHandlers.swift
│   ├── LogUploadHandler.swift
│   ├── MCPTransport.swift
│   ├── ProjectHandlers.swift
│   ├── SkillHandlers.swift
│   ├── TaskHandlers.swift
│   └── TaskRequestHandlers.swift
└── Middleware/                   （既存）
    ├── AuthMiddleware.swift
    └── CORSMiddleware.swift
```

**アクセス制御変更**: `private` → `internal`
- 20個のリポジトリプロパティ、mcpServer lazy var
- debugLog トップレベル関数
- 全ハンドラーメソッド

**テスト結果**:
- RESTServerTests: 49テスト全通過
- MCPServerTests: 221テスト, 5件失敗（全て既知、0 unexpected）
- パイロットテスト: ALL PASSED（439.3秒）
- ビルド: 全ターゲット成功

---

## Phase 2: UseCase 層の改善

### 概要

| 項目 | 値 |
|------|-----|
| 対象 | UseCase 層全体（12ファイル、3,869行） |
| 主要問題 | UpdateTaskStatusUseCase の肥大化、UseCaseError の肥大化 |
| 推定作業量 | 中 |
| リスク | 中（ビジネスロジックの中核） |

### 2-A: UpdateTaskStatusUseCase の分割

**現状**: 414行、7+の責務
- ステータスバリデーション
- 遷移ルール適用
- リソースチェック（assignee 可用性）
- 依存関係チェック
- ブロック状態解除
- イベント記録
- 親タスクステータス更新

**分割方針**:

```
Sources/UseCase/TaskStatusTransition/
├── UpdateTaskStatusUseCase.swift      （オーケストレーションのみ、~100行）
├── StatusTransitionValidator.swift    （遷移ルール検証）
├── ResourceAvailabilityChecker.swift  （リソースチェック）
├── DependencyBlockChecker.swift       （依存関係チェック）
└── ParentTaskUpdater.swift            （親タスク連動更新）
```

**テスト**: `swift test --filter UseCaseTests`（各分割後）

### 2-B: UseCaseError の整理

**現状**: 26ケースが単一 enum に集中

**分割方針**:

```swift
// 現在: UseCaseError に26ケース
// 改善: ドメイン別のエラー型を定義し、UseCaseError はラッパーに

enum TaskError: Error { ... }       // タスク固有エラー
enum AgentError: Error { ... }      // エージェント固有エラー
enum ProjectError: Error { ... }    // プロジェクト固有エラー
enum ChatError: Error { ... }       // チャット固有エラー
enum AuditError: Error { ... }      // 監査固有エラー

// UseCaseError は共通エラー + ドメインエラーラッパー
enum UseCaseError: Error {
    case notFound(String)
    case validationFailed(String)
    case unauthorized(String)
    case domain(Error)             // ドメイン固有エラーをラップ
}
```

**注意**: エラーハンドリングの変更は広範囲に影響する。段階的に移行し、後方互換性を維持する。

**テスト**: `swift test`（全ユニットテスト）

### 2-C: TaskUseCases.swift の分割

**現状**: 713行に複数の UseCase が混在

**分割方針**:

```
Sources/UseCase/
├── Task/
│   ├── CreateTaskUseCase.swift
│   ├── UpdateTaskUseCase.swift
│   ├── DeleteTaskUseCase.swift
│   ├── GetTaskUseCase.swift
│   ├── ListTasksUseCase.swift
│   ├── StatusTransition/
│   │   ├── UpdateTaskStatusUseCase.swift
│   │   ├── StatusTransitionValidator.swift
│   │   ├── ResourceAvailabilityChecker.swift
│   │   ├── DependencyBlockChecker.swift
│   │   └── ParentTaskUpdater.swift
│   └── TaskAssignmentUseCase.swift
├── Agent/
│   └── ... (既存の AgentUseCases.swift から分割)
├── Chat/
│   └── ... (既存の ChatUseCases.swift から分割)
└── ...
```

**テスト**: `swift test --filter UseCaseTests`

### Phase 2 実施結果（2026-02-09 完了）

**アプローチ**: Phase 2-C（ファイル分割）のみ実施。2-A（UpdateTaskStatusUseCase内部分割）と2-B（UseCaseError整理）はリスク対効果を考慮し今回はスキップ。

**実施前** → **実施後**:
- TaskUseCases.swift (713行) → 削除、3ファイルに分割
- UseCases.swift (518行) → 削除、UseCaseError.swift + 3ドメインファイルに分割
- InternalAuditUseCases.swift (709行) → 削除、3ファイルに分割

```
Sources/UseCase/
├── UseCaseError.swift           （99行: 共通エラー定義）
├── Task/
│   ├── UpdateTaskStatus.swift   （414行: ステータス更新）
│   ├── TaskCommands.swift       （CreateTask, AssignTask, UpdateTask, ApproveTask, RejectTask）
│   └── TaskQueries.swift        （GetTasks, GetTasksByAssignee, GetTaskDetail, GetMyTasks, GetPendingTasks）
├── Project/
│   └── ProjectUseCases.swift    （GetProjects, CreateProject, PauseProject, ResumeProject）
├── Agent/
│   └── AgentUseCases.swift      （GetAgents, CreateAgent, GetAgentProfile, GetAgentSessions, GetManagedAgents）
├── Audit/
│   ├── AuditUseCases.swift      （InternalAudit CRUD: Create, List, Get, Update, Suspend, Activate, Delete）
│   ├── AuditRuleUseCases.swift  （AuditRule CRUD + Trigger: Create, List, EnableDisable, GetWithRules, Delete, Update, Fire, CheckTriggers）
│   └── AuditLockUseCases.swift  （Lock/Unlock: LockTask, UnlockTask, LockAgent, UnlockAgent, GetLockedTasks, GetLockedAgents）
├── AuthenticationUseCases.swift （変更なし）
├── ContextUseCases.swift        （変更なし）
├── ExecutionLogUseCases.swift   （変更なし）
├── HandoffUseCases.swift        （変更なし）
├── NotificationUseCases.swift   （変更なし）
├── SessionUseCases.swift        （変更なし）
├── SkillUseCases.swift          （変更なし）
├── WorkDetectionService.swift   （変更なし）
└── WorkflowTemplateUseCases.swift（変更なし）
```

**テスト結果**:
- UseCaseTests: 152テスト全通過
- MCPServerTests: 221テスト, 5件失敗（全て既知、0 unexpected）
- RESTServerTests: 49テスト全通過
- パイロットテスト: ALL PASSED

**残タスク（Phase 2 後半として検討）**:
- 2-A: UpdateTaskStatusUseCase の内部責務分割（414行 → サブコンポーネント化）
- 2-B: UseCaseError のドメイン別分割（26ケース → ドメイン別エラー型）

---

## Phase 3: Infrastructure 層の整理

### 概要

| 項目 | 値 |
|------|-----|
| 対象 | Infrastructure 層（35ファイル、6,863行） |
| 主要問題 | DatabaseSetup.swift の肥大化（1,257行、51マイグレーション） |
| 推定作業量 | 小〜中 |
| リスク | 中（DB マイグレーションは慎重に） |

### 3-A: DatabaseSetup.swift の分割

**方針**: マイグレーションを論理グループに分割

```
Sources/Infrastructure/Database/
├── DatabaseSetup.swift            （残留: migrator 登録のみ）
├── Migrations/
│   ├── V001_V010_CoreEntities.swift    （初期エンティティ）
│   ├── V011_V020_AgentSystem.swift     （エージェント拡張）
│   ├── V021_V030_ChatSystem.swift      （チャット機能）
│   ├── V031_V040_AuditSystem.swift     （監査機能）
│   └── V041_V051_RecentAdditions.swift （直近の追加）
```

**注意**: マイグレーション実行順序は厳密に維持する必要がある。DatabaseSetup.swift の `migrator.registerMigration` 呼び出し順は変更しない。

**テスト**: `swift test --filter InfrastructureTests`

### 3-B: リポジトリ実装の整理

**現状**: GRDB リポジトリ実装が個別ファイルに分かれているが、一部の大きなリポジトリ（例: GRDBTaskRepository）を確認

**方針**: 500行超のリポジトリ実装があれば、クエリビルダーや変換ロジックを分離

**テスト**: `swift test --filter InfrastructureTests`

### Phase 3 完了チェック

| チェック項目 | コマンド |
|-------------|---------|
| InfrastructureTests 全通過 | `swift test --filter InfrastructureTests` |
| UseCaseTests 通過 | `swift test --filter UseCaseTests` |
| パイロットテスト | `npx playwright test --config=playwright.pilot.config.ts` |

---

## Phase 4: App 層 View の分割

### 概要

| 項目 | 値 |
|------|-----|
| 対象 | 1,000行超の SwiftUI View（4ファイル） |
| 推定作業量 | 小 |
| リスク | 低（UI 変更は局所的） |

### 対象ファイル

| ファイル | 行数 | 分割方針 |
|---------|------|---------|
| SettingsView.swift | 1,148 | タブごとにサブビュー化 |
| SkillManagementView.swift | 1,085 | リスト/フォーム/カテゴリに分割 |
| TaskDetailView.swift | 1,079 | セクションごとにサブビュー化 |
| AgentDetailView.swift | 921 | フォーム/スキル/ステータスに分割 |

### 分割パターン

```swift
// Before: 1,000行超の単一 View
struct TaskDetailView: View {
    var body: some View {
        // 全セクションがインラインで定義
    }
}

// After: セクションをサブビューに分離
struct TaskDetailView: View {
    var body: some View {
        TaskMetadataSection(task: task)
        TaskStatusSection(task: task)
        TaskDependencySection(task: task)
        TaskHistorySection(task: task)
    }
}
```

**テスト**: 対応する UITest クラスのみ実行
- SettingsView → 手動確認（UIテストなし）
- TaskDetailView → `xcodebuild test -scheme AIAgentPM -destination 'platform=macOS' -only-testing:AIAgentPMUITests/TaskDetailTests`

### Phase 4 完了チェック

| チェック項目 | コマンド |
|-------------|---------|
| ビルド成功 | `xcodebuild build -scheme AIAgentPM -destination 'platform=macOS'` |
| 関連 UITests | 変更した View に対応するテストクラスのみ実行 |

---

## Phase 5: 横断的な改善

### 5-A: RepositoryProtocols.swift の分割

**現状**: 23プロトコルが1ファイル（536行）

**方針**:
```
Sources/Domain/Repositories/
├── TaskRepository.swift
├── AgentRepository.swift
├── ProjectRepository.swift
├── ChatRepository.swift
├── AuditRepository.swift
└── ... （ドメインごとに分離）
```

### 5-B: DependencyContainer の整理

**現状**: 60+ の lazy UseCase がフラットに定義

**方針**: UseCase ファクトリをドメインごとにグループ化

```swift
class DependencyContainer {
    lazy var taskUseCases = TaskUseCaseFactory(...)
    lazy var agentUseCases = AgentUseCaseFactory(...)
    // ...
}
```

### 5-C: テストの改善

**現状**: UseCaseTests.swift（5,117行）、MCPServerTests.swift（6,826行）も肥大化

**方針**: ソースと対称的にテストも分割（ただしソース分割後に実施）

### Phase 5 完了チェック

| チェック項目 | コマンド |
|-------------|---------|
| 全ユニットテスト | `swift test` |
| パイロットテスト | `npx playwright test --config=playwright.pilot.config.ts` |

---

## テスト戦略

### 原則

- **ユニットテスト**: 各ステップ完了後に随時実行
- **パイロットテスト**: 各 Phase 完了時に実行（機能横断の回帰確認）
- **UIテスト**: 変更に関連するテストクラスのみ、必要時に実行
- **全テスト**: リファクタリング全体完了後のみ

### テスト実行マトリクス

| タイミング | テスト種別 | コマンド | 所要時間目安 |
|-----------|-----------|---------|-------------|
| 各ステップ後 | 対象ユニットテスト | `swift test --filter {TargetTests}` | ~30秒 |
| Phase 完了時 | 全ユニットテスト | `swift test` | ~2分 |
| Phase 完了時 | パイロットテスト | `npx playwright test --config=playwright.pilot.config.ts` | ~2-3分 |
| Phase 0, 1 完了時 | REST 関連テスト | `swift test --filter RESTServerTests` | ~30秒 |
| Phase 4 変更時 | 対象 UITest | `xcodebuild test -only-testing:{TestClass}` | ~1-2分 |
| 全完了後 | 全 UITest | `xcodebuild test -scheme AIAgentPM` | ~6分 |

### パイロットテストの活用

パイロットテスト（Hello World シナリオ）は以下の理由から各 Phase の区切りで活用する：

1. **実行時間が短い**（~2-3分）
2. **機能横断**：タスク作成 → ステータス更新 → チャット → 成果物確認まで一気通貫
3. **統合確認**：MCP ↔ REST ↔ DB の連携が正常に動作することを確認
4. **回帰検出**：リファクタリングによる意図しない動作変更を早期発見

```bash
# パイロットテスト実行
cd web-ui && npx playwright test --config=playwright.pilot.config.ts
```

### Phase 別テスト選定

| Phase | 随時実行（ユニット） | 完了時実行（統合） |
|-------|---------------------|-------------------|
| Phase 0 | MCPServerTests | 全ユニット + パイロット |
| Phase 1 | RESTServerTests | 全ユニット + パイロット |
| Phase 2 | UseCaseTests | 全ユニット + パイロット |
| Phase 3 | InfrastructureTests | 全ユニット + パイロット |
| Phase 4 | 対象 UITests | ビルド確認 + 対象 UITests |
| Phase 5 | 関連テスト | 全テスト（ユニット + パイロット + UITest） |

---

## リスク管理

### 高リスク要因

| リスク | 影響 | 対策 |
|--------|------|------|
| MCPServer 分割時のプロトコル互換性 | MCP クライアントとの通信断絶 | パイロットテストで早期検出 |
| RESTServer 分割時のルーティング不整合 | API エンドポイント404 | RESTServerTests + パイロットテスト |
| UseCaseError 変更時の広範囲影響 | エラーハンドリング破壊 | 後方互換を維持、段階移行 |
| マイグレーション分割時の実行順序 | DB 破損 | 順序は DatabaseSetup.swift で維持 |

### 安全策

1. **各ステップをコミット**: ロールバック可能な粒度で
2. **Phase ごとにブランチ**: `refactor/phase-0-mcp-server` 等
3. **パイロットテストをゲートに**: Phase 完了条件にパイロットテスト通過を含める
4. **段階的移行**: 一度に全てを変更しない、1ハンドラずつ抽出

---

## 実施順序サマリー

```
Phase 0: MCPServer.swift 分割
  ├── Step 0-1: Handler プロトコル定義
  ├── Step 0-2: TaskToolHandler 抽出
  ├── Step 0-3: AgentToolHandler 抽出
  ├── Step 0-4: ChatToolHandler 抽出
  ├── Step 0-5: 残りのハンドラ抽出
  ├── Step 0-6: ResourceHandler・PromptHandler 抽出
  ├── Step 0-7: EntityConverter 抽出
  ├── Step 0-8: ToolDefinitions 分割
  └── ✅ パイロットテスト + 全ユニットテスト

Phase 1: RESTServer.swift 分割
  ├── Step 1-1: ルートグループ抽象化
  ├── Step 1-2: TaskRoutes 抽出
  ├── Step 1-3: 残りのルート抽出
  ├── Step 1-4: DTO 整理
  └── ✅ パイロットテスト + 全ユニットテスト

Phase 2: UseCase 層の改善
  ├── Step 2-A: UpdateTaskStatusUseCase 分割
  ├── Step 2-B: UseCaseError 整理
  ├── Step 2-C: TaskUseCases.swift 分割
  └── ✅ パイロットテスト + 全ユニットテスト

Phase 3: Infrastructure 層の整理
  ├── Step 3-A: DatabaseSetup マイグレーション分割
  ├── Step 3-B: リポジトリ実装の整理
  └── ✅ パイロットテスト + 全ユニットテスト

Phase 4: App 層 View の分割
  ├── SettingsView / SkillManagementView 分割
  ├── TaskDetailView / AgentDetailView 分割
  └── ✅ 対象 UITests

Phase 5: 横断的な改善
  ├── RepositoryProtocols 分割
  ├── DependencyContainer 整理
  ├── テストファイル分割
  └── ✅ 全テスト実行（ユニット + パイロット + UITest）
```

---

## 完了基準

| 基準 | 目標値 |
|------|--------|
| 500行超のファイル | 50%削減（26個 → 13個以下） |
| MCPServer.swift | 500行以下 |
| RESTServer.swift | 300行以下 |
| 全ユニットテスト | GREEN |
| パイロットテスト | GREEN |
| 全 UIテスト | GREEN |
| Clean Architecture 違反 | 0（現状維持） |

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-02-09 | 初版作成: 6フェーズのリファクタリング計画 |
