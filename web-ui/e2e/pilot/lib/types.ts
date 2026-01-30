/**
 * Pilot Test Variation System - Type Definitions
 */

// ============================================================================
// Scenario Configuration
// ============================================================================

/**
 * 成果物のテスト定義
 */
export interface ArtifactTest {
  name: string // テスト名
  command: string // 実行コマンド
  expected_exit_code: number // 期待する終了コード
  expected_output?: string // 期待する出力（オプション）
}

/**
 * 期待する成果物の定義
 */
export interface ExpectedArtifact {
  path: string
  description?: string
  validation?: string // Shell command template with {path}
  // 複数テストをサポート
  tests?: ArtifactTest[]
  // 後方互換性のため単一テストもサポート
  test?: {
    command: string
    expected_output: string
  }
}

export interface ScenarioConfig {
  name: string
  description: string
  version: string

  project: {
    id: string
    name: string
    working_directory: string
  }

  // 初期ファイル（テスト開始前に配置）
  initial_files?: Array<{
    name: string
    content: string
  }>

  expected_artifacts: ExpectedArtifact[]

  timeouts: {
    task_creation: number // seconds
    task_completion: number // seconds
  }

  initial_action: {
    type: 'chat'
    from: string
    to: string
    message: string
  }
}

// ============================================================================
// Variation Configuration
// ============================================================================

export interface AgentConfig {
  id: string
  name: string
  role: string
  type: 'human' | 'ai'
  hierarchy_type: 'owner' | 'manager' | 'worker'
  parent_agent_id?: string
  capabilities?: string[]
  system_prompt?: string
  max_parallel_tasks?: number
  ai_type?: string  // e.g., 'gemini-2.5-pro', 'claude-sonnet-4-5'
}

export interface VariationConfig {
  name: string
  description: string
  version: string

  agents: Record<string, AgentConfig>

  credentials: {
    passkey: string
  }

  // スキル割り当て（オプション）
  // キー: エージェントID、値: スキル名の配列
  skill_assignments?: Record<string, string[]>
}

// ============================================================================
// Result Recording
// ============================================================================

export interface TaskResult {
  id: string
  title: string
  status: string
  created_at: string
  completed_at?: string
  duration_seconds?: number
  assignee_id?: string
}

export interface AgentResult {
  agent_id: string
  spawned_count: number
  total_turns: number
  tools_called: Array<{
    name: string
    count: number
  }>
}

export interface ArtifactTestResult {
  name: string // テスト名
  command: string
  exit_code: number
  expected_exit_code: number
  stdout: string
  stderr: string
  expected_output?: string
  passed: boolean // exit_code一致 かつ output一致（指定時）
}

export interface ArtifactResult {
  path: string
  exists: boolean
  validation_passed: boolean
  content_hash?: string
  test_results?: ArtifactTestResult[] // 複数テスト結果
  all_tests_passed?: boolean
}

export interface PilotResult {
  scenario: string
  variation: string
  run_id: string
  started_at: string
  finished_at: string
  duration_seconds: number

  outcome: {
    success: boolean
    failure_reason?: string
    artifacts: ArtifactResult[]
  }

  tasks: {
    total_created: number
    completed: number
    failed: number
    final_states: TaskResult[]
  }

  agents: Record<string, AgentResult>

  events: PilotEvent[]

  observations?: string
  issues?: string[]
}

// ============================================================================
// Event Tracking
// ============================================================================

export type PilotEventType =
  | 'agent_started'
  | 'agent_stopped'
  | 'task_created'
  | 'task_status_changed'
  | 'chat_message'
  | 'tool_called'
  | 'artifact_created'
  | 'artifacts_tested'
  | 'artifacts_verified'
  | 'performance_report'
  | 'error'
  // Pilot test specific events
  | 'test_started'
  | 'prerequisites_verified'
  | 'initial_action_sent'
  | 'tasks_created'
  | 'task_status_updated'
  | 'task_status_check'
  | 'all_tasks_completed'
  | 'task_completion_timeout'

export interface PilotEvent {
  timestamp: string
  elapsed_seconds: number
  type: PilotEventType
  data: Record<string, unknown>
}

// ============================================================================
// Comparison
// ============================================================================

export interface ComparisonReport {
  scenario: string
  variations: string[]
  generated_at: string

  summary: {
    variation: string
    success: boolean
    duration_seconds: number
    tasks_created: number
    manager_spawns: number
    manager_turns: number
  }[]

  differences: {
    category: string
    description: string
    details: Record<string, string>
  }[]

  recommendation?: string
}
