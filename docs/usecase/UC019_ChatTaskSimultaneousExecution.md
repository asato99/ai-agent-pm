# UC019: チャットとタスクの同時実行

## 概要

上位エージェント（owner/manager）がチャットでAIエージェントにタスクを依頼し、タスク実行中も同一エージェントとのチャットで進捗確認を行うフロー。チャットセッションとタスクセッションが同一エージェントで同時に実行できることを検証する。

---

## 前提条件

- 依頼者（owner）がプロジェクトオーナーとして設定されている
- Worker（AIエージェント）が依頼者の下位エージェントとして設定されている
- 依頼者はWorkerの上位者であるため、承認フローは不要

---

## アクター

| アクター | 種別 | 階層 | 役割 |
|----------|------|------|------|
| Owner | human | 最上位 | 依頼者・プロジェクトオーナー |
| Worker-01 | ai | Ownerの部下 | 作業者。タスク実行とチャット応答を同時に行う |

---

## 目的

1. 上位者からの直接タスク依頼が承認なしで実行されることを確認
2. **同一エージェントでChatセッションとTaskセッションが同時に実行できることを確認**
3. タスク実行中のエージェントとチャットで進捗確認ができることを確認

---

## 基本フロー

### Step 1: UIログイン（Owner）

```
Owner → Web UIにログイン
  - プロジェクト一覧からテストプロジェクトを選択
  - タスクボードを開く
```

**アサーション**: タスクボードが表示される

---

### Step 2: チャット開始（Owner → Worker-01）

```
Owner → Worker-01のチャットを開く
  - エージェント一覧からWorker-01を選択
  - チャットアイコンをクリック
    ↓
システム → Worker-01のチャットセッションを起動
  - purpose: chat
  - Coordinatorがエージェントをspawn
```

**アサーション**:
- チャットパネルが開く
- Worker-01のステータスが「起動中」→「オンライン」に変わる

---

### Step 3: タスク依頼メッセージ送信（Owner → Worker-01）

```
Owner → Worker-01へチャットでメッセージ送信
  「テスト用の簡単なタスクを作成してください。タイトルは『テストタスク001』で」
```

**アサーション**: Ownerのメッセージがチャットに表示される

---

### Step 4: タスク作成（Worker-01 → MCP）

```
Worker-01 → MCPツール create_task を実行
  - title: 「テストタスク001」
  - description: 「Ownerからの依頼で作成」
  - status: backlog
  - assignee_id: worker-01（自分自身）
    ↓
システム → タスクを作成
  - 上位者からの依頼のため承認不要
  - approval_status: approved（自動承認）
```

**アサーション**:
- タスクが作成される
- タスクボードのBacklog列にタスクが表示される

---

### Step 5: 応答メッセージ（Worker-01 → Owner）

```
Worker-01 → Ownerへチャットで応答
  「タスク『テストタスク001』を作成しました。Backlogに追加されています」
```

**アサーション**: Worker-01の応答メッセージがチャットに表示される

---

### Step 6: タスクステータス変更（Owner - 手動操作）【重要：同時実行開始】

```
Owner → タスクボードでタスクをドラッグ＆ドロップ
  - Backlog → In Progress へ移動
  - ※この時点でチャットパネルは開いたまま
    ↓
システム → タスクステータスを更新
  - status: in_progress
  - Coordinatorがタスクセッションを開始（既存chatセッションとは別プロセス）
    ↓
状態:
  - Chatセッション: 起動中（維持）
  - Taskセッション: 新規起動
```

**アサーション**:
- タスクがIn Progress列に移動する
- Worker-01がタスク実行を開始する
- **チャットパネルは開いたまま**
- **Worker-01のChatセッションは維持される（終了しない）**
- チャットで引き続きメッセージ送信可能

---

### Step 7: 進捗確認チャット（Owner → Worker-01）【重要：同時実行検証】

```
Owner → Worker-01へチャットでメッセージ送信
  「進捗はどうですか？」
    ↓
Worker-01 → Ownerへチャットで応答
  「現在タスク『テストタスク001』を実行中です。順調に進んでいます」
```

**アサーション**:
- **Chatセッションが生きている**（タスク実行中でも応答できる）
- Worker-01の応答がチャットに表示される
- タスク実行が中断されない

---

### Step 8: タスク完了確認

```
Worker-01 → タスク完了
  - MCPツール update_task_status を実行
  - status: done
    ↓
Owner → タスクボードを確認
  - タスクがDone列に移動している
```

**アサーション**:
- タスクがDone列に表示される
- Chatセッションは引き続き利用可能

---

## シーケンス図

