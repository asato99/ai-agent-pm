# UC009: エージェントとのチャット通信

## 概要

ユーザーがエージェントにチャットでメッセージを送信し、エージェントが応答する基本フロー。

---

## 前提条件

- エージェントが1名登録済み
- プロジェクトが存在し、エージェントがアサイン済み
- MCPサーバーがClaude Codeに設定済み
- プロジェクトにworkingDirectoryが設定済み

---

## アクター

| アクター | 種別 | 役割 |
|----------|------|------|
| ユーザー | Human | チャットでメッセージを送信 |
| エージェント | AI | メッセージを受信し応答 |

---

## 基本フロー

### 1. チャット画面を開く（ユーザー）

```
ユーザー → TaskBoardのヘッダーでエージェントアバターをクリック
  ↓
システム → 第3カラムにAgentChatViewを表示
```

### 2. メッセージ送信（ユーザー）

```
ユーザー → メッセージ入力・送信
  - 内容: "あなたの名前を教えてください"
  ↓
システム →
  - chat.jsonl にメッセージを追記
  - pending_agent_purposes に purpose="chat" を記録
```

### 3. エージェント起動（システム/Runner）

```
Runner → get_agent_action(agent_id, project_id) をポーリング
  ↓
MCP → pending_agent_purposes を確認
  - purpose="chat" あり → action: "start" を返す
  ↓
Runner → エージェントを起動
```

### 4. 認証とメッセージ取得（エージェント）

```
エージェント → authenticate(agent_id, passkey, project_id)
  ↓
MCP →
  - セッション作成（purpose="chat"）
  - pending_agent_purposes を削除
  ↓
エージェント → get_next_action()
  ↓
MCP → action: "respond_chat" を返す
  ↓
エージェント → get_pending_messages()
  ↓
MCP → 未読メッセージを返す
  - [{"id": "msg_01", "content": "あなたの名前を教えてください", ...}]
```

### 5. 応答送信（エージェント）

```
エージェント → respond_chat(content="私の名前は{agent_name}です")
  ↓
MCP → chat.jsonl にエージェント応答を追記
```

### 6. 応答表示（ユーザー）

```
PMアプリ → ポーリングで新メッセージ検知
  ↓
PMアプリ → チャット画面に応答を表示
  - "私の名前は{agent_name}です"
```

---

## シーケンス図

```
ユーザー        PMアプリ         MCP           Runner        エージェント
   |               |              |              |               |
   |--チャット開-->|              |              |               |
   |               |              |              |               |
   |--メッセージ-->|              |              |               |
   |  送信         |--ファイル--->|              |               |
   |               |  追記        |              |               |
   |               |--purpose---->|              |               |
   |               |  記録        |              |               |
   |               |              |              |               |
   |               |              |<--polling----|               |
   |               |              |--start------>|               |
   |               |              |              |--起動-------->|
   |               |              |              |               |
   |               |              |<--authenticate---------------|
   |               |              |--session-------------------->|
   |               |              |              |               |
   |               |              |<--get_next_action------------|
   |               |              |--respond_chat--------------->|
   |               |              |              |               |
   |               |              |<--get_pending_messages-------|
   |               |              |--messages------------------->|
   |               |              |              |               |
   |               |              |<--respond_chat---------------|
   |               |              |  (応答内容)  |               |
   |               |              |              |               |
   |               |<--ポーリング-|              |               |
   |<--応答表示----|              |              |               |
   |               |              |              |               |
```

---

## テストシナリオ（統合テスト）

### シナリオ: 名前を聞いて応答を受け取る

**目的**: チャット通信の基本フローが正常に動作することを確認

**テストデータ**:
- プロジェクト: `prj_uc009` (UC009 Chat Test)
- エージェント: `agt_uc009_chat` (chat-responder)
- Working Directory: `/tmp/uc009`

**手順**:
1. PMアプリを起動（UIテスト経由）
2. プロジェクト「UC009 Chat Test」を選択
3. エージェントアバターをクリックしてチャット画面を開く
4. 「あなたの名前を教えてください」と入力・送信
5. エージェントの応答を待機（最大60秒）
6. 応答に「chat-responder」が含まれることを確認

**期待結果**:
- エージェントが「私の名前はchat-responderです」のような応答を返す
- チャット画面に応答が表示される

---

## 検証項目（アサーション）

| # | 検証項目 | 説明 |
|---|----------|------|
| 1 | メッセージ送信 | ユーザーメッセージがchat.jsonlに記録される |
| 2 | エージェント起動 | purpose="chat"でエージェントが起動する |
| 3 | メッセージ取得 | get_pending_messagesでメッセージを取得できる |
| 4 | 応答送信 | respond_chatで応答が記録される |
| 5 | 応答表示 | PMアプリのチャット画面に応答が表示される |

---

## ファイル構成

```
/tmp/uc009/
└── .ai-pm/
    └── agents/
        └── agt_uc009_chat/
            └── chat.jsonl
```

**chat.jsonl（テスト後の期待内容）**:
```jsonl
{"id":"msg_...","sender":"user","content":"あなたの名前を教えてください","createdAt":"..."}
{"id":"msg_...","sender":"agent","content":"私の名前はchat-responderです","createdAt":"..."}
```

---

## 関連エンティティ

| エンティティ | 操作 |
|--------------|------|
| ChatMessage | 作成（ユーザー・エージェント両方） |
| PendingAgentPurpose | 作成・削除（起動理由管理） |
| AgentSession | 作成（purpose="chat"） |

---

## 備考

- チャット通信はファイルベース（.ai-pm/agents/{id}/chat.jsonl）
- 起動理由はDBで管理（pending_agent_purposes）
- エージェントはget_pending_messagesで未読メッセージを取得
- 応答はrespond_chatで送信
- 参照: docs/design/CHAT_FEATURE.md
