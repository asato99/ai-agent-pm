/**
 * Login Phase - オーナーとしてログイン
 */

import { expect } from '@playwright/test'
import { PhaseDefinition, PhaseContext } from '../flow-types.js'

export function login(): PhaseDefinition {
  return {
    name: 'ログイン',
    execute: async (ctx: PhaseContext) => {
      const credentials = ctx.variation.credentials
      const owner = Object.values(ctx.variation.agents).find(
        (a) => a.hierarchy_type === 'owner'
      )

      if (!owner) {
        return { success: false, message: 'No owner agent defined in variation' }
      }

      await ctx.page.goto(`${ctx.baseUrl}/login`)
      await ctx.page.getByLabel('Agent ID').fill(owner.id)
      await ctx.page.getByLabel('Passkey').fill(credentials.passkey)
      await ctx.page.getByRole('button', { name: 'Log in' }).click()

      await expect(ctx.page).toHaveURL(`${ctx.baseUrl}/projects`)

      const projectName = ctx.scenario.project.name
      await expect(ctx.page.getByRole('heading', { name: projectName })).toBeVisible()

      ctx.recorder.recordEvent('prerequisites_verified', {
        owner: owner.id,
        project: ctx.scenario.project.id,
      })

      return { success: true, data: { owner: owner.id } }
    },
  }
}
