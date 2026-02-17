---
name: project-docs
description: >
  プロジェクトドキュメント管理スキル。project_docs/ ディレクトリの構成・ライフサイクル・命名規則を定義する。
  ドキュメントの新規作成、参照、編集、ライフサイクル遷移（active → stable → archive）を管理する。
  以下の場面で自動適用する:
  (1) 設計書・計画書・調査報告・ガイドなどのドキュメントを作成する時
  (2) project_docs/ 内のファイルを参照・編集する時
  (3) ドキュメントのライフサイクル遷移（アーカイブ等）を行う時
  (4) ドキュメントの配置先を判断する時
  (5) レビュー結果・バグ報告・検証結果などの報告ドキュメントを作成する時
---

# Project Docs

プロジェクトドキュメントの管理規則。配置・命名・ライフサイクルを定義する。

## ディレクトリ構成

```
project_docs/
├── designs/            # 機能設計書
│   ├── active/         # 実装前〜実装中
│   ├── stable/         # 実装完了、今後の参考になる
│   └── archive/        # 大幅改修で陳腐化
├── plans/              # 実装計画・フェーズ計画
│   ├── active/         # 進行中
│   └── archive/        # 完了
├── reports/            # ワークフロー上の報告（レビュー・バグ・検証）
│   ├── active/         # 未対応・対応中
│   └── archive/        # 対応完了
├── issues/             # 問題の記録・追跡
│   ├── active/         # 未解決
│   └── archive/        # 解決済み
├── investigations/     # 技術調査・深掘り分析
│   ├── active/         # 調査中
│   ├── stable/         # 解決済み、再発時に参照
│   └── archive/        # 完全に過去の調査
├── guides/             # 運用ガイド・手順書
│   ├── active/         # 頻繁に参照
│   └── stable/         # たまに参照
└── references/         # 技術参考資料
    ├── active/         # 頻繁に参照
    └── stable/         # たまに参照
```

## カテゴリ定義

| カテゴリ | 用途 | issues との違い |
|---------|------|----------------|
| designs | 機能の設計書。実装前に作成し、実装の指針とする | - |
| plans | 実装計画。タスク分解とフェーズ管理 | - |
| reports | ワークフロー上の報告。レビュー結果・バグ報告・検証結果など、フェーズゲートで確認される | フェーズに紐づく公式な報告 |
| issues | 問題の記録・追跡。何が起き、どう対応したかの簡潔な記録 | アドホックな事実と対応の記録 |
| investigations | 技術的な深掘り分析。仮説検証・原因究明の過程を含む | 分析過程と技術的知見 |
| guides | 運用ガイド・手順書。繰り返し参照する手続き的な知識 | - |
| references | 技術参考資料。アーキテクチャ比較、技術選定の根拠など | - |

## ライフサイクル

### 状態の定義

| 状態 | 意味 |
|------|------|
| active | 現在作業中、または日常的に参照する |
| stable | 完了済みだが今後も参照する可能性がある |
| archive | 役目を終えた、ほぼ参照しない |

### カテゴリ別の遷移ルール

```
designs:        active → stable（実装完了時） → archive（大幅改修で陳腐化時）
plans:          active → archive（全タスク完了時）
reports:        active → archive（承認完了時）
issues:         active → archive（問題解決時）
investigations: active → stable（解決済み、再発可能性あり） → archive（完全解決）
guides:         active ⇄ stable（参照頻度の変化で双方向移動）
references:     active ⇄ stable（参照頻度の変化で双方向移動）
```

- plans, reports, issues は完了=用済みのため stable なし
- guides, references は陳腐化したら内容を更新するか削除。archive なし

### 遷移の判断基準

**active → stable**:
- designs: 実装が完了しコミット済み
- investigations: 問題は解決したが、類似問題で再参照する価値がある
- guides/references: 参照頻度が低下したが、内容は有効

**stable → archive**:
- designs: 後続の設計書で置き換えられた、または機能が大幅に変更された
- investigations: 根本的に異なるアーキテクチャになり、知見が適用不能

