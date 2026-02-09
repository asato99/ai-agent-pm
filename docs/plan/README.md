# 実装プラン

AI Agent Project Managerの実装計画ドキュメント。

---

## 現在進行中

| 計画 | 概要 | ドキュメント |
|------|------|-------------|
| 大規模リファクタリング | God Object 分割・構造改善（6フェーズ） | [REFACTORING_PLAN.md](./REFACTORING_PLAN.md) |

---

## アーカイブ

過去の実装計画は `archive/` ディレクトリに移動しました。

### 完了済み計画

| 計画 | 概要 | ドキュメント |
|------|------|-------------|
| 未読メッセージ判定リファクタリング | 未読判定を「返信ベース」から「既読時刻ベース」に変更 | [UNREAD_MESSAGE_REFACTOR_TDD.md](./UNREAD_MESSAGE_REFACTOR_TDD.md) |
| Phase 1: MCP連携検証 | MCPサーバーの基本動作確認 | [archive/PHASE1_MCP_VERIFICATION.md](./archive/PHASE1_MCP_VERIFICATION.md) |
| Phase 2: フル実装 | MacアプリとMCP機能の完全実装 | [archive/PHASE2_FULL_IMPLEMENTATION.md](./archive/PHASE2_FULL_IMPLEMENTATION.md) |
| Phase 3: プル型アーキテクチャ | Runner連携と認証基盤 | [archive/PHASE3_PULL_ARCHITECTURE.md](./archive/PHASE3_PULL_ARCHITECTURE.md) |
| Phase 4: Coordinator | マルチエージェント協調 | [archive/PHASE4_COORDINATOR_ARCHITECTURE.md](./archive/PHASE4_COORDINATOR_ARCHITECTURE.md) |
| チャット機能 | チャットUI/MCP/双方向保存 | [archive/CHAT_DUAL_STORAGE_IMPLEMENTATION.md](./archive/CHAT_DUAL_STORAGE_IMPLEMENTATION.md) |
| 通知システム | エージェント通知機能 | [archive/NOTIFICATION_SYSTEM_IMPLEMENTATION.md](./archive/NOTIFICATION_SYSTEM_IMPLEMENTATION.md) |
| セッションスポーン | セッション自動起動 | [archive/SESSION_SPAWN_IMPLEMENTATION.md](./archive/SESSION_SPAWN_IMPLEMENTATION.md) |
| AI間会話 | AI-to-AI コミュニケーション | [archive/AI_TO_AI_CONVERSATION_IMPLEMENTATION.md](./archive/AI_TO_AI_CONVERSATION_IMPLEMENTATION.md) |
| タスク/チャット分離 | セッション目的の分離 | [archive/TASK_CHAT_SEPARATION_IMPL_PLAN.md](./archive/TASK_CHAT_SEPARATION_IMPL_PLAN.md) |

### 参照用

| 計画 | 概要 | ドキュメント |
|------|------|-------------|
| マルチエージェント | アーキテクチャ設計 | [archive/MULTI_AGENT_ARCHITECTURE.md](./archive/MULTI_AGENT_ARCHITECTURE.md) |
| 状態駆動ワークフロー | タスク状態管理 | [archive/STATE_DRIVEN_WORKFLOW.md](./archive/STATE_DRIVEN_WORKFLOW.md) |
| Web UI拡張 | Web UI機能追加 | [archive/WEB_UI_FEATURE_EXPANSION.md](./archive/WEB_UI_FEATURE_EXPANSION.md) |
| パイロットテスト | E2Eテスト基盤 | [archive/PILOT_HELLO_WORLD_TDD.md](./archive/PILOT_HELLO_WORLD_TDD.md) |

---

## 変更履歴

| 日付 | 変更内容 |
|------|----------|
| 2026-02-02 | 未読メッセージリファクタリング計画を完了 |
| 2026-02-02 | アーカイブ構造に移行、未読メッセージリファクタリング計画を追加 |
| 2026-01-06 | Phase 3（プル型アーキテクチャ）を追加 |
| 2024-12-30 | 初版作成 |
