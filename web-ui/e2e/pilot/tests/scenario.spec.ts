/**
 * Scenario Test Runner - 汎用シナリオ実行
 *
 * シナリオディレクトリの flow.ts を読み込み、フェーズを順次実行
 *
 * 使用方法:
 *   PILOT_SCENARIO=hello-world PILOT_VARIATION=baseline npx playwright test pilot/tests/scenario.spec.ts
 */

import { test, expect } from '@playwright/test'
import * as path from 'path'
import * as fs from 'fs'
import { fileURLToPath } from 'url'
import { VariationLoader } from '../lib/variation-loader.js'
import { ResultRecorder, aggregateAgentStats } from '../lib/result-recorder.js'
import { PhaseContext, PhaseResult, ScenarioFlow } from '../lib/flow-types.js'
import { ScenarioConfig, VariationConfig, TaskResult } from '../lib/types.js'
import { execSync } from 'child_process'

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

test.describe(`Scenario: ${SCENARIO} / ${VARIATION}`, () => {
  test.setTimeout(scenarioConfig.timeouts.task_completion * 1000 + 300_000)

  test.beforeAll(async () => {
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
    copyMCPLogsForDebug()
    console.log(`Results saved to: ${recorder.getResultsDir()}`)
  })

  test('Execute scenario flow', async ({ page }) => {
    // フロー定義を動的にインポート
    const flowPath = path.join(BASE_DIR, 'scenarios', SCENARIO, 'flow.ts')
    if (!fs.existsSync(flowPath)) {
      throw new Error(`Flow definition not found: ${flowPath}`)
    }

    const flowModule = await import(flowPath)
    const flow: ScenarioFlow = flowModule.default

    // コンテキストを作成
    const baseUrl = process.env.INTEGRATION_WEB_URL || 'http://localhost:5173'
    const ctx: PhaseContext = {
      page,
      scenario: scenarioConfig,
      variation: variationConfig,
      recorder,
      baseUrl,
      shared: {},
    }

    // フェーズメトリクス
    const phaseMetrics: { phase: string; duration_ms: number; success: boolean }[] = []

    // フェーズを順次実行
    for (const phase of flow.phases) {
      const startTime = Date.now()
      console.log(`\n⏱️  [${phase.name}] 開始...`)

      let result: PhaseResult
      try {
        result = await phase.execute(ctx)
      } catch (error) {
        const duration = Date.now() - startTime
        phaseMetrics.push({ phase: phase.name, duration_ms: duration, success: false })
        console.log(`❌ [${phase.name}] 失敗 (${(duration / 1000).toFixed(1)}秒)`)
        throw error
      }

      const duration = Date.now() - startTime
      phaseMetrics.push({ phase: phase.name, duration_ms: duration, success: result.success })

      if (result.success) {
        console.log(`✅ [${phase.name}] 完了 (${(duration / 1000).toFixed(1)}秒)`)
      } else {
        console.log(`❌ [${phase.name}] 失敗 (${(duration / 1000).toFixed(1)}秒): ${result.message}`)
        // 失敗しても続行するフェーズもある（タイムアウトなど）
      }
    }

    // パフォーマンスレポート表示
    printPerformanceReport(phaseMetrics)

    recorder.recordEvent('performance_report', {
      phases: phaseMetrics,
      total_duration_ms: phaseMetrics.reduce((sum, p) => sum + p.duration_ms, 0),
    })

    // 結果を記録
    const tasks = await fetchTaskStates()
    const agentStats = aggregateAgentStats(recorder['events'])

    const artifactResults = (ctx.shared.artifactResults || ctx.shared.testResults || []) as Array<{
      path: string
      exists: boolean
      validation_passed: boolean
      all_tests_passed?: boolean
    }>
    const reportResult = ctx.shared.reportResult as { all_passed: boolean } | undefined

    const allSuccess =
      phaseMetrics.every((p) => p.success) &&
      artifactResults.every((a) => a.exists && (a.all_tests_passed ?? a.validation_passed))

    const result = recorder.saveResult({
      success: allSuccess,
      artifacts: artifactResults,
      tasks,
      agents: agentStats,
      observations: 'Flow completed',
    })

    expect(result.outcome.success).toBe(true)
  })

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

  function copyMCPLogsForDebug() {
    const appSupportDir = path.join(process.env.HOME || '', 'Library/Application Support/AIAgentPM')
    const resultsDir = recorder.getResultsDir()
    const debugLogsDir = path.join(resultsDir, 'debug-logs')

    try {
      fs.mkdirSync(debugLogsDir, { recursive: true })
      const logFiles = ['mcp-daemon.log', 'mcp.log', 'rest-server.log']
      for (const logFile of logFiles) {
        const srcPath = path.join(appSupportDir, logFile)
        if (fs.existsSync(srcPath)) {
          const destPath = path.join(debugLogsDir, logFile)
          fs.copyFileSync(srcPath, destPath)
        }
      }
    } catch {
      // ignore
    }
  }

  async function fetchTaskStates(): Promise<TaskResult[]> {
    const projectId = scenarioConfig.project.id
    const dbPath = '/tmp/AIAgentPM_Pilot.db'

    try {
      const result = execSync(
        `sqlite3 -json "${dbPath}" "SELECT id, title, status, assignee_id, created_at FROM tasks WHERE project_id = '${projectId}'"`,
        { encoding: 'utf8' }
      )

      if (!result.trim()) return []

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
