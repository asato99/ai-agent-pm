# UC014: チャットセッション即時応答

## 概要

チャットパネルを開いた時点でエージェントを起動・待機状態にし、ユーザーがメッセージを送信したら即座に応答を受け取る。

従来のUC009では、各メッセージごとにエージェントプロセスの起動・終了が発生し、応答まで数十秒〜1分以上かかっていた。本ユースケースでは、セッション維持により5秒以内の応答を実現する。

---

## 前提条件

- エージェントが1名登録済み
- プロジェクトが存在し、エージェントがアサイン済み
- MCPサーバーがClaude Codeに設定済み
- プロジェクトにworkingDirectoryが設定済み
- Coordinatorが稼働している

---

## アクター

| アクター | 種別 | 役割 |
|----------|------|------|
| ユーザー | Human | チャットパネルを開き、メッセージを送信 |
| エージェント | AI | 待機状態から即座にメッセージに応答 |
| Coordinator | System | エージェントプロセスの起動・監視 |

---

## 基本フロー

### 1. チャットパネルを開く（ユーザー）

```
ユーザー → TaskBoardのヘッダーでエージェントアバターをクリック
  ↓
システム → 第3カラムにチャットパネルを表示
  ↓
Web UI → POST /projects/{projectId}/chat/start を呼び出し
```

### 2. セッション開始（システム）

```
REST Server →
  - システムメッセージをchat.jsonlに書き込み（visible: false）
  - PendingAgentPurpose作成（purpose="chat"）
  ↓
Coordinator → PendingAgentPurposeを検知
  ↓
Coordinator → エージェントプロセスを起動
```

### 3. エージェント待機状態（エージェント）

```
エージェント → authenticate(agent_id, passkey, project_id)
  ↓
MCP → セッション作成（purpose="chat"）、PendingAgentPurpose削除
  ↓
エージェント → get_next_action()
  ↓
MCP → action: "wait_for_messages" を返す
  - instruction: "5秒後に再度get_next_actionを呼び出してください"
  - wait_seconds: 5
  ↓
エージェント → 5秒待機 → get_next_action() → (ループ)
```

### 4. 送信ボタン有効化（ユーザー）

```
Web UI → GET /projects/{projectId}/agent-sessions をポーリング
  ↓
Web UI → agentSessions[agentId].chat > 0 を検知
  ↓
Web UI → 送信ボタンを「準備中...」から「送信」に変更
```

### 5. メッセージ送信（ユーザー）

```
ユーザー → メッセージ入力・送信
  - 内容: "タスクの進捗を教えてください"
  ↓
Web UI → POST /projects/{projectId}/agents/{agentId}/chat/messages
  ↓
REST Server → chat.jsonl にメッセージを追記
```

### 6. 即時応答（エージェント）

```
エージェント → get_next_action()（ポーリング中）
  ↓
MCP → 未読メッセージを検知
  ↓
MCP → action: "get_pending_messages" を返す
  ↓
エージェント → get_pending_messages()
  ↓
MCP → 未読メッセージを返す
  ↓
エージェント → respond_chat(content="...")
  ↓
MCP → chat.jsonl にエージェント応答を追記、lastActivityAt更新
  ↓
エージェント → get_next_action() → "wait_for_messages" → (ループ継続)
```

### 7. 応答表示（ユーザー）

```
Web UI → ポーリングで新メッセージ検知
  ↓
Web UI → チャットパネルに応答を表示
```

---

## シーケンス図

