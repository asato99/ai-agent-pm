# UC001: エージェントによるタスク実行 - 実装計画

## 現状分析

### UC001の要件（docs/usecase/UC001_TaskExecutionByAgent.md より）

```
1. タスク作成（ユーザー）
   - タイトル: ドキュメントの作成
   - ファイル名: テストのドキュメント
   - 内容: テスト１
   - ステータス: backlog

2. エージェント割り当て（ユーザー）
   - assigneeId: [エージェントID]

3. ステータス変更（ユーザー）
   - ステータスを in_progress に変更
   - → システムがエージェントをキック（実行開始通知）

4. 作業計画（エージェント）
   - 子タスクを追加

5. タスク実行（エージェント）
   - 子タスクを順次実行

6. 完了通知（エージェント）
   - 親タスクを done に変更
   - → システムが親に完了通知
```

### 現状で実装済みの機能

| 機能 | 状態 | 備考 |
|------|------|------|
| タスク作成UI | ○ | タイトル、説明、優先度、アサイン先 |
| エージェント割り当てUI | ○ | TaskFormViewのPicker |
| ステータス変更UI | ○ | TaskDetailViewのStatusPicker |
| MCP経由のタスク操作 | ○ | agent-pm MCPサーバー実装済み |

### 未実装の機能

| 機能 | 必要性 | 理由 |
|------|--------|------|
| プロジェクト作業ディレクトリ | 必須 | Claude Codeがどこで作業するか不明 |
| タスク成果物情報（ファイル名等） | 必須 | 「ドキュメントの作成」に必要 |
| エージェントキック機能 | 必須 | in_progress時にClaude Code起動 |
| 子タスク機能 | 要検討 | 要件ではサブタスク不要とあるが、UC001では使用 |
| 完了通知機能 | 必須 | 親への通知 |

---

## 必要な機能の詳細設計

### 1. プロジェクト作業ディレクトリ

**目的**: Claude Codeエージェントがタスクを実行する際の作業場所を指定

**変更箇所**:
- `Sources/Domain/Entities/Project.swift` - `workingDirectory: String?` 属性追加
- `Sources/Infrastructure/Database/DatabaseSetup.swift` - マイグレーション追加
- `Sources/App/Features/ProjectList/ProjectFormView.swift` - 入力フィールド追加

**仕様**:
- 絶対パスで指定
- 存在確認はオプション（警告のみ）
- 未設定の場合、エージェントキック時にエラー

### 2. タスク成果物情報

**目的**: タスクで作成すべき成果物（ファイル）の情報を保持

**変更箇所**:
- `Sources/Domain/Entities/Task.swift` - 成果物情報属性追加
- `Sources/Infrastructure/Database/DatabaseSetup.swift` - マイグレーション追加
- `Sources/App/Features/TaskBoard/TaskFormView.swift` - 入力フィールド追加

**仕様案**:
```swift
// 案1: シンプルなファイル名と内容
struct Task {
    // 既存属性...
    var outputFileName: String?  // 成果物ファイル名
    var outputContent: String?   // 成果物の内容/指示
}

// 案2: 構造化された成果物情報
struct TaskOutput: Codable {
    var fileName: String
    var description: String
    var format: String?  // markdown, swift, etc.
}
```

**検討事項**:
- 複数ファイルを成果物とする場合の対応は？
- → 初期実装では単一ファイルのみ対応

### 3. エージェントキック機能

**目的**: ステータスが `in_progress` になった時にClaude Code CLIを起動

**変更箇所**:
- `Sources/UseCase/TaskUseCases.swift` - ステータス変更時のキック処理
- 新規: `Sources/Domain/Services/AgentKickService.swift` - キック処理のインターフェース
- 新規: `Sources/Infrastructure/Services/ClaudeCodeKickService.swift` - Claude Code CLI起動

**仕様**:
```
1. タスクステータスが in_progress に変更される
2. アサイン先エージェントのキック設定を確認
   - kickMethod: cli / script / api / notification
   - kickCommand: カスタムコマンド（オプション）
3. キック実行
   - CLI: claude-code コマンド起動
   - Script: 指定スクリプト実行
   - API: Webhook呼び出し
   - Notification: 通知のみ（手動実行を想定）
4. StateChangeEventに記録
```

