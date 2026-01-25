# パイロットテスト hello-world シナリオ TDD実装計画

## 概要

既存のweb-ui統合テスト基盤を活用し、hello-worldパイロットシナリオを実装する。
通常の統合テストとの主な違いは、**実際のAIエージェントが実際のLLMを使用して実際の開発作業を行う**点にある。

## 参照ドキュメント

- [パイロットテスト設計](../design/PILOT_TESTING.md)
- [hello-worldシナリオ](../../web-ui/e2e/pilot/scenarios/hello-world.md)
- [統合テストREADME](../../web-ui/e2e/integration/README.md)

## 既存インフラとの関係

### 再利用する部分

| コンポーネント | 既存パス | 用途 |
|--------------|---------|------|
| Playwrightインフラ | `playwright.integration.config.ts` | テスト実行基盤 |
| 環境セットアップ | `setup-integration-env.sh` のパターン | DB/サーバー起動 |
| テストパターン | `task-completion.spec.ts` | ログイン、UI操作 |
| ログ保持機構 | `run-uc001-test.sh` の cleanup 関数 | 失敗時の診断 |

### 新規作成が必要な部分

| コンポーネント | 目的 |
|--------------|------|
| パイロット専用Playwrightコンフィグ | 長時間タイムアウト、観察モード対応 |
| パイロット用シードSQL | 4エージェント構成（Owner, Manager, Worker-Dev, Worker-Review） |
| パイロットテストスペック | Owner役としてのUI操作、待機・観察ロジック |
| ランスクリプト | 作業ディレクトリ準備、成果物検証 |
| スタック検出ユーティリティ | 進捗監視、ループ検出 |

---

## フェーズ1: テスト基盤構築

### Phase 1.1: ディレクトリ構造作成

```bash
web-ui/e2e/pilot/
├── playwright.pilot.config.ts   # パイロット専用コンフィグ
├── scenarios/
│   └── hello-world.md           # （既存）シナリオ定義
├── setup/
│   └── seed-pilot-hello.sql     # パイロット用シードデータ
├── tests/
│   └── hello-world.spec.ts      # テストスペック
├── utils/
│   ├── pilot-helpers.ts         # パイロット用ヘルパー関数
│   └── progress-monitor.ts      # スタック・ループ検出
├── workspaces/
│   └── hello-world/             # 成果物出力先
└── run-pilot-hello.sh           # 実行スクリプト
```

### Phase 1.2: Playwrightコンフィグ（RED）

**ファイル**: `web-ui/e2e/pilot/playwright.pilot.config.ts`

```typescript
import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: './tests',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: 0, // パイロットはリトライしない
  workers: 1,
  reporter: [
    ['html', { outputFolder: '../../playwright-report-pilot' }],
    ['list'],
  ],
  // パイロットテストは最大60分
  timeout: 60 * 60 * 1000,
  use: {
    baseURL: process.env.PILOT_WEB_URL || 'http://localhost:5173',
    trace: 'on', // 常にトレース取得
    screenshot: 'on', // 常にスクリーンショット
    video: 'on', // 常にビデオ録画
    // スローモーション対応
    launchOptions: {
      slowMo: process.env.PILOT_SLOW_MO ? parseInt(process.env.PILOT_SLOW_MO) : 0,
    },
  },
  projects: [
    {
      name: 'pilot',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  // 外部で起動されるサービスを使用
})
```

**検証基準（RED状態）**:
- コンフィグファイルが存在する
- `npx playwright test --config=...` でコンフィグが読み込まれる

---

## フェーズ2: シードデータ定義

### Phase 2.1: パイロット用シードSQL（RED）

**ファイル**: `web-ui/e2e/pilot/setup/seed-pilot-hello.sql`