```
ユーザー      Web UI       REST Server    Coordinator    エージェント      MCP
   |            |              |              |              |              |
   |--パネル--->|              |              |              |              |
   |  を開く    |--POST------->|              |              |              |
   |            |  /chat/start |--purpose---->|              |              |
   |            |              |  記録        |              |              |
   |            |              |              |--起動------->|              |
   |            |              |              |              |--auth------->|
   |            |              |              |              |<--session----|
   |            |              |              |              |              |
   |            |              |              |              |--get_next--->|
   |            |              |              |              |<--wait-------|
   |            |              |              |              |   (5s loop)  |
   |            |              |              |              |              |
   |            |<--sessions---|              |              |              |
   |<--ボタン---|  (chat: 1)   |              |              |              |
   |  有効化    |              |              |              |              |
   |            |              |              |              |              |
   |--メッセージ送信---------->|              |              |              |
   |            |              |--file------->|              |              |
   |            |              |  追記        |              |              |
   |            |              |              |              |--get_next--->|
   |            |              |              |              |<--respond----|
   |            |              |              |              |--get_msgs--->|
   |            |              |              |              |<--messages---|
   |            |              |              |              |--respond---->|
   |            |              |              |              |  chat        |
   |            |<--ポーリング-|              |              |              |
   |<--応答-----|              |              |              |              |
   |  表示      |              |              |              |              |
```

---

## テストシナリオ（統合テスト）

### シナリオ: チャットパネルを開いてメッセージを送信すると5秒以内に応答が返る

**目的**: セッション維持による即時応答が実現されていることを確認

**テストデータ**:
- プロジェクト: `prj_uc014` (UC014 Chat Session Test)
- エージェント: `agt_uc014_chat` (session-responder)
- Working Directory: `/tmp/uc014`

**手順**:
1. PMアプリを起動
2. プロジェクト「UC014 Chat Session Test」を選択
3. エージェントアバターをクリックしてチャットパネルを開く
4. 送信ボタンが「送信」になるまで待機（セッション準備完了）
5. 「タスクの進捗を教えてください」と入力
6. 送信ボタンをクリック（タイマー開始）
7. エージェントの応答が表示される（タイマー終了）
8. 応答時間を計測

**成功基準**:
- 応答時間が **5秒以内** であること
- チャットパネルに応答メッセージが表示されること

---

## 検証項目（アサーション）

| # | 検証項目 | 説明 |
|---|----------|------|
| 1 | セッション開始 | チャットパネルを開くとPendingAgentPurposeが作成される |
| 2 | エージェント待機 | エージェントがwait_for_messagesループに入る |
| 3 | ボタン有効化 | agent-sessionsでchat > 0になると送信ボタンが有効になる |
| 4 | メッセージ送信 | ユーザーメッセージがchat.jsonlに記録される |
| 5 | 即時応答 | エージェントが5秒以内に応答を返す |
| 6 | 応答表示 | チャットパネルに応答が表示される |

---

## 成功基準

| 指標 | 目標値 | 従来値（UC009） |
|------|--------|-----------------|
| メッセージ応答時間 | 5秒以内 | 30秒〜60秒以上 |

---

## ファイル構成

```
/tmp/uc014/
└── .ai-pm/
    └── agents/
        └── agt_uc014_chat/
            └── chat.jsonl
```

**chat.jsonl（テスト後の期待内容）**:
```jsonl
{"id":"msg_...","senderId":"system","content":"セッション開始","createdAt":"...","visible":false}
{"id":"msg_...","senderId":"user","content":"タスクの進捗を教えてください","createdAt":"...","visible":true}
{"id":"msg_...","senderId":"agt_uc014_chat","content":"...","createdAt":"...","visible":true}
```

---

## 関連エンティティ

| エンティティ | 操作 |
|--------------|------|
| ChatMessage | 作成（システム・ユーザー・エージェント） |
| PendingAgentPurpose | 作成・削除（セッション開始トリガー） |
| AgentSession | 作成・更新（purpose="chat"、lastActivityAt更新） |

---

## 関連設計書

- docs/design/CHAT_SESSION_MAINTENANCE_MODE.md

---

## 備考

- UC009との違いは、エージェントが待機状態を維持する点
- セッションは10分間非アクティブでタイムアウト（logout）
- visible: false のメッセージはエージェントに渡されない（セッション開始トリガー用）
