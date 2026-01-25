# Pilot Test Framework

AIエージェントのシステムプロンプトや構成の変更が結果に与える影響を観察するためのテストフレームワーク。

## 概要

バリエーション（variation）を切り替えることで、異なるシステムプロンプトやエージェント構成でテストを実行し、結果を比較できます。

## ディレクトリ構造

```
pilot/
├── scenarios/                    # シナリオ定義
│   └── hello-world/             # シナリオ名
│       ├── scenario.yaml        # シナリオ設定
│       └── variations/          # バリエーション
│           ├── baseline.yaml    # ベースライン構成
│           └── explicit-flow.yaml # 明示的フロー指示版
├── lib/                         # ライブラリ
│   ├── types.ts                # 型定義
│   ├── variation-loader.ts     # 設定ファイルローダー
│   ├── seed-generator.ts       # シードSQL生成
│   ├── result-recorder.ts      # 結果記録
│   └── report-generator.ts     # 比較レポート生成
├── tests/                       # Playwrightテスト
│   └── pilot.spec.ts           # メインテスト
├── results/                     # 実行結果（自動生成）
├── reports/                     # 比較レポート（自動生成）
├── generated/                   # 生成ファイル（シードSQL等）
├── run-pilot.sh                # 単一バリエーション実行
└── compare-variations.sh       # 複数バリエーション比較
```

## 使用方法

### 単一バリエーションの実行

```bash
# デフォルト（baseline）で実行
./run-pilot.sh

# 特定のバリエーションで実行
./run-pilot.sh -v explicit-flow

# サーバー起動をスキップ（すでに起動している場合）
./run-pilot.sh --skip-server -v explicit-flow
```

### 複数バリエーションの比較

```bash
# 全バリエーションを比較
./compare-variations.sh --all

# 特定のバリエーションを比較
./compare-variations.sh -v baseline,explicit-flow
```

### バリエーション一覧の確認

```bash
npx ts-node lib/variation-loader.ts
```

## シナリオ定義

### scenario.yaml

シナリオ全体の設定を定義します。バリエーション間で共通です。

```yaml
name: hello-world
description: "Hello World プログラム作成"
version: "1.0"

project:
  id: pilot-project
  name: Pilot Test Project
  working_directory: /tmp/pilot-test

expected_artifacts:
  - path: hello.py
    validation: python {path}

timeouts:
  task_creation: 120   # 秒
  task_completion: 300 # 秒

initial_action:
  type: chat
  from: pilot-owner
  to: pilot-manager
  message: "「Hello, World!」と出力するPythonプログラムを作成してください"
```

### variation.yaml

システムプロンプトやエージェント構成のバリエーションを定義します。

```yaml
name: explicit-flow
description: "明示的フロー指示"
version: "1.0"

agents:
  manager:
    id: pilot-manager
    name: 開発マネージャー
    role: Development Manager
    type: ai
    hierarchy_type: manager
    system_prompt: |
      あなたは開発マネージャーです。
      必ず get_next_action に従ってください。
      ...

credentials:
  passkey: test-passkey
```

## 結果の確認

### 実行結果

各実行の結果は `results/{scenario}/{run-id}_{variation}/` に保存されます:

- `result.yaml` / `result.json`: 最終結果
- `events.jsonl`: イベントログ
- `agent-logs/`: エージェントログのコピー

### 比較レポート

複数バリエーションの比較結果は `reports/` に保存されます:

- `comparison-{scenario}-{timestamp}.yaml`: 詳細レポート
- `comparison-{scenario}-{timestamp}.md`: Markdown形式サマリー

## バリエーション追加

1. `scenarios/{scenario}/variations/` に新しいYAMLファイルを作成
2. `agents` セクションでエージェント構成とシステムプロンプトを定義
3. `./run-pilot.sh -v {新バリエーション名}` で実行

## ドキュメント

| ドキュメント | 内容 |
|-------------|------|
| `docs/design/PILOT_VARIATION_SYSTEM.md` | 設計詳細 |
| `docs/LOG_STRATEGY.md` | **ログ確認戦略・デバッグ手順** |

### テスト失敗時のデバッグ

テストが失敗した場合は、**必ず `docs/LOG_STRATEGY.md` の手順に従って調査**してください。

特に重要なポイント:
1. `error-context.md` を最優先で確認（UIの実際の状態が記録されている）
2. ログの「成功」メッセージを鵜呑みにしない
3. DBの直接確認で残存データをチェック
