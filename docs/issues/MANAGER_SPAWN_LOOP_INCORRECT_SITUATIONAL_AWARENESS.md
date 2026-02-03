# マネージャーのスポーンループ：状況認識の不正確さ

## 概要

パイロットテスト（weather-app-complete / specialist-team）において、マネージャーが短い間隔でスポーンと退出を繰り返す問題が発生した。根本原因は `situational_awareness` 状態でのサマリー情報が実際のシステム状態と乖離していることにある。

## 発生状況

- **シナリオ**: weather-app-complete
- **バリエーション**: specialist-team
- **日時**: 2026-02-03 20:25-20:28頃
- **ログ**: `web-ui/e2e/pilot/results/weather-app-complete/2026-02-03T19-48-54_specialist-team/logs/mcp-server.log`

## 症状

マネージャーが7-11秒間隔で連続して認証を繰り返す:

```
20:25:17 → 20:25:24 → 20:25:35 → 20:25:42 → 20:26:01 → 20:26:12 → 20:27:31
   (7秒)    (11秒)    (7秒)    (19秒)    (11秒)    (79秒)
```

## スポーンループのパターン

```
1. マネージャーが situational_awareness 状態になる
2. サマリーに基づいて select_action で wait を選択
3. waiting_for_workers 状態になり、logout を指示される
4. Coordinator が再スポーン
5. → 1に戻る（無限ループ）
```

## 根本原因：サマリーと実態の乖離

### ログの証拠（20:25:25）

```json
{
  "summary": {
    "in_progress_tasks": 0,      // ← 0と報告
    "completed_tasks": 5,
    "unassigned_tasks": 3,
    "executable_tasks": 0,       // ← 実行可能タスクなし
    "total_tasks": 8
  }
}
```

### 同時刻のDB実態

```sql
-- 実際には3つのタスクが in_progress
tsk_9b82dbc1-34b | in_progress | manager-dev
tsk_74f02d5a-70f | in_progress | worker-programmer-01
tsk_eb9f91db-204 | in_progress | worker-programmer-01
```

### マネージャーの誤った判断

サマリーでは `in_progress_tasks: 0` なのに、マネージャーは以下の理由で `wait` を選択:

```
"reason": "プログラマー1が基本機能実装中。他のタスクは依存関係により待機中のため、完了を待ちます"
```

**問題点**:
1. サマリーは `in_progress: 0` と報告しているのに、マネージャーは「作業中」と判断
2. `unassigned_tasks: 3` があるのに `dispatch_task` を選択しない
3. `executable_tasks: 0` になっている（依存関係で実行不可）

## 原因分析

### 仮説1: サマリー計算のスコープ問題

`situational_awareness` のサマリーが**マネージャー直下のサブタスクのみ**を対象にしている可能性:

```
親タスク (tsk_9b82dbc1-34b) - manager-dev
├── 子タスク (tsk_74f02d5a-70f) - worker-programmer-01, in_progress
│   └── 孫タスク (tsk_d4917095-272) - worker-programmer-01, in_progress  ← サマリーに含まれない?
└── 子タスク (tsk_d9652306-c45) - todo
```

孫タスクが `in_progress` でも、サマリーでは「子タスクレベルの in_progress」しかカウントしていない可能性。

### 仮説2: タイミング問題

タスクステータスの更新とサマリー計算のタイミングにズレがあり、一時的に不整合な状態が報告されている。

### 仮説3: 依存関係の計算問題

`executable_tasks: 0` になる原因:
- 未割り当てタスクはあるが、すべてに未完了の依存関係がある
- 依存関係のチェーン:

```
tsk_74f02d5a-70f (基本機能) - in_progress
    ↓ 依存
tsk_d9652306-c45 (雨雲レーダー) - todo, 実行不可
    ↓ 依存
tsk_cf778abd-54d (検証) - todo, 実行不可
```

## 依存関係の詳細

```
tsk_74f02d5a-70f (実装フェーズ：基本機能とUI実装)
  - status: in_progress
  - assignee: worker-programmer-01
  - depends on: tsk_285ea231-d06 (done)

tsk_d9652306-c45 (実装フェーズ：雨雲レーダー機能実装)
  - status: todo
  - assignee: worker-programmer-02
  - depends on: tsk_74f02d5a-70f (in_progress) ← 実行不可

tsk_cf778abd-54d (検証フェーズ：機能テストと品質確認)
  - status: todo
  - assignee: worker-qa-01
  - depends on: tsk_d9652306-c45 (todo) ← 実行不可
```

## 影響

1. **リソースの無駄遣い**: マネージャーが7-11秒ごとにスポーン
2. **APIコストの増加**: 認証・get_next_action の繰り返し呼び出し
3. **テストの遅延**: 本来の作業に時間を使えない
4. **Coordinator の負荷**: 不要な再スポーン処理

## 提案する対策

### 短期（サマリー情報の改善）

1. **孫タスクを含めたサマリー計算**:
   - `in_progress_tasks` は子タスク以下すべてを再帰的にカウント
   - または、Workerが実際に作業中かどうかを `agent_sessions` で判定

2. **`executable_tasks` の明確化**:
   - なぜ executable でないかの理由を含める
   - 「依存関係: tsk_xxx の完了待ち」

### 中期（waiting_for_workers の改善）

1. **即座のlogout指示を廃止**:
   - `waiting_for_workers` 状態でもマネージャーを維持
   - 定期的に状況をポーリングさせる

2. **Coordinator側での待機時間制御**:
   - Workerが作業中の間は再スポーンしない
   - `agent_sessions` を確認して判断

### 長期（状況認識の抜本的改善）

1. **リアルタイム状況追跡**:
   - Workerのセッション状態をマネージャーに公開
   - 「誰が何をしているか」の正確な把握

2. **サマリー計算ロジックの統一**:
   - どのレベルのタスクをカウントするか明確に定義
   - 一貫した計算方法をドキュメント化

## 関連ファイル

- `Sources/MCPServer/MCPServer.swift` - getManagerNextAction, situational_awareness サマリー計算
- `Sources/Coordinator/` - マネージャー再スポーンロジック
- `docs/design/MANAGER_STATE_MACHINE_V2.md` - マネージャーステートマシン設計

## 関連Issue

- [マネージャーがadjust状態で重複タスクを作成する問題](./MANAGER_DUPLICATE_TASK_CREATION_IN_ADJUST.md)

## 検証方法

1. パイロットテストを再実行
2. マネージャーの認証ログ間隔を監視
3. サマリー情報とDB実態の一致を確認

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
