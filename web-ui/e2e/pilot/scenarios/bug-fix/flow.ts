/**
 * Bug Fix Scenario - Flow Definition
 *
 * このシナリオのフェーズ構成を定義
 * hello-worldと同様、手動ステータス更新が必要
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
    // 手動ステータス更新
    updateTaskStatus('todo'),
    updateTaskStatus('in_progress'),
    // 完了待機と検証
    waitForTasksComplete(),
    verifyArtifacts(),
    testArtifacts(),
  ],
}

export default flow
