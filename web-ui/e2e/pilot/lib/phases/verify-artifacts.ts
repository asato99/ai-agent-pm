/**
 * Verify Artifacts Phase - 成果物の存在とバリデーションを検証
 */

import * as path from 'path'
import { PhaseDefinition, PhaseContext } from '../flow-types.js'

export function verifyArtifacts(): PhaseDefinition {
  return {
    name: '成果物検証',
    execute: async (ctx: PhaseContext) => {
      const artifacts = ctx.scenario.expected_artifacts
      const workingDir = ctx.scenario.project.working_directory

      const results = artifacts.map((artifact) => {
        const fullPath = path.join(workingDir, artifact.path)
        return ctx.recorder.validateArtifact(fullPath, artifact.validation)
      })

      ctx.recorder.recordEvent('artifacts_verified', {
        results: results.map((r) => ({
          path: r.path,
          exists: r.exists,
          validation_passed: r.validation_passed,
        })),
      })

      // 共有データに保存
      ctx.shared.artifactResults = results

      const allPassed = results.every((r) => r.exists && r.validation_passed)

      return {
        success: allPassed,
        message: allPassed ? undefined : 'Some artifacts failed validation',
        data: { results },
      }
    },
  }
}
