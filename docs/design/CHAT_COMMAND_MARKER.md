# 設計書: チャットコマンドマーカー

## 概要

チャットメッセージに明示的なマーカー（`@@`）を使用して、タスク作成やタスク通知などの操作を明確に指示する仕組みを導入する。

### 背景

現在のチャット→タスク連携には以下の問題がある：

| 問題 | 説明 |
|------|------|
| 自律判断の曖昧さ | AIエージェントが「作業依頼かどうか」を自律的に判断し、誤解が発生 |
| 重複タスク作成 | 同一依頼が複数回タスク化されるケースがある |
| 操作の混同 | 新規タスク作成とタスクセッション通知の区別が不明確 |

### 目的

- 明示的なマーカーにより操作意図を明確化
- エージェントの自律判断への依存を削減
- システムレベルでのバリデーションによる誤操作防止

---

## 設計方針

| 観点 | 決定 | 理由 |
|------|------|------|
| マーカー形式 | `@@コマンド:` | 入力しやすく視認性が高い |
| 文字対応 | 半角・全角両対応 | 日本語入力時の利便性確保 |
| 強制レベル | インストラクション + バリデーション | 段階的な導入が可能 |
| 既存互換 | 通常メッセージは従来通り | 後方互換性を維持 |

---

## コマンドマーカー一覧

| マーカー | 用途 | 対応ツール |
|----------|------|-----------|
| `@@タスク作成: タイトル` | 新規タスクを作成 | `request_task` |
| `@@タスク通知: メッセージ` | 既存タスクセッションに通知 | `notify_task_session` |
| `@@タスク調整: 内容` | 既存タスク(backlog/todo)の修正・削除 | `update_task_from_chat` |
| (マーカーなし) | 通常の会話・質問 | `send_message` |

### マーカー形式

```
@@タスク作成: ログイン機能を実装
＠＠タスク作成: ログイン機能を実装  (全角も可)
@@タスク通知: レビュー完了しました
@@タスク調整: タスクXXXの説明を更新
```

### 正規表現パターン

```swift
// 半角(@)・全角(＠)両対応
let taskCreatePattern = "[@＠][@＠]タスク作成:"
let taskNotifyPattern = "[@＠][@＠]タスク通知:"
let taskAdjustPattern = "[@＠][@＠]タスク調整:"
```

以下の入力はすべてマッチ：

| 入力 | マッチ |
|------|--------|
| `@@タスク作成:` | ✅ |
| `＠＠タスク作成:` | ✅ |
| `@＠タスク作成:` | ✅ |
| `＠@タスク作成:` | ✅ |

---

## 処理フロー

### タスク作成フロー

```
ユーザー: "ログイン機能を作ってください"
    ↓
エージェント: "タスク作成の場合は以下の形式でお送りください:
              @@タスク作成: ログイン機能を実装"
    ↓
ユーザー: "@@タスク作成: ログイン機能を実装"
    ↓
エージェント: request_task(title: "ログイン機能を実装")
    ↓ (バリデーション通過)
エージェント: "タスクを登録しました"
```

### タスク通知フロー

```
ユーザー: "@@タスク通知: 仕様を変更しました。確認してください"
    ↓
エージェント: notify_task_session(message: "仕様を変更しました。確認してください")
    ↓ (バリデーション通過)
エージェント: "タスクセッションに通知しました"
```

### タスク調整フロー

```
ユーザー: "@@タスク調整: タスクXXXの説明を「認証機能の改善」に変更"
    ↓
エージェント: update_task_from_chat(task_id: "XXX", description: "認証機能の改善", ...)
    ↓ (バリデーション通過)
エージェント: "タスクを更新しました"
```

### 通常会話フロー

```
ユーザー: "進捗を教えてください"
    ↓
エージェント: send_message(...) で応答
    ↓
エージェント: "現在の進捗は..."
```

---

## 実装設計

### 1. インストラクション変更

以下の4箇所のインストラクションを変更する：

| 箇所 | ファイル | 行番号 |
|------|----------|--------|
| getNextAction (sync) | MCPServer.swift | 2981-2985 |
| getNextActionAsync | MCPServer.swift | 3121-3127 |
| wait_for_messages | MCPServer.swift | 3173-3174 |
| getPendingMessages | MCPServer.swift | 6217-6219 |

#### 変更前（例: getPendingMessages）

```swift
instruction = """
【重要】メッセージが作業依頼の場合（「〜を実装してください」「〜を追加してください」など）:
1. まず request_task を呼び出してタスクを登録してください
2. その後 send_message で「ご依頼を承りました。タスクを登録し、承認待ちの状態です」と応答してください
...
"""
```

#### 変更後

```swift
instruction = """
【チャットコマンド】
以下のマーカーに応じて適切なツールを使用してください:

■ @@タスク作成: タイトル
  → request_task を呼び出して新規タスクを作成
  例: @@タスク作成: ログイン機能を実装

■ @@タスク通知: メッセージ
  → notify_task_session を呼び出して既存タスクに通知
  例: @@タスク通知: レビュー完了しました

■ @@タスク調整: 内容
  → update_task_from_chat で既存タスク(backlog/todo)の修正・削除
  例: @@タスク調整: タスクXXXの説明を更新

■ マーカーなし
  → send_message で通常の応答

マーカーなしで作業依頼を受けた場合:
「新規タスク作成: @@タスク作成: 、既存タスク通知: @@タスク通知: 、既存タスク調整: @@タスク調整: をつけてお送りください」と案内してください。
...
"""
```

