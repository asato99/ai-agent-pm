# UC013: Worker間メッセージ連携

## 概要

Worker-Aがタスク完了後、`send_message`でWorker-Bに報告。Worker-Bはチャットセッションでメッセージを受信し、人間にチャットで報告する連携フロー。

---

## 前提条件

- プロジェクトが存在し、workingDirectoryが設定済み
- Worker-A、Worker-B、Humanの3エージェントがプロジェクトにアサイン済み
- Worker-Aのタスクに`send_message`使用の指示が含まれている
- Worker-Bのシステムプロンプトに「受信メッセージを人間に報告する」指示が含まれている
- MCPサーバーが設定済み

---

## アクター

| アクター | 種別 | セッション | 役割 |
|----------|------|------------|------|
| Worker-A | AI | task | 作業実行、完了報告をWorker-Bに送信 |
| Worker-B | AI | chat | Worker-Aからのメッセージを受信し、人間に報告 |
| ユーザー | Human | - | 最終的にWorker-Bから報告を受ける |
| Coordinator | System | - | エージェント起動制御 |

---

## 基本フロー

### 1. タスク作成（ユーザー）

```
ユーザー → Worker-A用タスク作成
  - タイトル: "データ処理タスク"
  - 説明: send_message使用の指示を含む
  - 担当者: Worker-A
  - ステータス: todo
```

**タスク説明の例**:
```
以下の手順で作業してください:
1. データ処理を実行
2. send_message ツールで worker-b に結果を報告
   - target_agent_id: "worker-b"
   - content: "データ処理が完了しました。処理件数: 100件"
3. report_completed で完了報告
```

### 2. タスク開始（ユーザー）

```
ユーザー → タスクステータスを in_progress に変更
  ↓
システム → Worker-A起動が必要と判定
```

### 3. Worker-A起動・タスク実行（タスクセッション）

```
Runner → Worker-Aプロセス起動（purpose=task）
  ↓
Worker-A → authenticate → get_my_task
  ↓
Worker-A → タスク実行（データ処理等）
```

### 4. Worker-Aからメッセージ送信

```
Worker-A → send_message(
    target_agent_id: "worker-b",
    content: "データ処理が完了しました。処理件数: 100件"
)
  ↓
MCP → saveMessageDualWrite()
  - Worker-Aのchat.jsonl（receiverId: worker-b）
  - Worker-Bのchat.jsonl（receiverIdなし）
```

### 5. Worker-Aタスク完了

```
Worker-A → report_completed(result: "success")
  ↓
MCP → タスクステータスを done に更新
```

### 6. Worker-B起動（チャットセッション）

```
システム → Worker-B宛メッセージあり検知
  ↓
Runner → get_agent_action(worker-b, project_id)
  ↓
MCP → action: "start"（pending message あり）
  ↓
Runner → Worker-Bプロセス起動（purpose=chat）
```

### 7. Worker-Bメッセージ取得・人間へ報告

```
Worker-B → authenticate（purpose=chat）
  ↓
Worker-B → get_next_action()
  ↓
MCP → action: "respond_chat"
  ↓
Worker-B → get_pending_messages()
  ↓
MCP → Worker-Aからのメッセージを返す
  - [{"senderId": "worker-a", "content": "データ処理が完了しました..."}]
  ↓
Worker-B → respond_chat(
    content: "Worker-Aからの報告: データ処理が完了しました。処理件数: 100件"
)
  ↓
MCP → saveMessageDualWrite()
  - Worker-Bのchat.jsonl（receiverId: human）
  - Humanのchat.jsonl（receiverIdなし）
```

### 8. ユーザーがメッセージ確認

```
ユーザー → Web UIでプロジェクトを開く
  ↓
Web UI → Humanエージェントに未読インジケータ表示
  ↓
ユーザー → チャットパネルを開く
  ↓
Web UI → Worker-Bからのメッセージ表示
  - "Worker-Aからの報告: データ処理が完了しました。処理件数: 100件"
```

---

## シーケンス図

