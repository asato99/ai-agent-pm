# パイロットテスト シードデータクリーンアップ漏れ問題

**日付**: 2026-01-25
**カテゴリ**: E2E/統合テスト
**影響範囲**: パイロットテストフレームワーク

---

## 問題の概要

パイロットテストが失敗。テストログでは成功を示すメッセージが出力されているが、実際にはシステムが期待通りに動作していなかった。

## 症状

1. Playwrightログに「Chat session is ready」「Sent initial message」と表示
2. MCPログに「Chat session with no pending messages」と表示
3. テストは最終的に別のエラー（`require is not defined`）でクラッシュ

## 調査過程

### 初期の誤った方向性

1. MCPログで「no pending messages」を見て、メッセージ送信が失敗したと推測
2. チャットAPIの実装を調査
3. Viteの設定、APIクライアントの設定を確認
4. → **ログの表面的な情報だけで判断し、実際のUI状態を確認していなかった**

### 正しい調査手順

1. **error-context.md を確認**
   ```bash
   cat web-ui/test-results/.../error-context.md
   ```

2. **発見**: チャットパネルに表示されているメッセージが、テストが送信しようとしているメッセージと**異なっていた**
   - 表示されていたメッセージ: 「作成後、実行して動作確認も行ってください」
   - テストが送信しようとしていたメッセージ: 「作業ディレクトリに保存し、動作確認まで行ってください」

3. **原因特定**: 前回のテスト実行のチャットデータがDBに残存していた

## 根本原因

`seed-generator.ts` が以下のテーブルをクリアしていなかった：

- `chat_messages`
- `chat_sessions`
- `pending_agent_purposes`

## 修正内容

```typescript
// seed-generator.ts に追加
`DELETE FROM chat_messages WHERE project_id = '${project.id}';`,
`DELETE FROM chat_sessions WHERE project_id = '${project.id}';`,
`DELETE FROM pending_agent_purposes WHERE project_id = '${project.id}';`,
```

## 教訓

### 1. error-context.md は最優先で確認する

Playwrightが生成するページスナップショットには、テスト失敗時のUIの実際の状態が記録されている。ログファイルよりも先にこれを確認すべき。

### 2. ログの「成功」メッセージを鵜呑みにしない

テストが「Sent initial message」とログに出力しても、それは：
- メッセージがUIに表示されたことを示すだけ
- 実際には別のデータ（古いメッセージ）にマッチしていた可能性がある

### 3. シードデータは関連する全テーブルをクリアする

テストの前提条件として必要なデータだけでなく、**テスト実行に影響を与える可能性のある全てのデータ**をクリアする必要がある。

### 4. 「簡単なミス」ほど見落としやすい

複雑な原因を探る前に、基本的な確認を行う：
- DBに古いデータが残っていないか
- シードSQLが全ての関連テーブルをカバーしているか
- 表示されているデータが本当に期待値と一致するか

## 関連ドキュメント

- `web-ui/e2e/pilot/docs/LOG_STRATEGY.md` - パイロットテストのログ確認戦略
- `CLAUDE.md` - E2E/統合テスト失敗時の調査手順

## 変更されたファイル

1. `web-ui/e2e/pilot/lib/seed-generator.ts` - チャットテーブルのクリーンアップ追加
2. `web-ui/e2e/pilot/docs/LOG_STRATEGY.md` - 新規作成
3. `web-ui/e2e/pilot/README.md` - デバッグ手順への参照追加
4. `CLAUDE.md` - 調査手順と問題記録を追加
