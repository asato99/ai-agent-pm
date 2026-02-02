/**
 * Verify Report Phase - JSONレポートを検証
 */

import * as path from 'path'
import * as fs from 'fs'
import { PhaseDefinition, PhaseContext } from '../flow-types.js'
import { ReportAssertion, ReportAssertionResult, ReportResult } from '../types.js'

export function verifyReport(): PhaseDefinition {
  return {
    name: 'レポート検証',
    execute: async (ctx: PhaseContext) => {
      const expectedReport = ctx.scenario.expected_report

      if (!expectedReport) {
        return { success: true, message: 'No report verification configured' }
      }

      const workingDir = ctx.scenario.project.working_directory
      const fullPath = path.join(workingDir, expectedReport.path)

      console.log('\n' + '='.repeat(60))
      console.log('📋 レポート検証')
      console.log('='.repeat(60))
      console.log(`ファイル: ${fullPath}`)

      // ファイル存在確認
      if (!fs.existsSync(fullPath)) {
        console.log('❌ レポートファイルが存在しません')
        ctx.recorder.recordEvent('report_verified', { exists: false, all_passed: false })

        const result: ReportResult = {
          path: expectedReport.path,
          exists: false,
          assertions: [],
          all_passed: false,
        }
        ctx.shared.reportResult = result

        return { success: false, message: 'Report file not found' }
      }
      console.log('✅ ファイル存在確認')

      // JSON パース
      let report: unknown
      try {
        const content = fs.readFileSync(fullPath, 'utf-8')
        report = JSON.parse(content)
        console.log('✅ JSONパース成功')
      } catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error)
        console.log(`❌ JSONパースエラー: ${errorMessage}`)
        ctx.recorder.recordEvent('report_verified', { exists: true, parse_error: errorMessage, all_passed: false })

        const result: ReportResult = {
          path: expectedReport.path,
          exists: true,
          parse_error: errorMessage,
          assertions: [],
          all_passed: false,
        }
        ctx.shared.reportResult = result

        return { success: false, message: `JSON parse error: ${errorMessage}` }
      }

      // アサーション評価
      console.log(`\nアサーション (${expectedReport.assertions.length} 件):`)
      const assertionResults: ReportAssertionResult[] = []

      for (const assertion of expectedReport.assertions) {
        const result = evaluateAssertion(report, assertion)
        assertionResults.push(result)

        const icon = result.passed ? '✅' : '❌'
        console.log(`  ${icon} [${assertion.type}] ${assertion.field}`)
        if (!result.passed && result.message) {
          console.log(`     → ${result.message}`)
        }
      }

      const allPassed = assertionResults.every((r) => r.passed)
      console.log('\n' + '='.repeat(60))
      console.log(`📋 レポート検証結果: ${allPassed ? '✅ ALL PASSED' : '❌ SOME FAILED'}`)
      console.log('='.repeat(60) + '\n')

      ctx.recorder.recordEvent('report_verified', {
        exists: true,
        assertions: assertionResults,
        all_passed: allPassed,
      })

      const reportResult: ReportResult = {
        path: expectedReport.path,
        exists: true,
        assertions: assertionResults,
        all_passed: allPassed,
      }
      ctx.shared.reportResult = reportResult

      return {
        success: allPassed,
        message: allPassed ? undefined : 'Some report assertions failed',
      }
    },
  }
}

function getValueByPath(obj: unknown, pathStr: string): unknown {
  const parts = pathStr.split('.')
  let current: unknown = obj

  for (const part of parts) {
    if (current === null || current === undefined) {
      return undefined
    }

    const arrayMatch = part.match(/^(\d+)$/)
    if (arrayMatch && Array.isArray(current)) {
      current = current[parseInt(arrayMatch[1], 10)]
    } else if (typeof current === 'object' && current !== null) {
      current = (current as Record<string, unknown>)[part]
    } else {
      return undefined
    }
  }

  return current
}

function evaluateAssertion(report: unknown, assertion: ReportAssertion): ReportAssertionResult {
  const value = getValueByPath(report, assertion.field)

  switch (assertion.type) {
    case 'exists': {
      const passed = value !== undefined && value !== null
      return {
        assertion,
        passed,
        actual_value: value,
        message: passed ? undefined : `フィールド '${assertion.field}' が存在しません`,
      }
    }

    case 'equals': {
      const passed = value === assertion.value
      return {
        assertion,
        passed,
        actual_value: value,
        message: passed ? undefined : `期待値: ${assertion.value}, 実際: ${value}`,
      }
    }

    case 'matches': {
      const stringValue = typeof value === 'string' ? value : String(value ?? '')
      const regex = new RegExp(assertion.pattern)
      const passed = regex.test(stringValue)
      return {
        assertion,
        passed,
        actual_value: value,
        message: passed ? undefined : `パターン '${assertion.pattern}' に一致しません`,
      }
    }

    case 'contains': {
      const stringValue = typeof value === 'string' ? value : String(value ?? '')
      const passed = assertion.values.some((v) => stringValue.includes(v))
      return {
        assertion,
        passed,
        actual_value: value,
        message: passed ? undefined : `いずれの値も含まれません: [${assertion.values.join(', ')}]`,
      }
    }

    case 'min_length': {
      const length = Array.isArray(value) ? value.length : 0
      const passed = length >= assertion.min
      return {
        assertion,
        passed,
        actual_value: length,
        message: passed ? undefined : `最小長 ${assertion.min} 未満です (実際: ${length})`,
      }
    }

    default:
      return {
        assertion,
        passed: false,
        message: `未知のアサーションタイプ: ${(assertion as ReportAssertion).type}`,
      }
  }
}
