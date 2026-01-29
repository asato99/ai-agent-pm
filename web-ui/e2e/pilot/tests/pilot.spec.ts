/**
 * Pilot Test - Variation-based System Prompt Testing
 *
 * シナリオ・バリエーションを切り替えてAIエージェントの振る舞いを検証
 *
 * 使用方法:
 *   PILOT_SCENARIO=hello-world PILOT_VARIATION=baseline npx playwright test pilot/tests/pilot.spec.ts
 *   または
 *   ./pilot/run-pilot.sh -v explicit-flow
 */

import { test, expect, Page } from '@playwright/test'
import * as path from 'path'
import * as fs from 'fs'
import { execSync } from 'child_process'
import { fileURLToPath } from 'url'
import { VariationLoader } from '../lib/variation-loader.js'
import { ResultRecorder, aggregateAgentStats } from '../lib/result-recorder.js'
import { ScenarioConfig, VariationConfig, TaskResult, ArtifactTest, ArtifactResult } from '../lib/types.js'

// ES module で __dirname を取得
const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

// 環境変数から設定を取得
const SCENARIO = process.env.PILOT_SCENARIO || 'hello-world'
const VARIATION = process.env.PILOT_VARIATION || 'baseline'
const BASE_DIR = process.env.PILOT_BASE_DIR || path.join(__dirname, '..')

// 設定読み込み
const loader = new VariationLoader(BASE_DIR)
let scenarioConfig: ScenarioConfig
let variationConfig: VariationConfig

try {
  const config = loader.load(SCENARIO, VARIATION)
  scenarioConfig = config.scenario
  variationConfig = config.variation
} catch (error) {
  console.error(`Failed to load configuration: ${error}`)
  process.exit(1)
}

// ResultRecorder インスタンス
const recorder = new ResultRecorder(SCENARIO, VARIATION, BASE_DIR)

