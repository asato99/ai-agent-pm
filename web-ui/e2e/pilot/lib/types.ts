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

// ============================================================================
// Structured Report Assertions
// ============================================================================

/**
 * フィールド存在アサーション
 */
export interface ExistsAssertion {
  type: 'exists'
  field: string // JSONパス（ドット区切り: e.g., "bug.description"）
}

/**
 * 正規表現マッチアサーション
 */
export interface MatchesAssertion {
  type: 'matches'
  field: string
  pattern: string // 正規表現パターン
}

/**
 * 文字列含有アサーション
 */
export interface ContainsAssertion {
  type: 'contains'
  field: string
  values: string[] // いずれかを含む
}

/**
 * 配列最小長アサーション
 */
export interface MinLengthAssertion {
  type: 'min_length'
  field: string
  min: number
}

/**
 * 値一致アサーション
 */
export interface EqualsAssertion {
  type: 'equals'
  field: string
  value: string | number | boolean
}

export type ReportAssertion =
  | ExistsAssertion
  | MatchesAssertion
  | ContainsAssertion
  | MinLengthAssertion
  | EqualsAssertion

/**
 * 期待するレポートの定義
 * AIエージェントが作成する構造化レポート（JSON形式）の検証ルール
 */
export interface ExpectedReport {
  /** レポートファイルのパス（作業ディレクトリからの相対パス） */
  path: string
  /** レポートの形式（現在はjsonのみサポート） */
  format: 'json'
  /** アサーションの配列 */
  assertions: ReportAssertion[]
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

  // 期待するレポート（オプション）
  // AIエージェントが作成する構造化レポートの検証ルール
  expected_report?: ExpectedReport

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

  // E2Eテストケース（オプション）
  // ブラウザでの自動テストを定義
  e2e_tests?: E2ETestCase[]
}

// ============================================================================
// E2E Test Configuration
// ============================================================================

/**
 * E2Eテストのステップ
 */
export interface E2ETestStep {
  action: 'fill' | 'click' | 'wait' | 'reload' | 'assert_text' | 'assert_exists' | 'assert_not_exists' | 'assert_not_text' | 'drag'
  selector?: string
  value?: string
  expected?: string
  timeout?: number
  // drag action用
  from?: string
  to?: string
}

/**
 * E2Eテストケース
 */
export interface E2ETestCase {
  id: string
  name: string
  steps: E2ETestStep[]
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

/**
 * レポートアサーションの検証結果
 */
export interface ReportAssertionResult {
  assertion: ReportAssertion
  passed: boolean
  actual_value?: unknown
  message?: string
}

/**
 * レポート検証結果
 */
export interface ReportResult {
  path: string
  exists: boolean
  parse_error?: string
  assertions: ReportAssertionResult[]
  all_passed: boolean
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
    report?: ReportResult
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
  | 'report_verified'
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
  | 'e2e_tests_completed'
  | 'generated_e2e_tests_completed'

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
