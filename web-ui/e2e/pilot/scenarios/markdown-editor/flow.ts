/**
 * Markdown Editor Scenario - Flow Definition
 *
 * 単一ワーカー構成のフロー
 */

import { ScenarioFlow } from '../../lib/flow-types.js'
import {
  login,
  sendMessage,
  waitForTasksCreated,
  updateTaskStatus,
  waitForTasksComplete,
  verifyArtifacts,
} from '../../lib/phases/index.js'
import { runE2ETests } from '../../lib/phases/run-e2e-tests.js'

const flow: ScenarioFlow = {
  phases: [
    login(),
    sendMessage(),
    waitForTasksCreated({ minCount: 1 }),
    updateTaskStatus('todo'),
    updateTaskStatus('in_progress'),
    waitForTasksComplete(),
    verifyArtifacts(),
    runE2ETests(),
  ],
}

export default flow
