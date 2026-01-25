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
import { VariationLoader } from '../lib/variation-loader.js'
import { ResultRecorder, aggregateAgentStats } from '../lib/result-recorder.js'
import { ScenarioConfig, VariationConfig, TaskResult } from '../lib/types.js'

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
  test.setTimeout(300_000) // 5分

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
    console.log(`Results saved to: ${recorder.getResultsDir()}`)
  })

  /**
   * メインテスト: シナリオの初期アクションから成果物生成までの全フローを検証
   */
  test('Full scenario execution', async ({ page }) => {
    // 前提条件の検証
    await verifyPrerequisites(page)

    // 初期アクションを実行（Human → Manager へのチャット送信）
    await executeInitialAction(page)

    // タスク作成を待機
    await waitForTaskCreation(page)

    // タスク完了を待機
    await waitForTaskCompletion(page)

    // 成果物を検証
    const artifactResults = await verifyArtifacts()

    // 結果を記録
    const tasks = await fetchTaskStates()
    const agentStats = aggregateAgentStats(recorder['events'])

    const result = recorder.saveResult({
      success: artifactResults.every((a) => a.exists && a.validation_passed),
      artifacts: artifactResults,
      tasks,
      agents: agentStats,
      observations: 'Full flow completed',
    })

    // テスト結果を検証
    expect(result.outcome.success).toBe(true)
  })

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
    await page.goto('/login')
    await page.getByLabel('Agent ID').fill(owner.id)
    await page.getByLabel('Passkey').fill(credentials.passkey)
    await page.getByRole('button', { name: 'Log in' }).click()

    // プロジェクト一覧にリダイレクト
    await expect(page).toHaveURL('/projects')

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

    // プロジェクトに移動
    await page.goto(`/projects/${project.id}`)

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
    await expect(sendButton).toHaveText('送信', { timeout: 120_000 })
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
      const createdTasks = tasks.filter((t) => t.status !== 'backlog')

      if (createdTasks.length > 0) {
        recorder.recordEvent('tasks_created', {
          count: createdTasks.length,
          tasks: createdTasks.map((t) => ({ id: t.task_id, title: t.title, status: t.status })),
        })
        console.log(`Tasks created: ${createdTasks.length}`)
        return
      }

      await page.waitForTimeout(pollInterval)
    }

    throw new Error(`Task creation timeout after ${timeout / 1000}s`)
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
          task_id: task.task_id,
          title: task.title,
          status: task.status,
        })
      }

      if (pendingTasks.length === 0 && tasks.length > 0) {
        recorder.recordEvent('all_tasks_completed', {
          tasks: tasks.map((t) => ({ id: t.task_id, title: t.title, status: t.status })),
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
   * データベースからタスク状態を取得
   */
  async function fetchTaskStates(): Promise<TaskResult[]> {
    const projectId = scenarioConfig.project.id
    const dbPath = path.join(BASE_DIR, '../../..', 'data/test.db')

    // sqlite3コマンドで直接クエリ
    const { execSync } = require('child_process')
    try {
      const result = execSync(
        `sqlite3 -json "${dbPath}" "SELECT id, title, status, assigned_to FROM tasks WHERE project_id = '${projectId}'"`,
        { encoding: 'utf8' }
      )

      if (!result.trim()) {
        return []
      }

      const rows = JSON.parse(result)
      return rows.map((row: { id: string; title: string; status: string; assigned_to: string }) => ({
        task_id: row.id,
        title: row.title,
        status: row.status as 'backlog' | 'todo' | 'in_progress' | 'done' | 'cancelled',
        assigned_to: row.assigned_to,
      }))
    } catch {
      return []
    }
  }
})
