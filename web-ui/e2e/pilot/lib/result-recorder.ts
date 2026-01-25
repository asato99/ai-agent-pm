/**
 * Result Recorder
 *
 * パイロットテストの実行結果を記録・保存
 */

import * as fs from 'fs'
import * as path from 'path'
import * as crypto from 'crypto'
import { PilotResult, PilotEvent, TaskResult, AgentResult, ArtifactResult } from './types.js'

export class ResultRecorder {
  private scenario: string
  private variation: string
  private runId: string
  private startedAt: Date
  private events: PilotEvent[] = []
  private resultsDir: string

  constructor(scenario: string, variation: string, baseDir: string) {
    this.scenario = scenario
    this.variation = variation
    this.startedAt = new Date()
    this.runId = this.generateRunId()
    this.resultsDir = path.join(
      baseDir,
      'results',
      scenario,
      `${this.runId}_${variation}`
    )
  }

  private generateRunId(): string {
    return this.startedAt.toISOString().replace(/[:.]/g, '-').slice(0, 19)
  }

  /**
   * 結果ディレクトリを作成
   */
  initialize(): void {
    fs.mkdirSync(this.resultsDir, { recursive: true })
    fs.mkdirSync(path.join(this.resultsDir, 'agent-logs'), { recursive: true })
  }

  /**
   * イベントを記録
   */
  recordEvent(type: PilotEvent['type'], data: Record<string, unknown>): void {
    const event: PilotEvent = {
      timestamp: new Date().toISOString(),
      elapsed_seconds: (Date.now() - this.startedAt.getTime()) / 1000,
      type,
      data,
    }
    this.events.push(event)

    // リアルタイムでイベントファイルに追記
    const eventsPath = path.join(this.resultsDir, 'events.jsonl')
    fs.appendFileSync(eventsPath, JSON.stringify(event) + '\n')
  }

  /**
   * 成果物を検証
   */
  validateArtifact(
    artifactPath: string,
    validationCommand?: string
  ): ArtifactResult {
    const exists = fs.existsSync(artifactPath)

    if (!exists) {
      return { path: artifactPath, exists: false, validation_passed: false }
    }

    const content = fs.readFileSync(artifactPath)
    const contentHash = `sha256:${crypto.createHash('sha256').update(content).digest('hex').slice(0, 16)}`

    let validationPassed = true
    if (validationCommand) {
      const { execSync } = require('child_process')
      const cmd = validationCommand.replace('{path}', artifactPath)
      try {
        execSync(cmd, { stdio: 'pipe' })
        validationPassed = true
      } catch {
        validationPassed = false
      }
    }

    return {
      path: artifactPath,
      exists: true,
      validation_passed: validationPassed,
      content_hash: contentHash,
    }
  }

  /**
   * 最終結果を保存
   */
  saveResult(params: {
    success: boolean
    failure_reason?: string
    artifacts: ArtifactResult[]
    tasks: TaskResult[]
    agents: Record<string, AgentResult>
    observations?: string
    issues?: string[]
  }): PilotResult {
    const finishedAt = new Date()
    const durationSeconds = (finishedAt.getTime() - this.startedAt.getTime()) / 1000

    const result: PilotResult = {
      scenario: this.scenario,
      variation: this.variation,
      run_id: this.runId,
      started_at: this.startedAt.toISOString(),
      finished_at: finishedAt.toISOString(),
      duration_seconds: Math.round(durationSeconds),

      outcome: {
        success: params.success,
        failure_reason: params.failure_reason,
        artifacts: params.artifacts,
      },

      tasks: {
        total_created: params.tasks.length,
        completed: params.tasks.filter((t) => t.status === 'done').length,
        failed: params.tasks.filter((t) => t.status === 'cancelled').length,
        final_states: params.tasks,
      },

      agents: params.agents,
      events: this.events,
      observations: params.observations,
      issues: params.issues,
    }

    // YAML形式で保存
    const yaml = require('js-yaml')
    const resultPath = path.join(this.resultsDir, 'result.yaml')
    fs.writeFileSync(resultPath, yaml.dump(result, { lineWidth: -1 }))

    // JSON形式でも保存（プログラムからの読み込み用）
    const jsonPath = path.join(this.resultsDir, 'result.json')
    fs.writeFileSync(jsonPath, JSON.stringify(result, null, 2))

    return result
  }

  /**
   * エージェントログをコピー
   */
  copyAgentLogs(sourceDir: string): void {
    if (!fs.existsSync(sourceDir)) return

    const destDir = path.join(this.resultsDir, 'agent-logs')
    const files = fs.readdirSync(sourceDir)

    for (const file of files) {
      const src = path.join(sourceDir, file)
      const dest = path.join(destDir, file)
      if (fs.statSync(src).isFile()) {
        fs.copyFileSync(src, dest)
      }
    }
  }

  /**
   * 結果ディレクトリのパスを取得
   */
  getResultsDir(): string {
    return this.resultsDir
  }

  /**
   * 実行IDを取得
   */
  getRunId(): string {
    return this.runId
  }
}

/**
 * イベントからエージェント統計を集計
 */
export function aggregateAgentStats(events: PilotEvent[]): Record<string, AgentResult> {
  const stats: Record<string, AgentResult> = {}

  for (const event of events) {
    if (event.type === 'agent_started') {
      const agentId = event.data.agent as string
      if (!stats[agentId]) {
        stats[agentId] = { agent_id: agentId, spawned_count: 0, total_turns: 0, tools_called: [] }
      }
      stats[agentId].spawned_count++
    }

    if (event.type === 'tool_called') {
      const agentId = event.data.agent as string
      const toolName = event.data.tool as string
      if (!stats[agentId]) {
        stats[agentId] = { agent_id: agentId, spawned_count: 0, total_turns: 0, tools_called: [] }
      }
      stats[agentId].total_turns++
      const existing = stats[agentId].tools_called.find((t) => t.name === toolName)
      if (existing) {
        existing.count++
      } else {
        stats[agentId].tools_called.push({ name: toolName, count: 1 })
      }
    }
  }

  return stats
}
