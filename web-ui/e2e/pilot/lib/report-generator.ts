/**
 * Report Generator
 *
 * バリエーション間の比較レポートを生成
 */

import * as fs from 'fs'
import * as path from 'path'
import * as yaml from 'js-yaml'
import { fileURLToPath } from 'url'
import { PilotResult } from './types.js'

const __filename_report = fileURLToPath(import.meta.url)
const __dirname_report = path.dirname(__filename_report)

export interface ComparisonReport {
  generated_at: string
  scenario: string
  variations_compared: string[]
  summary: {
    best_performer: string
    success_rate: Record<string, number>
    avg_duration: Record<string, number>
  }
  detailed_comparison: {
    outcome: Record<string, { success: boolean; failure_reason?: string }>
    tasks: Record<string, { created: number; completed: number; failed: number }>
    agents: Record<string, Record<string, { spawned: number; turns: number }>>
    artifacts: Record<string, { exists: boolean; validated: boolean }[]>
  }
  observations: string[]
  recommendations: string[]
}

/**
 * 結果ディレクトリから最新の結果を読み込む
 */
export function loadLatestResults(
  baseDir: string,
  scenario: string
): Record<string, PilotResult> {
  const resultsDir = path.join(baseDir, 'results', scenario)

  if (!fs.existsSync(resultsDir)) {
    return {}
  }

  const results: Record<string, PilotResult> = {}
  const runDirs = fs.readdirSync(resultsDir)

  // バリエーションごとに最新の結果を取得
  const latestByVariation: Record<string, string> = {}

  for (const runDir of runDirs) {
    const match = runDir.match(/^(.+)_(.+)$/)
    if (match) {
      const [, runId, variation] = match
      if (!latestByVariation[variation] || runId > latestByVariation[variation]) {
        latestByVariation[variation] = runDir
      }
    }
  }

  // 各バリエーションの最新結果を読み込む
  for (const [variation, runDir] of Object.entries(latestByVariation)) {
    const resultPath = path.join(resultsDir, runDir, 'result.json')
    if (fs.existsSync(resultPath)) {
      const content = fs.readFileSync(resultPath, 'utf8')
      results[variation] = JSON.parse(content) as PilotResult
    }
  }

  return results
}

/**
 * 比較レポートを生成
 */
export function generateComparisonReport(
  results: Record<string, PilotResult>,
  scenario: string
): ComparisonReport {
  const variations = Object.keys(results)

  // 成功率を計算
  const successRate: Record<string, number> = {}
  const avgDuration: Record<string, number> = {}

  for (const [variation, result] of Object.entries(results)) {
    successRate[variation] = result.outcome.success ? 1.0 : 0.0
    avgDuration[variation] = result.duration_seconds
  }

  // ベストパフォーマーを特定
  const successfulVariations = variations.filter((v) => results[v].outcome.success)
  let bestPerformer = 'none'

  if (successfulVariations.length > 0) {
    // 成功した中で最も短時間のものをベストとする
    bestPerformer = successfulVariations.reduce((best, current) =>
      avgDuration[current] < avgDuration[best] ? current : best
    )
  }

  // 詳細比較
  const outcome: Record<string, { success: boolean; failure_reason?: string }> = {}
  const tasks: Record<string, { created: number; completed: number; failed: number }> = {}
  const agents: Record<string, Record<string, { spawned: number; turns: number }>> = {}
  const artifacts: Record<string, { exists: boolean; validated: boolean }[]> = {}

  for (const [variation, result] of Object.entries(results)) {
    outcome[variation] = {
      success: result.outcome.success,
      failure_reason: result.outcome.failure_reason,
    }

    tasks[variation] = {
      created: result.tasks.total_created,
      completed: result.tasks.completed,
      failed: result.tasks.failed,
    }

    agents[variation] = {}
    for (const [agentId, agentResult] of Object.entries(result.agents)) {
      agents[variation][agentId] = {
        spawned: agentResult.spawned_count,
        turns: agentResult.total_turns,
      }
    }

    artifacts[variation] = result.outcome.artifacts.map((a) => ({
      exists: a.exists,
      validated: a.validation_passed,
    }))
  }

  // 観察事項を生成
  const observations: string[] = []

  if (successfulVariations.length === 0) {
    observations.push('All variations failed to complete successfully.')
  } else if (successfulVariations.length === variations.length) {
    observations.push('All variations completed successfully.')
  } else {
    observations.push(
      `Partial success: ${successfulVariations.join(', ')} succeeded, ` +
        `${variations.filter((v) => !results[v].outcome.success).join(', ')} failed.`
    )
  }

  // タスク作成数の比較
  const taskCounts = variations.map((v) => tasks[v].created)
  const minTasks = Math.min(...taskCounts)
  const maxTasks = Math.max(...taskCounts)
  if (minTasks !== maxTasks) {
    observations.push(
      `Task creation varies: min ${minTasks}, max ${maxTasks} tasks.`
    )
  }

  // 所要時間の比較
  const durations = variations.map((v) => avgDuration[v])
  const minDuration = Math.min(...durations)
  const maxDuration = Math.max(...durations)
  if (maxDuration > minDuration * 1.5) {
    observations.push(
      `Significant duration difference: ${Math.round(minDuration)}s to ${Math.round(maxDuration)}s.`
    )
  }

  // 推奨事項を生成
  const recommendations: string[] = []

  if (bestPerformer !== 'none') {
    recommendations.push(`Consider using '${bestPerformer}' as the default variation.`)
  }

  const failedVariations = variations.filter((v) => !results[v].outcome.success)
  for (const failed of failedVariations) {
    const reason = results[failed].outcome.failure_reason || 'Unknown'
    recommendations.push(
      `Investigate '${failed}' failure: ${reason}`
    )
  }

  return {
    generated_at: new Date().toISOString(),
    scenario,
    variations_compared: variations,
    summary: {
      best_performer: bestPerformer,
      success_rate: successRate,
      avg_duration: avgDuration,
    },
    detailed_comparison: {
      outcome,
      tasks,
      agents,
      artifacts,
    },
    observations,
    recommendations,
  }
}

