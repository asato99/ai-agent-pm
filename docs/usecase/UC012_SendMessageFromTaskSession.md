# UC012: タスクセッションからのメッセージ送信

## 概要

タスク実行中のAIエージェントが、`send_message`ツールを使用して同一プロジェクト内の他のエージェント（Human含む）にメッセージを送信するフロー。

---

## 前提条件

- プロジェクトが存在し、workingDirectoryが設定済み
- 送信元エージェント（Worker）がプロジェクトにアサイン済み
- 送信先エージェント（Human等）がプロジェクトにアサイン済み
- タスクの説明に`send_message`ツール使用の指示が含まれている
- MCPサーバーが設定済み

---

## アクター

| アクター | 種別 | 役割 |
|----------|------|------|
| ユーザー | Human | タスク作成・ステータス変更・メッセージ確認 |
| Worker | AI | タスク実行中にsend_messageでメッセージ送信 |
| Coordinator | System | エージェント起動制御 |

---

## 基本フロー

### 1. タスク作成（ユーザー）

```
ユーザー → タスク作成
  - タイトル: "メッセージ送信テスト"
  - 説明: send_message使用の指示を含む
  - 担当者: Worker
  - ステータス: todo
```

**タスク説明の例**:
```
以下の手順で作業してください:
1. このタスクを確認
2. send_message ツールで integ-human にメッセージを送信
   - target_agent_id: "integ-human"
   - content: "タスク完了報告です。問題なく処理が完了しました。"
3. report_completed で完了報告
```

### 2. タスク開始（ユーザー）

```
ユーザー → タスクステータスを in_progress に変更
  ↓
システム → Worker起動が必要と判定
```

### 3. Worker起動（Coordinator/Runner）

```
Runner → get_agent_action(agent_id, project_id) をポーリング
  ↓
MCP → action: "start" を返す（in_progressタスクあり）
  ↓
Runner → Workerプロセスを起動（purpose=task）
```

### 4. タスク取得と実行（Worker）

```
Worker → authenticate(agent_id, passkey, project_id)
  ↓
MCP → セッション作成（purpose=task）
  ↓
Worker → get_my_task()
  ↓
MCP → タスク詳細を返す（send_message使用指示を含む）
  ↓
Worker → タスク内容を解析し、send_messageを呼び出す
```

### 5. メッセージ送信（Worker）

```
Worker → send_message(
    session_token: "...",
    target_agent_id: "integ-human",
    content: "タスク完了報告です。問題なく処理が完了しました。"
)
  ↓
MCP →
  1. セッション検証（purpose=taskでもOK）
  2. 送信先がプロジェクト内か確認
  3. 自分自身への送信でないか確認
  4. ChatMessage作成
  5. saveMessageDualWrite()で双方向保存
  ↓
MCP → 成功レスポンス返却
  - { "success": true, "message_id": "msg_...", "target_agent_id": "integ-human" }
```

### 6. タスク完了報告（Worker）

```
Worker → report_completed(
    session_token: "...",
    result: "success",
    summary: "メッセージ送信完了"
)
  ↓
MCP → タスクステータスを done に更新
```

### 7. メッセージ確認（ユーザー）

```
ユーザー → Web UIでプロジェクトを開く
  ↓
Web UI → エージェント一覧で未読インジケータ表示
  - integ-human に未読メッセージあり
  ↓
ユーザー → エージェントをクリックしてチャットパネルを開く
  ↓
Web UI → メッセージ一覧を表示
  - "タスク完了報告です。問題なく処理が完了しました。"
```

---

## シーケンス図

```
ユーザー     Web UI        MCP          Runner       Worker
   |           |            |             |            |
   |--タスク-->|            |             |            |
   |  作成     |--DB保存--->|             |            |
   |           |            |             |            |
   |--ステータス変更------->|             |            |
   |  (in_progress)        |             |            |
   |           |            |             |            |
   |           |            |<--polling---|            |
   |           |            |--start----->|            |
   |           |            |             |--起動----->|
   |           |            |             |            |
   |           |            |<--authenticate-----------|
   |           |            |--session---------------->|
   |           |            |             |            |
   |           |            |<--get_my_task------------|
   |           |            |--task detail------------>|
   |           |            |             |            |
   |           |            |<--send_message-----------|
   |           |            |  (to: integ-human)       |
   |           |            |--dualWrite-------------->|
   |           |            |  (両者のファイルに保存)   |
   |           |            |--success---------------->|
   |           |            |             |            |
   |           |            |<--report_completed-------|
   |           |            |--done------------------->|
   |           |            |             |            |
   |--チャット確認--------->|             |            |
   |           |<--未読表示-|             |            |
   |<--メッセージ表示-------|             |            |
   |           |            |             |            |
```

---

## テストシナリオ（統合テスト）

### シナリオ: タスク実行中にメッセージを送信

**目的**: タスクセッションからsend_messageでメッセージを送信し、Web UIで確認できることを検証

**テストデータ**:
- プロジェクト: `prj_uc012` (UC012 SendMessage Test)
- 送信元: `agt_uc012_worker` (Worker, AI)
- 送信先: `agt_uc012_human` (Human)
- タスク: send_message使用指示を含むタスク
- Working Directory: `/tmp/uc012`

