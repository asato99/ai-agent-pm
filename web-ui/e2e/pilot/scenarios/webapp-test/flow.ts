/**
 * Webapp Test Scenario - Flow Definition
 *
 * このシナリオのフェーズ構成を定義
 * 手動ステータス更新なし、レポート検証あり
 */

import { ScenarioFlow } from '../../lib/flow-types.js'
import {
  login,
  sendMessage,
  waitForTasksCreated,
  waitForTasksComplete,
  verifyReport,
} from '../../lib/phases/index.js'

const flow: ScenarioFlow = {
  phases: [
    login(),
    sendMessage(),
    waitForTasksCreated({ minCount: 1 }),
    // 手動ステータス更新なし（このシナリオでは不要）
    waitForTasksComplete(),
    verifyReport(),
  ],
}

export default flow