```sql
-- Pilot Test: hello-world scenario seed data
--
-- 注意: このシードは「前提条件」のみを作成する
-- 期待結果（タスク作成、ステータス変更など）は絶対にシードしない

-- Owner (human role - operated by test script)
INSERT OR REPLACE INTO agents (
    id, name, type, hierarchy_type,
    passkey, status, parent_id,
    created_at, updated_at
) VALUES (
    'pilot-owner', 'パイロットオーナー', 'human', 'owner',
    'pilot-passkey', 'active', NULL,
    datetime('now'), datetime('now')
);

-- Manager (AI - task management only)
INSERT OR REPLACE INTO agents (
    id, name, type, hierarchy_type,
    passkey, status, parent_id,
    ai_provider, ai_model, system_prompt,
    created_at, updated_at
) VALUES (
    'pilot-manager', '開発マネージャー', 'ai', 'manager',
    'pilot-passkey', 'active', 'pilot-owner',
    'anthropic', 'claude-sonnet-4-20250514',
    'あなたは開発マネージャーです。

## 責務
- Ownerからの要件を理解し、実行可能なタスクに分解する
- 各タスクを適切なWorkerに割り当てる
- タスク間の依存関係を設定する

## 行動指針
- タスクは1つの明確な成果物を持つ粒度に分解する
- 実装タスクと確認タスクは別のWorkerに割り当てる
- 自分自身で実装や確認作業は行わない（管理業務のみ）

## 利用可能なWorker
- pilot-worker-dev: 実装担当
- pilot-worker-review: 確認担当',
    datetime('now'), datetime('now')
);

-- Worker-Dev (AI - implementation)
INSERT OR REPLACE INTO agents (
    id, name, type, hierarchy_type,
    passkey, status, parent_id,
    ai_provider, ai_model, system_prompt,
    created_at, updated_at
) VALUES (
    'pilot-worker-dev', '開発エンジニア', 'ai', 'worker',
    'pilot-passkey', 'active', 'pilot-manager',
    'anthropic', 'claude-sonnet-4-20250514',
    'あなたは開発エンジニアです。

## 責務
- 割り当てられた実装タスクを遂行する
- コードを作成し、プロジェクトの作業ディレクトリに保存する
- 作業完了後、進捗を報告する

## 行動指針
- シンプルで読みやすいコードを書く
- ファイルは作業ディレクトリに保存する
- 完了したら必ずタスクのステータスを更新する',
    datetime('now'), datetime('now')
);

-- Worker-Review (AI - verification)
INSERT OR REPLACE INTO agents (
    id, name, type, hierarchy_type,
    passkey, status, parent_id,
    ai_provider, ai_model, system_prompt,
    created_at, updated_at
) VALUES (
    'pilot-worker-review', 'レビューエンジニア', 'ai', 'worker',
    'pilot-passkey', 'active', 'pilot-manager',
    'anthropic', 'claude-sonnet-4-20250514',
    'あなたはレビューエンジニアです。

## 責務
- 他のWorkerが作成した成果物を確認する
- 実際にコードを実行して動作を検証する
- 確認結果を報告する

## 行動指針
- 実装されたコードを実際に実行して確認する
- 期待通りの動作をするか検証する
- 問題があれば具体的に報告する',
    datetime('now'), datetime('now')
);

-- Pilot Project
INSERT OR REPLACE INTO projects (
    id, name, description, status,
    owner_id, workspace_path,
    created_at, updated_at
) VALUES (
    'pilot-hello', 'Hello World パイロット',
    'パイロットテスト: Hello Worldスクリプトの作成',
    'active',
    'pilot-owner', '/tmp/pilot_hello_workspace',
    datetime('now'), datetime('now')
);

-- Project-Agent assignments
INSERT OR REPLACE INTO project_agents (project_id, agent_id) VALUES
    ('pilot-hello', 'pilot-owner'),
    ('pilot-hello', 'pilot-manager'),
    ('pilot-hello', 'pilot-worker-dev'),
    ('pilot-hello', 'pilot-worker-review');
```

**検証基準（RED状態）**:
- SQLファイルがパースエラーなく実行できる
- 4エージェントがDBに登録される
- プロジェクトが作成される
- ※タスクは作成されていない（Managerが作成する）

---

## フェーズ3: ヘルパー関数実装

### Phase 3.1: パイロットヘルパー（RED）

**ファイル**: `web-ui/e2e/pilot/utils/pilot-helpers.ts`

