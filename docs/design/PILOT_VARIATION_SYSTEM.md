# パイロットテスト バリエーション管理システム 設計書

## 概要

システムプロンプトやエージェント構成の変化が結果に与える影響を観察するための仕組み。

## 目的

1. **実験の容易さ**: コマンド一つでバリエーションを切り替え
2. **再現性**: 同じ設定で同じ実験を再実行可能
3. **比較可能性**: 結果を構造化して記録し、バリエーション間で比較
4. **バージョン管理**: 設定ファイルを Git で管理

## ディレクトリ構造

```
web-ui/e2e/pilot/
├── scenarios/
│   └── hello-world/
│       ├── scenario.yaml           # シナリオ定義（共通）
│       ├── test.spec.ts            # Playwright テスト
│       └── variations/
│           ├── baseline.yaml       # 基準構成
│           ├── explicit-flow.yaml  # 明示的フロー指示版
│           └── minimal-prompt.yaml # 最小プロンプト版
│
├── results/                        # 実行結果（.gitignore）
│   └── hello-world/
│       └── 2026-01-25T12-00-00_baseline/
│           ├── result.yaml         # 結果サマリー
│           ├── events.json         # 詳細イベントログ
│           └── agent-logs/         # 各エージェントのログ
│
├── lib/
│   ├── variation-loader.ts         # バリエーション読み込み
│   ├── seed-generator.ts           # SQL生成
│   └── result-recorder.ts          # 結果記録
│
└── run-pilot.sh                    # 統合実行スクリプト
```

## 設定ファイルスキーマ

### scenario.yaml（シナリオ定義）

```yaml
name: hello-world
description: "Hello World スクリプト作成"
version: "1.0"

# 共通設定
project:
  id: pilot-hello
  name: "Hello World パイロット"
  working_directory: /tmp/pilot_hello_workspace

# 期待する成果物
expected_artifacts:
  - path: hello.py
    validation: |
      python3 {path} | grep -q "Hello, World!"

# タイムアウト設定
timeouts:
  task_creation: 600    # タスク作成待ち（秒）
  task_completion: 1800 # 全タスク完了待ち（秒）

# 初期アクション（テストスクリプトが実行）
initial_action:
  type: chat
  from: pilot-owner
  to: pilot-manager
  message: |
    「Hello, World!」を出力するPythonスクリプト hello.py を作成してください。
    作業ディレクトリに保存し、動作確認まで行ってください。
```

### variation.yaml（バリエーション定義）

```yaml
name: baseline
description: "基準構成 - 製品デフォルトのワークフローに依存"
version: "1.0"

# エージェント定義
agents:
  owner:
    id: pilot-owner
    name: パイロットオーナー
    role: Project Owner
    type: human
    hierarchy_type: owner
    # human はシステムプロンプト不要

  manager:
    id: pilot-manager
    name: 開発マネージャー
    role: Development Manager
    type: ai
    hierarchy_type: manager
    parent_agent_id: pilot-owner
    capabilities: ["management"]
    system_prompt: |
      あなたは開発マネージャーです。

      ## 行動原則
      1. get_next_action を呼び出して次のアクションを確認
      2. 指示に従ってツールを実行
      3. 完了後は再度 get_next_action を呼び出す

      ## 禁止事項
      - 自己判断でのタスク作成（get_next_action の指示なしに）
      - ワーカーへの直接指示（タスク経由で指示）

  worker-dev:
    id: pilot-worker-dev
    name: 開発エンジニア
    role: Developer
    type: ai
    hierarchy_type: worker
    parent_agent_id: pilot-manager
    capabilities: ["coding"]
    system_prompt: |
      あなたは開発エンジニアです。

      ## 行動原則
      1. get_next_action で割り当てられたタスクを確認
      2. タスクの指示に従って実装
      3. 完了後は update_task_status で done に変更
      4. get_next_action で次のアクションを確認

  worker-review:
    id: pilot-worker-review
    name: レビューエンジニア
    role: Reviewer
    type: ai
    hierarchy_type: worker
    parent_agent_id: pilot-manager
    capabilities: ["testing"]
    system_prompt: |
      あなたはレビューエンジニアです。

      ## 行動原則
      1. get_next_action で割り当てられたタスクを確認
      2. 成果物を実際に実行して検証
      3. 完了後は update_task_status で done に変更

# 認証情報
credentials:
  passkey: test-passkey  # 全エージェント共通（テスト用）
```

### result.yaml（結果記録）

