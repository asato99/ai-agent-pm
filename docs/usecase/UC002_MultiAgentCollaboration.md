# UC002: マルチエージェント協調作業

## 概要

**同一のタスク指示**を異なるAIプロバイダー・system_promptのエージェントに与え、**振る舞いの違い**を検証するフロー。

---

## 検証したいこと

「異なるsystem_prompt = 異なる専門家」というコンセプトの実証：
- 同じタスク指示でも、system_promptによって成果物が異なる
- ai_typeによって適切なCLIが選択される

---

## 前提条件

- 2つのエージェントが登録済み
  - 詳細ライター（Claude）: 詳細で包括的なドキュメントを作成
  - 簡潔ライター（Gemini）: 簡潔で要点のみのドキュメントを作成
- 各エージェントに異なる `ai_type` と `system_prompt` が設定済み
- プロジェクトが存在（working_directory 設定済み）
- Coordinatorが起動中

---

## アクター

| アクター | 種別 | AIタイプ | system_prompt |
|----------|------|----------|---------------|
| 詳細ライター | AI | Claude | 「詳細で包括的なドキュメントを作成してください。背景、目的、使用例を必ず含めてください。」 |
| 簡潔ライター | AI | Gemini | 「簡潔に要点のみ記載してください。箇条書きで3項目以内にまとめてください。」 |

---

## タスク指示（両エージェント共通）

```
タイトル: プロジェクト概要の作成
説明: PROJECT_SUMMARY.md を作成してください。
      このプロジェクトは「タスク管理システム」です。
```

**ポイント**: 指示は同一。system_promptの違いだけで成果物が変わることを検証。

---

## 基本フロー

### Phase 1: 詳細ライター（Claude）による作成

#### 1-1. タスク作成・割り当て

```
ユーザー → タスクを作成
  - タイトル: プロジェクト概要の作成
  - 説明: PROJECT_SUMMARY.md を作成してください。
          このプロジェクトは「タスク管理システム」です。
  - assigneeId: agt_detailed_writer
  - ステータス: in_progress
```

#### 1-2. Coordinatorが起動判断

```
Coordinator → should_start(agt_detailed_writer)
  ↓
MCP Server → 応答
  {
    "should_start": true,
    "ai_type": "claude"        ← Claude CLI を選択
  }
  ↓
Coordinator → claude --dangerously-skip-permissions で起動
```

#### 1-3. 詳細ライターが認証

```
詳細ライター → authenticate(agt_detailed_writer, passkey)
  ↓
MCP Server → 応答
  {
    "success": true,
    "session_token": "sess_xxx",
    "system_prompt": "詳細で包括的なドキュメントを作成してください。背景、目的、使用例を必ず含めてください。"
  }
```

#### 1-4. タスク実行

```
詳細ライター → get_my_task() → タスク詳細取得
  ↓
詳細ライター → PROJECT_SUMMARY.md を作成
  ↓
詳細ライター → report_completed(result: "success")
```

**期待される成果物（詳細版）**:
```markdown
# タスク管理システム

## 背景
現代のソフトウェア開発において、タスク管理は...（詳細な説明）

## 目的
本システムは以下の課題を解決します...（複数段落）

## 主な機能
1. タスクの作成・編集・削除
2. エージェントへの割り当て
3. ステータス管理
4. 進捗追跡
...（詳細なリスト）

## 使用例
### ケース1: 新規タスクの作成
ユーザーがダッシュボードから...（具体的な手順）
```

---

### Phase 2: 簡潔ライター（Gemini）による作成

#### 2-1. 同じタスクを別エージェントに割り当て

```
ユーザー → 新しいタスクを作成（同じ指示）
  - タイトル: プロジェクト概要の作成
  - 説明: PROJECT_SUMMARY_SHORT.md を作成してください。
          このプロジェクトは「タスク管理システム」です。
  - assigneeId: agt_concise_writer
  - ステータス: in_progress
```

#### 2-2. Coordinatorが起動判断