```typescript
import { Page, expect } from '@playwright/test'

export interface PilotConfig {
  // タイムアウト設定（ミリ秒）
  scenarioTimeout: number      // シナリオ全体: 30-60分
  phaseTimeout: number         // 各フェーズ: 10-15分
  taskTimeout: number          // 単一タスク: 5-10分
  pollInterval: number         // ポーリング間隔: 5秒
  staleThreshold: number       // スタック判定: 5分
}

export const DEFAULT_PILOT_CONFIG: PilotConfig = {
  scenarioTimeout: 30 * 60 * 1000,   // 30分
  phaseTimeout: 10 * 60 * 1000,      // 10分
  taskTimeout: 5 * 60 * 1000,        // 5分
  pollInterval: 5 * 1000,            // 5秒
  staleThreshold: 5 * 60 * 1000,     // 5分
}

/**
 * Ownerとしてログイン
 */
export async function loginAsOwner(page: Page, agentId: string, passkey: string) {
  await page.goto('/login')
  await page.getByLabel('Agent ID').fill(agentId)
  await page.getByLabel('Passkey').fill(passkey)
  await page.getByRole('button', { name: 'Log in' }).click()
  await expect(page).toHaveURL('/projects')
}

/**
 * プロジェクトページに移動
 */
export async function navigateToProject(page: Page, projectId: string) {
  await page.goto(`/projects/${projectId}`)
  await expect(page.locator('[data-testid="task-board"]')).toBeVisible()
}

/**
 * Managerとのチャットを開始し、要件を送信
 */
export async function sendRequirementToManager(
  page: Page,
  managerId: string,
  message: string
) {
  // チャットパネルを開く
  await page.getByRole('button', { name: /chat|チャット/i }).click()

  // Manager選択（チャット相手）
  const chatPanel = page.locator('[data-testid="chat-panel"]')
  await expect(chatPanel).toBeVisible()

  // メッセージ送信
  await chatPanel.getByRole('textbox').fill(message)
  await chatPanel.getByRole('button', { name: /send|送信/i }).click()

  // 送信完了待機
  await expect(chatPanel.getByText(message)).toBeVisible()
}

/**
 * タスク完了を待機（進捗監視付き）
 */
export async function waitForAllTasksComplete(
  page: Page,
  config: PilotConfig = DEFAULT_PILOT_CONFIG
): Promise<{ success: boolean; tasks: TaskStatus[] }> {
  const startTime = Date.now()
  let lastProgressTime = Date.now()
  let previousTaskStates: string = ''

  while (Date.now() - startTime < config.scenarioTimeout) {
    // タスク状態取得
    const tasks = await getTaskStatuses(page)
    const currentStates = JSON.stringify(tasks)

    // 全タスク完了チェック
    const allDone = tasks.length > 0 && tasks.every(t => t.status === 'done')
    if (allDone) {
      return { success: true, tasks }
    }

    // 進捗チェック
    if (currentStates !== previousTaskStates) {
      lastProgressTime = Date.now()
      previousTaskStates = currentStates
      console.log(`[Progress] Tasks: ${tasks.map(t => `${t.title}:${t.status}`).join(', ')}`)
    }

    // スタック検出
    if (Date.now() - lastProgressTime > config.staleThreshold) {
      console.warn(`[Warning] No progress for ${config.staleThreshold / 1000}s`)
      // 継続判断：さらに待機するかどうか
    }

    await page.waitForTimeout(config.pollInterval)
  }

  return { success: false, tasks: await getTaskStatuses(page) }
}

interface TaskStatus {
  id: string
  title: string
  status: string
}

async function getTaskStatuses(page: Page): Promise<TaskStatus[]> {
  // タスクボードからタスク状態を取得
  const tasks: TaskStatus[] = []

  const taskCards = page.locator('[data-testid="task-card"]')
  const count = await taskCards.count()

  for (let i = 0; i < count; i++) {
    const card = taskCards.nth(i)
    const id = await card.getAttribute('data-task-id') || ''
    const title = await card.locator('[data-testid="task-title"]').textContent() || ''

    // 親カラムからステータス取得
    const column = card.locator('xpath=ancestor::*[@data-column]')
    const status = await column.getAttribute('data-column') || ''

    tasks.push({ id, title, status })
  }

  return tasks
}
```

### Phase 3.2: 進捗監視ユーティリティ（RED）

