/**
 * Test Artifacts Phase - 成果物を実行テスト
 */

import * as path from 'path'
import * as fs from 'fs'
import { PhaseDefinition, PhaseContext } from '../flow-types.js'
import { ArtifactResult } from '../types.js'

export function testArtifacts(): PhaseDefinition {
  return {
    name: '成果物テスト実行',
    execute: async (ctx: PhaseContext) => {
      const artifacts = ctx.scenario.expected_artifacts
      const workingDir = ctx.scenario.project.working_directory
      const allResults: ArtifactResult[] = []

      console.log('\n' + '='.repeat(60))
      console.log('🧪 成果物テスト実行')
      console.log('='.repeat(60))

      for (const artifact of artifacts) {
        const fullPath = path.join(workingDir, artifact.path)

        if (artifact.tests && artifact.tests.length > 0) {
          console.log(`\n📄 ${artifact.path}: (${artifact.tests.length} テスト)`)

          const testResults = ctx.recorder.runArtifactTests(fullPath, artifact.tests)
          const allTestsPassed = testResults.every((r) => r.passed)

          for (const result of testResults) {
            const statusIcon = result.passed ? '✅' : '❌'
            console.log(`   ${statusIcon} ${result.name}`)
            console.log(`      コマンド: ${result.command}`)
            console.log(`      終了コード: ${result.exit_code} (期待: ${result.expected_exit_code})`)
          }

          allResults.push({
            path: artifact.path,
            exists: fs.existsSync(fullPath),
            validation_passed: true,
            test_results: testResults,
            all_tests_passed: allTestsPassed,
          })
        } else if (artifact.test) {
          console.log(`\n📄 ${artifact.path}:`)
          console.log(`   コマンド: ${artifact.test.command.replace('{path}', fullPath)}`)

          const testResult = ctx.recorder.testArtifact(
            fullPath,
            artifact.test.command,
            artifact.test.expected_output
          )

          const passed = testResult.passed
          console.log(`   終了コード: ${testResult.exit_code}`)
          console.log(`   標準出力: "${testResult.stdout}"`)
          console.log(`   結果: ${passed ? '✅ PASS' : '❌ FAIL'}`)

          allResults.push({
            path: artifact.path,
            exists: fs.existsSync(fullPath),
            validation_passed: true,
            test_results: [testResult],
            all_tests_passed: passed,
          })
        } else {
          console.log(`\n📄 ${artifact.path}: テスト設定なし（スキップ）`)
          allResults.push({
            path: artifact.path,
            exists: fs.existsSync(fullPath),
            validation_passed: true,
            all_tests_passed: true,
          })
        }
      }

      console.log('\n' + '='.repeat(60))
      const allPassed = allResults.every((r) => r.all_tests_passed)
      console.log(`🧪 成果物テスト結果: ${allPassed ? '✅ ALL PASSED' : '❌ SOME FAILED'}`)
      console.log('='.repeat(60) + '\n')

      ctx.recorder.recordEvent('artifacts_tested', { results: allResults, all_passed: allPassed })

      // 共有データに保存
      ctx.shared.testResults = allResults
      ctx.shared.allTestsPassed = allPassed

      return {
        success: allPassed,
        message: allPassed ? undefined : 'Some artifact tests failed',
      }
    },
  }
}
