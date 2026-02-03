# Issue: マネージャーの自律性と状況認識の欠如

## 概要

現在の実装では、マネージャーエージェントが `get_next_action` の指示に従うだけの「状態機械の奴隷」となっており、本来期待されるマネジメント機能（判断、調整、レビュー）を発揮できていない。

## 問題の詳細

### 1. `start_task` アクションの過剰な指示

**現状:**
```json
{
  "action": "start_task",
  "instruction": "次のサブタスクを実行開始してください。update_task_status で...",
  "next_subtask": {
    "id": "tsk_xxx",
    "title": "具体的なタスク名",
    "assignee_id": "worker-programmer-01"
  }
}
```

**問題点:**
- どのタスクを開始するかがシステムによって決定されている
- マネージャーに選択の余地がない
- 優先順位の判断、リソース状況の考慮ができない

**あるべき姿:**
- マネージャーが実行可能なタスク一覧を把握
- 現在の状況（ワーカーの負荷、依存関係、優先度）を考慮
- マネージャーの裁量でどのタスクをどのワーカーに開始させるか決定

### 2. ワーカー待ちからの復帰時に状況把握の機会がない

**現状のフロー:**
```
ワーカー待ち (exit)
    ↓
[ワーカー完了]
    ↓
再起動 → get_next_action → start_task（即座に次タスク開始）
```

**問題点:**
- ワーカーの成果をレビューする機会がない
- 何が完了し、何が残っているか俯瞰できない
- 計画の修正やタスクの振り直しを検討する機会がない
- 問題が発生していても気づけない

**あるべき姿:**
```
ワーカー待ち (exit)
    ↓
[ワーカー完了]
    ↓
再起動 → get_next_action → situational_awareness（状況把握フェーズ）
    ↓
マネージャーが判断:
  - 成果のレビュー
  - 計画の見直し
  - タスクの修正・振り直し
  - 次のアクションの決定
```

### 3. マネージャーが使用していないツール

調査の結果、マネージャーは以下のツールを一度も呼んでいない:

| ツール | 用途 | 呼び出し回数 |
|--------|------|-------------|
| `list_subordinates` | ワーカーの状態確認 | 0 |
| `list_tasks` | タスク進捗の俯瞰 | 0 |
| `get_task` | 完了タスクの成果確認 | 0 |
| `get_subordinate_profile` | ワーカーのスキル確認 | 0 |

これらは全て `get_next_action` が指示しないため呼ばれない。

## 提案する改善

### A. `situational_awareness` アクションの導入

ワーカー待ちから復帰した際、まず状況把握フェーズを設ける:

```json
{
  "action": "situational_awareness",
  "instruction": "ワーカーの作業が進行しました。現在の状況を把握し、次のアクションを決定してください。",
  "context": {
    "recently_completed": [
      {
        "task_id": "tsk_xxx",
        "title": "...",
        "completed_by": "worker-programmer-01",
        "summary": "..." // 成果サマリー（あれば）
      }
    ],
    "in_progress": [...],
    "pending": [...],
    "blocked": [...]
  },
  "available_actions": [
    "list_tasks で詳細を確認",
    "get_task で成果をレビュー",
    "assign_task でタスクを振り直し",
    "update_task_status でタスクを開始"
  ]
}
```

### B. `start_task` の廃止または変更

**オプション1: 廃止**
- マネージャーが自分で `update_task_status` を呼んでタスクを開始
- どのタスクを開始するかはマネージャーの判断

**オプション2: 推奨ベースに変更**
```json
{
  "action": "recommend_start",
  "instruction": "以下のタスクが開始可能です。状況を確認の上、適切なタスクを開始してください。",
  "executable_tasks": [
    {"id": "tsk_a", "title": "...", "assignee": "worker-01", "priority": "high"},
    {"id": "tsk_b", "title": "...", "assignee": "worker-02", "priority": "medium"}
  ],
  "recommendation": "tsk_a（優先度が高いため）"
}
```

### C. マネージャーのシステムプロンプト強化

現在のシステムプロンプトに加え、状況把握の習慣を促す:

```
## 復帰時の行動指針
ワーカー待ちから復帰した場合:
1. まず list_tasks で全体状況を確認
2. 完了タスクがあれば get_task で成果をレビュー
3. 問題があればタスクの修正や振り直しを検討
4. 状況を把握した上で次のアクションを決定
```

## 影響範囲

- `Sources/MCPServer/MCPServer.swift` - `getManagerNextAction` の修正
- `Sources/MCPServer/Tools/ToolDefinitions.swift` - 新アクションの追加（必要に応じて）
- マネージャーのシステムプロンプト
- ドキュメント更新

## 優先度

**高** - マネージャーの本質的な機能に関わる問題

## 関連調査

- パイロットテスト（weather-app-complete / specialist-team）での観察
- マネージャーのツール使用統計
- `get_next_action` レスポンスの分析

## 参考：現在のマネージャー動作ログ

```
セッション復帰後:
  authenticate
  get_next_action → report_model
  report_model
  get_next_action → start_task (tsk_xxx)  ← 即座にタスク開始指示
  update_task_status → in_progress
  get_next_action → start_task (tsk_yyy)
  update_task_status → in_progress
  get_next_action → exit (waiting_for_workers)
  logout
```

状況確認なし、レビューなし、判断なしで機械的に処理している。