```
ユーザー   Worker-A(task)   MCP/Files   Worker-B(chat)   Human(WebUI)
   |            |              |              |              |
   |--タスク--->|              |              |              |
   |  作成      |              |              |              |
   |--in_progress------------>|              |              |
   |            |              |              |              |
   |            |<--起動(task)-|              |              |
   |            |              |              |              |
   |            |--タスク実行->|              |              |
   |            |              |              |              |
   |            |--send_message|              |              |
   |            |  (to: B)    -|->save------->|              |
   |            |              |  B's chat.jsonl             |
   |            |              |              |              |
   |            |--report_done>|              |              |
   |            |              |              |              |
   |            |              |--起動(chat)->|              |
   |            |              |              |              |
   |            |              |<-get_pending-|              |
   |            |              |--A's msg---->|              |
   |            |              |              |              |
   |            |              |<-respond_chat|              |
   |            |              |  (to: Human) |              |
   |            |              |--save------->|              |
   |            |              |  Human's chat.jsonl         |
   |            |              |              |              |
   |            |              |              |<--確認-------|
   |            |              |              |--メッセージ->|
   |            |              |              |              |
```

---

## テストシナリオ（統合テスト）

### シナリオ: タスク完了報告のリレー

**目的**: Worker-A(task) → Worker-B(chat) → Human のメッセージリレーが正常動作することを検証

**テストデータ**:
- プロジェクト: `prj_uc013` (UC013 Message Relay Test)
- Worker-A: `agt_uc013_worker_a` (タスク実行、メッセージ送信)
- Worker-B: `agt_uc013_worker_b` (メッセージ中継、人間に報告)
- Human: `agt_uc013_human` (最終受信者)
- Working Directory: `/tmp/uc013`

**シードデータ**:
```sql
-- プロジェクト
INSERT INTO projects (id, name, working_directory, ...)
VALUES ('prj_uc013', 'UC013 Message Relay Test', '/tmp/uc013', ...);

-- Human
INSERT INTO agents (id, name, agent_type, ...)
VALUES ('agt_uc013_human', 'Test Human', 'human', ...);

-- Worker-A（メッセージ送信元）
INSERT INTO agents (id, name, agent_type, system_prompt, ...)
VALUES (
  'agt_uc013_worker_a',
  'Task Worker A',
  'worker',
  'タスクの指示に従って作業し、send_messageで報告してください。',
  ...
);

-- Worker-B（メッセージ中継）
INSERT INTO agents (id, name, agent_type, system_prompt, ...)
VALUES (
  'agt_uc013_worker_b',
  'Relay Worker B',
  'worker',
  '他のエージェントからメッセージを受け取ったら、その内容を人間(agt_uc013_human)にrespond_chatで報告してください。',
  ...
);

-- プロジェクトへのアサイン
INSERT INTO project_agent_assignments (project_id, agent_id)
VALUES
  ('prj_uc013', 'agt_uc013_human'),
  ('prj_uc013', 'agt_uc013_worker_a'),
  ('prj_uc013', 'agt_uc013_worker_b');

-- タスク（Worker-A用）
INSERT INTO tasks (id, project_id, title, description, status, assignee_id, ...)
VALUES (
  'task_uc013_process',
  'prj_uc013',
  'データ処理タスク',
  '以下の手順で作業してください:
1. データ処理を実行（シミュレーション）
2. send_message ツールで agt_uc013_worker_b に結果を報告
   - target_agent_id: "agt_uc013_worker_b"
   - content: "データ処理完了。処理件数: 100件"
3. report_completed で完了報告',
  'todo',
  'agt_uc013_worker_a',
  ...
);
```

**手順**:
1. Web UIを起動
2. プロジェクト「UC013 Message Relay Test」を選択
3. タスク「データ処理タスク」を選択
4. ステータスを「In Progress」に変更（Worker-A起動）
5. Worker-A完了を待機（最大60秒）
6. タスクステータスが「Done」になることを確認
7. Worker-B起動・完了を待機（最大60秒）
8. Humanエージェントに未読インジケータが表示されることを確認
9. Humanのチャットパネルを開く
10. Worker-Bからの報告メッセージが表示されることを確認