**Claude Code CLI起動例**:
```bash
cd /path/to/project/workingDirectory
claude-code --task "タスクタイトル" --description "タスク説明" --output-file "ファイル名"
```

**検討事項**:
- Claude Code CLIの正確な起動方法は？
- 非同期実行か同期実行か？
- エラーハンドリングは？

### 4. 子タスク機能

**現状**: 要件（TASKS.md）では「サブタスク: 初期実装では不要」とある

**UC001との矛盾**:
- UC001のフローでは「エージェントが子タスクを追加」がある
- 依存関係のみでタスク間関係を表現する方針

**対応案**:
1. UC001のフローを修正（子タスクではなく依存タスクとして作成）
2. サブタスク機能を実装（要件変更）

**決定必要**: どちらの方針で進めるか

### 5. 完了通知機能

**目的**: タスク完了時に親（作成者/監視者）に通知

**変更箇所**:
- `Sources/UseCase/TaskUseCases.swift` - done変更時の通知処理
- 新規: `Sources/Domain/Services/NotificationService.swift`

**仕様**:
- タスクが done になった時に通知
- 通知方法は検討（macOS通知、ログ、UI更新等）
- Handoffエンティティとの関連

---

## Feature分解と実装順序

UC001を直接実装する前に、必要な機能を個別のFeatureとして分解し、
それぞれを「UI設計 → UIテスト作成 → 実装 → テストパス確認」の順で進める。

---

## Feature 06: プロジェクト作業ディレクトリ

### 概要
Claude Codeエージェントがタスクを実行する際の作業ディレクトリをプロジェクトに設定する。

### UI設計

**ProjectFormView に追加する要素:**
```
Section("Execution Settings") {
    TextField("Working Directory", text: $workingDirectory)
        .accessibilityIdentifier("ProjectWorkingDirectoryField")

    Text("Claude Code agent will execute tasks in this directory")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

**ProjectDetailView に追加する要素:**
```
// 作業ディレクトリ表示
Text("Working Directory: \(project.workingDirectory ?? "Not set")")
    .accessibilityIdentifier("ProjectWorkingDirectory")
```

### UIテスト設計

| テストID | テスト内容 | アサーション |
|----------|-----------|-------------|
| F06-01 | 作業ディレクトリフィールド存在 | ProjectFormViewにWorkingDirectoryFieldが存在する |
| F06-02 | 作業ディレクトリ保存 | 入力した値が保存され、詳細画面に表示される |
| F06-03 | 作業ディレクトリ未設定 | 未設定の場合「Not set」と表示される |

### 実装箇所

| ファイル | 変更内容 |
|----------|----------|
| Sources/Domain/Entities/Project.swift | workingDirectory属性追加 |
| Sources/Infrastructure/Database/DatabaseSetup.swift | v6マイグレーション |
| Sources/Infrastructure/Repositories/ProjectRepository.swift | 属性対応 |
| Sources/App/Features/ProjectList/ProjectFormView.swift | UI追加 |
| Sources/App/Features/ProjectList/ProjectDetailView.swift | 表示追加 |

### 状態
- [ ] UI設計完了
- [ ] UIテスト作成
- [ ] 実装
- [ ] テストパス確認

---

## Feature 07: タスク成果物情報

### 概要
タスクで作成すべき成果物（ファイル名、内容/指示）を入力・保存する。

### UI設計

**TaskFormView に追加する要素:**
```
Section("Output") {
    TextField("Output File Name", text: $outputFileName)
        .accessibilityIdentifier("TaskOutputFileNameField")

    TextField("Output Description", text: $outputDescription, axis: .vertical)
        .lineLimit(3...6)
        .accessibilityIdentifier("TaskOutputDescriptionField")
}
```

**TaskDetailView に追加する要素:**
```
Section("Output") {
    if let fileName = task.outputFileName {
        LabeledContent("File Name", value: fileName)
            .accessibilityIdentifier("TaskOutputFileName")
    }
    if let desc = task.outputDescription {
        Text(desc)
            .accessibilityIdentifier("TaskOutputDescription")
    }
}
.accessibilityIdentifier("OutputSection")
```

### UIテスト設計

| テストID | テスト内容 | アサーション |
|----------|-----------|-------------|
| F07-01 | 成果物ファイル名フィールド存在 | TaskFormViewにOutputFileNameFieldが存在する |
| F07-02 | 成果物説明フィールド存在 | TaskFormViewにOutputDescriptionFieldが存在する |
| F07-03 | 成果物情報保存 | 入力した値が保存され、詳細画面に表示される |
| F07-04 | OutputSection表示 | タスク詳細にOutputSectionが表示される |

### 実装箇所

| ファイル | 変更内容 |
|----------|----------|
| Sources/Domain/Entities/Task.swift | outputFileName, outputDescription属性追加 |
| Sources/Infrastructure/Database/DatabaseSetup.swift | v6マイグレーション（同一） |
| Sources/Infrastructure/Repositories/TaskRepository.swift | 属性対応 |
| Sources/App/Features/TaskBoard/TaskFormView.swift | UI追加 |
| Sources/App/Features/TaskDetail/TaskDetailView.swift | 表示追加 |

### 状態
- [ ] UI設計完了
- [ ] UIテスト作成
- [ ] 実装
- [ ] テストパス確認

---

## Feature 08: エージェントキック実行

### 概要
タスクステータスがin_progressに変更された時、アサイン先エージェントをキック（Claude Code CLI起動）する。

### 前提
- Feature 06（プロジェクト作業ディレクトリ）完了
- Feature 07（タスク成果物情報）完了
- エージェントにkickMethod設定済み

### UI設計

**TaskDetailView ステータス変更時の動作:**
```
1. ステータスをin_progressに変更
2. キック実行
   - 成功: HistorySectionに「Agent kicked: claude-code-agent」記録
   - 失敗: エラーアラート表示
