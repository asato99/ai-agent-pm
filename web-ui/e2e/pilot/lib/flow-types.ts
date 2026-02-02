/**
 * Flow Types - シナリオフロー定義の型
 */

import { Page } from '@playwright/test'
import { ScenarioConfig, VariationConfig } from './types.js'
import { ResultRecorder } from './result-recorder.js'

/**
 * フェーズ実行時のコンテキスト
 */
export interface PhaseContext {
  page: Page
  scenario: ScenarioConfig
  variation: VariationConfig
  recorder: ResultRecorder
  baseUrl: string
  /** フェーズ間で共有するデータ */
  shared: Record<string, unknown>
}

/**
 * フェーズの実行結果
 */
export interface PhaseResult {
  success: boolean
  message?: string
  data?: Record<string, unknown>
}

/**
 * フェーズ関数の型
 */
export type PhaseFunction = (ctx: PhaseContext) => Promise<PhaseResult>

/**
 * フェーズ定義
 */
export interface PhaseDefinition {
  /** フェーズ名（ログ表示用） */
  name: string
  /** フェーズ実行関数 */
  execute: PhaseFunction
}

/**
 * シナリオフロー定義
 */
export interface ScenarioFlow {
  /** フェーズのリスト */
  phases: PhaseDefinition[]
}
