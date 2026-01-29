# Issue: セッションの自動クリーンアップが未実装

## 概要

エージェントが適切にログアウトしなかった場合、セッションが長時間残り続ける問題。

## 現状

| 項目 | 設定値 |
|------|--------|
| デフォルト有効期限 | 1時間（3600秒） |
| 自動クリーンアップ | なし |

### 関連コード

- `Sources/Domain/Entities/AgentSession.swift:30`
  ```swift
  public static let defaultExpirationInterval: TimeInterval = 3600
  ```

- `Sources/UseCase/AuthenticationUseCases.swift:184-197`
  - `CleanupExpiredSessionsUseCase` が定義されているが、どこからも呼び出されていない

- `Sources/Infrastructure/Repositories/AgentSessionRepository.swift:183`
  - `deleteExpired()` メソッドは実装済み

## 問題点

1. **セッションが1時間残る**: エージェントがログアウトしないと、セッションは1時間有効なまま残る
2. **期限切れセッションが削除されない**: 自動削除されず、クエリ時に `expires_at > Date()` でフィルタリングされるだけ
3. **リソースの無駄**: 不要なセッションがDBに蓄積される
4. **二重起動防止への影響**: 古いセッションが残っていると、新しいエージェントのスポーンがブロックされる可能性

## 再現条件

1. エージェントをスポーン
2. Ctrl+C や kill でプロセスを強制終了
3. セッションがDBに残り続ける

## 対策案

### 案1: セッション有効期限の短縮
- 1時間 → 10分程度に短縮
- 影響: 長時間タスク実行中にセッションが切れる可能性

### 案2: 定期的なクリーンアップ処理
- MCPサーバーで定期的に `CleanupExpiredSessionsUseCase` を実行
- タイマーで5分ごとなど

### 案3: Coordinator終了時のセッションクリア
- `Coordinator.stop()` でアクティブセッションを明示的に終了
- `end_session` ツールを呼び出すか、直接DBを更新

### 案4: ハートビート機構
- エージェントが定期的にハートビートを送信
- 一定時間ハートビートがないセッションを自動終了

## 推奨対策

**案2 + 案3 の組み合わせ**:
1. Coordinator終了時に管理中のセッションを終了
2. 万が一のために定期クリーンアップも実装

## 関連ドキュメント

- `docs/design/SESSION_SPAWN_ARCHITECTURE.md`

## 発見日

2026-01-29

## ステータス

未対応
