/**
 * Pilot Test Variation System - Type Definitions
 */

// ============================================================================
// Scenario Configuration
// ============================================================================

export interface ScenarioConfig {
  name: string
  description: string
  version: string

  project: {
    id: string
    name: string
    working_directory: string
  }

  expected_artifacts: Array<{
    path: string
    validation?: string // Shell command template with {path}
    test?: {
      command: string // Execution command template with {path}
      expected_output: string // Expected output string to match
    }
  }>

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
}

export interface VariationConfig {
  name: string
  description: string
  version: string

  agents: Record<string, AgentConfig>

  credentials: {
    passkey: string
  }
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
  command: string
  exit_code: number
  stdout: string
  stderr: string
  expected_output?: string
  output_matched: boolean
}

export interface ArtifactResult {
  path: string
  exists: boolean
  validation_passed: boolean
  content_hash?: string
  test_result?: ArtifactTestResult
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
  | 'performance_report'
  | 'error'

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
