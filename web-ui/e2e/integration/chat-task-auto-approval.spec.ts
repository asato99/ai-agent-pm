import { test, expect } from '@playwright/test'

/**
 * Integration Test: Parent Agent Auto-Approval (UC018-B)
 *
 * 上位エージェント（親）がチャットで依頼した場合、タスクは自動承認される。
 *
 * UC018との違い:
 *   - UC018: 田中（非上位）→ Worker-01 → pending_approval
 *   - UC018-B: 佐藤（上位/親）→ Worker-01 → approved（自動承認）
 *
 * Prerequisites:
 *   - Services must be running (MCP, REST)
 *   - Seed data must be loaded (creates test agents with parent-child relationship)
 */

test.describe('Parent Agent Auto-Approval - UC018-B', () => {
  const TEST_PROJECT = {
    id: 'uc018b-project',
    name: 'Parent Auto-Approval Test Project',
  }

  const SATO = {
    agentId: 'uc018b-sato',
    passkey: 'test-passkey',
    name: '佐藤',
  }

  const WORKER_01 = {
    agentId: 'uc018b-worker-01',
    name: 'Worker-01',
  }

  const REQUEST_MESSAGE = 'API認証機能を実装してほしい'

  /**
   * Step 1: 佐藤（上位）のメッセージがチャットに表示される
   *
   * アサーション:
   *   - チャットセッションが準備完了
   *   - 送信したメッセージがチャットに表示される
   */
  test('Step 1: 佐藤（上位）のメッセージがチャットに表示される', async ({ page }) => {
    // タイムアウト延長（Coordinatorがエージェントをspawnするまで時間がかかる）
    test.setTimeout(180_000) // 3 minutes

    // 佐藤がログイン
    await page.goto('/login')
    await page.getByLabel('Agent ID').fill(SATO.agentId)
    await page.getByLabel('Passkey').fill(SATO.passkey)
    await page.getByRole('button', { name: 'Log in' }).click()
    await expect(page).toHaveURL('/projects', { timeout: 5000 })

    // プロジェクトページへ遷移
    await page.goto(`/projects/${TEST_PROJECT.id}`)
    await expect(page.getByText(TEST_PROJECT.name)).toBeVisible({ timeout: 5000 })

    // Worker-01のアバターをクリックしてチャットを開く
    const workerAvatar = page.getByTestId(`agent-avatar-${WORKER_01.agentId}`)
    await expect(workerAvatar).toBeVisible({ timeout: 5000 })
    await workerAvatar.click()

    // チャットパネル
    const chatPanel = page.getByTestId('chat-panel')
    await expect(chatPanel).toBeVisible({ timeout: 5000 })

    // セッションが準備完了するまで待機
    // Coordinatorがエージェントをspawnし、認証が完了するまで待機
    const sendButton = page.getByTestId('chat-send-button')
    await expect(sendButton).toHaveText('送信', { timeout: 90_000 })

    // メッセージを入力
    const chatInput = page.getByTestId('chat-input')
    await chatInput.fill(REQUEST_MESSAGE)

    // 送信ボタンをクリック
    await sendButton.click()

    // === アサーション ===
    await expect(
      page.getByText(REQUEST_MESSAGE).first(),
      'UC018-B Step 1: 佐藤のメッセージがチャットに表示されない'
    ).toBeVisible({ timeout: 10_000 })
  })

  /**
   * Step 2: Worker-01の応答メッセージがチャットに表示される
   *
   * アサーション:
   *   - Worker-01からの応答（「承知」を含む）が表示される
   *   - 上位からの依頼なので承認依頼の言及がない
   */
  test('Step 2: Worker-01の応答メッセージがチャットに表示される', async ({ page }) => {
    test.setTimeout(180_000)

    // 佐藤がログイン
    await page.goto('/login')
    await page.getByLabel('Agent ID').fill(SATO.agentId)
    await page.getByLabel('Passkey').fill(SATO.passkey)
    await page.getByRole('button', { name: 'Log in' }).click()
    await expect(page).toHaveURL('/projects', { timeout: 5000 })

    // プロジェクトページへ遷移してチャットを開く
    await page.goto(`/projects/${TEST_PROJECT.id}`)
    const workerAvatar = page.getByTestId(`agent-avatar-${WORKER_01.agentId}`)
    await expect(workerAvatar).toBeVisible({ timeout: 5000 })
    await workerAvatar.click()

    const chatPanel = page.getByTestId('chat-panel')
    await expect(chatPanel).toBeVisible({ timeout: 5000 })

    // セッション準備完了を待機
    const sendButton = page.getByTestId('chat-send-button')
    await expect(sendButton).toHaveText('送信', { timeout: 90_000 })

    // メッセージを送信
    const chatInput = page.getByTestId('chat-input')
    await chatInput.fill(REQUEST_MESSAGE)
    await sendButton.click()

    // === アサーション ===
    // Worker-01からの応答が表示される（「承認」「依頼」を含むメッセージ）
    // Note: エージェントはUC018と同じ振る舞いをする。承認はシステム側で自動的に行われる
    // Note: Claude processing + request_task + respond_chat takes ~40-60 seconds
    await expect(
      page.getByText(/承認.*依頼|依頼.*承認/).first(),
      'UC018-B Step 2: Worker-01の応答メッセージがチャットに表示されない'
    ).toBeVisible({ timeout: 60_000 })
  })

  /**
   * Step 3: タスクがapproved（自動承認）で作成される
   *
   * アサーション:
   *   - 「API認証」を含むタスクが存在する
   *   - approvalStatusがapproved（pending_approvalではない）
   *   - requesterIdがWorker-01
   *
   * Note: 上位エージェントからの依頼なので、承認プロセスをスキップして
   *       自動的にapprovedになる。
   */
  test('Step 3: タスクがapproved（自動承認）で作成される', async ({ page }) => {
    // 佐藤がログイン
    await page.goto('/login')
    await page.getByLabel('Agent ID').fill(SATO.agentId)
    await page.getByLabel('Passkey').fill(SATO.passkey)
    await page.getByRole('button', { name: 'Log in' }).click()
    await expect(page).toHaveURL('/projects', { timeout: 5000 })

    // REST APIからタスク一覧を取得
    const restPort = process.env.AIAGENTPM_WEBSERVER_PORT || '8080'
    const response = await page.evaluate(
      async ({ projectId, restPort }) => {
        const token = localStorage.getItem('sessionToken')
        const apiBase = `http://localhost:${restPort}/api`
        const res = await fetch(`${apiBase}/projects/${projectId}/tasks`, {
          headers: {
            Authorization: `Bearer ${token}`,
          },
        })
        return {
          ok: res.ok,
          status: res.status,
          data: await res.json(),
        }
      },
      { projectId: TEST_PROJECT.id, restPort }
    )

    expect(response.ok, `API returned ${response.status}`).toBeTruthy()

    const tasks = Array.isArray(response.data) ? response.data : []

    // === アサーション ===
    // UC018-B Step 3-1: API認証タスクが存在する
    const apiTask = tasks.find(
      (t: { title: string }) => t.title.includes('API認証')
    )
    expect(apiTask, 'UC018-B Step 3: タスク「API認証」が存在しない').toBeDefined()

    // UC018-B Step 3-2: approvalStatusがapproved（自動承認）
    // ★ここが重要: 上位からの依頼なのでpending_approvalではなくapproved
    expect(
      apiTask.approvalStatus,
      'UC018-B Step 3: approvalStatusがapprovedでない（自動承認されていない）'
    ).toBe('approved')

    // UC018-B Step 3-3: requesterIdがWorker-01
    expect(
      apiTask.requesterId,
      'UC018-B Step 3: requesterIdがWorker-01でない'
    ).toBe(WORKER_01.agentId)
  })

  /**
   * Step 4: タスクボードに承認済みタスクが表示される
   *
   * アサーション:
   *   - 「API認証」を含むタスクカードが表示される
   *   - 「承認待ち」バッジがない（自動承認済みなので）
   */
  test('Step 4: タスクボードに承認済みタスクが表示される', async ({ page }) => {
    // 佐藤がログイン
    await page.goto('/login')
    await page.getByLabel('Agent ID').fill(SATO.agentId)
    await page.getByLabel('Passkey').fill(SATO.passkey)
    await page.getByRole('button', { name: 'Log in' }).click()
    await expect(page).toHaveURL('/projects', { timeout: 5000 })

    // プロジェクトページ（タスクボード）へ遷移
    await page.goto(`/projects/${TEST_PROJECT.id}`)
    await expect(page.getByText(TEST_PROJECT.name)).toBeVisible({ timeout: 5000 })

    // === アサーション ===
    // UC018-B Step 4-1: API認証タスクカードが表示される
    const taskCard = page.locator('[data-testid="task-card"]', {
      has: page.getByText(/API認証/),
    })
    await expect(
      taskCard,
      'UC018-B Step 4: タスクカード「API認証」が表示されない'
    ).toBeVisible({ timeout: 5000 })

    // UC018-B Step 4-2: 承認待ちバッジがない（自動承認済み）
    const pendingBadge = taskCard.getByText('🔔 承認待ち')
    await expect(
      pendingBadge,
      'UC018-B Step 4: 自動承認されたはずなのに「承認待ち」バッジがある'
    ).not.toBeVisible()
  })
})