3. StateChangeEvent記録
```

**キック成功時のHistory表示:**
```
HistoryRow:
  - イベント種別: "Agent Kicked"
  - エージェント名: "claude-code-agent"
  - タイムスタンプ
```

### UIテスト設計

| テストID | テスト内容 | アサーション |
|----------|-----------|-------------|
| F08-01 | キック成功時のHistory記録 | in_progress変更後、HistorySectionに「Agent Kicked」が表示される |
| F08-02 | キック失敗時のエラー表示 | 作業ディレクトリ未設定時、エラーアラートが表示される |
| F08-03 | キック設定なしエージェント | kickMethod未設定の場合、エラーアラートが表示される |

### 実装箇所

| ファイル | 変更内容 |
|----------|----------|
| Sources/Domain/Services/AgentKickService.swift | 新規：キックサービスプロトコル |
| Sources/Infrastructure/Services/ClaudeCodeKickService.swift | 新規：Claude Code CLI起動 |
| Sources/UseCase/TaskUseCases.swift | ステータス変更時のキック呼び出し |
| Sources/App/Core/DependencyContainer.swift | キックサービス登録 |

### 状態
- [ ] UI設計完了
- [ ] UIテスト作成
- [ ] 実装
- [ ] テストパス確認

---

## 実装順序

1. **Feature 06: プロジェクト作業ディレクトリ** ← 最初に実装
2. **Feature 07: タスク成果物情報**
3. **Feature 08: エージェントキック実行**
4. **UC001統合テスト** ← 全Feature完了後

---

## UIテスト設計（Phase 1用）

### テストデータ前提（セットアップ）

```swift
// UITestScenario:UC001 で投入するデータ
- プロジェクト:
  - id: "prj_uc001_test"
  - name: "UC001テストプロジェクト"
  - workingDirectory: "/tmp/uc001_test"  // ← 新規

- エージェント:
  - id: "agt_claude_code"
  - name: "claude-code-agent"
  - type: .ai
  - kickMethod: .cli
  - status: .active
```

### テストケース

| ID | テスト内容 | アサーション |
|----|-----------|-------------|
| UC001-P1-01 | プロジェクト作業ディレクトリ設定 | 作業ディレクトリフィールドが存在し、保存される |
| UC001-P1-02 | タスク成果物情報入力 | ファイル名フィールドが存在し、保存される |
| UC001-P1-03 | 成果物情報がタスク詳細に表示 | 詳細画面に成果物情報が表示される |

---

## 進捗記録

| 日時 | 作業内容 | 結果 |
|------|----------|------|
| 2026-01-02 17:40 | 実装計画書作成開始 | 進行中 |

---

## 未解決事項

1. Claude Code CLIの正確な起動方法・引数
2. 子タスク vs 依存タスクの方針決定
3. 成果物が複数ファイルの場合の対応
4. 非同期キック時のエラーハンドリング方針
