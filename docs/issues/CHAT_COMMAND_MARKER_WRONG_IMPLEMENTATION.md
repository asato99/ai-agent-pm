# Issue: チャットコマンドマーカーの実装が設計と乖離

## 概要

`96b9007` で実装されたチャットコマンドマーカー機能が、設計書（`docs/design/CHAT_COMMAND_MARKER.md`）の意図と根本的に異なる方法で実装されている。

## 設計意図

ユーザーがチャットメッセージに `@@タスク作成:` マーカーを付けることで、タスク作成の意思を明示する。システムは**チャット履歴の最新受信メッセージ**にマーカーがあるかを検証し、エージェントの自律判断による誤操作を防ぐ。

### 設計書で想定されたフロー

```
ユーザー: "@@タスク作成: ログイン機能を実装"
    ↓
エージェント: チャット履歴からマーカーを検出
エージェント: request_task(title: "ログイン機能を実装")  ← マーカーを除去した純粋なタイトル
    ↓
システム: チャット履歴の最新受信メッセージに @@タスク作成: があるか検証
    ↓ (バリデーション通過)
タスク作成成功
```

### 設計書の該当コード（正しいバリデーション）

```swift
// docs/design/CHAT_COMMAND_MARKER.md より
if session.purpose == .chat {
    let messages = try chatRepository.findMessages(
        projectId: session.projectId,
        agentId: session.agentId
    )
    let incomingMessages = messages.filter { $0.senderId != session.agentId }

    let markerPattern = "[@＠][@＠]タスク作成:"
    guard let lastMessage = incomingMessages.last,
          lastMessage.content.range(of: markerPattern, options: .regularExpression) != nil else {
        throw MCPError.taskRequestMarkerRequired
    }
}
```

## 実際の実装（問題）

### 問題1: ツール引数を検証している（チャット履歴を見ていない）

`Sources/MCPServer/MCPServer.swift:1101-1106`

```swift
if session.purpose == .chat {
    guard ChatCommandMarker.containsTaskCreateMarker(title) else {
        throw MCPError.taskRequestMarkerRequired
    }
}
```

**`title` 引数**（`request_task` ツールの引数）にマーカー文字列が含まれているかを検証している。設計書が求めている**チャット履歴の最新受信メッセージ**の検証は一切行っていない。

同様に `notify_task_session` でも `message` 引数を検証している（`MCPServer.swift:1210-1214`）。

### 問題2: タスクタイトルにマーカーが残る

インストラクション4箇所で、エージェントに対して title 引数にマーカーを含めるよう指示している：

```swift
// MCPServer.swift:2999-3001
【重要】タスク作成時は @@タスク作成: マーカーが必要です
request_task の title には「@@タスク作成: タスクタイトル」の形式で指定してください。
例: title = "@@タスク作成: ログイン機能を実装"
```

この結果、タスクのタイトルが `"@@タスク作成: ログイン機能を実装"` のままDBに保存される。設計書では `request_task(title: "ログイン機能を実装")` のようにマーカーを除去した純粋なタイトルが渡されることを想定している。

### 問題3: 設計の防御機能が無効化されている

設計の本来の目的は「**ユーザーが明示的にマーカーをつけたかどうか**をシステムが検証する」こと。しかし実装では「**エージェントがツール引数にマーカー文字列を含めたかどうか**」を見ているだけ。

これにより：
- エージェントが勝手にマーカーを付加してツールを呼べば、ユーザーの意思確認なしにバリデーションを通過する
- 設計書が解決しようとした「エージェントの自律判断による誤操作」が防げない
- マーカーの存在意義（ユーザーの明示的な意思表示）が完全に失われている

### 問題4: テストがプレースホルダー

`Tests/MCPServerTests/ChatCommandMarkerValidationTests.swift` の統合テスト5件中3件が常にパスするプレースホルダー：

```swift
func testRequestTaskWithMarkerSucceeds() {
    XCTAssertTrue(true, "Placeholder - full integration test in E2E tests")
}

func testRequestTaskWithoutMarkerFails() {
    XCTAssertTrue(true, "Placeholder - full integration test in E2E tests")
}

func testRequestTaskFromTaskSessionSkipsMarkerValidation() {
    XCTAssertTrue(true, "Placeholder - full integration test in E2E tests")
}
```

バリデーションの中核ロジック（マーカーなしで拒否されるか、タスクセッションでは不要か）が全くテストされていない。

### 問題5: テストの重複

`ChatCommandMarkerTests.swift`（185行、新規ファイル）と `DomainTests.swift`（125行追加）にほぼ同一のテストが存在する。同じ `ChatCommandMarker` のユニットテストが2ファイルに重複して書かれている。

## 影響範囲

| ファイル | 問題 |
|----------|------|
| `Sources/MCPServer/MCPServer.swift` | バリデーションが title/message 引数を検証（2箇所） |
| `Sources/MCPServer/MCPServer.swift` | インストラクション4箇所でマーカーをtitleに含めるよう指示 |
| `Tests/MCPServerTests/ChatCommandMarkerValidationTests.swift` | プレースホルダーテスト |
| `Tests/DomainTests/DomainTests.swift` | テスト重複 |

## 修正方針

### 1. バリデーションの修正

`request_task` / `notify_task_session` のバリデーションを、設計書通り**チャット履歴の最新受信メッセージ**を検証するように変更する。

### 2. インストラクションの修正

エージェントへの指示を「titleにマーカーを含めろ」から「ユーザーメッセージの @@マーカーを確認してからツールを呼べ」に変更する。

### 3. テストの修正

- プレースホルダーを実際のバリデーションテストに置き換える
- 重複テストを整理する

## 関連

- 設計書: `docs/design/CHAT_COMMAND_MARKER.md`
- コミット: `96b9007` (Add chat command marker validation for task creation and notification)
- Domain層の `ChatCommandMarker` enum 自体は正しく実装されている（マーカーの検出・抽出ロジック）

## 発見日

2026-02-09