/**
 * レポートをファイルに保存
 */
export function saveReport(report: ComparisonReport, baseDir: string): string {
  const reportsDir = path.join(baseDir, 'reports')
  fs.mkdirSync(reportsDir, { recursive: true })

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)
  const filename = `comparison-${report.scenario}-${timestamp}`

  // YAML形式
  const yamlPath = path.join(reportsDir, `${filename}.yaml`)
  fs.writeFileSync(yamlPath, yaml.dump(report, { lineWidth: -1 }))

  // Markdown形式
  const mdPath = path.join(reportsDir, `${filename}.md`)
  fs.writeFileSync(mdPath, generateMarkdownReport(report))

  return reportsDir
}

/**
 * Markdown形式のレポートを生成
 */
function generateMarkdownReport(report: ComparisonReport): string {
  const lines: string[] = [
    `# Pilot Test Comparison Report`,
    ``,
    `**Scenario**: ${report.scenario}`,
    `**Generated**: ${report.generated_at}`,
    `**Variations**: ${report.variations_compared.join(', ')}`,
    ``,
    `## Summary`,
    ``,
    `| Variation | Success | Duration (s) |`,
    `|-----------|---------|--------------|`,
  ]

  for (const v of report.variations_compared) {
    const success = report.summary.success_rate[v] === 1.0 ? '✅' : '❌'
    const duration = Math.round(report.summary.avg_duration[v])
    lines.push(`| ${v} | ${success} | ${duration} |`)
  }

  lines.push(``)
  lines.push(`**Best Performer**: ${report.summary.best_performer}`)
  lines.push(``)

  // Tasks comparison
  lines.push(`## Task Comparison`)
  lines.push(``)
  lines.push(`| Variation | Created | Completed | Failed |`)
  lines.push(`|-----------|---------|-----------|--------|`)

  for (const v of report.variations_compared) {
    const t = report.detailed_comparison.tasks[v]
    lines.push(`| ${v} | ${t.created} | ${t.completed} | ${t.failed} |`)
  }

  lines.push(``)

  // Observations
  lines.push(`## Observations`)
  lines.push(``)
  for (const obs of report.observations) {
    lines.push(`- ${obs}`)
  }
  lines.push(``)

  // Recommendations
  lines.push(`## Recommendations`)
  lines.push(``)
  for (const rec of report.recommendations) {
    lines.push(`- ${rec}`)
  }

  return lines.join('\n')
}

/**
 * CLI: 比較レポート生成
 */
if (process.argv[1] === __filename_report) {
  const args = process.argv.slice(2)
  const scenario = args[0] || 'hello-world'
  const baseDir = path.join(__dirname_report, '..')

  console.log(`Generating comparison report for scenario: ${scenario}`)

  const results = loadLatestResults(baseDir, scenario)
  const variations = Object.keys(results)

  if (variations.length === 0) {
    console.log('No results found.')
    process.exit(1)
  }

  console.log(`Found results for: ${variations.join(', ')}`)

  const report = generateComparisonReport(results, scenario)
  const outputDir = saveReport(report, baseDir)

  console.log(`\nReport saved to: ${outputDir}`)
  console.log(`\n--- Summary ---`)
  console.log(`Best performer: ${report.summary.best_performer}`)
  console.log(`\nObservations:`)
  for (const obs of report.observations) {
    console.log(`  - ${obs}`)
  }
}
