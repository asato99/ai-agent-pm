import { test, expect } from '@playwright/test'
import { LoginPage } from '../pages/login.page'
import { TaskBoardPage } from '../pages/task-board.page'

test.describe('タスクボード', () => {
  test.beforeEach(async ({ page }) => {
    // ログイン
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('manager-1', 'test-passkey')
    await expect(page).toHaveURL('/projects')

    // プロジェクトページへ遷移
    const taskBoard = new TaskBoardPage(page)
    await taskBoard.goto('project-1')
  })

  test('カンバンボードが表示される', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    // 5つのカラムが表示される
    await expect(taskBoard.getColumn('backlog')).toBeVisible()
    await expect(taskBoard.getColumn('todo')).toBeVisible()
    await expect(taskBoard.getColumn('in_progress')).toBeVisible()
    await expect(taskBoard.getColumn('done')).toBeVisible()
    await expect(taskBoard.getColumn('blocked')).toBeVisible()
  })

  test('プロジェクト名が表示される', async ({ page }) => {
    await expect(page.getByText('ECサイト開発')).toBeVisible()
  })

  test('タスクカードが表示される', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    await expect(taskBoard.getTaskCard('API実装')).toBeVisible()
    await expect(taskBoard.getTaskCard('DB設計')).toBeVisible()
  })

  test('タスクカードにタスク情報が表示される', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)
    const apiTask = taskBoard.getTaskCard('API実装')

    await expect(apiTask).toBeVisible()
    await expect(apiTask.getByText('High')).toBeVisible()
  })

  test('タスクをドラッグ＆ドロップでステータス変更できる', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    // 最初はin_progressカラムにある
    await expect(taskBoard.getTaskCardInColumn('in_progress', 'API実装')).toBeVisible()

    // doneカラムにドラッグ
    await taskBoard.dragTask('task-1', 'done')

    // doneカラムに移動している
    await expect(taskBoard.getTaskCardInColumn('done', 'API実装')).toBeVisible()
  })

  test('タスク作成ボタンをクリックするとモーダルが開く', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    await taskBoard.openCreateTaskModal()

    await expect(page.getByRole('dialog')).toBeVisible()
    await expect(page.getByRole('heading', { name: 'タスク作成' })).toBeVisible()
  })

  test('タスクを新規作成できる', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    await taskBoard.openCreateTaskModal()
    await taskBoard.fillTaskForm({
      title: '新しいタスク',
      description: 'テスト用タスクの説明',
      priority: 'high',
    })
    await taskBoard.submitTaskForm()

    // モーダルが閉じる
    await expect(page.getByRole('dialog')).not.toBeVisible()

    // 新しいタスクがBacklogカラムに表示される
    await expect(taskBoard.getTaskCardInColumn('backlog', '新しいタスク')).toBeVisible()
  })

  test('タスクカードをクリックすると詳細パネルが開く', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    await taskBoard.clickTask('API実装')

    await expect(page.getByRole('dialog')).toBeVisible()
    await expect(page.getByText('REST APIエンドポイントの実装')).toBeVisible()
  })

  test('プロジェクト一覧に戻るボタンが機能する', async ({ page }) => {
    await page.getByRole('link', { name: 'プロジェクト一覧' }).click()

    await expect(page).toHaveURL('/projects')
  })

  test('タスクを削除できる', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    // タスクカードが表示されていることを確認
    await expect(taskBoard.getTaskCard('API実装')).toBeVisible()

    // タスクカードのメニューボタンを直接取得してクリック
    const taskCard = taskBoard.getTaskCard('API実装')
    const menuButton = taskCard.getByRole('button', { name: 'メニュー' })
    await expect(menuButton).toBeVisible()
    await menuButton.click()

    // メニューが表示されるのを待つ
    const deleteMenuItem = page.getByRole('menuitem', { name: '削除' })
    await expect(deleteMenuItem).toBeVisible()
    await deleteMenuItem.click()

    // 確認ダイアログが表示されるのを待つ
    const confirmDialog = page.getByRole('dialog')
    await expect(confirmDialog).toBeVisible()

    // 確認ダイアログ内の削除ボタンをクリック
    await confirmDialog.getByRole('button', { name: '削除' }).click()

    // タスクが画面から消える（cancelledステータスになり、カンバンに表示されなくなる）
    await expect(taskBoard.getTaskCard('API実装')).not.toBeVisible()
  })
})
