import { test, expect } from '@playwright/test'

/**
 * Integration Test: Chat Task Request Flow (UC018)
 *
 * Reference: docs/usecase/UC018_ChatTaskRequest.md
 *
 * このテストはUC018の各ステップのアサーションを正確に検証する。
 * 前提条件の失敗と本来のアサーションの失敗を区別できるよう設計。
 *
 * Prerequisites:
 *   - Services must be running (MCP, REST)
 *   - Seed data must be loaded (creates test agents and chat session)
 */

test.describe('Chat Task Request Flow - UC018', () => {
  const TEST_PROJECT = {
    id: 'uc018-project',
    name: 'Chat Task Request Test Project',
  }

  const TANAKA = {
    agentId: 'uc018-tanaka',
    passkey: 'test-passkey',
    name: '田中',
  }

  const WORKER_01 = {
    agentId: 'uc018-worker-01',
    name: 'Worker-01',
  }

  const SATO = {
    agentId: 'uc018-sato',
    passkey: 'test-passkey',
    name: '佐藤',
  }

  const REQUEST_MESSAGE = 'ユーザー一覧画面に検索機能を追加してほしい'

  /**
   * Step 1: 田中のメッセージがチャットに表示される
   *
   * アサーション:
   *   - チャットセッションが準備完了（送信ボタンが「送信」表示）
   *   - 送信したメッセージがチャットパネル内に表示される
   *
   * Note: このテストはUC018のStep 1をテストする。
   *       チャットにメッセージを送信し、それが表示されることを確認する。
   */
  test('Step 1: 田中のメッセージがチャットに表示される', async ({ page }) => {
    // タイムアウト延長（Coordinatorがエージェントをspawnするまで時間がかかる）
    test.setTimeout(180_000) // 3 minutes

    // 田中がログイン
    await page.goto('/login')
    await page.getByLabel('Agent ID').fill(TANAKA.agentId)
    await page.getByLabel('Passkey').fill(TANAKA.passkey)
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

    // セッションが準備完了するまで待機（送信ボタンが「送信」になる）
    // Coordinatorがエージェントをspawnし、認証が完了するまで待機
    const sendButton = page.getByTestId('chat-send-button')
    await expect(sendButton).toHaveText('送信', { timeout: 90_000 })

    // メッセージを入力
    const chatInput = page.getByTestId('chat-input')
    await chatInput.fill(REQUEST_MESSAGE)

    // 送信ボタンをクリック
    await sendButton.click()

    // === アサーション ===
    // UC018 Step 1: 送信したメッセージがチャットに表示される
    // Note: chatPanelスコープではなくpage全体で検索（ロケーターの問題を回避）
    await expect(
      page.getByText(REQUEST_MESSAGE).first(),
      'UC018 Step 1: 田中のメッセージがチャットに表示されない'
    ).toBeVisible({ timeout: 10_000 })
  })

  /**
   * Step 2: Worker-01の応答メッセージがチャットに表示される
   *
   * アサーション:
   *   - Worker-01からの応答（「承認」「依頼」を含む）が表示される
   *
   * Note: このテストはUC018のStep 2をテストする。
   *       田中がメッセージを送信後、Worker-01からの応答が表示されることを確認する。
   */
  test('Step 2: Worker-01の応答メッセージがチャットに表示される', async ({ page }) => {
    // タイムアウト延長
    test.setTimeout(180_000) // 3 minutes

    // 田中がログイン
    await page.goto('/login')
    await page.getByLabel('Agent ID').fill(TANAKA.agentId)
    await page.getByLabel('Passkey').fill(TANAKA.passkey)
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
    // UC018 Step 2: Worker-01からの応答が表示される（「承認」「依頼」を含むメッセージ）
    // Note: Use page-level search to avoid scoped locator issues
    // Note: Claude processing + request_task + respond_chat takes ~40-60 seconds
    await expect(
      page.getByText(/承認.*依頼|依頼.*承認/).first(),
      'UC018 Step 2: Worker-01の応答メッセージがチャットに表示されない'
    ).toBeVisible({ timeout: 60_000 })
  })

  /**
   * Step 3: タスクがpending_approvalで作成される
   *
   * アサーション:
   *   - 「検索機能」を含むタスクが存在する
   *   - そのタスクのapprovalStatusがpending_approval
   *   - requesterIdがWorker-01
   *
   * Note: このテストはUC018のStep 3をテストする。
   *       Worker-01がMCPツールrequest_taskを実行し、タスクが作成されることを確認する。
   */
  test('Step 3: タスクがpending_approvalで作成される', async ({ page }) => {
    // ログインしてからAPI呼び出し（認証が必要）
    await page.goto('/login')
    await page.getByLabel('Agent ID').fill(TANAKA.agentId)
    await page.getByLabel('Passkey').fill(TANAKA.passkey)
    await page.getByRole('button', { name: 'Log in' }).click()
    await expect(page).toHaveURL('/projects', { timeout: 5000 })

    // REST APIからタスク一覧を取得（ブラウザコンテキストでAPIを呼び出し）
    // Note: フロントエンドはlocalStorageのtokenをAuthorizationヘッダーで送信する
    // Note: 環境変数からREST APIポートを取得
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

    // REST APIは配列を直接返す
    const tasks = Array.isArray(response.data) ? response.data : []

    // === アサーション ===
    // UC018 Step 3-1: 検索機能タスクが存在する
    const searchTask = tasks.find(
      (t: { title: string }) => t.title.includes('検索機能')
    )
    expect(searchTask, 'UC018 Step 3: タスク「検索機能」が存在しない').toBeDefined()

    // UC018 Step 3-2: approvalStatusがpending_approval (REST API uses camelCase)
    expect(
      searchTask.approvalStatus,
      'UC018 Step 3: approvalStatusがpending_approvalでない'
    ).toBe('pending_approval')

    // UC018 Step 3-3: requesterIdがWorker-01 (REST API uses camelCase)
    expect(
      searchTask.requesterId,
      'UC018 Step 3: requesterIdがWorker-01でない'
    ).toBe(WORKER_01.agentId)
  })

  /**
   * Step 4: 佐藤にシステムチャット通知が届く
   *
   * アサーション:
   *   - Worker-01からの未読バッジが表示される
   *   - またはチャット内にタスク依頼通知メッセージがある
   *
   * Note: このテストはUC018のStep 4をテストする。
   *       タスク作成後、承認者（佐藤）にシステム通知が届くことを確認する。
   */
  test('Step 4: 佐藤にシステムチャット通知が届く', async ({ page }) => {
    // 佐藤がログイン
    await page.goto('/login')
    await page.getByLabel('Agent ID').fill(SATO.agentId)
    await page.getByLabel('Passkey').fill(SATO.passkey)
    await page.getByRole('button', { name: 'Log in' }).click()
    await expect(page).toHaveURL('/projects', { timeout: 5000 })

    // プロジェクトページへ遷移
    await page.goto(`/projects/${TEST_PROJECT.id}`)
    await expect(page.getByText(TEST_PROJECT.name)).toBeVisible({ timeout: 5000 })

    // === アサーション ===
    // UC018 Step 4: Worker-01に未読バッジがある、またはチャットに通知がある
    const unreadBadge = page.getByTestId(`unread-badge-${WORKER_01.agentId}`)
    const hasUnreadBadge = await unreadBadge.isVisible().catch(() => false)

    if (!hasUnreadBadge) {
      // バッジがない場合、チャットを開いて通知を確認
      const workerAvatar = page.getByTestId(`agent-avatar-${WORKER_01.agentId}`)
      await expect(workerAvatar).toBeVisible({ timeout: 5000 })
      await workerAvatar.click()

      const chatPanel = page.getByTestId('chat-panel')
      await expect(chatPanel).toBeVisible({ timeout: 5000 })

      // チャット内にタスク依頼通知がある
      await expect(
        chatPanel.getByText(/タスク依頼|承認依頼|依頼があります/),
        'UC018 Step 4: 佐藤へのシステム通知メッセージがない'
      ).toBeVisible({ timeout: 10_000 })
    }
    // バッジがある場合はアサーション成功
  })

  /**
   * Step 5: タスクボードに承認待ちタスクが表示される
   *
   * アサーション:
   *   - 「検索機能」を含むタスクカードが表示される
   *   - そのカードに「承認待ち」バッジが表示される
   *
   * Note: このテストはUC018のStep 5をテストする。
   *       佐藤がタスクボードを開くと、承認待ちタスクが視覚的に識別できる形で表示される。
   */
  test('Step 5: タスクボードに承認待ちタスクが表示される', async ({ page }) => {
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
    // UC018 Step 5-1: 検索機能タスクカードが表示される
    const taskCard = page.locator('[data-testid="task-card"]', {
      has: page.getByText(/検索機能/),
    })
    await expect(
      taskCard,
      'UC018 Step 5: タスクカード「検索機能」が表示されない'
    ).toBeVisible({ timeout: 5000 })

    // UC018 Step 5-2: 承認待ちバッジが表示される
    await expect(
      taskCard.getByText('🔔 承認待ち'),
      'UC018 Step 5: タスクカードに「承認待ち」バッジがない'
    ).toBeVisible()
  })
})
