/**
 * Run Generated E2E Tests Phase - AI作成のE2Eテストを実行
 *
 * AIが作成したPlaywright形式のE2Eテストファイルを実行し、
 * 元のコードに対して正常に動作するか（ベースライン）を確認
 */

import * as path from 'path'
import * as fs from 'fs'
import { execSync } from 'child_process'
import { PhaseDefinition, PhaseContext } from '../flow-types.js'

interface GeneratedTestResult {
  passed: number
  failed: number
  total: number
  duration_ms: number
  output: string
}

export function runGeneratedE2ETests(): PhaseDefinition {
  return {
    name: 'AI作成E2Eテスト実行',
    execute: async (ctx: PhaseContext) => {
      const workingDir = ctx.scenario.project.working_directory

      // E2Eテストファイルを探す
      const testFile = path.join(workingDir, 'e2e-tests.spec.js')
      if (!fs.existsSync(testFile)) {
        console.log('⚠️ AI作成のE2Eテストファイルが見つかりません')
        return { success: false, message: 'Generated E2E test file not found: e2e-tests.spec.js' }
      }

      // メインHTMLのパス
      const mainArtifact = ctx.scenario.expected_artifacts[0]
      const htmlPath = path.join(workingDir, mainArtifact.path)

      console.log('\n' + '='.repeat(60))
      console.log('🤖 AI作成E2Eテスト実行（ベースライン検証）')
      console.log('='.repeat(60))
      console.log(`📄 テストファイル: ${testFile}`)
      console.log(`🎯 対象HTML: ${htmlPath}`)

      const startTime = Date.now()

      try {
        // Playwrightでテスト実行（web-uiディレクトリから実行）
        const webUiDir = path.resolve(__dirname, '../../../../')
        const result = execSync(
          `npx playwright test "${testFile}" --reporter=list`,
          {
            cwd: webUiDir,
            env: {
              ...process.env,
              TEST_HTML_PATH: htmlPath,
            },
            encoding: 'utf-8',
            timeout: 120000, // 2分
          }
        )

        const duration = Date.now() - startTime
        console.log('\n' + result)
        console.log(`\n✅ AI作成E2Eテスト: 全て成功 (${duration}ms)`)

        ctx.recorder.recordEvent('generated_e2e_tests_completed', {
          success: true,
          duration_ms: duration,
          output: result,
        })

        ctx.shared.generatedE2ETestsPassed = true

        return { success: true }
      } catch (error: any) {
        const duration = Date.now() - startTime
        const output = error.stdout || error.message

        console.log('\n' + output)
        console.log(`\n❌ AI作成E2Eテスト: 一部失敗 (${duration}ms)`)

        // 失敗してもテスト自体は実行できたので、結果を記録
        ctx.recorder.recordEvent('generated_e2e_tests_completed', {
          success: false,
          duration_ms: duration,
          output: output,
          error: error.message,
        })

        ctx.shared.generatedE2ETestsPassed = false

        // ベースライン検証なので、失敗は重要な情報
        // ただし、フェーズとしては成功扱い（テスト実行自体はできた）
        // 本当の検証はミューテーションテストで行う
        return {
          success: false,
          message: 'Some generated E2E tests failed on baseline code',
          data: { output },
        }
      }
    },
  }
}
