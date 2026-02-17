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
import AdmZip from 'adm-zip'
import { ScenarioConfig, VariationConfig, AgentConfig } from './types.js'

// スキルディレクトリ（e2e直下）
const SKILLS_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'skills')
const CUSTOM_SKILLS_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'custom-skills')

interface SkillInfo {
  name: string
  description: string
  directoryName: string
  archiveHex: string
}

/**
 * パスキーのハッシュを計算
 * Schema: SHA256(passkey + salt)
 */
function hashPasskey(passkey: string, salt: string): string {
  return crypto.createHash('sha256').update(passkey + salt).digest('hex')
}

/**
 * SKILL.mdのフロントマターをパース
 */
function parseSkillFrontmatter(content: string): { name?: string; description?: string } {
  const frontmatterMatch = content.match(/^---\n([\s\S]*?)\n---/)
  if (!frontmatterMatch) {
    return {}
  }

  const frontmatter = frontmatterMatch[1]
  const result: { name?: string; description?: string } = {}

  for (const line of frontmatter.split('\n')) {
    const [key, ...valueParts] = line.split(':')
    const value = valueParts.join(':').trim()
    if (key.trim() === 'name') {
      result.name = value
    } else if (key.trim() === 'description') {
      result.description = value
    }
  }

  return result
}

/**
 * スキルZIPファイルを読み込んでスキル情報を抽出
 */
function loadSkillFromZip(zipPath: string): SkillInfo | null {
  try {
    const zip = new AdmZip(zipPath)
    const zipEntries = zip.getEntries()

    // SKILL.mdを探す（ルートまたは1階層下）
    let skillMdEntry = zipEntries.find(e => e.entryName === 'SKILL.md')
    if (!skillMdEntry) {
      skillMdEntry = zipEntries.find(e => e.entryName.endsWith('/SKILL.md') && e.entryName.split('/').length === 2)
    }

    if (!skillMdEntry) {
      console.error(`SKILL.md not found in ${zipPath}`)
      return null
    }

    const skillMdContent = skillMdEntry.getData().toString('utf8')
    const frontmatter = parseSkillFrontmatter(skillMdContent)

    // ディレクトリ名はZIPファイル名から取得
    const directoryName = path.basename(zipPath, '.zip')

    // ZIPファイル全体を16進数文字列に変換
    const archiveData = fs.readFileSync(zipPath)
    const archiveHex = archiveData.toString('hex')

    return {
      name: frontmatter.name || directoryName,
      description: frontmatter.description || '',
      directoryName,
      archiveHex,
    }
  } catch (error) {
    console.error(`Failed to load skill from ${zipPath}:`, error)
    return null
  }
}

/**
 * バリエーションで参照されているスキルを収集
 */