```
Coordinator → should_start(agt_concise_writer)
  ↓
MCP Server → 応答
  {
    "should_start": true,
    "ai_type": "gemini"        ← Gemini CLI を選択
  }
  ↓
Coordinator → gemini-cli --project xxx で起動
```

#### 2-3. 簡潔ライターが認証

```
簡潔ライター → authenticate(agt_concise_writer, passkey)
  ↓
MCP Server → 応答
  {
    "success": true,
    "session_token": "sess_yyy",
    "system_prompt": "簡潔に要点のみ記載してください。箇条書きで3項目以内にまとめてください。"
  }
```

#### 2-4. タスク実行

```
簡潔ライター → get_my_task() → タスク詳細取得
  ↓
簡潔ライター → PROJECT_SUMMARY_SHORT.md を作成
  ↓
簡潔ライター → report_completed(result: "success")
```

**期待される成果物（簡潔版）**:
```markdown
# タスク管理システム

- タスクの作成・管理
- エージェントへの割り当て
- 進捗追跡
```

---

## 検証可能なアサーション

### 機能検証

| 検証項目 | 方法 |
|----------|------|
| 詳細版ファイル存在 | `test -f PROJECT_SUMMARY.md` |
| 簡潔版ファイル存在 | `test -f PROJECT_SUMMARY_SHORT.md` |
| 両タスク完了 | DB: `tasks.status = 'done'` |

### 振る舞いの違いを検証

| 検証項目 | 詳細ライター | 簡潔ライター |
|----------|--------------|--------------|
| 文字数 | > 500文字 | < 200文字 |
| セクション数 | >= 3 | <= 2 |
| 「背景」含む | ✓ | ✗ |
| 「使用例」含む | ✓ | ✗ |
| 箇条書き項目数 | >= 5 | <= 3 |

```bash
# 文字数検証
detailed_chars=$(wc -c < PROJECT_SUMMARY.md)
concise_chars=$(wc -c < PROJECT_SUMMARY_SHORT.md)

[ $detailed_chars -gt 500 ] && echo "詳細版: OK"
[ $concise_chars -lt 200 ] && echo "簡潔版: OK"
[ $detailed_chars -gt $concise_chars ] && echo "詳細版 > 簡潔版: OK"

# セクション検証
grep -c "^##" PROJECT_SUMMARY.md      # >= 3
grep -c "^##" PROJECT_SUMMARY_SHORT.md # <= 2

# キーワード検証
grep "背景" PROJECT_SUMMARY.md        # 存在する
grep "背景" PROJECT_SUMMARY_SHORT.md  # 存在しない
```

---

## 代替フロー

### 認証失敗

```
エージェント → authenticate(agent_id, wrong_passkey)
  ↓
MCP Server → { "success": false, "error": "Invalid agent_id or passkey" }
```

### タスク実行失敗

```
エージェント → 作業ディレクトリにアクセス不可
  ↓
エージェント → report_completed(result: "blocked")
  ↓
タスクステータス: blocked
```

---

## 事後条件

- `PROJECT_SUMMARY.md` が作成されている（詳細、500文字以上）
- `PROJECT_SUMMARY_SHORT.md` が作成されている（簡潔、200文字未満）
- 両者の内容が明確に異なる（同じ指示でも異なる成果物）
- 両タスクのステータスが `done`

---

## まとめ：検証のポイント

```
同じタスク指示
    │
    ├─→ [詳細ライター (Claude)]
    │     system_prompt: "詳細で包括的に..."
    │     成果物: 長い、セクション多い、背景・使用例あり
    │
    └─→ [簡潔ライター (Gemini)]
          system_prompt: "簡潔に要点のみ..."
          成果物: 短い、箇条書き3項目以内

結論: system_prompt が振る舞いを決定する
```

---

## 関連

- UC001: エージェントによるタスク実行
- docs/plan/MULTI_AGENT_ARCHITECTURE.md - アーキテクチャ設計
