/**
 * Hello World Scenario - Flow Definition
 *
 * このシナリオのフェーズ構成を定義
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
    // このシナリオ固有: 手動でステータスを更新
    updateTaskStatus('todo'),
    updateTaskStatus('in_progress'),
    // 共通フェーズ
    waitForTasksComplete(),
    verifyArtifacts(),
    testArtifacts(),
  ],
}

export default flow