**期待結果**:
- Worker-Aのタスクが正常に完了
- Worker-BがWorker-Aからのメッセージを受信
- Worker-Bが人間にメッセージを転送
- Web UIで人間がWorker-Bからの報告を確認可能

---

## 検証項目（アサーション）

| # | 検証項目 | 説明 |
|---|----------|------|
| 1 | Worker-Aタスク完了 | タスクステータスがdoneになる |
| 2 | A→Bメッセージ保存 | Worker-Bのchat.jsonlにWorker-Aからのメッセージ |
| 3 | Worker-B起動 | purpose=chatでWorker-Bが起動 |
| 4 | B→Humanメッセージ保存 | Humanのchat.jsonlにWorker-Bからのメッセージ |
| 5 | 未読インジケータ | Web UIでHumanに未読表示 |
| 6 | メッセージ内容 | Worker-Aの報告内容がHumanまで伝達される |

---

## ファイル構成

```
/tmp/uc013/
└── .ai-pm/
    └── agents/
        ├── agt_uc013_worker_a/
        │   └── chat.jsonl      # A→Bメッセージ（receiverId: worker_b）
        ├── agt_uc013_worker_b/
        │   └── chat.jsonl      # A→Bメッセージ + B→Humanメッセージ
        └── agt_uc013_human/
            └── chat.jsonl      # B→Humanメッセージ
```

**Worker-Aのchat.jsonl**:
```jsonl
{"id":"msg_01","senderId":"agt_uc013_worker_a","receiverId":"agt_uc013_worker_b","content":"データ処理完了。処理件数: 100件","createdAt":"..."}
```

**Worker-Bのchat.jsonl**:
```jsonl
{"id":"msg_01","senderId":"agt_uc013_worker_a","content":"データ処理完了。処理件数: 100件","createdAt":"..."}
{"id":"msg_02","senderId":"agt_uc013_worker_b","receiverId":"agt_uc013_human","content":"Worker-Aからの報告: データ処理完了。処理件数: 100件","createdAt":"..."}
```

**Humanのchat.jsonl**:
```jsonl
{"id":"msg_02","senderId":"agt_uc013_worker_b","content":"Worker-Aからの報告: データ処理完了。処理件数: 100件","createdAt":"..."}
```

---

## 関連エンティティ

| エンティティ | 操作 |
|--------------|------|
| Task | 読取・更新（ステータス変更） |
| ChatMessage | 作成（3回: A→B, B→Human） |
| AgentSession | 作成（Worker-A: task, Worker-B: chat） |
| PendingAgentPurpose | Worker-B起動トリガー |

---

## UC012との違い

| 観点 | UC012 | UC013 |
|------|-------|-------|
| 送信先 | AI → Human | AI → AI → Human |
| セッション | task のみ | task + chat |
| メッセージ数 | 1通 | 2通（リレー） |
| 使用ツール | send_message | send_message + respond_chat |
| 用途 | 直接報告 | 中継・集約報告 |

---

## 関連ドキュメント

- [docs/design/SEND_MESSAGE_FROM_TASK_SESSION.md](../design/SEND_MESSAGE_FROM_TASK_SESSION.md) - send_message設計書
- [docs/design/CHAT_FEATURE.md](../design/CHAT_FEATURE.md) - チャット機能全体設計
- [docs/usecase/UC009_ChatCommunication.md](UC009_ChatCommunication.md) - チャット通信UC
- [docs/usecase/UC012_SendMessageFromTaskSession.md](UC012_SendMessageFromTaskSession.md) - タスクからのメッセージ送信UC

---

## 備考

- Worker-Bの起動トリガーは「未読メッセージあり」による自動起動
- Worker-Bはチャットセッション（purpose=chat）で起動されるため`get_pending_messages`と`respond_chat`が使用可能
- このパターンは「監視エージェント」「集約報告エージェント」などに応用可能
