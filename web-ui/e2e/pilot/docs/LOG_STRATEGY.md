# パイロットテスト ログ確認戦略

パイロットテストのデバッグにおけるログ確認の体系的アプローチ。

---

## ログソース一覧

パイロットテスト実行時に生成されるログファイル:

**結果ディレクトリ**: `pilot/results/{scenario}/{timestamp}_{variation}/`

| ファイル | コンポーネント | 内容 |
|----------|---------------|------|
| `logs/combined.log` | 全コンポーネント | 統合ログ（タイムスタンプソート） |
| `logs/mcp-server.log` | MCP Server | API呼び出し、DB操作、チャット/タスク処理 |
| `logs/rest-server.log` | REST Server | HTTPリクエスト、サーバー起動 |
| `logs/coordinator.log` | Coordinator | エージェントポーリング、アクション取得 |
| `logs/playwright.log` | Playwright | テスト実行、アサーション結果 |
| `logs/vite.log` | Vite Dev Server | フロントエンドビルド、HMR |
| `logs/db-snapshot.sql` | Database | テスト終了時のDBダンプ |
| `agent-logs/{agent-id}/` | Per-agent logs | 各エージェントの実行ログ |
| `events.jsonl` | ResultRecorder | テストイベントの時系列記録 |

**クイックアクセス**: `pilot/results/{scenario}/latest/` → 最新の結果ディレクトリへのシンボリックリンク

---

## デバッグフロー

### Step 1: Playwrightログで全体像を把握

```bash
# 最新のテスト結果を確認
cat web-ui/e2e/pilot/results/hello-world/latest/logs/playwright.log

# または統合ログで全体の流れを確認
cat web-ui/e2e/pilot/results/hello-world/latest/logs/combined.log
```

確認ポイント:
- [ ] テストがどこまで進んだか
- [ ] エラーメッセージと発生箇所
- [ ] タイムアウトの有無

### Step 2: エラータイプに応じた調査

#### A. コードエラー（ReferenceError, TypeError等）

→ **pilot.spec.ts のソースコードを確認**

```bash
# エラー行の周辺を確認
head -n {エラー行+5} pilot/tests/pilot.spec.ts | tail -n 10
```

#### B. チャットメッセージが届かない

→ **MCP ログでpending_agent_purposes を確認**

```bash
grep -E "pending_agent_purposes|chat|message" \
  web-ui/e2e/pilot/results/hello-world/latest/logs/mcp-server.log | head -50
```

確認ポイント:
- [ ] `pending_agent_purposes rows:` が空ではないか
- [ ] チャットセッションが作成されているか
- [ ] メッセージが保存されているか

#### C. タスクが作成されない

→ **Coordinator ログでエージェントアクションを確認**

```bash
grep -E "getAgentAction|action_type|no_actionable" \
  web-ui/e2e/pilot/results/hello-world/latest/logs/coordinator.log | tail -50
```

確認ポイント:
- [ ] エージェントが `hold` 以外を返しているか
- [ ] `no_actionable_task` が続いていないか
- [ ] エージェントがアクティブになっているか

#### D. エージェントが実行されない

→ **エージェントログディレクトリを確認**

```bash
ls -la web-ui/e2e/pilot/results/hello-world/latest/agent-logs/
```

空の場合、エージェントは一度も起動していない。

### Step 3: DBの状態を直接確認

テスト終了時のDBスナップショットを確認:

```bash
# DBスナップショットをロード
sqlite3 :memory: < web-ui/e2e/pilot/results/hello-world/latest/logs/db-snapshot.sql

# またはテスト実行中のDBを直接確認（テスト失敗時のみ残る）
sqlite3 /tmp/AIAgentPM_Pilot.db "SELECT * FROM chat_sessions"
sqlite3 /tmp/AIAgentPM_Pilot.db "SELECT * FROM chat_messages"
sqlite3 /tmp/AIAgentPM_Pilot.db "SELECT * FROM pending_agent_purposes"
sqlite3 /tmp/AIAgentPM_Pilot.db "SELECT id, title, status FROM tasks"
```

---

## トラブルシューティングパターン

### パターン1: 「Chat session is ready」後にタイムアウト

**症状**: Playwrightログに「Chat session is ready」「Sent initial message」があるが、その後タスク作成がタイムアウト

**調査手順**:
1. MCP ログで `pending_agent_purposes` が空かどうか確認
2. 空の場合 → チャットメッセージがDBに保存されていない
3. DBで直接 `chat_messages` テーブルを確認

**よくある原因**:
- チャット送信APIが呼ばれていない
- REST API側でエラーが発生
- フロントエンドのAPI呼び出しが失敗

### パターン2: エージェントが全て `hold` を返す

**症状**: Coordinatorログで全エージェントが `hold` with `no_actionable_task`

