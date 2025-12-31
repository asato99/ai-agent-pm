# PRD: AI Agent Project Manager

## 製品ビジョン

AIエージェントをファーストクラス市民として扱うプロジェクト管理アプリ。
人間とAIエージェントが協調してソフトウェア開発を行うための基盤を提供する。

---

## 背景・課題

### 現状の課題
1. **コンテキスト喪失** - AIエージェントのセッションが切れると作業状況が失われる
2. **分断された作業** - 複数エージェントセッション間で情報共有ができない
3. **人間中心設計** - 既存ツール（Jira、Linear）はAIエージェントを考慮していない
4. **手動の引き継ぎ** - セッション開始時に毎回状況説明が必要

### 解決策
MCPサーバーを通じて、AIエージェントがプロジェクト情報に直接アクセス・更新できる仕組みを構築する。

---

## ターゲットユーザー

### プライマリ
- **AIエージェント**（Claude Code、将来的にGemini等）
  - タスクの取得・更新
  - 作業状況の記録
  - 他エージェントへの引き継ぎ情報の登録

### セカンダリ
- **開発者（人間）**
  - プロジェクト全体の監督
  - タスクの作成・優先順位付け
  - エージェント作業の確認・承認

---

## ドキュメント構成

### コンセプト・設計
| ドキュメント | 説明 |
|-------------|------|
| [AGENT_CONCEPT.md](./AGENT_CONCEPT.md) | エージェント・セッション・AIツールの概念設計 |
| [TASK_MANAGEMENT.md](./TASK_MANAGEMENT.md) | タスク管理・ステータスフロー設計 |
| [PERMISSIONS.md](./PERMISSIONS.md) | 権限システム設計 |
| [STATE_HISTORY.md](./STATE_HISTORY.md) | イベントソーシング・監査ログ設計 |
| [MCP_DESIGN.md](./MCP_DESIGN.md) | MCP Tools/Resources/Prompts設計 |

### システム設計
| ドキュメント | 説明 |
|-------------|------|
| [SYSTEM_ARCHITECTURE.md](./SYSTEM_ARCHITECTURE.md) | システム構成・技術スタック |
| [SETUP_FLOW.md](./SETUP_FLOW.md) | セットアップフロー |

### アーキテクチャ設計
| ドキュメント | 説明 |
|-------------|------|
| [architecture/README.md](../architecture/README.md) | アーキテクチャ概要 |
| [architecture/DOMAIN_MODEL.md](../architecture/DOMAIN_MODEL.md) | ドメインモデル・Entity設計 |
| [architecture/DATABASE_SCHEMA.md](../architecture/DATABASE_SCHEMA.md) | SQLiteスキーマ設計 |
| [architecture/APP_ARCHITECTURE.md](../architecture/APP_ARCHITECTURE.md) | Macアプリ内部構成 |
| [architecture/MCP_SERVER.md](../architecture/MCP_SERVER.md) | MCPサーバー設計 |
| [architecture/DATA_FLOW.md](../architecture/DATA_FLOW.md) | データフロー・状態管理 |

### 開発ガイドライン
| ドキュメント | 説明 |
|-------------|------|
| [guide/README.md](../guide/README.md) | 開発ガイドライン目次 |
| [guide/CLEAN_ARCHITECTURE.md](../guide/CLEAN_ARCHITECTURE.md) | クリーンアーキテクチャ原則 |
| [guide/TDD.md](../guide/TDD.md) | テスト駆動開発 |
| [guide/NAMING_CONVENTIONS.md](../guide/NAMING_CONVENTIONS.md) | 命名規則 |
| [guide/DEPENDENCY_INJECTION.md](../guide/DEPENDENCY_INJECTION.md) | 依存性注入 |
| [guide/CODE_REVIEW.md](../guide/CODE_REVIEW.md) | コードレビュー |

### UI設計
| ドキュメント | 説明 |
|-------------|------|
| [01_project_list.md](../ui/01_project_list.md) | プロジェクト一覧画面 |
| [02_task_board.md](../ui/02_task_board.md) | タスクボード画面 |
| [03_agent_management.md](../ui/03_agent_management.md) | エージェント管理画面 |
| [04_task_detail.md](../ui/04_task_detail.md) | タスク詳細画面 |
| [05_handoff.md](../ui/05_handoff.md) | ハンドオフ画面 |
| [06_settings.md](../ui/06_settings.md) | 設定画面 |

### 実装プラン
| ドキュメント | 説明 |
|-------------|------|
| [plan/README.md](../plan/README.md) | 実装プラン概要 |
| [plan/PHASE1_MCP_VERIFICATION.md](../plan/PHASE1_MCP_VERIFICATION.md) | Phase 1: MCP連携検証 |
| [plan/PHASE2_FULL_IMPLEMENTATION.md](../plan/PHASE2_FULL_IMPLEMENTATION.md) | Phase 2: フル実装 |

---

## MVP スコープ

### In Scope
- [ ] プロジェクト CRUD
- [ ] タスク CRUD
- [ ] ステータス管理
- [ ] コンテキスト記録
- [ ] ハンドオフ機能
- [ ] MCP Server（Claude Code連携）
- [ ] 基本的なUI（タスクボード）
- [ ] エージェント管理（作成・編集・一覧）
- [ ] セッション管理（開始・終了・履歴）
- [ ] セットアップウィザード（エージェント作成 + Claude Code設定自動化）

### Out of Scope (将来)
- メトリクス・分析
- Gemini等の他AIツール対応
- チーム機能（複数人間）
- クラウド同期
- 通知機能
- エージェント自己登録

---

## 成功指標

### MVP
1. Claude Codeが自分のエージェント情報を取得できる（`get_my_profile`）
2. Claude Codeがタスクの取得・更新ができる
3. ハンドオフ情報が次のセッションで利用できる
4. 複数エージェント間でコンテキストが共有できる
5. 人間がUIからプロジェクト・エージェント全体を把握できる

---

## 決定事項

| 項目 | 決定 | 理由 |
|------|------|------|
| MCP Server実装方式 | 別プロセス（CLIバンドル） | Claude Codeの標準接続方式、アプリ非起動時も動作可能 |
| データ形式 | SQLite（直接） | アプリとMCPサーバーで共有しやすい |
| セットアップ方式 | アプリ側で自動化 | ユーザー体験の簡素化 |
| エージェント管理 | アプリ側で一元管理 | 堅牢性、永続性、人間による監督 |
| エージェント識別 | `--agent-id` 引数で認証 | シンプル、確実、MCPサーバー起動時に決定 |
| 人間の扱い | エージェントの一種（type: human） | 統一的なモデル、ハンドオフの一貫性 |

## 未決定事項

| 項目 | 選択肢 | 決定期限 |
|------|--------|----------|
| SQLiteライブラリ | GRDB vs SQLite.swift vs 直接C API | 設計フェーズ |
| アプリ名 | AI Agent PM vs 他の候補 | 実装前 |
| セッション自動終了 | タイムアウト vs 明示的終了のみ | 実装フェーズ |

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2024-12-30 | 0.1.0 | 初版作成 |
| 2024-12-30 | 0.2.0 | システム構成決定（別プロセスMCP + アプリ側セットアップ自動化） |
| 2024-12-30 | 0.3.0 | エージェント管理詳細設計（Agent/Session概念、MCP Tools拡張、セットアップフロー更新） |
| 2024-12-30 | 0.4.0 | ドキュメント分割・再構成（詳細を個別ファイルへ移動） |
