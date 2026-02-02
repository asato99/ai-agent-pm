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

## 根本原因（調査結果: 2026-02-02）

### 確認事項

1. **AgentSessionのタイムアウト値**: 1時間（3600秒）
   - `Sources/Domain/Entities/AgentSession.swift:30`: `defaultExpirationInterval = 3600`
   - これは十分長いので、セッションの有効期限切れが原因ではない

2. **ツール呼び出し時のセッション延長**: `lastActivityAt`のみ更新
   - `Sources/MCPServer/MCPServer.swift:5680`: `updateLastActivity(token:)` が呼ばれる
   - しかし`expiresAt`は延長されない（将来的にアイドルタイムアウト用として検討可能）

### 真の原因

**Claude Codeプロセスの予期しない終了**

1. Claude Codeプロセスが約5分で終了する
2. Coordinatorがプロセス終了を検出
3. `invalidate_session` APIが呼ばれ、セッションが**削除**される
4. 以降のツール呼び出しで「Invalid session_token」エラー

**なぜ「Invalid session_token」か？**
- セッションが**期限切れ**ではなく**削除済み**のため
- `findByToken`がnilを返し、`sessionTokenInvalid`エラーになる

### Claude Code終了の推測原因

1. **コンテキスト制限**: 大量のポーリング応答でコンテキストウィンドウが枯渇
2. **内部アイドルタイムアウト**: Claude Codeに5分程度の内部タイムアウトがある可能性
3. **max-turns制限**: --max-turns 50 が何らかの理由で早期に到達

## 関連ファイル

- `Sources/Domain/Entities/AgentSession.swift:30` - defaultExpirationInterval = 3600秒（1時間）
- `Sources/MCPServer/MCPServer.swift:5680` - lastActivityAt更新（expiresAtは延長しない）
- `Sources/MCPServer/MCPServer.swift:5309-5334` - invalidateSession（セッション削除）
- `runner/src/aiagent_runner/coordinator.py:268-289` - プロセス終了時のセッション無効化

## 調査項目

1. [x] AgentSessionのタイムアウト値を確認 → **1時間（問題なし）**
2. [x] ツール呼び出し時にセッション有効期限が延長されるか確認 → **延長されない（lastActivityAtのみ更新）**
3. [ ] Claude Code終了の原因を特定
   - [ ] コンテキスト使用量のログ追加
   - [ ] Claude Code内部のアイドルタイムアウト設定確認
4. [ ] 対策検討
   - [ ] ポーリング応答のトークン削減（コンテキスト節約）
   - [ ] セッション再開メカニズム（同じタスクを継続）
   - [ ] または、タスクセッションの expiresAt をツール呼び出しごとに延長

## 暫定対策

- `get_task_conversations`で親タスクの会話も検索するよう修正済み（2026-02-02）
  - これにより再認証後も会話が見える

## 参照

- docs/design/TASK_CONVERSATION_AWAIT.md
- UC020テスト: web-ui/e2e/integration/run-uc020-test.sh