**active → archive**（stable を経由しない）:
- plans: 全タスクが完了
- reports: マネージャーが承認し、対応が完了
- issues: 問題が解決

## ドキュメント作成

### 命名規則

`<短い説明>.md`（ケバブケース）

```
# Good
v2-exercise-part-navigation-design.md
uitest-completion-flow-timeout.md
sampler-latency-measurement-plan.md
cart-api-review.md
cart-api-bug.md
cart-api-verification.md

# Bad
EXERCISE_PART_NAVIGATION_DESIGN.md   # SCREAMING_SNAKE は避ける
design.md                             # 内容不明
2024-01-15-investigation.md           # 日付でなく内容で命名
```

### 作成時のルール

1. カテゴリを判断し、適切なディレクトリに配置する
2. 新規ドキュメントは必ず `active/` に作成する
3. 同カテゴリの既存ドキュメントをテンプレートとして参照する

### カテゴリ判断の指針

| 作業内容 | カテゴリ |
|---------|---------|
| 新機能の仕様を決める | designs |
| 実装のタスク分解・順序を決める | plans |
| レビュー結果・バグ報告・検証結果を残す | reports |
| バグや不具合を記録する | issues |
| 原因不明の問題を分析する | investigations |
| 繰り返し使う手順をまとめる | guides |
| 技術選定の根拠や比較をまとめる | references |

## 報告ドキュメント（reports）

### 種別

| 種別 | 用途 | 命名例 |
|------|------|--------|
| review | 計画に対するレビュー結果 | `cart-api-review.md` |
| bug | 検証で発見した不具合 | `cart-api-bug.md` |
| verification | QA検証の結果 | `cart-api-verification.md` |

### ドキュメント構造

```markdown
# <タイトル>

- 種別: review | bug | verification
- 対象: <関連する計画・成果物へのパス>
- 報告者: <役割>
- 判定: APPROVED | CHANGES_REQUESTED

## 指摘事項

### 1. <指摘タイトル>
- 対象箇所: <計画のステップ / ファイル / コンポーネント>
- 内容: <具体的な不整合・問題>
- 状態: open | resolved
```

### ハンドオフプロトコル

報告ドキュメントは、報告者とマネージャーの間のハンドオフに使う。

```
1. 報告者が reports/active/ に報告を作成する
2. マネージャーがフェーズゲートで reports/active/ を確認する
3. APPROVED → マネージャーが archive/ へ遷移する
4. CHANGES_REQUESTED → マネージャーがワーカーに修正を指示する
5. 修正後、報告者が同じドキュメントの指摘事項を更新する（open → resolved）
6. 全指摘が resolved → 報告者が判定を APPROVED に更新する
7. 2 に戻る
```

- 報告者はドキュメントの作成と更新を行う。フェーズ遷移の判断はしない
- マネージャーは報告を確認しフェーズ遷移を判断する。報告の内容は編集しない

## ドキュメント参照

### 検索の優先順位

1. `active/` を最初に検索する
2. 見つからなければ `stable/` を検索する
3. `archive/` は明示的に過去の経緯を調べる場合のみ

### 参照時の注意

- `stable/` のドキュメントは内容が現状と乖離している可能性がある
- `archive/` のドキュメントは歴史的参考としてのみ扱う
- 頻繁に参照する `stable/` は `active/` への昇格を検討する

## ドキュメント編集

### 編集可能な状態

| 状態 | 内容の編集 | ライフサイクル遷移 |
|------|-----------|------------------|
| active | 自由に編集可 | stable or archive へ遷移可 |
| stable | 軽微な修正のみ（誤字、リンク修正等） | active へ昇格 or archive へ遷移可 |
| archive | 編集不可 | 必要なら active にコピーして新版を作成 |

### 大幅な更新が必要な場合

stable のドキュメントに大幅な更新が必要な場合:
1. active に移動する
2. 内容を更新する
3. 完了後に stable に戻す
