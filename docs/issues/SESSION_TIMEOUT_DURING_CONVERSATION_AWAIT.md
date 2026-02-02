# Issue: Session Timeout During Conversation Await

## Status: OPEN - 調査対象

## 発見日: 2026-02-02

## 概要

タスクセッション中にAI-to-AI会話の完了を待機している間、セッションがタイムアウトする問題。

## 現象

UC020テストで観察された挙動:

1. Worker-Aが`delegate_to_chat_session`で会話を委譲
2. Worker-Aが`get_task_conversations`で定期的にポーリング（約30秒間隔）
3. 約4分後（20:53:40 → 20:58:51）にセッションタイムアウト
4. 再認証後、別のタスク（サブタスク）のセッションが作成される
5. 元の会話が見えなくなる（別途修正済み）

## ログ証跡

```
2026-02-02 20:53:40 [authenticate] Worker-A認証 → task_id: uc020-task-shiritori
2026-02-02 20:54:54 - 20:57:56 [get_task_conversations] 定期的にポーリング（active: 1）
2026-02-02 20:58:51 [ERROR] Invalid session_token. Please re-authenticate.
2026-02-02 20:59:00 [authenticate] Worker-A再認証 → task_id: tsk_346a58c7-f9a（サブタスク）
```

## 根本原因（推測）

- AgentSessionのデフォルトタイムアウト（5分程度？）が会話待機には短すぎる
- または、タスクセッション中の活動（get_task_conversationsの呼び出し）がセッション延長として認識されていない

## 関連ファイル

- `Sources/Domain/Entities/AgentSession.swift` - セッションタイムアウト設定
- `Sources/UseCase/AuthenticationUseCases.swift` - セッション作成ロジック
- `Sources/MCPServer/MCPServer.swift` - ツール呼び出し時のセッション検証

## 調査項目

1. [ ] AgentSessionのタイムアウト値を確認
2. [ ] ツール呼び出し時にセッション有効期限が延長されるか確認
3. [ ] タスクセッションのタイムアウトを延長すべきか検討
4. [ ] セッション延長メカニズムの実装を検討

## 暫定対策

- `get_task_conversations`で親タスクの会話も検索するよう修正済み（2026-02-02）
  - これにより再認証後も会話が見える

## 参照

- docs/design/TASK_CONVERSATION_AWAIT.md
- UC020テスト: web-ui/e2e/integration/run-uc020-test.sh