**ファイル**: `web-ui/e2e/pilot/utils/progress-monitor.ts`

```typescript
export interface ProgressEvent {
  timestamp: Date
  type: 'task_created' | 'status_change' | 'context_added' | 'chat_message'
  details: Record<string, unknown>
}

export class ProgressMonitor {
  private events: ProgressEvent[] = []
  private lastEventTime: Date = new Date()

  recordEvent(type: ProgressEvent['type'], details: Record<string, unknown>) {
    const event: ProgressEvent = {
      timestamp: new Date(),
      type,
      details,
    }
    this.events.push(event)
    this.lastEventTime = event.timestamp
    console.log(`[Monitor] ${type}: ${JSON.stringify(details)}`)
  }

  getTimeSinceLastEvent(): number {
    return Date.now() - this.lastEventTime.getTime()
  }

  /**
   * ループ検出：同一パターンの繰り返しを検出
   */
  detectLoop(windowSize: number = 5): boolean {
    if (this.events.length < windowSize * 2) {
      return false
    }

    const recent = this.events.slice(-windowSize)
    const previous = this.events.slice(-windowSize * 2, -windowSize)

    const recentPattern = recent.map(e => `${e.type}:${JSON.stringify(e.details)}`).join('|')
    const previousPattern = previous.map(e => `${e.type}:${JSON.stringify(e.details)}`).join('|')

    return recentPattern === previousPattern
  }

  /**
   * レポート生成
   */
  generateReport(): string {
    const lines: string[] = [
      '=== Progress Report ===',
      `Total events: ${this.events.length}`,
      `Duration: ${(Date.now() - this.events[0]?.timestamp.getTime()) / 1000}s`,
      '',
      '=== Event Timeline ===',
    ]

    for (const event of this.events) {
      lines.push(`[${event.timestamp.toISOString()}] ${event.type}: ${JSON.stringify(event.details)}`)
    }

    return lines.join('\n')
  }
}
```

---

## フェーズ4: テストスペック実装

### Phase 4.1: hello-worldテストスペック（RED）

**ファイル**: `web-ui/e2e/pilot/tests/hello-world.spec.ts`

```typescript
import { test, expect } from '@playwright/test'
import { execSync } from 'child_process'
import * as fs from 'fs'
import * as path from 'path'
import {
  loginAsOwner,
  navigateToProject,
  sendRequirementToManager,
  waitForAllTasksComplete,
  DEFAULT_PILOT_CONFIG,
  PilotConfig,
} from '../utils/pilot-helpers'
import { ProgressMonitor } from '../utils/progress-monitor'

/**
 * Pilot Test: hello-world scenario
 *
 * 実際のAIエージェントが実際のLLMを使用して
 * Hello Worldスクリプトを作成・検証するパイロットテスト
 *
 * Prerequisites:
 *   - Run: ./e2e/pilot/run-pilot-hello.sh
 *   - Coordinator must be running with real LLM access
 */

test.describe('Pilot: hello-world', () => {
  const PILOT_CONFIG: PilotConfig = {
    ...DEFAULT_PILOT_CONFIG,
    scenarioTimeout: 30 * 60 * 1000, // 30分
  }

  const CREDENTIALS = {
    agentId: 'pilot-owner',
    passkey: 'pilot-passkey',
  }

  const PROJECT_ID = 'pilot-hello'
  const WORKSPACE_PATH = '/tmp/pilot_hello_workspace'

  const REQUIREMENT_MESSAGE = `「Hello, World!」を出力するPythonスクリプト hello.py を作成してください。
