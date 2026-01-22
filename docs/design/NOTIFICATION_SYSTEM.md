# 通知システム設計

タスク実行中のエージェントに対する割り込み・通知の仕組み。

## 概要

### 課題

- エージェントがタスク実行中に、ユーザーからのキャンセルやメッセージを受け取る手段がない
- `get_next_action` のポーリング間隔に依存するとリアルタイム性が低い

### 解決策

全MCPツールのレスポンスに `notification` フィールドを追加し、エージェントが任意のツール呼び出し時に通知の存在を検知できるようにする。

---

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────┐
│                    MCPServer                            │
│                                                         │
│  handleToolsCall()                                      │
│       │                                                 │
│       ├── executeTool() → result                        │
│       │                                                 │
│       ├── getNotificationMessage(caller) ← ミドルウェア │
│       │                                                 │
│       └── return { result, notification }               │
└─────────────────────────────────────────────────────────┘
```

---

## レスポンス構造

### notification フィールド

全MCPツールのレスポンスに固定フィールドとして追加。

**通知なし:**
```json
{
  "result": { ... },
  "notification": "通知はありません"
}
```

**通知あり:**
```json
{
  "result": { ... },
  "notification": "通知があります。get_notificationsを呼び出して確認してください。"
}
```

### 設計原則

- **固定フィールド**: `notification` は常に存在
- **自然言語**: エージェントが理解しやすい形式
- **詳細分離**: 通知の存在シグナルのみ、詳細は別ツールで取得

---

## get_notifications ツール

エージェントが通知の詳細を取得するためのツール。

### リクエスト

```json
{
  "session_token": "xxx"
}
```

### レスポンス

```json
{
  "notifications": [
    {
      "type": "...",
      "action": "...",
      "message": "...",
      "instruction": "..."
    }
  ]
}
```

### 通知タイプ（案）

| type | action | 説明 |
|------|--------|------|
| interrupt | cancel | タスクキャンセル要求 |
| interrupt | pause | 一時停止要求 |
| message | - | ユーザーからのメッセージ |

> **TODO**: 具体的な type/action の種類と instruction の文言を確定する

---

## エージェント側の処理フロー

```
1. 任意のMCPツールを呼び出す
2. レスポンスの notification フィールドを確認
3. "通知があります" の場合:
   a. get_notifications を呼び出す
   b. 通知内容に応じて対応（キャンセル、メッセージ確認など）
4. 通常の処理を継続
```

---

## 実装箇所

### MCPServer（ミドルウェア）

- `handleToolsCall()` にて全レスポンスに notification を付加
- `getNotificationMessage(caller)` で通知有無を判定

### 新規ツール

- `get_notifications`: 通知詳細取得

### データモデル（検討中）

通知の格納方法:
- 新規テーブル `notifications`
- または既存の仕組み（chat, event など）を活用

---

## ユースケース

- [UC010: タスク実行中にステータス変更による割り込み](../usecase/UC010_TaskInterruptByStatusChange.md)

---

## 未確定事項

- [ ] 通知タイプの詳細定義（status_change 以外）
- [ ] 通知の格納・既読管理方法
- [ ] 通知の有効期限・クリーンアップ
- [ ] 複数通知が溜まった場合の処理
- [ ] 通知の対象単位（セッション？エージェント+プロジェクト？）

---

## 参照

- MCPServer実装: `Sources/MCPServer/MCPServer.swift`
- handleToolsCall: 264行目付近
