# UC001: エージェントによるタスク実行

## 概要

ユーザーがタスクを作成し、エージェントに割り当てて実行させる基本フロー。

---

## 前提条件

- エージェントが1名登録済み
- プロジェクトが存在し、エージェントがアサイン可能な状態
- MCPサーバーがClaude Codeに設定済み

---

## アクター

| アクター | 種別 | 役割 |
|----------|------|------|
| ユーザー | Human | タスク作成・割り当て・監視（上位エージェント） |
| エージェント | AI | タスク実行・作業タスク管理（下位エージェント） |

---

## 基本フロー

### 1. タスク作成（ユーザー）

```
ユーザー → タスク作成
  - タイトル: ドキュメントの作成
  - 説明: テストのドキュメント.md を作成してください。内容はテスト１について記述してください。
  - ステータス: backlog
```

※ ファイル名や成果物の内容は、タスクの説明（description）に指示として含める

### 2. エージェント割り当て（ユーザー）

```
ユーザー → タスクにエージェントをアサイン
  - assigneeId: [エージェントID]
```

### 3. ステータス変更とキック（ユーザー/システム）

```
ユーザー → ステータスを in_progress に変更
  ↓
システム → エージェントをキック
  - プロンプトに以下の情報を含める:
    - Task ID
    - Project ID
    - Agent ID
    - Agent Name
    - タスク詳細
```

### 4. タスク開始（エージェント）

```
エージェント（Claude Code）→ キック時のプロンプトからID情報を読み取る
  - Task ID: task_xxx
  - Project ID: proj_yyy
  - Agent ID: agt_zzz
  ↓
エージェント → MCPツールでコンテキスト確認（オプション）
  - get_task_context(task_id="task_xxx")
  - get_pending_handoffs(agent_id="agt_zzz")
```

### 5. 作業計画（エージェント）

```
エージェント → 自分の作業を作業タスクとして追加（依存関係で親タスクに紐づけ）
  - 作業タスク1: 要件確認 (todo) ← 親タスクに依存
  - 作業タスク2: 下書き作成 (todo) ← 作業タスク1に依存
  - 作業タスク3: レビュー依頼 (todo) ← 作業タスク2に依存
  - 作業タスク4: 最終調整 (todo) ← 作業タスク3に依存
```

### 6. タスク実行（エージェント）

```
エージェント → 作業タスクを順次実行（依存関係に従って）
  作業タスク1: todo → in_progress → done
    - save_context(task_id="task_xxx", progress="要件確認完了", ...)
  作業タスク2: todo → in_progress → done
    - save_context(task_id="task_xxx", progress="下書き完了", ...)
  ...
```

### 7. 完了通知（エージェント）

```
エージェント → MCPツールでステータス更新
  - update_task_status(task_id="task_xxx", status="done")
  ↓
システム → 親（ユーザー）に完了通知
```

### 7b. ハンドオフ（引き継ぎが必要な場合）

```
エージェント → ハンドオフを作成
  - create_handoff(
      task_id="task_xxx",
      from_agent_id="agt_zzz",  ← キック時のプロンプトから取得
      to_agent_id="agt_other",
      summary="認証機能実装完了。UIテストが必要"
    )
```

---

## シーケンス図

```
ユーザー          システム          エージェント
   |                 |                   |
   |--タスク作成---->|                   |
   |                 |                   |
   |--エージェント-->|                   |
   |  割り当て       |                   |
   |                 |                   |
   |--in_progress--->|                   |
   |                 |---キック--------->|
   |                 |  (プロンプトに     |
   |                 |   ID情報を含む)    |
   |                 |                   |
   |                 |                   |--ID情報を読み取り
   |                 |                   |
   |                 |                   |--作業計画
   |                 |                   |  (作業タスク追加)
   |                 |                   |
   |                 |                   |--順次実行
   |                 |                   |  (save_context呼び出し)
   |                 |                   |
   |                 |<--update_status---|
   |                 |  (task_id引数)    |
   |<--通知----------|                   |
   |                 |                   |
```

---

## キック時のプロンプト例

```markdown
# Task: ドキュメントの作成

## Identification
- Task ID: task_abc123
- Project ID: proj_xyz789
- Agent ID: agt_dev001
- Agent Name: document-writer

## Description
テストのドキュメント.md を作成してください。
内容はテスト１について記述してください。

## Working Directory
Path: /Users/xxx/projects/myproject
IMPORTANT: Create any output files within this directory.

## Instructions
1. Complete the task as described above
2. When done, update the task status using:
   update_task_status(task_id="task_abc123", status="done")
3. If handing off to another agent, use:
   create_handoff(task_id="task_abc123", from_agent_id="agt_dev001", ...)
```

---

## MCPツール呼び出し例

エージェントはキック時のプロンプトからID情報を読み取り、MCPツール呼び出し時に引数として渡す:

```
# コンテキスト保存
save_context(
  task_id="task_abc123",
  progress="要件を確認し、ドキュメント構成を決定",
  next_steps="下書きを作成する"
)

# ステータス更新
update_task_status(
  task_id="task_abc123",
  status="done"
)

# ハンドオフ作成
create_handoff(
  task_id="task_abc123",
  from_agent_id="agt_dev001",  ← プロンプトから取得
  to_agent_id="agt_reviewer",
  summary="ドキュメント作成完了。レビューをお願いします"
)
```

---

## ステータス遷移

### 親タスク
```
backlog → (割り当て) → todo → in_progress → done
```

### 作業タスク（下位エージェント作成）
```
todo → in_progress → done
```

---

## 関連エンティティ

| エンティティ | 操作 |
|--------------|------|
| Task | 作成、更新（ステータス、assigneeId、dependencies） |
| Agent | 参照（割り当て対象、親子関係） |
| Context | 作成（進捗情報の保存） |
| StateChangeEvent | 記録（ステータス変更履歴） |
| Handoff | 作成（引き継ぎ時） |

---

## 備考

- エージェントのキック時にプロンプトでID情報を渡す（MCP_DESIGN.md参照）
- MCPサーバーはステートレス設計。IDは各ツール呼び出し時に引数で渡す
- 作業タスクは `dependencies` で親タスクに紐づく（依存関係）
- エージェントの並列実行数は `maxParallelTasks` で制限
- エージェント間の親子関係は `parentAgentId` で表現（AGENTS.md参照）
