# Integration Tests

Web UIの統合テスト。ランナー・コーディネーターを含む全体のフローを検証します。

---

## ⚠️⚠️⚠️ 絶対禁止事項 ⚠️⚠️⚠️

### 🚫 期待結果のシードは最悪の不正行為

**シードデータに期待結果（テストで検証すべきデータ）を事前に作成してはならない**

```
❌ 最悪の不正（絶対禁止）:
  - テストで「タスクが作成される」ことを検証する場合に、シードでタスクを作成
  - テストで「ステータスがapprovedになる」ことを検証する場合に、シードでapprovedのデータを作成
  - 「simulates XX having done YY」というコメントで正当化しようとする行為

✅ 正しいシードデータ:
  - テストの前提条件のみをシード（エージェント、プロジェクト、セッション等）
  - 検証対象のデータは絶対にシードしない
  - 機能が未実装ならテストは失敗するべき（TDD RED状態）
```

**なぜ最悪の不正か**:
1. **統合テストの本質破壊**: 「実際のシステムが正しく連携して動作するか」を検証できなくなる
2. **偽のGREEN**: 機能が動作していなくてもテストが通り、バグを見逃す
3. **チームへの背信**: 偽りのテスト結果でチーム全体を欺く行為

**過去の違反事例（2026-01-24発覚）**:
UC018のシードデータでタスクを事前作成し、テストを不正に通過させた。
「This simulates Worker-01 having created a task via request_task tool」というコメントで正当化を試みた。
実際にはrequest_task機能が動作しているかは一切検証されていなかった。

---

## E2Eテストとの違い

| 項目 | E2E Tests (`e2e/tests/`) | Integration Tests (`e2e/integration/`) |
|------|--------------------------|----------------------------------------|
| バックエンド | MSW (モック) | 実際のREST/MCPサーバー |
| 目的 | フロントエンド機能のテスト | 全体システムの統合検証 |
| 速度 | 高速 | 低速（実サービス起動） |
| 信頼性 | 高（モックによる制御） | 中（外部要因に依存） |

## 前提条件

```bash
# Swiftプロジェクトのビルド
swift build -c release

# Node.js依存関係のインストール
cd web-ui && npm install
```

## セットアップ

### 1. 統合テスト環境の起動

```bash
./e2e/integration/setup/setup-integration-env.sh
```

これにより以下が行われます：
- テスト用データベースの作成
- 統合テストデータのシード
- MCPサーバーとRESTサーバーの起動

### 2. Web UIの起動

別のターミナルで：

```bash
cd web-ui
AIAGENTPM_WEBSERVER_PORT=8082 npm run dev
```

### 3. テストの実行

```bash
npx playwright test --config=e2e/integration/playwright.integration.config.ts
```

## テストの停止

```bash
./e2e/integration/setup/setup-integration-env.sh --stop
```

## 環境変数

| 変数名 | デフォルト値 | 説明 |
|--------|-------------|------|
| `AIAGENTPM_INTEGRATION_DB_PATH` | `/tmp/AIAgentPM_Integration.db` | テストDB |
| `AIAGENTPM_INTEGRATION_SOCKET` | `/tmp/aiagentpm_integration.sock` | MCPソケット |
| `AIAGENTPM_INTEGRATION_REST_PORT` | `8082` | RESTサーバーポート |

## テストケース

### UC010: タスク実行中のステータス変更による割り込み

`task-interrupt.spec.ts` - タスク実行中にステータスが変更された場合の動作を検証

**前提テスト（GREEN）:**
- 統合プロジェクトの存在確認
- カウントダウンタスクの存在と割り当て確認
- ステータス変更機能の動作確認

**割り込みテスト（現在GREEN / 通知実装後RED→GREEN）:**
- タスクを`in_progress`に変更
- タスクを`blocked`に変更
- 変更がUI反映されることを確認
- （通知実装後）エージェントが割り込み通知を受信することを確認
- （通知実装後）エージェントが`report_completed(result='blocked')`を呼び出すことを確認

## データリセット

テストデータを初期状態に戻す場合：

```bash
./e2e/integration/setup/setup-integration-env.sh --seed
```

## 参照

- [UC010: タスク実行中にステータス変更による割り込み](../../docs/usecase/UC010_TaskInterruptByStatusChange.md)
- [通知システム設計](../../docs/design/NOTIFICATION_SYSTEM.md)