作成後、実行して動作確認も行ってください。`

  let monitor: ProgressMonitor

  test.beforeAll(async () => {
    // 作業ディレクトリをクリーンアップ
    if (fs.existsSync(WORKSPACE_PATH)) {
      fs.rmSync(WORKSPACE_PATH, { recursive: true })
    }
    fs.mkdirSync(WORKSPACE_PATH, { recursive: true })
  })

  test.beforeEach(async () => {
    monitor = new ProgressMonitor()
  })

  test.afterEach(async () => {
    // 進捗レポート出力
    console.log(monitor.generateReport())
  })

  test('Phase 1: Environment verification', async ({ page }) => {
    // ログイン
    await loginAsOwner(page, CREDENTIALS.agentId, CREDENTIALS.passkey)

    // プロジェクト存在確認
    await expect(page.getByText('Hello World パイロット')).toBeVisible()

    // プロジェクトページへ移動
    await navigateToProject(page, PROJECT_ID)

    // 初期状態：タスクなし
    const taskCards = page.locator('[data-testid="task-card"]')
    expect(await taskCards.count()).toBe(0)
  })

  test('Phase 2: Send requirement to Manager', async ({ page }) => {
    await loginAsOwner(page, CREDENTIALS.agentId, CREDENTIALS.passkey)
    await navigateToProject(page, PROJECT_ID)

    // Managerに要件を送信
    await sendRequirementToManager(page, 'pilot-manager', REQUIREMENT_MESSAGE)

    monitor.recordEvent('chat_message', { to: 'pilot-manager', message: REQUIREMENT_MESSAGE })

    // メッセージ送信確認
    const chatPanel = page.locator('[data-testid="chat-panel"]')
    await expect(chatPanel.getByText(REQUIREMENT_MESSAGE)).toBeVisible()
  })

  test('Phase 3: Development progress (AI execution)', async ({ page }) => {
    // このテストはAIエージェントの実行を待機する
    test.setTimeout(PILOT_CONFIG.scenarioTimeout)

    // Skip if not in pilot environment
    test.skip(
      !process.env.PILOT_WITH_COORDINATOR,
      'Requires pilot environment with Coordinator and LLM access'
    )

    await loginAsOwner(page, CREDENTIALS.agentId, CREDENTIALS.passkey)
    await navigateToProject(page, PROJECT_ID)

    console.log('[Pilot] Waiting for AI agents to execute development tasks...')
    console.log('[Pilot] This may take 10-30 minutes')

    // 全タスク完了を待機
    const result = await waitForAllTasksComplete(page, PILOT_CONFIG)

    // 検証：タスクが作成されたか
    expect(result.tasks.length).toBeGreaterThanOrEqual(2)

    // 検証：全タスクがdoneか
    expect(result.success).toBe(true)

    for (const task of result.tasks) {
      monitor.recordEvent('status_change', { task: task.title, status: task.status })
    }
  })

  test('Phase 4: Verify deliverables', async ({ page }) => {
    // Skip if not in pilot environment
    test.skip(
      !process.env.PILOT_WITH_COORDINATOR,
      'Requires pilot environment with Coordinator and LLM access'
    )

    // 成果物ファイル存在確認
    const helloPath = path.join(WORKSPACE_PATH, 'hello.py')
    expect(fs.existsSync(helloPath)).toBe(true)

    // ファイル内容確認
    const content = fs.readFileSync(helloPath, 'utf-8')
    expect(content).toContain('print')
    expect(content.toLowerCase()).toContain('hello')

    // 実行確認
    const output = execSync(`python3 ${helloPath}`, { encoding: 'utf-8' })
    expect(output.trim()).toBe('Hello, World!')

    console.log('[Pilot] Deliverable verification passed!')
    console.log(`[Pilot] File: ${helloPath}`)
    console.log(`[Pilot] Output: ${output.trim()}`)
  })
})
```

---

## フェーズ5: 実行スクリプト

### Phase 5.1: ランスクリプト（RED）

**ファイル**: `web-ui/e2e/pilot/run-pilot-hello.sh`

