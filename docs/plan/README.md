# 実装プラン

AI Agent Project Managerの実装計画。2フェーズに分割して段階的に開発する。

---

## フェーズ概要

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Implementation Roadmap                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Phase 1: MCP連携検証                         Phase 2: フル実装          │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━          ━━━━━━━━━━━━━━━━━━━━━━    │
│                                                                          │
│  ┌─────────────────────────┐                ┌─────────────────────┐     │
│  │ 目標: Claude Codeから   │                │ 目標: 本番利用可能な │     │
│  │ MCPサーバーに接続して   │                │ 完全なアプリケーション│     │
│  │ 基本操作ができることを  │                │ を完成させる         │     │
│  │ 最短で確認する          │                │                      │     │
│  └─────────────────────────┘                └─────────────────────┘     │
│                                                                          │
│  ┌─────────────────────────┐                ┌─────────────────────┐     │
│  │ 成果物:                 │                │ 成果物:              │     │
│  │ • 最小限のMCPサーバー   │                │ • 完全なMacアプリ    │     │
│  │ • 基本的なDB/Domain     │                │ • 全MCP機能          │     │
│  │ • 動作確認用CLI         │                │ • イベントソーシング │     │
│  └─────────────────────────┘                └─────────────────────┘     │
│                                                                          │
│  Week 1-2                                   Week 3-8                     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## フェーズ詳細

| フェーズ | 目標 | 主要成果物 | ドキュメント |
|---------|------|-----------|-------------|
| **Phase 1** | MCP連携が動作することを最短で確認 | MCPサーバー + 最小DB | [PHASE1_MCP_VERIFICATION.md](./PHASE1_MCP_VERIFICATION.md) |
| **Phase 2** | 本番利用可能なアプリを完成 | 完全なMacアプリ + MCP | [PHASE2_FULL_IMPLEMENTATION.md](./PHASE2_FULL_IMPLEMENTATION.md) |
| **Phase 3** | プル型アーキテクチャへ移行 | 認証 + Runner連携 + 実行ログ | [PHASE3_PULL_ARCHITECTURE.md](./PHASE3_PULL_ARCHITECTURE.md) |

---

## Phase 1: MCP連携検証

**目標**: Claude CodeからMCPサーバーに接続し、基本的なTool呼び出しができることを確認する

**スコープ**:
- 最小限のDomain層（Agent, Task）
- SQLiteセットアップ + 基本Repository
- MCPサーバー（stdio通信 + 3-5個のTool）
- 動作確認（Claude Codeで実際に呼び出し）

**スコープ外（Phase 2へ）**:
- GUIアプリ
- イベントソーシング
- 全Tool/Resource/Prompt
- ハンドオフ機能

**成功基準**:
```
Claude Code で以下が動作すること:
1. mcp-server-pm に接続できる
2. get_my_profile でエージェント情報を取得できる
3. list_tasks でタスク一覧を取得できる
4. update_task_status でタスクを更新できる
5. 更新がDBに永続化されている
```

---

## Phase 2: フル実装

**目標**: 本番利用可能な完全なアプリケーションを完成させる

**スコープ**:
- 完全なMacアプリ（SwiftUI）
- 全画面実装
- 全MCP機能（Tools/Resources/Prompts）
- イベントソーシング
- セッション管理
- ハンドオフ機能

**成功基準**:
```
1. Macアプリでプロジェクト/タスク/エージェントを管理できる
2. 複数のAIエージェントがMCP経由で協調作業できる
3. ハンドオフで情報が正しく引き継がれる
4. 全操作がイベントとして記録される
5. UIがリアルタイムで更新される
```

---

## Phase 3: プル型アーキテクチャ

**目標**: タスク実行をプル型アーキテクチャに移行し、外部Runnerからのタスク実行を可能にする

**スコープ**:
- 認証基盤（AgentCredential, AgentSession）
- Runner向けMCPツール（authenticate, get_pending_tasks）
- 実行ログ管理（ExecutionLog）
- エージェント設定UI（Passkey管理）
- 実行ログUI

**成功基準**:
```
1. Runner が authenticate でセッションを取得できる
2. Runner が get_pending_tasks で自分のタスクを取得できる
3. Runner が report_execution_start/complete で実行ログを報告できる
4. アプリでエージェントのPasskeyを管理できる
5. アプリで実行ログを閲覧できる
```

**開発方針**: TDD（テスト駆動開発）で各コンポーネントを実装

---

## 技術的判断

### Phase 1で確認すべき技術リスク

| リスク | 確認方法 |
|--------|---------|
| MCP Protocolの理解が正しいか | 実際にClaude Codeから呼び出し |
| stdio通信が安定するか | 複数回のTool呼び出しテスト |
| SQLite共有が動作するか | MCPサーバーとCLIから同時アクセス |
| Swift CLIのビルド/配布 | アプリバンドルへの組み込み |

### Phase 1で採用する簡略化

| 項目 | Phase 1 | Phase 2 |
|------|---------|---------|
| UI | なし（CLIのみ） | SwiftUI完全実装 |
| イベント記録 | なし | StateChangeEvent |
| エージェント認証 | 単純な--agent-id | 完全なセッション管理 |
| エラーハンドリング | 最小限 | 完全なエラー処理 |
| テスト | 手動確認 | TDD + 自動テスト |

---

## プロジェクト構造（Phase 1開始時）

```
AIAgentPM/
├── Package.swift
├── Sources/
│   ├── Domain/
│   │   ├── Entities/
│   │   │   ├── Agent.swift
│   │   │   ├── Project.swift
│   │   │   └── Task.swift
│   │   └── ValueObjects/
│   │       ├── AgentID.swift
│   │       ├── ProjectID.swift
│   │       └── TaskID.swift
│   │
│   ├── Infrastructure/
│   │   ├── Database/
│   │   │   ├── DatabaseSetup.swift
│   │   │   └── Records/
│   │   │       ├── AgentRecord.swift
│   │   │       ├── ProjectRecord.swift
│   │   │       └── TaskRecord.swift
│   │   └── Repositories/
│   │       ├── AgentRepository.swift
│   │       ├── ProjectRepository.swift
│   │       └── TaskRepository.swift
│   │
│   └── MCPServer/
│       ├── main.swift
│       ├── MCPServer.swift
│       ├── Transport/
│       │   └── StdioTransport.swift
│       └── Tools/
│           ├── AgentTools.swift
│           └── TaskTools.swift
│
└── Tests/
    └── (Phase 2で追加)
```

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2024-12-30 | 1.0.0 | 初版作成 |
| 2026-01-06 | 1.1.0 | Phase 3（プル型アーキテクチャ）を追加 |
