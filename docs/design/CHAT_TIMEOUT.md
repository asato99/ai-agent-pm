# チャットタイムアウト機能 設計書

## 概要

チャットメッセージ送信後、エージェントが応答しない場合のタイムアウト処理を定義する。

---

## フロー

### 正常フロー

```
1. ユーザー: チャットでメッセージ送信
   → PMアプリ:
     - chat.jsonl にメッセージ追記
     - pending_agent_purposes に purpose="chat" を記録

2. Runner: get_agent_action をポーリング
   → MCP:
     - action: "start" を返す
     - started_at をセット（重複起動回避）

3. Runner: エージェントを起動

4. エージェント: authenticate
   → MCP:
     - 認証成功
     - pending_agent_purposes を削除
     - セッションに purpose を設定

5. エージェント: チャット応答処理
   → MCP: chat.jsonl に応答を追記

6. PMアプリ: ポーリングで応答を検知 → 画面に表示
```

### タイムアウトフロー（認証失敗のケース）

```
1. ユーザー: チャットでメッセージ送信
   → PMアプリ:
     - chat.jsonl にメッセージ追記
     - pending_agent_purposes に purpose="chat" を記録

2. Runner: get_agent_action をポーリング
   → MCP:
     - action: "start" を返す
     - started_at をセット

3. Runner: エージェントを起動

4. エージェント: authenticate（パスキー間違い等）
   → MCP:
     - 認証失敗 → action: "exit" を返す
     - pending_agent_purposes は残ったまま（started_at はセット済み）

5. エージェント: 終了

6. TTL経過後、Runner: get_agent_action をポーリング
   → MCP:
     - TTL超過を検知
     - pending_agent_purposes を削除
     - chat.jsonl にシステムエラーメッセージを追記
     - action: "hold", reason: "no_pending_work" を返す

7. PMアプリ: ポーリングでエラーメッセージを検知 → 画面に表示
```

---

## データベース

### pending_agent_purposes テーブル

| カラム | 型 | 説明 |
|--------|------|------|
| agent_id | TEXT | エージェントID（PK） |
| project_id | TEXT | プロジェクトID（PK） |
| purpose | TEXT | "task" or "chat" |
| created_at | DATETIME | 作成日時 |
| started_at | DATETIME | 起動開始日時（nullなら未起動） |

### app_settings テーブル

| カラム | 型 | 説明 |
|--------|------|------|
| pending_purpose_ttl_seconds | INTEGER | TTL秒数（デフォルト: 300） |

---

## MCPサーバー処理

### get_agent_action

```
1. pending_agent_purposes を検索

2. pending が存在する場合:
   a. started_at が null（未起動）
      → started_at を更新、start を返す

   b. started_at が存在（起動済み）
      → TTL超過チェック（started_at + TTL < now）
         - 超過: pending を削除、chat にエラー書込
         - 超過しない: 何もしない（認証完了待ち）
      → hold を返す

3. pending がない場合:
   → タスク有無をチェック、適切な action を返す
```

**ポイント**: hold を返す理由は「started_at がセットされているから（起動済み）」であり、タイムアウト処理は hold を返す際の副作用として実行される。

### authenticate

```
1. パスキー検証
   → 失敗: action: "exit" を返す（pending は残る）
   → 成功: 続行

2. pending_agent_purposes を参照 → purpose 取得

3. セッション作成（purpose を含む）

4. pending_agent_purposes を削除

5. 成功レスポンスを返す
```

---

## チャットファイル

### 形式: JSONL

```jsonl
{"id":"msg_01","sender":"user","content":"進捗を教えて","createdAt":"2026-01-11T10:00:00Z"}
{"id":"msg_02","sender":"agent","content":"50%完了です","createdAt":"2026-01-11T10:00:05Z"}
{"id":"sys_03","sender":"system","content":"エージェントの起動がタイムアウトしました...","createdAt":"2026-01-11T10:05:00Z"}
```

### SenderType

| 値 | 説明 |
|------|------|
| user | ユーザーからのメッセージ |
| agent | エージェントからの応答 |
| system | システムメッセージ（エラー等） |

---

## UI表示

### システムメッセージ（ChatMessageRow）

- 中央揃え
- 赤い背景（Color.red.opacity(0.1)）
- 赤い文字色
- 警告アイコン（⚠️）
- "System" ラベル

---

## 設定

### TTL設定（設定画面）

- 場所: Settings → MCP Server
- 選択肢: 1分、2分、5分（デフォルト）、10分、30分
- 保存先: app_settings.pending_purpose_ttl_seconds

---

## テスト

### バックエンド統合テスト（scripts/tests/test_chat_timeout_error.sh）

MCPサーバーとデータベースの動作を検証するbashスクリプト。

検証項目:
1. get_agent_action が action: start を返す
2. パスキー間違いで認証が拒否される
3. 認証失敗時に action: exit が返される
4. TTL経過後、started_atがあるので action: hold を返す
5. チャットファイルにシステムエラーメッセージが書き込まれる
6. pending_agent_purpose が削除される

### UI統合テスト（UITests/USECASE/UC010_ChatTimeoutTests.swift）

Runner統合テストとして、UIからタイムアウトエラーの表示を検証。

シードデータ（UC010シナリオ）:
- プロジェクト: UC010 Timeout Test (prj_uc010)
- エージェント: timeout-test-agent (agt_uc010_timeout)
- 認証情報: なし（認証失敗させるため）
- TTL: 10秒

テストフロー:
1. プロジェクト選択
2. エージェントアバタークリック → チャット画面表示
3. メッセージ送信 → pending_agent_purpose作成
4. TTL経過を待機（10秒 + バッファ）
5. システムエラーメッセージが表示されることを確認

検証項目:
1. チャット画面にシステムエラーメッセージが表示される
2. メッセージに「タイムアウト」が含まれる