```bash
#!/bin/bash
# Pilot Test: hello-world scenario
#
# 実際のAIエージェントがHello Worldスクリプトを作成するパイロットテスト
#
# フロー:
#   1. テスト環境準備
#   2. MCP + RESTサーバー起動
#   3. Coordinator起動（実LLM接続）
#   4. Web UI起動
#   5. Playwrightテスト実行
#   6. 成果物検証

set -e

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# パス設定
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_UI_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# パイロット設定
TEST_DB_PATH="/tmp/AIAgentPM_Pilot_Hello.db"
MCP_SOCKET_PATH="/tmp/aiagentpm_pilot_hello.sock"
REST_PORT="8085"
WEB_UI_PORT="5173"
WORKSPACE_PATH="/tmp/pilot_hello_workspace"

export MCP_COORDINATOR_TOKEN="pilot_coordinator_token_hello"

COORDINATOR_PID=""
MCP_PID=""
REST_PID=""
WEB_UI_PID=""
TEST_PASSED=false

cleanup() {
    echo ""
    echo -e "${YELLOW}Cleanup${NC}"

    [ -n "$WEB_UI_PID" ] && kill -0 "$WEB_UI_PID" 2>/dev/null && kill "$WEB_UI_PID" 2>/dev/null
    [ -n "$COORDINATOR_PID" ] && kill -0 "$COORDINATOR_PID" 2>/dev/null && kill "$COORDINATOR_PID" 2>/dev/null
    [ -n "$REST_PID" ] && kill -0 "$REST_PID" 2>/dev/null && kill "$REST_PID" 2>/dev/null
    [ -n "$MCP_PID" ] && kill -0 "$MCP_PID" 2>/dev/null && kill "$MCP_PID" 2>/dev/null

    rm -f "$MCP_SOCKET_PATH"

    if [ "$TEST_PASSED" == "true" ]; then
        echo -e "${GREEN}Cleaning up temporary files...${NC}"
        rm -f /tmp/pilot_hello_*.log
        rm -f /tmp/coordinator_pilot_hello_config.yaml
        rm -rf /tmp/coordinator_logs_pilot_hello
        rm -f "$TEST_DB_PATH" "$TEST_DB_PATH-shm" "$TEST_DB_PATH-wal"
    else
        echo -e "${YELLOW}Preserving logs for debugging:${NC}"
        echo "  - /tmp/pilot_hello_*.log"
        echo "  - $WORKSPACE_PATH"
    fi
}

trap cleanup EXIT

echo "=========================================="
echo -e "${BLUE}Pilot Test: hello-world${NC}"
echo -e "${BLUE}(Real AI agents creating Hello World)${NC}"
echo "=========================================="
echo ""
echo -e "${YELLOW}Note: This test uses real LLM API calls.${NC}"
echo -e "${YELLOW}      Estimated time: 10-30 minutes${NC}"
echo -e "${YELLOW}      API costs will be incurred.${NC}"
echo ""

# Step 1: 環境準備
echo -e "${YELLOW}Step 1: Preparing environment${NC}"
ps aux | grep -E "(mcp-server-pm|rest-server-pm)" | grep -v grep | awk '{print $2}' | xargs -I {} kill -9 {} 2>/dev/null || true
rm -f "$TEST_DB_PATH" "$TEST_DB_PATH-shm" "$TEST_DB_PATH-wal" "$MCP_SOCKET_PATH"
rm -rf "$WORKSPACE_PATH"
mkdir -p "$WORKSPACE_PATH"
echo "DB: $TEST_DB_PATH"
echo "Workspace: $WORKSPACE_PATH"
echo ""

# Step 2: ビルド確認
echo -e "${YELLOW}Step 2: Checking server binaries${NC}"
cd "$PROJECT_ROOT"

DERIVED_DATA_DIR=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 -name "AIAgentPM-*" -type d 2>/dev/null | head -1)
if [ -n "$DERIVED_DATA_DIR" ] && [ -x "$DERIVED_DATA_DIR/Build/Products/Debug/mcp-server-pm" ]; then
    MCP_SERVER_BIN="$DERIVED_DATA_DIR/Build/Products/Debug/mcp-server-pm"
    REST_SERVER_BIN="$DERIVED_DATA_DIR/Build/Products/Debug/rest-server-pm"
elif [ -x ".build/release/mcp-server-pm" ]; then
    MCP_SERVER_BIN=".build/release/mcp-server-pm"
    REST_SERVER_BIN=".build/release/rest-server-pm"
else
    echo -e "${YELLOW}Building servers...${NC}"
    swift build -c release --product mcp-server-pm 2>&1 | tail -2
    swift build -c release --product rest-server-pm 2>&1 | tail -2
    MCP_SERVER_BIN=".build/release/mcp-server-pm"
    REST_SERVER_BIN=".build/release/rest-server-pm"
fi
echo -e "${GREEN}✓ Server binaries ready${NC}"
echo ""

# Step 3: DB初期化
echo -e "${YELLOW}Step 3: Initializing database${NC}"
AIAGENTPM_DB_PATH="$TEST_DB_PATH" "$MCP_SERVER_BIN" daemon \
    --socket-path "$MCP_SOCKET_PATH" --foreground > /tmp/pilot_hello_mcp_init.log 2>&1 &
INIT_PID=$!
sleep 3
kill "$INIT_PID" 2>/dev/null || true
rm -f "$MCP_SOCKET_PATH"

SQL_FILE="$SCRIPT_DIR/setup/seed-pilot-hello.sql"
[ -f "$SQL_FILE" ] && sqlite3 "$TEST_DB_PATH" < "$SQL_FILE"
echo "Database initialized with pilot agents"
echo ""

# Step 4: サーバー起動
echo -e "${YELLOW}Step 4: Starting servers${NC}"

AIAGENTPM_DB_PATH="$TEST_DB_PATH" "$MCP_SERVER_BIN" daemon \
    --socket-path "$MCP_SOCKET_PATH" --foreground > /tmp/pilot_hello_mcp.log 2>&1 &
MCP_PID=$!

for i in {1..10}; do [ -S "$MCP_SOCKET_PATH" ] && break; sleep 0.5; done
echo -e "${GREEN}✓ MCP server running${NC}"

AIAGENTPM_DB_PATH="$TEST_DB_PATH" AIAGENTPM_WEBSERVER_PORT="$REST_PORT" \
    "$REST_SERVER_BIN" > /tmp/pilot_hello_rest.log 2>&1 &
REST_PID=$!

for i in {1..10}; do curl -s "http://localhost:$REST_PORT/health" > /dev/null 2>&1 && break; sleep 0.5; done
echo -e "${GREEN}✓ REST server running at :$REST_PORT${NC}"
echo ""

# Step 5: Coordinator起動
echo -e "${YELLOW}Step 5: Starting Coordinator (with real LLM)${NC}"

RUNNER_DIR="$PROJECT_ROOT/runner"
PYTHON="${RUNNER_DIR}/.venv/bin/python"
[ ! -x "$PYTHON" ] && PYTHON="python3"

# Coordinatorコンフィグ作成
cat > /tmp/coordinator_pilot_hello_config.yaml << EOF
polling_interval: 5
max_concurrent: 1
coordinator_token: ${MCP_COORDINATOR_TOKEN}
mcp_socket_path: $MCP_SOCKET_PATH
ai_providers:
  claude:
    cli_command: claude
    cli_args: ["--dangerously-skip-permissions", "--max-turns", "50"]
agents:
  pilot-manager:
    passkey: pilot-passkey
  pilot-worker-dev:
    passkey: pilot-passkey
  pilot-worker-review:
    passkey: pilot-passkey
log_directory: /tmp/coordinator_logs_pilot_hello
log_upload:
  enabled: true
work_directory: $WORKSPACE_PATH
EOF

mkdir -p /tmp/coordinator_logs_pilot_hello
AIAGENTPM_WEBSERVER_PORT="$REST_PORT" $PYTHON -m aiagent_runner --coordinator -c /tmp/coordinator_pilot_hello_config.yaml -v > /tmp/pilot_hello_coordinator.log 2>&1 &
COORDINATOR_PID=$!
sleep 2
echo -e "${GREEN}✓ Coordinator running (real LLM mode)${NC}"
echo ""

# Step 6: Web UI起動
echo -e "${YELLOW}Step 6: Starting Web UI${NC}"
cd "$WEB_UI_ROOT"

AIAGENTPM_WEBSERVER_PORT="$REST_PORT" npm run dev -- --port "$WEB_UI_PORT" > /tmp/pilot_hello_vite.log 2>&1 &
WEB_UI_PID=$!

for i in {1..20}; do curl -s "http://localhost:$WEB_UI_PORT" > /dev/null 2>&1 && break; sleep 1; done
echo -e "${GREEN}✓ Web UI running at :$WEB_UI_PORT${NC}"
echo ""

# Step 7: Playwrightテスト実行
echo -e "${YELLOW}Step 7: Running Playwright pilot test${NC}"
echo -e "${YELLOW}       (Waiting for AI agents to complete development)${NC}"
echo ""

PILOT_WEB_URL="http://localhost:$WEB_UI_PORT" \
PILOT_WITH_COORDINATOR="true" \
AIAGENTPM_WEBSERVER_PORT="$REST_PORT" \
npx playwright test \
    --config=e2e/pilot/playwright.pilot.config.ts \
    hello-world.spec.ts \
    2>&1 | tee /tmp/pilot_hello_playwright.log

echo ""

# Step 8: 成果物検証
echo -e "${YELLOW}Step 8: Verifying deliverables${NC}"
echo ""

# 成果物ファイル確認
HELLO_PY="$WORKSPACE_PATH/hello.py"
if [ -f "$HELLO_PY" ]; then
    echo -e "${GREEN}✓ hello.py exists${NC}"
    echo "Content:"
    cat "$HELLO_PY"
    echo ""

    # 実行確認
    echo "Execution:"
    OUTPUT=$(python3 "$HELLO_PY" 2>&1)
    echo "$OUTPUT"

    if [ "$OUTPUT" == "Hello, World!" ]; then
        echo -e "${GREEN}✓ Output is correct${NC}"
    else
        echo -e "${RED}✗ Output mismatch (expected: Hello, World!)${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ hello.py not found${NC}"
    exit 1
fi

echo ""

# Step 9: DB状態確認
echo -e "${YELLOW}Step 9: Checking final state${NC}"
echo "=== Tasks ==="
sqlite3 "$TEST_DB_PATH" "SELECT id, title, status FROM tasks WHERE project_id = 'pilot-hello';"
echo ""
echo "=== Contexts (latest 5) ==="
sqlite3 "$TEST_DB_PATH" "SELECT task_id, substr(content, 1, 50) FROM contexts ORDER BY created_at DESC LIMIT 5;"
echo ""

# 結果判定
if grep -qE "[0-9]+ passed" /tmp/pilot_hello_playwright.log && ! grep -qE "[0-9]+ failed" /tmp/pilot_hello_playwright.log; then
    TEST_PASSED=true
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Pilot Test hello-world: PASSED${NC}"
    echo -e "${GREEN}========================================${NC}"
    exit 0
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Pilot Test hello-world: FAILED${NC}"
    echo -e "${RED}========================================${NC}"
    echo "Logs preserved at: /tmp/pilot_hello_*.log"
    exit 1
fi
```

