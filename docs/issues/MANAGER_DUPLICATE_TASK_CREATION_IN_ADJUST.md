# マネージャーがadjust状態で重複タスクを作成する問題

## 概要

パイロットテスト（weather-app-complete / specialist-team）において、マネージャーが同一機能に対して重複するタスクを作成する問題が発生した。

## 発生状況

- **シナリオ**: weather-app-complete
- **バリエーション**: specialist-team
- **日時**: 2026-02-03 19:48-20:00頃
- **ログ**: `web-ui/e2e/pilot/results/weather-app-complete/2026-02-03T19-48-54_specialist-team/logs/mcp-server.log`

## 詳細なタイムライン

### 1回目のタスク作成: 19:51:57

- **状態**: `needs_subtask_creation`
- **エージェント**: manager-dev
- **親タスク**: `tsk_9b82dbc1-34b` (天気予報Webアプリ完全版の実装)

**作成されたタスク:**

| ID | タイトル | 備考 |
|----|----------|------|
| tsk_285ea231-d06 | 設計・計画フェーズ：アーキテクチャ設計とAPI選定 | |
| tsk_74f02d5a-70f | **実装フェーズ：基本機能とUI実装** | 重複① |
| tsk_d9652306-c45 | **実装フェーズ：雨雲レーダー機能実装** | 重複② |
| tsk_cf778abd-54d | 検証フェーズ：機能テストと品質確認 | |

**ログ:**
```
2026-02-03 19:51:57.354 [INFO] [mcp] [create_tasks_batch] agent:manager-dev project:pilot-weather-app-complete Tool called: create_tasks_batch details:{"parent_task_id":"tsk_9b82dbc1-34b",...,"tasks":[
  {"local_id":"task_1_planning","title":"設計・計画フェーズ：アーキテクチャ設計とAPI選定"},
  {"local_id":"task_2_core_implementation","title":"実装フェーズ：基本機能とUI実装"},
  {"local_id":"task_3_radar_implementation","title":"実装フェーズ：雨雲レーダー機能実装"},
  {"local_id":"task_4_qa_verification","title":"検証フェーズ：機能テストと品質確認"}
]}
```

### 2回目のタスク作成: 19:54:54

- **状態**: `adjust` (select_action で選択)
- **エージェント**: manager-dev
- **親タスク**: `tsk_9b82dbc1-34b` (同じ親タスク)

**select_action の呼び出し:**
```
2026-02-03 19:53:58.233 [INFO] [system] [MCP] selectAction: agent=manager-dev, action=adjust, reason=Need to check current subtask situation and decide on task assignment strategy
```

**get_next_action の応答 (adjust 状態の指示):**
```
2026-02-03 19:54:00.751 [INFO] [mcp] [get_next_action] ...
{
  "state": "adjust",
  "instruction": "必要な調整を行ってください。\n\n■ 調整用ツール\n- assign_task: 担当者変更・振り直し\n- update_task_status: ステータス変更\n- create_tasks_batch: 追加タスク作成\n\n■ コミュニケーション（状況確認・変更指示）\n- delegate_to_chat_session: 下位エージェントにチャット移譲\n..."
}
```

**作成されたタスク:**

| ID | タイトル | 備考 |
|----|----------|------|
| tsk_38357be7-cc8 | 設計・計画フェーズ | |
| tsk_b6fc42a4-56c | **コア機能実装（検索・現在天気・予報）** | 重複① |
| tsk_7564be29-85e | **雨雲レーダー機能実装** | 重複② |
| tsk_c6ea7a5f-be3 | QA検証・デバッグ | |

**ログ:**
```
2026-02-03 19:54:54.462 [INFO] [mcp] [create_tasks_batch] agent:manager-dev project:pilot-weather-app-complete Tool called: create_tasks_batch details:{"parent_task_id":"tsk_9b82dbc1-34b",...,"tasks":[
  {"local_id":"planning","title":"設計・計画フェーズ"},
  {"local_id":"implementation_core","title":"コア機能実装（検索・現在天気・予報）"},
  {"local_id":"implementation_radar","title":"雨雲レーダー機能実装"},
  {"local_id":"qa_verification","title":"QA検証・デバッグ"}
]}
```

## 重複タスクの対応関係