```yaml
scenario: hello-world
variation: baseline
run_id: "2026-01-25T12-00-00"
started_at: "2026-01-25T12:00:00Z"
finished_at: "2026-01-25T12:15:30Z"
duration_seconds: 930

# 結果サマリー
outcome:
  success: true
  artifacts_created:
    - path: hello.py
      validation_passed: true
      content_hash: "sha256:abc123..."

# タスク統計
tasks:
  total_created: 5
  completed: 5
  failed: 0
  final_states:
    - id: tsk_xxx
      title: "hello.pyの作成"
      status: done
      duration_seconds: 120

# エージェント統計
agents:
  pilot-manager:
    spawned_count: 2
    total_turns: 15
    tools_called:
      - name: get_next_action
        count: 8
      - name: create_task
        count: 2
  pilot-worker-dev:
    spawned_count: 1
    total_turns: 10

# 観察メモ（手動追記用）
observations: |
  - Manager が get_next_action を正しく使用
  - タスク作成から in_progress への遷移がスムーズ

# 問題点（手動追記用）
issues: []
```

## 実行フロー

### 1. 実行コマンド

```bash
# 基本実行
./run-pilot.sh hello-world --variation baseline

# 複数バリエーションを連続実行
./run-pilot.sh hello-world --variation baseline,explicit-flow,minimal-prompt

# 結果比較レポート生成
./run-pilot.sh --compare hello-world/2026-01-25T12-00-00_baseline \
                          hello-world/2026-01-25T12-05-00_explicit-flow
```

### 2. 実行スクリプト処理フロー

```
1. バリエーション設定読み込み
2. シナリオ設定読み込み
3. seed SQL 動的生成
4. データベース初期化
5. サーバー起動（MCP, REST, Coordinator）
6. Playwright テスト実行
7. 結果収集・記録
8. クリーンアップ
```

### 3. seed SQL 動的生成

`lib/seed-generator.ts`:

```typescript
interface Agent {
  id: string;
  name: string;
  role: string;
  type: 'human' | 'ai';
  hierarchy_type: 'owner' | 'manager' | 'worker';
  parent_agent_id?: string;
  capabilities?: string[];
  system_prompt?: string;
}

function generateSeedSQL(
  scenario: ScenarioConfig,
  variation: VariationConfig
): string {
  const agents = variation.agents;
  const project = scenario.project;

  return `
-- Auto-generated seed for: ${scenario.name} / ${variation.name}
-- Generated at: ${new Date().toISOString()}

-- Cleanup
DELETE FROM tasks WHERE project_id = '${project.id}';
DELETE FROM agent_sessions WHERE agent_id IN (${agentIds});
DELETE FROM agent_credentials WHERE agent_id IN (${agentIds});
DELETE FROM agents WHERE id IN (${agentIds});
DELETE FROM project_agents WHERE project_id = '${project.id}';
DELETE FROM projects WHERE id = '${project.id}';

-- Agents
${generateAgentInserts(agents)}

-- Credentials
${generateCredentialInserts(agents, variation.credentials.passkey)}

-- Project
INSERT INTO projects (id, name, description, status, working_directory, created_at, updated_at)
VALUES ('${project.id}', '${project.name}', '', 'active', '${project.working_directory}',
        datetime('now'), datetime('now'));

-- Project-Agent assignments
${generateProjectAgentInserts(project.id, agents)}
`;
}
```

## 比較レポート

### 出力例

```
================================================================================
PILOT TEST COMPARISON REPORT
================================================================================

Scenario: hello-world
Compared variations: baseline vs explicit-flow

--------------------------------------------------------------------------------
SUMMARY
--------------------------------------------------------------------------------
                          baseline        explicit-flow
Success                   ✓               ✓
Duration                  930s            720s            (-22%)
Tasks Created             5               4
Manager Spawns            2               1               (-50%)
Manager Turns             15              8               (-47%)

--------------------------------------------------------------------------------
KEY DIFFERENCES
--------------------------------------------------------------------------------

1. Task Creation Flow
   - baseline: Manager created tasks via REST API (backlog status)
   - explicit-flow: Manager used MCP create_task (todo status)

2. Status Transitions
   - baseline: Manual intervention needed for in_progress
   - explicit-flow: Automatic via get_next_action workflow

--------------------------------------------------------------------------------
OBSERVATIONS
--------------------------------------------------------------------------------

explicit-flow variation shows:
- Faster completion time
- Fewer manager spawns (more efficient)
- Correct workflow adherence

Recommendation: Use explicit-flow as new baseline
```

## 実装計画

### Phase 1: 基盤構築
1. ディレクトリ構造作成
2. 設定ファイルスキーマ定義（TypeScript types）
3. バリエーション読み込みライブラリ
4. seed SQL 生成ライブラリ

### Phase 2: 実行基盤
5. 統合実行スクリプト（run-pilot.sh）
6. 結果記録ライブラリ
7. イベント収集機構

### Phase 3: 分析ツール
8. 比較レポート生成
9. 結果可視化（オプション）

## 今後の拡張

- Web UI での実験管理
- 自動回帰テスト（新しいコードで過去の実験を再実行）
- A/B テスト的な統計比較
