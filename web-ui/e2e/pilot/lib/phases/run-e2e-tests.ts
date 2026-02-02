/**
 * Run E2E Tests Phase - ブラウザでの成果物E2Eテスト実行
 *
 * 成果物のHTMLファイルをPlaywrightで開き、定義されたテストケースを実行
 */

import * as path from 'path'
import * as fs from 'fs'
import { PhaseDefinition, PhaseContext } from '../flow-types.js'
import { E2ETestCase, E2ETestStep } from '../types.js'

interface E2ETestResult {
  id: string
  name: string
  passed: boolean
  error?: string
  duration_ms: number
}

export function runE2ETests(): PhaseDefinition {
  return {
    name: 'E2Eテスト実行',
    execute: async (ctx: PhaseContext) => {
      const e2eTests = ctx.scenario.e2e_tests
      const workingDir = ctx.scenario.project.working_directory

      if (!e2eTests || e2eTests.length === 0) {
        console.log('ℹ️ E2Eテストが定義されていません（スキップ）')
        return { success: true }
      }

      // メインHTML取得
      const mainArtifact = ctx.scenario.expected_artifacts[0]
      if (!mainArtifact) {
        return { success: false, message: 'No artifacts defined for E2E testing' }
      }

      const htmlPath = path.join(workingDir, mainArtifact.path)
      if (!fs.existsSync(htmlPath)) {
        return { success: false, message: `Artifact not found: ${htmlPath}` }
      }

      console.log('\n' + '='.repeat(60))
      console.log('🌐 E2Eテスト実行')
      console.log('='.repeat(60))
      console.log(`📄 対象: ${htmlPath}`)
      console.log(`🧪 テストケース数: ${e2eTests.length}`)

      const results: E2ETestResult[] = []

      // 新しいページを開く
      const page = ctx.page

      try {
        // ローカルファイルを開く
        await page.goto(`file://${htmlPath}`)
        await page.waitForLoadState('domcontentloaded')

        for (const testCase of e2eTests) {
          console.log(`\n🔹 ${testCase.id}: ${testCase.name}`)
          const startTime = Date.now()

          try {
            for (const step of testCase.steps) {
              await executeStep(page, step)
            }

            const duration = Date.now() - startTime
            console.log(`   ✅ PASS (${duration}ms)`)
            results.push({
              id: testCase.id,
              name: testCase.name,
              passed: true,
              duration_ms: duration,
            })
          } catch (error) {
            const duration = Date.now() - startTime
            const errorMessage = error instanceof Error ? error.message : String(error)
            console.log(`   ❌ FAIL: ${errorMessage}`)
            results.push({
              id: testCase.id,
              name: testCase.name,
              passed: false,
              error: errorMessage,
              duration_ms: duration,
            })
          }

          // テスト間でページをリロードしてクリーンな状態に
          await page.goto(`file://${htmlPath}`)
          await page.waitForLoadState('domcontentloaded')
        }
      } catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error)
        console.log(`\n❌ E2Eテスト実行エラー: ${errorMessage}`)
        return { success: false, message: `E2E test execution error: ${errorMessage}` }
      }

      // 結果サマリー
      const passed = results.filter((r) => r.passed).length
      const failed = results.filter((r) => !r.passed).length
      const allPassed = failed === 0

      console.log('\n' + '='.repeat(60))
      console.log(`🌐 E2Eテスト結果: ${passed}/${results.length} 成功`)
      if (failed > 0) {
        console.log(`   失敗: ${results.filter((r) => !r.passed).map((r) => r.id).join(', ')}`)
      }
      console.log('='.repeat(60) + '\n')

      ctx.recorder.recordEvent('e2e_tests_completed', {
        results,
        passed_count: passed,
        failed_count: failed,
        all_passed: allPassed,
      })

      ctx.shared.e2eTestResults = results
      ctx.shared.allE2ETestsPassed = allPassed

      return {
        success: allPassed,
        message: allPassed ? undefined : `${failed} E2E test(s) failed`,
        data: { results },
      }
    },
  }
}

async function executeStep(page: any, step: E2ETestStep): Promise<void> {
  const timeout = step.timeout || 5000

  switch (step.action) {
    case 'fill':
      if (!step.selector || step.value === undefined) {
        throw new Error('fill action requires selector and value')
      }
      await page.locator(step.selector).fill(step.value, { timeout })
      // Ensure input event is dispatched for localStorage save
      await page.locator(step.selector).dispatchEvent('input')
      break

    case 'click':
      if (!step.selector) {
        throw new Error('click action requires selector')
      }
      await page.locator(step.selector).click({ timeout })
      break

    case 'wait':
      await page.waitForTimeout(step.timeout || 500)
      break

    case 'reload':
      await page.reload()
      await page.waitForLoadState('domcontentloaded')
      break

    case 'assert_text':
      if (!step.selector || step.expected === undefined) {
        throw new Error('assert_text action requires selector and expected')
      }
      const text = await page.locator(step.selector).textContent({ timeout })
      if (!text?.includes(step.expected)) {
        throw new Error(`Expected text "${step.expected}" not found in "${text}"`)
      }
      break

    case 'assert_exists':
      if (!step.selector) {
        throw new Error('assert_exists action requires selector')
      }
      // Use first() to handle multiple elements
      await page.locator(step.selector).first().waitFor({ state: 'visible', timeout })
      break

    case 'assert_not_exists':
      if (!step.selector) {
        throw new Error('assert_not_exists action requires selector')
      }
      const count = await page.locator(step.selector).count()
      if (count > 0) {
        throw new Error(`Element "${step.selector}" should not exist but found ${count} elements`)
      }
      break

    default:
      throw new Error(`Unknown action: ${step.action}`)
  }
}