### 2. システムバリデーション

#### request_task バリデーション

`Sources/MCPServer/MCPServer.swift` の `requestTask` 関数に追加：

```swift
// チャットセッションの場合、@@タスク作成マーカーを検証
if session.purpose == .chat {
    let messages = try chatRepository.findMessages(
        projectId: session.projectId,
        agentId: session.agentId
    )
    let incomingMessages = messages.filter { $0.senderId != session.agentId }

    // 最新の受信メッセージに @@タスク作成 マーカーがあるか確認
    let markerPattern = "[@＠][@＠]タスク作成:"
    guard let lastMessage = incomingMessages.last,
          lastMessage.content.range(of: markerPattern, options: .regularExpression) != nil else {
        throw MCPError.taskRequestMarkerRequired
    }
}
```

#### notify_task_session バリデーション

`Sources/MCPServer/MCPServer.swift` の `notifyTaskSession` 関数に追加：

```swift
// チャットセッションの場合、@@タスク通知マーカーを検証
if session.purpose == .chat {
    let messages = try chatRepository.findMessages(
        projectId: session.projectId,
        agentId: session.agentId
    )
    let incomingMessages = messages.filter { $0.senderId != session.agentId }

    // 最新の受信メッセージに @@タスク通知 マーカーがあるか確認
    let markerPattern = "[@＠][@＠]タスク通知:"
    guard let lastMessage = incomingMessages.last,
          lastMessage.content.range(of: markerPattern, options: .regularExpression) != nil else {
        throw MCPError.taskNotifyMarkerRequired
    }
}
```

#### update_task_from_chat バリデーション

`Sources/MCPServer/MCPServer.swift` の `update_task_from_chat` ハンドラに追加：

```swift
// チャットセッションの場合、@@タスク調整マーカーを検証
if session.purpose == .chat {
    let messages = try chatRepository.findMessages(
        projectId: session.projectId,
        agentId: session.agentId
    )
    let incomingMessages = messages.filter { $0.senderId != session.agentId }

    guard let lastMessage = incomingMessages.last,
          lastMessage.content.range(of: "[@＠][@＠]タスク調整:", options: .regularExpression) != nil else {
        throw MCPError.taskAdjustMarkerRequired
    }
}
```

### 3. エラー定義

`MCPError` に追加：

```swift
case taskRequestMarkerRequired
case taskNotifyMarkerRequired
case taskAdjustMarkerRequired

var localizedDescription: String {
    switch self {
    case .taskRequestMarkerRequired:
        return "新規タスク作成には @@タスク作成: マーカーが必要です"
    case .taskNotifyMarkerRequired:
        return "タスク通知には @@タスク通知: マーカーが必要です"
    case .taskAdjustMarkerRequired:
        return "タスク調整には @@タスク調整: マーカーが必要です"
    // ...
    }
}
```

---

## 将来拡張

今回は実装しないが、以下のコマンドも将来追加可能：

| コマンド | 用途 | 備考 |
|----------|------|------|
| `@@タスク確認` | 現在のタスク状況を確認 | 検討中 |
| `@@ブロック報告: 理由` | ブロック状態を報告 | 検討中 |
| `@@完了報告` | タスク完了を報告 | 検討中 |

---

## テスト計画

### ユニットテスト

| テストケース | 期待結果 |
|--------------|----------|
| `@@タスク作成:` マーカーあり + request_task | 成功 |
| マーカーなし + request_task | MCPError.taskRequestMarkerRequired |
| `@@タスク通知:` マーカーあり + notify_task_session | 成功 |
| マーカーなし + notify_task_session | MCPError.taskNotifyMarkerRequired |
| `@@タスク調整:` マーカーあり + update_task_from_chat | 成功 |
| マーカーなし + update_task_from_chat | MCPError.taskAdjustMarkerRequired |
| 全角`＠＠タスク作成:` + request_task | 成功 |
| 混合`@＠タスク作成:` + request_task | 成功 |

### 統合テスト

| シナリオ | 確認内容 |
|----------|----------|
| チャット経由のタスク作成 | マーカーを案内 → マーカー付きで送信 → タスク作成成功 |
| チャット経由のタスク通知 | マーカー付き送信 → 通知成功 |
| チャット経由のタスク調整 | マーカー付き送信 → タスク修正成功 |
| 通常会話 | マーカーなしでも正常に会話継続 |

---

## 関連ドキュメント

- [TASK_REQUEST_APPROVAL.md](./TASK_REQUEST_APPROVAL.md) - タスク依頼・承認機能
- [CHAT_FEATURE.md](./CHAT_FEATURE.md) - チャット機能設計
- [TASK_CHAT_SESSION_SEPARATION.md](./TASK_CHAT_SESSION_SEPARATION.md) - タスク/チャットセッション分離
- [NOTIFICATION_SYSTEM.md](./NOTIFICATION_SYSTEM.md) - 通知システム設計

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-02-08 | 初版作成 |
