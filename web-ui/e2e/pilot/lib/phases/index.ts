/**
 * Phases - 再利用可能なテストフェーズ
 *
 * 各フェーズは PhaseDefinition を返すファクトリ関数として実装
 */

export { login } from './login.js'
export { sendMessage } from './send-message.js'
export { waitForTasksCreated } from './wait-for-tasks-created.js'
export { waitForTasksComplete } from './wait-for-tasks-complete.js'
export { verifyArtifacts } from './verify-artifacts.js'
export { testArtifacts } from './test-artifacts.js'
export { verifyReport } from './verify-report.js'
export { updateTaskStatus } from './update-task-status.js'
export { runE2ETests } from './run-e2e-tests.js'
export { runGeneratedE2ETests } from './run-generated-e2e-tests.js'