```
Owner           Web UI         Coordinator      Worker-01        MCP Server
  |               |               |               |                  |
  |--ログイン---->|               |               |                  |
  |               |               |               |                  |
  |--チャット開始>|               |               |                  |
  |               |--spawn要求--->|               |                  |
  |               |               |--spawn------->|                  |
  |               |               |  (purpose=    |                  |
  |               |               |   chat)       |                  |
  |               |               |               |--authenticate--->|
  |               |               |               |  (purpose=chat)  |
  |               |               |               |<--session--------|
  |               |<--チャット準備完了------------|                  |
  |               |               |               |                  |
  |--「タスク作成」>              |               |                  |
  |               |--メッセージ-->|               |                  |
  |               |               |-------------->|                  |
  |               |               |               |--create_task---->|
  |               |               |               |<--success--------|
  |               |               |<--------------|                  |
  |               |<--応答「作成しました」---------|                  |
  |               |               |               |                  |
  |--ドラッグ---->|               |               |                  |
  |  (→in_progress)              |               |                  |
  |               |--ステータス-->|               |                  |
  |               |   変更        |--spawn------->|                  |
  |               |               |  (purpose=    |                  |
  |               |               |   task)       |                  |
  |               |               |               |--authenticate--->|
  |               |               |               |  (purpose=task)  |
  |               |               |               |<--session--------|
  |               |               |               |  ※chatと別セッション
  |               |               |               |                  |
  |--「進捗は？」->              |               |                  |
  |               |--メッセージ-->|               |                  |
  |               |               |--chat------->|                  |
  |               |               |  session     |                  |
  |               |               |<--応答--------|                  |
  |               |<--「実行中です」--------------|                  |
  |               |               |               |                  |
  |               |               |  ※同時に     |                  |
  |               |               |  taskセッションも|                |
  |               |               |  実行中       |                  |
```

---

## 技術的検証ポイント

### 同時セッション管理

| 項目 | 期待動作 |
|------|---------|
| PendingAgentPurpose | (agent, project, chat) と (agent, project, task) が同時に存在可能 |
| AgentSession | purpose=chat と purpose=task の2つのセッションが同時にアクティブ |
| endChatSession | chat purposeのセッションのみがterminatingになる |
| getNextAction | 各セッションが独立して正しいアクションを受け取る |

### セッション独立性

```
Worker-01のセッション状態:
├── Chat Session (token: sess_xxx)
│   ├── purpose: chat
│   ├── state: active
│   └── 進捗確認に応答
│
└── Task Session (token: sess_yyy)
    ├── purpose: task
    ├── state: active
    └── タスク実行中
```

---

## 検証ポイントまとめ

| Step | 検証内容 | 同時実行関連 |
|------|---------|-------------|
| 1 | UIログイン成功 | - |
| 2 | チャットセッション起動 | ○ |
| 3 | メッセージ送信成功 | - |
| 4 | タスク作成（承認なし） | - |
| 5 | チャット応答受信 | ○ |
| 6 | **タスク移動時もチャット維持** | ○ **重要：チャット終了しない** |
| 7 | **タスク実行中にチャット応答** | ○ **最重要検証** |
| 8 | タスク完了 | - |

---

## 失敗パターン（修正前の動作）

### 問題: タスクエージェントがchat終了通知を受け取る

```
修正前のフロー:
1. chat pending purpose作成
2. task pending purpose作成
3. task agentが先に認証
4. find(agentId, projectId)がchat purposeを返す ← バグ
5. task sessionがpurpose=chatで作成される
6. ユーザーがchatを閉じる
7. task sessionもterminatingに ← 誤動作
8. task agentが"user_closed_chat"を受け取る
```

### 修正後の期待動作

```
修正後のフロー:
1. chat pending purpose作成 → markAsStarted(T1)
2. task pending purpose作成 → markAsStarted(T2)
3. task agentが認証
4. find()がstarted_at DESC順で最新（task）を返す ← 修正済み
5. task sessionがpurpose=taskで作成される
6. ユーザーがchatを閉じる
7. chat sessionのみterminatingに
8. task agentは影響を受けない ← 正常動作
```

---

## 関連ユースケース

| UC | 関係 |
|----|------|
| UC009: チャットコミュニケーション | チャット基本機能 |
| UC001: タスク実行 | タスク実行フロー |
| UC014: チャットセッション即応答 | チャットセッションの即時応答 |
| UC015: チャットセッション終了 | セッション終了のpurpose分離 |

---

## 関連する技術修正

- `PendingAgentPurpose` 複合主キー変更: `(agent_id, project_id)` → `(agent_id, project_id, purpose)`
- `PendingAgentPurposeRepository.find()` ソート順修正: `started_at DESC, created_at DESC`
- `endChatSession` フィルタリング: `purpose == .chat` のセッションのみ終了

---

## 備考

- 本UCは同一エージェントでのChat/Task同時実行の検証が主目的
- 上位者からの依頼のため承認フローは発生しない
- タスクの内容自体は検証用の簡易なもので良い
