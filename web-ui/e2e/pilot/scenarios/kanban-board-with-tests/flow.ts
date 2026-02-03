/**
 * Kanban Board with Tests Scenario - Flow Definition
 *
 * 単一ワーカー構成のフロー
 * アプリ検証 + AI作成E2Eテストの実行
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
import { runGeneratedE2ETests } from '../../lib/phases/run-generated-e2e-tests.js'

const flow: ScenarioFlow = {
  phases: [
    login(),
    sendMessage(),
    waitForTasksCreated({ minCount: 1 }),
    updateTaskStatus('todo'),
    updateTaskStatus('in_progress'),
    waitForTasksComplete(),
    verifyArtifacts(),
    runE2ETests(),           // 定義済みE2Eでアプリ検証
    runGeneratedE2ETests(),  // AI作成E2Eの実行（ベースライン）
  ],
}

export default flow