---

## フェーズ6: 成功基準チェックリスト

### テスト実行前（RED状態確認）

- [ ] `playwright.pilot.config.ts` が存在する
- [ ] `seed-pilot-hello.sql` が構文エラーなく実行できる
- [ ] `hello-world.spec.ts` がコンパイルエラーなし
- [ ] `run-pilot-hello.sh` が実行可能

### テスト実行後（GREEN状態確認）

- [ ] Phase 1: 環境確認テストがパス
- [ ] Phase 2: 要件送信テストがパス
- [ ] Phase 3: AIエージェントによるタスク作成・完了
- [ ] Phase 4: 成果物検証
  - [ ] `hello.py` が作成されている
  - [ ] `python3 hello.py` の出力が `Hello, World!`
- [ ] 全タスクが `done` ステータス

---

## 実装順序

1. **Day 1**: Phase 1.1-1.2（ディレクトリ構造、Playwrightコンフィグ）
2. **Day 2**: Phase 2.1（シードSQL）
3. **Day 3**: Phase 3.1-3.2（ヘルパー関数、進捗監視）
4. **Day 4**: Phase 4.1（テストスペック）
5. **Day 5**: Phase 5.1（ランスクリプト）、統合テスト実行

---

## 注意事項

1. **LLM API費用**: パイロットテストは実際のLLM APIを使用するため、費用が発生する
2. **実行時間**: 10-30分程度を想定、スタック検出で無限ループを回避
3. **ネットワーク**: LLM API接続が必要
4. **APIキー**: Coordinatorに正しいAPIキーが設定されていること
5. **作業ディレクトリ**: `/tmp/pilot_hello_workspace` が書き込み可能であること
