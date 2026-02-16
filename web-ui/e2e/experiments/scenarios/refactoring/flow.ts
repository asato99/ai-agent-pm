/**
 * Refactoring Experiment - Flow Definition
 *
 * リファクタリング実験のフェーズ構成
 */

import { ScenarioFlow } from '../../lib/flow-types.js'
import {
  login,
  sendMessage,
  waitForTasksCreated,
  updateTaskStatus,
  waitForTasksComplete,
  verifyArtifacts,
  testArtifacts,
} from '../../lib/phases/index.js'

const flow: ScenarioFlow = {
  phases: [
    login(),
    sendMessage(),
    waitForTasksCreated({ minCount: 1 }),
    updateTaskStatus('todo'),
    updateTaskStatus('in_progress'),
    waitForTasksComplete(),
    verifyArtifacts(),
    testArtifacts(),
  ],
}

export default flow