**調査手順**:
1. MCP ログで `getNextAction` の詳細を確認
2. `Chat session with no pending messages` があるか確認
3. DBで `chat_messages` と `pending_agent_purposes` を確認

**よくある原因**:
- チャットメッセージが保存されていない
- `pending_agent_purposes` への挿入が失敗
- エージェントIDとセッションの紐付けが不正

### パターン3: コードエラー（require, import等）

**症状**: PlaywrightログにReferenceError, SyntaxError等

**調査手順**:
1. エラー行のソースコードを確認
2. ESM/CommonJSの互換性を確認

**よくある原因**:
- ESM環境で `require()` を使用
- importの漏れ
- 重複定義

---

## ログ改善提案

### 現状の課題

1. **REST APIリクエストログがない**: `/tmp/pilot_rest.log` はサーバー起動のみ
2. **フロントエンドログがない**: ブラウザコンソールログが取得されていない
3. **チャットAPI呼び出しのトレース不足**: メッセージ送信がどこで失敗したか特定困難

### 改善案

#### 1. REST API リクエストログ追加

```swift
// Logger middleware for all endpoints
app.middleware.use(RequestLoggerMiddleware())
```

→ `/tmp/pilot_rest.log` に全リクエスト/レスポンスを記録

#### 2. フロントエンドログ取得

```typescript
// pilot.spec.ts
page.on('console', msg => {
  fs.appendFileSync('/tmp/pilot_browser.log',
    `[${msg.type()}] ${msg.text()}\n`)
})
```

#### 3. チャットAPI呼び出しのデバッグログ

フロントエンドの `sendMessage` 関数にログを追加:

```typescript
console.log('[Chat] Sending message:', { sessionId, content })
const response = await api.sendMessage(sessionId, content)
console.log('[Chat] Response:', response)
```

---

## クイックリファレンス

### ログ確認ワンライナー

```bash
# 最新の結果ディレクトリへの短縮パス
LATEST="web-ui/e2e/pilot/results/hello-world/latest"

# 統合ログを確認
cat $LATEST/logs/combined.log

# エラーを含む行を検索
grep -i error $LATEST/logs/*.log

# チャット関連を検索
grep -iE "chat|message|pending" $LATEST/logs/mcp-server.log

# エージェントアクションを検索
grep -E "action_type|hold|work" $LATEST/logs/coordinator.log

# DBスナップショットを確認
sqlite3 :memory: < $LATEST/logs/db-snapshot.sql
```

### テスト再実行前のクリーンアップ

```bash
# 古い結果を削除（オプション）
rm -rf web-ui/e2e/pilot/results/hello-world/2026-*

# 手動でテスト環境をクリア（通常は不要）
rm -f /tmp/AIAgentPM_Pilot.db
rm -f /tmp/aiagentpm_pilot.sock
```

---

---

## 実例: チャットデータ残存問題の発見（2026-01-25）

### 問題

パイロットテストが失敗。テストログでは「Chat session is ready」「Sent initial message」と成功を示しているが、実際には期待通りに動作していなかった。

### 調査プロセス

1. **Playwright ログ確認**
   - 「Chat session is ready」「Sent initial message」と表示
   - その後 `require is not defined` エラーで crash

2. **MCP ログ確認**
   - `pending_agent_purposes` にchatセッションが作成されている
   - しかし「Chat session with no pending messages」と表示

3. **エラーコンテキスト確認**（重要！）
   ```bash
   cat /path/to/test-results/.../error-context.md
   ```
   - チャットパネルに**異なる内容のメッセージ**が表示されている
   - シナリオの期待メッセージ: 「作業ディレクトリに保存し...」
   - 実際に表示されているメッセージ: 「作成後、実行して動作確認も...」

4. **シードSQL確認**
   - `chat_messages`, `chat_sessions`, `pending_agent_purposes` がクリアされていない
   - 前回テストのデータが残存

### 根本原因

seed-generator.ts でチャット関連テーブルのクリーンアップが漏れていた。

### 修正

```typescript
// seed-generator.ts に追加
`DELETE FROM chat_messages WHERE project_id = '${project.id}';`,
`DELETE FROM chat_sessions WHERE project_id = '${project.id}';`,
`DELETE FROM pending_agent_purposes WHERE project_id = '${project.id}';`,
```

### 教訓

1. **error-context.md は必ず確認する**: Playwright が生成するページスナップショットには、UI の実際の状態が記録されている
2. **テストログの「成功」を鵜呑みにしない**: テストが通過したステップでも、実際には別のデータにマッチしている可能性がある
3. **シードデータのクリーンアップは完全に**: すべての関連テーブルをクリアする必要がある

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-01-25 | 初版作成 |
| 2026-01-25 | チャットデータ残存問題の実例を追加 |
| 2026-01-28 | ログアーキテクチャ改善: 結果ディレクトリへの集約、統合ログ生成、latestリンク追加 |