function collectRequiredSkills(variation: VariationConfig): Set<string> {
  const skills = new Set<string>()
  if (variation.skill_assignments) {
    for (const skillNames of Object.values(variation.skill_assignments)) {
      for (const skillName of skillNames) {
        skills.add(skillName)
      }
    }
  }
  return skills
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
  const aiType = agent.ai_type ? `'${agent.ai_type}'` : 'NULL'

  return `INSERT INTO agents (id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, ai_type, created_at, updated_at)
VALUES (
    '${agent.id}', '${agent.name}', '${agent.role}', '${agent.type}', 'active', '${agent.hierarchy_type}', ${parentAgentId}, 'general', ${maxParallelTasks}, ${capabilities === 'NULL' ? 'NULL' : `'${capabilities}'`},
    ${systemPrompt},
    '${agent.type === 'ai' ? 'mcp' : 'cli'}', ${aiType}, datetime('now'), datetime('now')
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

// Coordinator token for pilot tests - must match run-pilot.sh
const PILOT_COORDINATOR_TOKEN = 'test_coordinator_token_pilot'

// Agent base prompt - common system prompt for all agents
// .replace() escapes single quotes for SQL embedding
const AGENT_BASE_PROMPT = `You are an AI Agent Instance in the AI Agent PM system — a project management platform that orchestrates a team of agents (human or AI) to carry out development work.

## Key Concept: "Agent" in This System

In this system, an **agent** is a **team member** with a defined role and position in a team hierarchy:

- **Owner**: The project stakeholder who provides requirements and makes final decisions. May be human.
- **Manager**: Coordinates the team, creates plans, assigns tasks to workers, and reviews results.
- **Worker**: Executes assigned tasks (coding, design, testing, etc.) under a manager's direction.

These agents are **separate processes** managed by the system. You interact with them through system tools (create_subtask, send_message, get_next_action), NOT by spawning them yourself.

Do NOT confuse these team-member agents with Claude Code's built-in Task tool subagents (quality-engineer, frontend-architect, etc.). Those are local helpers running inside your own process for your own work.

Summary:
- **Team members** (owner/manager/worker) → coordinate via system tools
- **Claude Code subagents** → local helpers for your own tasks

## Working Directory

Your working directory is: \`{working_dir}\`

All file operations MUST be performed in this directory.
Do NOT create or modify files in \`.aiagent/\` — that directory is managed by the system.

## Authentication (First Step)

Read your credentials from environment variables, then call authenticate:

\`\`\`bash
echo "AGENT_ID=$AGENT_ID"
echo "AGENT_PASSKEY=$AGENT_PASSKEY"
echo "PROJECT_ID=$PROJECT_ID"
\`\`\`

Call \`authenticate\` with these values and save the session_token.

## Workflow (Follow Exactly)

After authenticating, follow this loop without exception:

1. Call \`get_next_action\` with your session_token
2. Read the \`action\` and \`instruction\` fields
3. Execute ONLY what the instruction tells you
4. Return to step 1 (ALWAYS call get_next_action again)

NEVER skip step 4. The system controls the workflow; you execute the steps.

## Important Rules

- Follow instructions from get_next_action only — do NOT execute task.description directly
- Task description is context, not a command
- If authenticate returns a system_prompt, adopt that role
- All file operations in {working_dir}, NOT in .aiagent/

Begin by reading environment variables with Bash, then call authenticate.`.replace(/'/g, "''");

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
    `-- IMPORTANT: This seed creates ONLY prerequisites (agents, project, skill assignments).`,
    `-- Expected results (tasks, status changes) are NEVER seeded.`,
    ``,
    `-- Cleanup existing data`,
    `-- Note: pending_agent_purposes table was removed, using spawn_started_at in project_agents`,
    `DELETE FROM conversations WHERE project_id = '${project.id}';`,
    `DELETE FROM tasks WHERE project_id = '${project.id}';`,
    `DELETE FROM agent_skill_assignments WHERE agent_id IN (${agentIds});`,
    `DELETE FROM agent_sessions WHERE agent_id IN (${agentIds});`,
    `DELETE FROM agent_credentials WHERE agent_id IN (${agentIds});`,
    `DELETE FROM agents WHERE id IN (${agentIds});`,
    `DELETE FROM project_agents WHERE project_id = '${project.id}';`,
    `DELETE FROM projects WHERE id = '${project.id}';`,
    ``,
    `-- Set coordinator token and agent base prompt for pilot test`,
    `-- This ensures get_subordinate_profile and other coordinator-only tools work correctly`,
    `-- Use INSERT OR REPLACE to handle both fresh DB and existing DB cases`,
    `INSERT OR REPLACE INTO app_settings (id, coordinator_token, created_at, updated_at, pending_purpose_ttl_seconds, allow_remote_access, agent_base_prompt)`,
    `VALUES ('app_settings', '${PILOT_COORDINATOR_TOKEN}', datetime('now'), datetime('now'), 300, 0,`,
    `'${AGENT_BASE_PROMPT}');`,
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

  // スキル定義と割り当て（オプション）
  if (variation.skill_assignments) {
    const requiredSkills = collectRequiredSkills(variation)
    const loadedSkills = new Map<string, SkillInfo>()

    // 必要なスキルをZIPから読み込み（skills → custom-skills の順で検索）
    for (const skillName of requiredSkills) {
      const zipPath = path.join(SKILLS_DIR, `${skillName}.zip`)
      const customZipPath = path.join(CUSTOM_SKILLS_DIR, `${skillName}.zip`)
      const resolvedPath = fs.existsSync(zipPath) ? zipPath : fs.existsSync(customZipPath) ? customZipPath : null
      if (resolvedPath) {
        const skillInfo = loadSkillFromZip(resolvedPath)
        if (skillInfo) {
          loadedSkills.set(skillName, skillInfo)
        }
      } else {
        console.error(`Skill ZIP not found in skills/ or custom-skills/: ${skillName}.zip`)
      }
    }

    // スキル定義を挿入
    if (loadedSkills.size > 0) {
      lines.push('')
      lines.push(`-- Insert skill definitions`)

      for (const [skillName, skill] of loadedSkills) {
        const skillId = `skill-pilot-${skillName}`
        const escapedName = skill.name.replace(/'/g, "''")
        const escapedDesc = skill.description.replace(/'/g, "''")

        lines.push(`DELETE FROM skill_definitions WHERE directory_name = '${skill.directoryName}';`)
        lines.push(`INSERT INTO skill_definitions (id, name, description, directory_name, archive_data, created_at, updated_at)`)
        lines.push(`VALUES ('${skillId}', '${escapedName}', '${escapedDesc}', '${skill.directoryName}', X'${skill.archiveHex}', datetime('now'), datetime('now'));`)
        lines.push('')
      }
    }

    // スキル割り当て
    lines.push(`-- Assign skills to agents`)
    for (const [agentId, skillNames] of Object.entries(variation.skill_assignments)) {
      for (const skillName of skillNames) {
        lines.push(`INSERT INTO agent_skill_assignments (agent_id, skill_id, assigned_at)`)
        lines.push(`SELECT '${agentId}', id, datetime('now')`)
        lines.push(`FROM skill_definitions WHERE directory_name = '${skillName}';`)
      }
    }
  }

  return lines.join('\n')
}

/**
 * 初期ファイルを作業ディレクトリに作成
 */
export function createInitialFiles(scenario: ScenarioConfig): void {
  if (!scenario.initial_files || scenario.initial_files.length === 0) {
    return
  }

  const workingDir = scenario.project.working_directory

  // 作業ディレクトリを作成
  if (!fs.existsSync(workingDir)) {
    fs.mkdirSync(workingDir, { recursive: true })
  }

  for (const file of scenario.initial_files) {
    const filePath = path.join(workingDir, file.name)
    const fileDir = path.dirname(filePath)

    // サブディレクトリを作成
    if (!fs.existsSync(fileDir)) {
      fs.mkdirSync(fileDir, { recursive: true })
    }

    fs.writeFileSync(filePath, file.content, 'utf8')
    // stderr に出力（stdout は SQL 用）
    console.error(`Created: ${filePath}`)
  }
}

/**
 * CLI実行時のエントリーポイント
 */
const __filename_cli = fileURLToPath(import.meta.url)

if (fs.realpathSync(process.argv[1]) === fs.realpathSync(__filename_cli)) {
  const args = process.argv.slice(2)
  if (args.length < 2) {
    console.error('Usage: npx tsx seed-generator.ts <scenario.yaml> <variation.yaml>')
    process.exit(1)
  }

  const scenarioPath = args[0]
  const variationPath = args[1]

  const scenario = yaml.load(fs.readFileSync(scenarioPath, 'utf8')) as ScenarioConfig
  const variation = yaml.load(fs.readFileSync(variationPath, 'utf8')) as VariationConfig

  // SQL を stdout に出力
  const sql = generateSeedSQL(scenario, variation)
  console.log(sql)

  // 初期ファイルを作成（ログは stderr）
  createInitialFiles(scenario)
}