**シードデータ**:
```sql
-- プロジェクト
INSERT INTO projects (id, name, working_directory, ...)
VALUES ('prj_uc012', 'UC012 SendMessage Test', '/tmp/uc012', ...);

-- 送信先エージェント（Human）
INSERT INTO agents (id, name, agent_type, ...)
VALUES ('agt_uc012_human', 'Test Human', 'human', ...);

-- 送信元エージェント（Worker）
INSERT INTO agents (id, name, agent_type, system_prompt, ...)
VALUES (
  'agt_uc012_worker',
  'Message Sender Worker',
  'worker',
  'タスクの指示に従ってsend_messageを使用してください。',
  ...
);

-- プロジェクトへのアサイン
INSERT INTO project_agent_assignments (project_id, agent_id)
VALUES ('prj_uc012', 'agt_uc012_human');
INSERT INTO project_agent_assignments (project_id, agent_id)
VALUES ('prj_uc012', 'agt_uc012_worker');

-- タスク
INSERT INTO tasks (id, project_id, title, description, status, assignee_id, ...)
VALUES (
  'task_uc012_send',
  'prj_uc012',
  'メッセージ送信テスト',
  '以下の手順で作業してください:
1. このタスクを確認
2. send_message ツールで agt_uc012_human にメッセージを送信
   - target_agent_id: "agt_uc012_human"
   - content: "タスク実行中からの報告です。"
3. report_completed で完了報告',
  'todo',
  'agt_uc012_worker',
  ...
);
```

**手順**:
1. Web UIを起動
2. プロジェクト「UC012 SendMessage Test」を選択
3. タスク「メッセージ送信テスト」を選択
4. ステータスを「In Progress」に変更（Worker起動トリガー）
5. Worker完了を待機（最大60秒）
6. タスクステータスが「Done」になることを確認
7. エージェント一覧で`agt_uc012_human`に未読インジケータが表示されることを確認
8. `agt_uc012_human`のチャットパネルを開く
9. 「タスク実行中からの報告です。」メッセージが表示されることを確認

**期待結果**:
- タスクが正常に完了（Done）
- 送信先エージェントのチャットファイルにメッセージが保存される
- Web UIで未読インジケータが表示される
- チャットパネルでメッセージが確認できる

---

## 検証項目（アサーション）

| # | 検証項目 | 説明 |
|---|----------|------|
| 1 | タスク完了 | タスクステータスがdoneになる |
| 2 | メッセージ保存（送信者） | Worker側のchat.jsonlにreceiverIdあり |
| 3 | メッセージ保存（受信者） | Human側のchat.jsonlにreceiverIdなし |
| 4 | 未読インジケータ | Web UIでHumanエージェントに未読表示 |
| 5 | メッセージ表示 | チャットパネルでメッセージが確認可能 |

---

## ファイル構成

```
/tmp/uc012/
└── .ai-pm/
    └── agents/
        ├── agt_uc012_worker/
        │   └── chat.jsonl      # 送信者ファイル（receiverId含む）
        └── agt_uc012_human/
            └── chat.jsonl      # 受信者ファイル（receiverId含まず）
```

**chat.jsonl（送信者: agt_uc012_worker）**:
```jsonl
{"id":"msg_...","senderId":"agt_uc012_worker","receiverId":"agt_uc012_human","content":"タスク実行中からの報告です。","createdAt":"..."}
```

**chat.jsonl（受信者: agt_uc012_human）**:
```jsonl
{"id":"msg_...","senderId":"agt_uc012_worker","content":"タスク実行中からの報告です。","createdAt":"..."}
```

---

## 関連エンティティ

| エンティティ | 操作 |
|--------------|------|
| Task | 読取・更新（ステータス変更） |
| ChatMessage | 作成（双方向保存） |
| AgentSession | 作成（purpose=task） |

---

## エラーケース

| エラー | 条件 | 期待動作 |
|--------|------|----------|
| プロジェクト外への送信 | target_agent_idがプロジェクト外 | 403 Forbidden |
| 自分自身への送信 | target_agent_id = 送信者ID | 400 Bad Request |
| 存在しないエージェント | target_agent_idが未登録 | 404 Not Found |
| コンテンツ長超過 | content > 4,000文字 | 400 Bad Request |

---

## UC009との違い

| 観点 | UC009（チャット通信） | UC012（タスクからのメッセージ） |
|------|----------------------|-------------------------------|
| セッション種別 | purpose=chat | purpose=task |
| 起動トリガー | チャットメッセージ受信 | タスクステータス変更 |
| 送信ツール | respond_chat | send_message |
| 応答期待 | あり（双方向会話） | なし（一方向通知） |
| 使用ケース | 対話・質問応答 | 進捗報告・通知 |

---

## 関連ドキュメント

- [docs/design/SEND_MESSAGE_FROM_TASK_SESSION.md](../design/SEND_MESSAGE_FROM_TASK_SESSION.md) - 機能設計書
- [docs/design/CHAT_FEATURE.md](../design/CHAT_FEATURE.md) - チャット機能全体設計
- [docs/usecase/UC009_ChatCommunication.md](UC009_ChatCommunication.md) - チャット通信UC

---

## 備考

- `send_message`は`.authenticated`権限のため、タスク・チャット両方のセッションで使用可能
- 応答を受け取るには別途チャットセッションが必要（`get_pending_messages`は`.chatOnly`）
- 通知システム連携は将来実装予定