test.describe(`Pilot Test: ${SCENARIO} / ${VARIATION}`, () => {
  // テストタイムアウトをシナリオ設定に合わせる
  // task_completion (1800s) + バッファ (5分) = 約35分
  test.setTimeout(scenarioConfig.timeouts.task_completion * 1000 + 300_000)

  test.beforeAll(async () => {
    // 結果ディレクトリを初期化
    recorder.initialize()
    recorder.recordEvent('test_started', {
      scenario: SCENARIO,
      variation: VARIATION,
      config: {
        scenario_name: scenarioConfig.name,
        variation_name: variationConfig.name,
        agents: Object.keys(variationConfig.agents),
      },
    })
  })

  test.afterAll(async () => {
    // MCPログをデバッグ用にコピー
    copyMCPLogsForDebug()
    console.log(`Results saved to: ${recorder.getResultsDir()}`)
  })

  /**
   * メインテスト: シナリオの初期アクションから成果物生成までの全フローを検証
   */
  test('Full scenario execution', async ({ page }) => {
    // フェーズごとのパフォーマンス測定
    const phaseMetrics: { phase: string; duration_ms: number; success: boolean }[] = []

    async function measurePhase<T>(phaseName: string, fn: () => Promise<T>): Promise<T> {
      const startTime = Date.now()
      console.log(`\n⏱️  [${phaseName}] 開始...`)
      try {
        const result = await fn()
        const duration = Date.now() - startTime
        phaseMetrics.push({ phase: phaseName, duration_ms: duration, success: true })
        console.log(`✅ [${phaseName}] 完了 (${(duration / 1000).toFixed(1)}秒)`)
        return result
      } catch (error) {
        const duration = Date.now() - startTime
        phaseMetrics.push({ phase: phaseName, duration_ms: duration, success: false })
        console.log(`❌ [${phaseName}] 失敗 (${(duration / 1000).toFixed(1)}秒)`)
        throw error
      }
    }

    // Phase 1: 前提条件の検証
    await measurePhase('前提条件検証', () => verifyPrerequisites(page))

    // Phase 2: 初期アクションを実行（Human → Manager へのチャット送信）
    await measurePhase('初期アクション送信', () => executeInitialAction(page))

    // Phase 3: タスク作成を待機
    await measurePhase('タスク作成待機', () => waitForTaskCreation(page))

    // Phase 4: オーナーがタスクのステータスを更新（backlog → todo → in_progress）
    await measurePhase('ステータス更新 (todo)', () => updateTaskStatusByOwner(page, 'todo'))
    await measurePhase('ステータス更新 (in_progress)', () => updateTaskStatusByOwner(page, 'in_progress'))

    // Phase 5: タスク完了を待機
    await measurePhase('タスク完了待機', () => waitForTaskCompletion(page))

    // Phase 6: 成果物を検証
    const artifactResults = await measurePhase('成果物検証', () => verifyArtifacts())

    // Phase 7: 成果物を実行テスト
    const { testResults, allPassed: artifactTestsPassed } = await measurePhase(
      '成果物テスト実行',
      () => testArtifacts()
    )

    // 結果を記録
    const tasks = await fetchTaskStates()
    const agentStats = aggregateAgentStats(recorder['events'])

    // パフォーマンスレポートを生成・表示
    printPerformanceReport(phaseMetrics)

    // フェーズメトリクスをイベントとして記録
    recorder.recordEvent('performance_report', {
      phases: phaseMetrics,
      total_duration_ms: phaseMetrics.reduce((sum, p) => sum + p.duration_ms, 0),
    })

    const result = recorder.saveResult({
      success: artifactResults.every((a) => a.exists && a.validation_passed) && artifactTestsPassed,
      artifacts: artifactResults,
      tasks,
      agents: agentStats,
      observations: 'Full flow completed',
    })

    // テスト結果を検証
    expect(result.outcome.success).toBe(true)
    expect(artifactTestsPassed).toBe(true)
  })

  /**
   * パフォーマンスレポートを表示
   */
  function printPerformanceReport(metrics: { phase: string; duration_ms: number; success: boolean }[]) {
    const totalDuration = metrics.reduce((sum, p) => sum + p.duration_ms, 0)

    function getDisplayWidth(str: string): number {
      let width = 0
      for (const char of str) {
        width += /[\u3000-\u9fff\uff00-\uffef]/.test(char) ? 2 : 1
      }
      return width
    }

    function padEndDisplay(str: string, targetWidth: number): string {
      const currentWidth = getDisplayWidth(str)
      const padding = Math.max(0, targetWidth - currentWidth)
      return str + ' '.repeat(padding)
    }

    console.log('\n')
    console.log('┌' + '─'.repeat(68) + '┐')
    console.log('│' + ' '.repeat(20) + '📊 Performance Report' + ' '.repeat(27) + '│')
    console.log('├' + '─'.repeat(68) + '┤')
    console.log('│  Phase                                            Duration   Status │')
    console.log('├' + '─'.repeat(68) + '┤')

    for (const metric of metrics) {
      const phaseName = padEndDisplay(metric.phase, 45)
      const duration = `${(metric.duration_ms / 1000).toFixed(1)}s`.padStart(8)
      const status = metric.success ? '✅' : '❌'
      console.log(`│  ${phaseName}${duration}     ${status}  │`)
    }

    console.log('├' + '─'.repeat(68) + '┤')
    const totalStr = `${(totalDuration / 1000).toFixed(1)}s`.padStart(8)
    console.log(`│  ${padEndDisplay('TOTAL', 45)}${totalStr}         │`)
    console.log('└' + '─'.repeat(68) + '┘')
    console.log('\n')
  }

  // ============ Helper Functions ============

  /**
   * 前提条件の検証: エージェントとプロジェクトが正しくセットアップされているか
   */
  async function verifyPrerequisites(page: Page) {
    const credentials = variationConfig.credentials
    const owner = Object.values(variationConfig.agents).find(
      (a) => a.hierarchy_type === 'owner'
    )

    if (!owner) {
      throw new Error('No owner agent defined in variation')
    }

    // ログイン
    const baseUrl = process.env.INTEGRATION_WEB_URL || 'http://localhost:5173'
    await page.goto(`${baseUrl}/login`)
    await page.getByLabel('Agent ID').fill(owner.id)
    await page.getByLabel('Passkey').fill(credentials.passkey)
    await page.getByRole('button', { name: 'Log in' }).click()

    // プロジェクト一覧にリダイレクト
    await expect(page).toHaveURL(`${baseUrl}/projects`)

    // プロジェクトが表示されることを確認
    const projectName = scenarioConfig.project.name
    await expect(page.getByText(projectName)).toBeVisible()

    recorder.recordEvent('prerequisites_verified', {
      owner: owner.id,
      project: scenarioConfig.project.id,
    })
  }

  /**
   * 初期アクションを実行: チャットでManagerにメッセージを送信
   */
  async function executeInitialAction(page: Page) {
    const action = scenarioConfig.initial_action
    const project = scenarioConfig.project
    const baseUrl = process.env.INTEGRATION_WEB_URL || 'http://localhost:5173'

    // プロジェクトに移動
    await page.goto(`${baseUrl}/projects/${project.id}`)

    // Managerのアバターをクリックしてチャットを開く
    const managerAvatar = page.locator(`[data-testid="agent-avatar-${action.to}"]`)
    await expect(managerAvatar).toBeVisible({ timeout: 10_000 })
    await managerAvatar.click()

    // チャットパネルが表示されるのを待機
    const chatPanel = page.getByTestId('chat-panel')
    await expect(chatPanel).toBeVisible()

    // セッション準備完了を待機
    const sendButton = page.getByTestId('chat-send-button')
    console.log('Waiting for chat session to be ready...')
    await expect(sendButton).toHaveText('送信', { timeout: 180_000 })
    console.log('Chat session is ready')

    // メッセージを送信
    const chatInput = page.getByTestId('chat-input')
    await chatInput.fill(action.message)
    await sendButton.click()

    // メッセージが送信されたことを確認
    await expect(chatPanel.getByText(action.message)).toBeVisible({ timeout: 5_000 })

    recorder.recordEvent('initial_action_sent', {
      from: action.from,
      to: action.to,
      message: action.message,
    })

    console.log(`Sent initial message: "${action.message}"`)
  }

  /**
   * タスク作成を待機
   */
  async function waitForTaskCreation(page: Page) {
    const timeout = scenarioConfig.timeouts.task_creation * 1000
    const startTime = Date.now()
    const pollInterval = 5_000

    console.log(`Waiting for task creation (timeout: ${timeout / 1000}s)...`)

    while (Date.now() - startTime < timeout) {
      // タスクボードでタスクを確認
      const tasks = await fetchTaskStates()

      // タスクが1つでも存在すれば「作成済み」とみなす
      if (tasks.length > 0) {
        recorder.recordEvent('tasks_created', {
          count: tasks.length,
          tasks: tasks.map((t) => ({ id: t.id, title: t.title, status: t.status })),
        })
        console.log(`Tasks created: ${tasks.length}`)
        return
      }

      await page.waitForTimeout(pollInterval)
    }

    throw new Error(`Task creation timeout after ${timeout / 1000}s`)
  }

  /**
   * オーナーがタスクのステータスを更新
   * 現状の仕様では、マネージャーが作成したタスクはbacklog状態のため、
   * オーナーが手動でステータスを更新して作業を開始させる必要がある
   */
  async function updateTaskStatusByOwner(page: Page, targetStatus: 'todo' | 'in_progress') {
    console.log(`Updating task status to ${targetStatus}...`)

    // タスクカードをクリックして詳細ダイアログを開く
    const taskCard = page.locator('[data-testid="task-card"]').first()
    await taskCard.click()
    await page.waitForTimeout(1000) // ダイアログが開くのを待つ

    // ダイアログ内のステータスセレクトボックスを操作
    const dialog = page.getByRole('dialog')
    const statusSelect = dialog.getByRole('combobox')

    // selectOptionを使ってステータスを変更
    await statusSelect.selectOption(targetStatus)

    await page.waitForTimeout(1000) // 更新を待つ

    // ダイアログを閉じる
    await dialog.getByRole('button', { name: 'Close' }).first().click()
    await page.waitForTimeout(500)

    recorder.recordEvent('task_status_updated', {
      target_status: targetStatus,
      updated_by: 'owner',
    })
    console.log(`Task status updated to ${targetStatus}`)
  }

  /**
   * タスク完了を待機
   */
  async function waitForTaskCompletion(page: Page) {
    const timeout = scenarioConfig.timeouts.task_completion * 1000
    const startTime = Date.now()
    const pollInterval = 10_000

    console.log(`Waiting for task completion (timeout: ${timeout / 1000}s)...`)

    while (Date.now() - startTime < timeout) {
      const tasks = await fetchTaskStates()
      const pendingTasks = tasks.filter(
        (t) => t.status !== 'done' && t.status !== 'cancelled'
      )

      console.log(
        `Task status: ${tasks.length} total, ${pendingTasks.length} pending (${Math.round((Date.now() - startTime) / 1000)}s elapsed)`
      )

      // ステータス変化をイベントとして記録
      for (const task of tasks) {
        recorder.recordEvent('task_status_check', {
          task_id: task.id,
          title: task.title,
          status: task.status,
        })
      }

      if (pendingTasks.length === 0 && tasks.length > 0) {
        recorder.recordEvent('all_tasks_completed', {
          tasks: tasks.map((t) => ({ id: t.id, title: t.title, status: t.status })),
        })
        console.log('All tasks completed!')
        return
      }

      await page.waitForTimeout(pollInterval)
    }

    // タイムアウトしても続行（結果に記録される）
    console.warn(`Task completion timeout after ${timeout / 1000}s`)
    recorder.recordEvent('task_completion_timeout', {
      elapsed_seconds: timeout / 1000,
    })
  }

  /**
   * 成果物を検証
   */
  async function verifyArtifacts() {
    const artifacts = scenarioConfig.expected_artifacts
    const workingDir = scenarioConfig.project.working_directory

    const results = artifacts.map((artifact) => {
      const fullPath = path.join(workingDir, artifact.path)
      return recorder.validateArtifact(fullPath, artifact.validation)
    })

    recorder.recordEvent('artifacts_verified', {
      results: results.map((r) => ({
        path: r.path,
        exists: r.exists,
        validation_passed: r.validation_passed,
      })),
    })

    return results
  }

  /**
   * 成果物を実行テスト
   */
  async function testArtifacts() {
    const artifacts = scenarioConfig.expected_artifacts
    const workingDir = scenarioConfig.project.working_directory
    const allResults: ArtifactResult[] = []

    console.log('\n' + '='.repeat(60))
    console.log('🧪 成果物テスト実行')
    console.log('='.repeat(60))

    for (const artifact of artifacts) {
      const fullPath = path.join(workingDir, artifact.path)

      // 新形式 (tests 配列) または旧形式 (test オブジェクト) を処理
      if (artifact.tests && artifact.tests.length > 0) {
        // 新形式: 複数テスト
        console.log(`\n📄 ${artifact.path}: (${artifact.tests.length} テスト)`)

        const testResults = recorder.runArtifactTests(fullPath, artifact.tests)
        const allTestsPassed = testResults.every((r) => r.passed)

        for (const result of testResults) {
          const statusIcon = result.passed ? '✅' : '❌'
          console.log(`   ${statusIcon} ${result.name}`)
          console.log(`      コマンド: ${result.command}`)
          console.log(`      終了コード: ${result.exit_code} (期待: ${result.expected_exit_code})`)
          if (result.stdout) {
            console.log(`      stdout: "${result.stdout.slice(0, 100)}${result.stdout.length > 100 ? '...' : ''}"`)
          }
          if (result.stderr) {
            console.log(`      stderr: "${result.stderr.slice(0, 100)}${result.stderr.length > 100 ? '...' : ''}"`)
          }
        }

        allResults.push({
          path: artifact.path,
          exists: fs.existsSync(fullPath),
          validation_passed: true,
          test_results: testResults,
          all_tests_passed: allTestsPassed,
        })
      } else if (artifact.test) {
        // 旧形式: 単一テスト (後方互換)
        console.log(`\n📄 ${artifact.path}:`)
        console.log(`   コマンド: ${artifact.test.command.replace('{path}', fullPath)}`)

        const testResult = recorder.testArtifact(
          fullPath,
          artifact.test.command,
          artifact.test.expected_output
        )

        const passed = testResult.passed
        console.log(`   終了コード: ${testResult.exit_code}`)
        console.log(`   標準出力: "${testResult.stdout}"`)
        if (testResult.stderr) {
          console.log(`   標準エラー: "${testResult.stderr}"`)
        }
        if (testResult.expected_output) {
          console.log(`   期待出力: "${testResult.expected_output}"`)
        }
        console.log(`   結果: ${passed ? '✅ PASS' : '❌ FAIL'}`)

        allResults.push({
          path: artifact.path,
          exists: fs.existsSync(fullPath),
          validation_passed: true,
          test_results: [testResult],
          all_tests_passed: passed,
        })
      } else {
        console.log(`\n📄 ${artifact.path}: テスト設定なし（スキップ）`)
        allResults.push({
          path: artifact.path,
          exists: fs.existsSync(fullPath),
          validation_passed: true,
          all_tests_passed: true, // テストなしは成功扱い
        })
      }
    }

    console.log('\n' + '='.repeat(60))
    const allPassed = allResults.every((r) => r.all_tests_passed)
    console.log(`🧪 成果物テスト結果: ${allPassed ? '✅ ALL PASSED' : '❌ SOME FAILED'}`)
    console.log('='.repeat(60) + '\n')

    recorder.recordEvent('artifacts_tested', { results: allResults, all_passed: allPassed })

    return { testResults: allResults, allPassed }
  }

  /**
   * MCPログをデバッグ用に結果ディレクトリにコピー
   */
  function copyMCPLogsForDebug() {
    const appSupportDir = path.join(
      process.env.HOME || '',
      'Library/Application Support/AIAgentPM'
    )
    const resultsDir = recorder.getResultsDir()
    const debugLogsDir = path.join(resultsDir, 'debug-logs')

    try {
      fs.mkdirSync(debugLogsDir, { recursive: true })

      // MCPログファイルをコピー
      const logFiles = ['mcp-daemon.log', 'mcp.log', 'rest-server.log']
      for (const logFile of logFiles) {
        const srcPath = path.join(appSupportDir, logFile)
        if (fs.existsSync(srcPath)) {
          const destPath = path.join(debugLogsDir, logFile)
          fs.copyFileSync(srcPath, destPath)
          console.log(`📋 Copied ${logFile} to debug-logs/`)
        }
      }

      // 最新のMCP構造化ログもコピー（存在する場合）
      const logDir = path.join(appSupportDir, 'logs')
      if (fs.existsSync(logDir)) {
        const files = fs.readdirSync(logDir).filter(f => f.endsWith('.log'))
        for (const file of files.slice(-5)) { // 最新5ファイルまで
          const srcPath = path.join(logDir, file)
          const destPath = path.join(debugLogsDir, file)
          fs.copyFileSync(srcPath, destPath)
        }
        console.log(`📋 Copied ${Math.min(files.length, 5)} structured log files to debug-logs/`)
      }
    } catch (error) {
      console.warn(`⚠️ Failed to copy MCP logs: ${error}`)
    }
  }

  /**
   * データベースからタスク状態を取得
   */
  async function fetchTaskStates(): Promise<TaskResult[]> {
    const projectId = scenarioConfig.project.id
    // パイロットテスト用のDB
    const dbPath = '/tmp/AIAgentPM_Pilot.db'

    // sqlite3コマンドで直接クエリ
    try {
      const result = execSync(
        `sqlite3 -json "${dbPath}" "SELECT id, title, status, assignee_id, created_at FROM tasks WHERE project_id = '${projectId}'"`,
        { encoding: 'utf8' }
      )

      if (!result.trim()) {
        return []
      }

      const rows = JSON.parse(result)
      return rows.map((row: { id: string; title: string; status: string; assignee_id: string; created_at: string }) => ({
        id: row.id,
        title: row.title,
        status: row.status,
        created_at: row.created_at,
        assignee_id: row.assignee_id,
      }))
    } catch {
      return []
    }
  }
})