同一の親タスク（`tsk_9b82dbc1-34b`）配下に、同じ機能を対象とした重複タスクが作成された:

| 機能 | 1回目 (19:51:57) | 2回目 (19:54:54) | 状態 |
|------|------------------|------------------|------|
| コア機能 | 実装フェーズ：基本機能とUI実装 (`tsk_74f02d5a`) | コア機能実装（検索・現在天気・予報） (`tsk_b6fc42a4`) | 1回目: todo (未割当), 2回目: in_progress (プログラマー1) |
| 雨雲レーダー | 実装フェーズ：雨雲レーダー機能実装 (`tsk_d9652306`) | 雨雲レーダー機能実装 (`tsk_7564be29`) | 1回目: todo (未割当), 2回目: in_progress (プログラマー2) |

**結果:**
- 1回目のタスク（実装フェーズ：〇〇）は**未割り当てのまま放置**
- 2回目のタスク（コア機能実装、雨雲レーダー機能実装）がプログラマーに割り当てられて実行
- リソースの無駄、タスク管理の混乱を招く

## 根本原因

### 1. adjust 状態の指示に `create_tasks_batch: 追加タスク作成` が含まれている

マネージャーは「追加タスク」として新規作成を行ったが、実際には既存タスクと機能的に重複していた。

### 2. 既存サブタスクの確認が不十分

`adjust` 状態で `create_tasks_batch` を使用する前に、既存サブタスクの確認を強制していない。

### 3. 重複検出メカニズムがない

同一親タスク配下に類似タイトル/内容のタスクがあっても検出・警告されない。

## 影響

- タスク数の不必要な増加（22タスク中、少なくとも2タスクが重複）
- 未割り当てタスクの残存による管理の複雑化
- ワーカーが間違ったタスクを実行するリスク
- タスク進捗の誤認（pendingカウントが実態より多くなる）

## 提案する対策

### 短期（指示の改善）

`adjust` 状態の instruction を修正:

```diff
■ 調整用ツール
- assign_task: 担当者変更・振り直し
- update_task_status: ステータス変更
- create_tasks_batch: 追加タスク作成
+   ⚠️ 使用前に list_tasks で既存サブタスクを確認し、重複がないことを確認してください
```

**実装箇所**: `Sources/MCPServer/MCPServer.swift` の `getManagerNextAction` 内、`adjust` 状態の instruction 生成部分

### 中期（バリデーションの追加）

`create_tasks_batch` に重複チェックロジックを追加:

1. 同一 `parent_task_id` 配下の既存タスクを取得
2. 新規タスクのタイトルと既存タスクのタイトルを比較
3. 類似度が閾値を超える場合に警告を返す（エラーではなく警告として作成は許可）

**類似度判定の候補:**
- キーワードマッチング（「実装」「雨雲」「レーダー」等）
- 編集距離（Levenshtein distance）
- 単語の重複率

### 長期（アーキテクチャ改善）

1. **タスク作成意図の明示化**
   - `create_tasks_batch` に `intent` パラメータを追加（"new" | "refine" | "replace"）
   - "refine" の場合は既存タスクとの関連付けを必須に

2. **マネージャーのコンテキスト強化**
   - タスク作成履歴をコンテキストに含める
   - 「既に〇〇というタスクが存在します」という情報を提供

3. **タスクのマージ/統合機能**
   - 重複が検出された場合にタスクをマージするツールを提供

## 関連ファイル

- `Sources/MCPServer/MCPServer.swift` - getManagerNextAction, createTasksBatch
- `Sources/MCPServer/Tools/ToolDefinitions.swift` - create_tasks_batch 定義
- `docs/design/MANAGER_STATE_MACHINE_V2.md` - マネージャーステートマシン設計

## 検証方法

1. パイロットテスト（weather-app-complete / specialist-team）を再実行
2. タスク作成ログを確認し、重複が発生していないことを確認
3. または、専用のユニットテストを追加

## 関連Issue

- GitHub Issue: https://github.com/asato99/ai-agent-pm/issues/1

## ステータス

- [x] 問題の特定
- [x] 根本原因の分析
- [x] 対策の提案
- [ ] 短期対策の実装
- [ ] 中期対策の実装
- [ ] 検証

---

**作成日**: 2026-02-03
**発見者**: パイロットテスト観察中に発見
