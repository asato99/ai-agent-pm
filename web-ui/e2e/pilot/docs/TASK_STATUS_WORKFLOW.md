# タスクステータス遷移ワークフロー

## 概要

パイロットテストにおけるタスクステータス遷移の責任分担を明確にする。

## 核心原則: エージェントは自身のサブタスクの管理責任を持つ

**各エージェントは、自身が作成したサブタスクのステータス管理に責任を持つ。**

これは以下を意味する：
- サブタスクを作成したエージェントが、そのステータスを `in_progress` に変更する責任がある
- 他のエージェントが作成したサブタスクのステータスを変更する必要はない

## ステータス遷移の責任者

| タスクの作成者 | ステータス遷移の責任者 | 操作方法 |
|----------------|------------------------|----------|
| Owner/System（Manager向け） | **Owner** | UI から `in_progress` に更新 |
| Manager（Worker向けサブタスク） | **Manager** | `update_task_status` で `in_progress` に更新 |
| Worker（自身のサブタスク） | **Worker** | `update_task_status` で `in_progress` に更新 |

## 重要な原則

### 1. Owner はマネージャーのタスクのみを更新する

Owner（Human）は Web UI を通じて操作する。Owner が直接更新するのは：
- **マネージャーに割り当てられたタスク**のみ

Owner はワーカーのサブタスクを直接更新**しない**。

### 2. Manager は自身が作成したサブタスクを管理する

Manager が `create_task` でワーカー向けサブタスクを作成した場合：
- Manager が `assign_task` で割り当て
- **Manager が `update_task_status` で `in_progress` に変更**

### 3. Worker は自身が作成したサブタスクを管理する

Worker が自身の作業を細分化してサブタスクを作成した場合：
- **Worker 自身が `update_task_status` で `in_progress` に変更**

### 4. タスクが開始されないのは作成者の判断ミス

タスクが `todo` のままで `in_progress` に遷移しない場合：
- これは**システムの問題ではない**
- **タスク作成者の判断ミス**（`update_task_status` を呼んでいない）
- 作成者のシステムプロンプトまたは `get_next_action` のガイダンスを修正する必要がある

## 期待されるフロー

```
1. Owner → Manager: チャットで依頼送信
2. Manager: get_next_action で指示を確認
3. Manager: create_task でサブタスクを作成（status: backlog）
4. Manager: assign_task でワーカーに割り当て
5. Manager: update_task_status でサブタスクを in_progress に変更  ← 重要
6. Coordinator: in_progress タスクを検知 → Worker をスポーン
7. Worker: タスクを実行 → done に変更
8. Manager: 次のサブタスク（レビューなど）を in_progress に変更
9. Coordinator: in_progress タスクを検知 → 次の Worker をスポーン
10. 繰り返し...
```

## システム側の動作

### Coordinator (`getAgentAction`)

Coordinator は以下の条件で Worker をスポーンする：
- `in_progress` ステータスのタスクが存在する
- かつ、そのタスクの担当者（assignee）にアクティブなセッションがない

**`todo` ステータスのタスクは無視される**。これは意図した動作であり、マネージャーが明示的にタスクを開始（`in_progress` に変更）するまでワーカーはスポーンされない。

### get_next_action のガイダンス（実装済み）

Manager が `get_next_action` を呼び出したとき、システムは以下の指示を返す：

| Phase | action | 内容 |
|-------|--------|------|
| 1 | `create_subtasks` | サブタスクを作成せよ |
| 2 | `assign` | サブタスクをワーカーに割り当てよ（assignee変更のみ） |
| 3 | **`start_task`** | サブタスクを `in_progress` に変更せよ（`update_task_status` を使用） |
| 4 | `exit` | 作業完了、Worker の完了を待つ |
| 5 | `report_completion` | 全サブタスク完了、メインタスクを完了せよ |

**参照**: `Sources/MCPServer/MCPServer.swift` の `getManagerNextAction()` 関数

### start_task が返される条件

`start_task` は以下の条件を満たすサブタスクがある場合に返される：
1. **ワーカーに割り当て済み**（`assigneeId != nil && assigneeId != managerの担当者ID`）
2. **依存関係がクリア**（依存タスクがないか、全ての依存タスクが `done`）

### 依存関係がある場合のフロー

```
1. Manager: create_subtasks → Task1（dep: なし）, Task2（dep: Task1）
2. Manager: assign → Task1 を worker-dev に割り当て
3. Manager: assign → Task2 を worker-review に割り当て
4. Manager: start_task → Task1 を in_progress に変更
5. Manager: exit → Worker の完了を待つ
6. Worker-dev: Task1 を完了 → done
7. Coordinator: Manager を再スポーン  ← 重要
8. Manager: start_task → Task2 を in_progress に変更（依存関係クリア）
9. Coordinator: Worker-review をスポーン
```

**重要**: Worker 完了後に Manager が再スポーンされないと、依存関係のあるタスクは `in_progress` に遷移しない。

## トラブルシューティング

### 症状: ワーカーがスポーンされない

**確認事項**:
1. ワーカーのタスクのステータスは何か？
   - `todo` → マネージャーが `update_task_status` を呼んでいない
   - `in_progress` → 別の問題（セッション重複など）

2. マネージャーのログを確認
   - `get_next_action` が `start_task` を指示しているか？
   - マネージャーが `update_task_status` を呼んでいるか？

**対策**:
- マネージャーのシステムプロンプトで `update_task_status` の使用を明示的に指示
- `get_next_action` のガイダンスロジックを確認・修正

## 関連ドキュメント

- `docs/design/SESSION_SPAWN_ARCHITECTURE.md` - セッションスポーンの詳細設計
- `proposals/001_auto_task_progression.md` - 自動タスク進行の改善提案
- `scenarios/hello-world/variations/explicit-flow.yaml` - 明示的フロー指示版シナリオ
