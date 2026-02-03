/**
 * Variation Loader
 *
 * シナリオとバリエーションの設定ファイルを読み込み
 */

import * as fs from 'fs'
import * as path from 'path'
import * as yaml from 'js-yaml'
import { ScenarioConfig, VariationConfig } from './types.js'

export class VariationLoader {
  private baseDir: string

  constructor(baseDir: string) {
    this.baseDir = baseDir
  }

  /**
   * シナリオ一覧を取得
   */
  listScenarios(): string[] {
    const scenariosDir = path.join(this.baseDir, 'scenarios')
    if (!fs.existsSync(scenariosDir)) return []

    return fs
      .readdirSync(scenariosDir, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .filter((d) => fs.existsSync(path.join(scenariosDir, d.name, 'scenario.yaml')))
      .map((d) => d.name)
  }

  /**
   * シナリオのバリエーション一覧を取得
   */
  listVariations(scenario: string): string[] {
    const variationsDir = path.join(this.baseDir, 'scenarios', scenario, 'variations')
    if (!fs.existsSync(variationsDir)) return []

    return fs
      .readdirSync(variationsDir)
      .filter((f) => f.endsWith('.yaml'))
      .map((f) => f.replace('.yaml', ''))
  }

  /**
   * シナリオ設定を読み込み
   */
  loadScenario(scenario: string): ScenarioConfig {
    const scenarioPath = path.join(this.baseDir, 'scenarios', scenario, 'scenario.yaml')

    if (!fs.existsSync(scenarioPath)) {
      throw new Error(`Scenario not found: ${scenario}`)
    }

    const content = fs.readFileSync(scenarioPath, 'utf8')
    return yaml.load(content) as ScenarioConfig
  }

  /**
   * バリエーション設定を読み込み
   */
  loadVariation(scenario: string, variation: string): VariationConfig {
    const variationPath = path.join(
      this.baseDir,
      'scenarios',
      scenario,
      'variations',
      `${variation}.yaml`
    )

    if (!fs.existsSync(variationPath)) {
      throw new Error(`Variation not found: ${scenario}/${variation}`)
    }

    const content = fs.readFileSync(variationPath, 'utf8')
    return yaml.load(content) as VariationConfig
  }

  /**
   * シナリオとバリエーションを両方読み込み
   * バリエーションにinitial_actionがある場合はシナリオの設定を上書き
   */
  load(scenario: string, variation: string): {
    scenario: ScenarioConfig
    variation: VariationConfig
  } {
    const scenarioConfig = this.loadScenario(scenario)
    const variationConfig = this.loadVariation(scenario, variation)

    // バリエーションにinitial_actionがある場合、シナリオの設定を上書き
    if (variationConfig.initial_action) {
      scenarioConfig.initial_action = {
        ...scenarioConfig.initial_action,
        ...variationConfig.initial_action,
        // messageが省略されている場合はシナリオのものを使用
        message: variationConfig.initial_action.message ?? scenarioConfig.initial_action.message,
      }
    }

    return {
      scenario: scenarioConfig,
      variation: variationConfig,
    }
  }

  /**
   * バリエーションの概要を取得（比較用）
   */
  getVariationSummary(scenario: string, variation: string): {
    name: string
    description: string
    agentCount: number
    managerPromptLength: number
  } {
    const v = this.loadVariation(scenario, variation)
    const agents = Object.values(v.agents)
    const manager = agents.find((a) => a.hierarchy_type === 'manager')

    return {
      name: v.name,
      description: v.description,
      agentCount: agents.length,
      managerPromptLength: manager?.system_prompt?.length ?? 0,
    }
  }
}

/**
 * CLI: バリエーション一覧表示
 */
import { fileURLToPath } from 'url'
const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

if (process.argv[1] === __filename) {
  const baseDir = path.join(__dirname, '..')
  const loader = new VariationLoader(baseDir)

  const scenarios = loader.listScenarios()
  console.log('Available scenarios and variations:\n')

  for (const scenario of scenarios) {
    const scenarioConfig = loader.loadScenario(scenario)
    console.log(`${scenario}: ${scenarioConfig.description}`)

    const variations = loader.listVariations(scenario)
    for (const variation of variations) {
      const summary = loader.getVariationSummary(scenario, variation)
      console.log(`  - ${variation}: ${summary.description}`)
      console.log(`    (${summary.agentCount} agents, manager prompt: ${summary.managerPromptLength} chars)`)
    }
    console.log()
  }
}
