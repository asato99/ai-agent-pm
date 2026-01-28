/**
 * Seed SQL Generator
 *
 * バリエーション設定からデータベース初期化用のSQLを生成
 */

import * as fs from 'fs'
import * as path from 'path'
import * as crypto from 'crypto'
import * as yaml from 'js-yaml'
import { fileURLToPath } from 'url'
import { ScenarioConfig, VariationConfig, AgentConfig } from './types.js'

/**
 * パスキーのハッシュを計算
 * Schema: SHA256(passkey + salt)
 */
function hashPasskey(passkey: string, salt: string): string {
  return crypto.createHash('sha256').update(passkey + salt).digest('hex')
}

/**
 * エージェントのINSERT文を生成
 */
function generateAgentInsert(agent: AgentConfig): string {
  const capabilities = agent.capabilities ? JSON.stringify(agent.capabilities) : 'NULL'
  const systemPrompt = agent.system_prompt
    ? `'${agent.system_prompt.replace(/'/g, "''")}'`
    : 'NULL'
  const parentAgentId = agent.parent_agent_id ? `'${agent.parent_agent_id}'` : 'NULL'
  const maxParallelTasks = agent.max_parallel_tasks ?? 1

  return `INSERT INTO agents (id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, created_at, updated_at)
VALUES (
    '${agent.id}', '${agent.name}', '${agent.role}', '${agent.type}', 'active', '${agent.hierarchy_type}', ${parentAgentId}, 'general', ${maxParallelTasks}, ${capabilities === 'NULL' ? 'NULL' : `'${capabilities}'`},
    ${systemPrompt},
    '${agent.type === 'ai' ? 'mcp' : 'cli'}', datetime('now'), datetime('now')
);`
}

/**
 * 認証情報のINSERT文を生成
 */
function generateCredentialInsert(agentId: string, passkey: string): string {
  const salt = 'salt'
  const hash = hashPasskey(passkey, salt)
  const credId = `cred-${agentId}`

  return `INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, raw_passkey, created_at)
VALUES ('${credId}', '${agentId}', '${hash}', '${salt}', '${passkey}', datetime('now'));`
}

/**
 * シナリオとバリエーションからseed SQLを生成
 */
export function generateSeedSQL(
  scenario: ScenarioConfig,
  variation: VariationConfig
): string {
  const agents = Object.values(variation.agents)
  const agentIds = agents.map((a) => `'${a.id}'`).join(', ')
  const project = scenario.project

  const lines: string[] = [
    `-- Auto-generated seed for: ${scenario.name} / ${variation.name}`,
    `-- Generated at: ${new Date().toISOString()}`,
    `--`,
    `-- IMPORTANT: This seed creates ONLY prerequisites (agents, project).`,
    `-- Expected results (tasks, status changes) are NEVER seeded.`,
    ``,
    `-- Cleanup existing data`,
    `-- Note: pending_agent_purposes table was removed, using spawn_started_at in project_agents`,
    `DELETE FROM conversations WHERE project_id = '${project.id}';`,
    `DELETE FROM tasks WHERE project_id = '${project.id}';`,
    `DELETE FROM agent_sessions WHERE agent_id IN (${agentIds});`,
    `DELETE FROM agent_credentials WHERE agent_id IN (${agentIds});`,
    `DELETE FROM agents WHERE id IN (${agentIds});`,
    `DELETE FROM project_agents WHERE project_id = '${project.id}';`,
    `DELETE FROM projects WHERE id = '${project.id}';`,
    ``,
    `-- Insert agents`,
  ]

  // エージェント（親から順に挿入するためソート）
  const sortedAgents = [...agents].sort((a, b) => {
    if (!a.parent_agent_id) return -1
    if (!b.parent_agent_id) return 1
    return 0
  })

  for (const agent of sortedAgents) {
    lines.push(generateAgentInsert(agent))
    lines.push('')
  }

  // 認証情報
  lines.push(`-- Insert credentials`)
  for (const agent of agents) {
    lines.push(generateCredentialInsert(agent.id, variation.credentials.passkey))
  }
  lines.push('')

  // プロジェクト
  lines.push(`-- Insert project`)
  lines.push(`INSERT INTO projects (id, name, description, status, working_directory, created_at, updated_at)
VALUES (
    '${project.id}', '${project.name}', '${scenario.description}', 'active',
    '${project.working_directory}', datetime('now'), datetime('now')
);`)
  lines.push('')

  // プロジェクト-エージェント割り当て
  lines.push(`-- Assign agents to project`)
  lines.push(`INSERT INTO project_agents (project_id, agent_id, assigned_at)`)
  lines.push(`VALUES`)
  const assignments = agents.map((a) => `    ('${project.id}', '${a.id}', datetime('now'))`)
  lines.push(assignments.join(',\n') + ';')

  return lines.join('\n')
}

/**
 * CLI実行時のエントリーポイント
 */
const __filename_cli = fileURLToPath(import.meta.url)

if (process.argv[1] === __filename_cli) {
  const args = process.argv.slice(2)
  if (args.length < 2) {
    console.error('Usage: npx tsx seed-generator.ts <scenario.yaml> <variation.yaml>')
    process.exit(1)
  }

  const scenarioPath = args[0]
  const variationPath = args[1]

  const scenario = yaml.load(fs.readFileSync(scenarioPath, 'utf8')) as ScenarioConfig
  const variation = yaml.load(fs.readFileSync(variationPath, 'utf8')) as VariationConfig

  const sql = generateSeedSQL(scenario, variation)
  console.log(sql)
}
