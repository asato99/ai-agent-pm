# タスク関係性表示 TDD実装プラン

## 概要

`docs/design/TASK_RELATIONSHIP_DISPLAY.md` の仕様を TDD で実装するための計画。

## テスト戦略

| レイヤー | ツール | 対象 |
|----------|--------|------|
| ユニットテスト | Vitest + React Testing Library | コンポーネント、フック、ユーティリティ |
| E2Eテスト | Playwright | ユーザーフロー、視覚的確認 |
| MSW | Mock Service Worker | API モック |

---

## Phase 0: Web UI 型定義の同期

### 目的
バックエンドから返却されるフィールドを Web UI の型定義に反映

### 0.1 型定義の更新

**ファイル**: `web-ui/src/types/task.ts`

```typescript
// 追加フィールド
parentTaskId: string | null
dependentTasks: string[]
blockedReason: string | null
estimatedMinutes: number | null
actualMinutes: number | null
```

**テスト（型チェック）**:
- TypeScript コンパイルが通ることを確認
- 既存テストが壊れないことを確認

```bash
npm run typecheck
npm test
```

### 0.2 MSW ハンドラーの更新

**ファイル**: `web-ui/tests/mocks/handlers.ts`

**RED**: 新フィールドを含むモックデータでテストが失敗することを確認

```typescript
// tests/mocks/handlers.ts
const mockTask = {
  // ...既存フィールド
  parentTaskId: 'parent-task-1',
  dependentTasks: ['dep-task-1', 'dep-task-2'],
  blockedReason: 'Waiting for API completion',
  estimatedMinutes: 120,
  actualMinutes: 90,
}
```

**GREEN**: 型定義を更新してテストが通ることを確認

---

## Phase 1: TaskCard の拡張

### 1.1 左ボーダー（深さ色）

**ファイル**: `web-ui/src/components/task/TaskCard/TaskCard.tsx`

#### ユニットテスト

**ファイル**: `web-ui/src/components/task/TaskCard/TaskCard.test.tsx`

```typescript
describe('TaskCard - Depth Indicator', () => {
  it('renders blue left border for root task (depth 0)', () => {
    render(<TaskCard task={mockTask} depth={0} />)
    const card = screen.getByTestId('task-card')
    expect(card).toHaveClass('border-l-depth-0')
  })

  it('renders green left border for depth 1', () => {
    render(<TaskCard task={mockTask} depth={1} />)
    const card = screen.getByTestId('task-card')
    expect(card).toHaveClass('border-l-depth-1')
  })

  it('renders yellow left border for depth 2', () => {
    render(<TaskCard task={mockTask} depth={2} />)
    const card = screen.getByTestId('task-card')
    expect(card).toHaveClass('border-l-depth-2')
  })

  it('renders orange left border for depth 3', () => {
    render(<TaskCard task={mockTask} depth={3} />)
    const card = screen.getByTestId('task-card')
    expect(card).toHaveClass('border-l-depth-3')
  })

  it('renders red left border for depth 4+', () => {
    render(<TaskCard task={mockTask} depth={5} />)
    const card = screen.getByTestId('task-card')
    expect(card).toHaveClass('border-l-depth-4')
  })
})
```

#### 実装

**RED**: テスト実行 → 失敗（depth prop が存在しない）

**GREEN**:
1. `TaskCard` に `depth` prop を追加
2. 深さに応じた CSS クラスを適用
3. Tailwind カスタムカラーを定義

```typescript
// TaskCard.tsx
interface TaskCardProps {
  task: Task
  depth?: number  // 追加
}

const depthColors = {
  0: 'border-l-blue-500',
  1: 'border-l-green-500',
  2: 'border-l-yellow-500',
  3: 'border-l-orange-500',
  4: 'border-l-red-500',
}

const getDepthClass = (depth: number) => {
  return depthColors[Math.min(depth, 4)] || depthColors[0]
}
```

**REFACTOR**: スタイル定数を別ファイルに抽出

---

### 1.2 親バッジ

#### ユニットテスト

```typescript
describe('TaskCard - Parent Badge', () => {
  it('does not render parent badge when parentTaskId is null', () => {
    const task = { ...mockTask, parentTaskId: null }
    render(<TaskCard task={task} />)
    expect(screen.queryByTestId('parent-badge')).not.toBeInTheDocument()
  })

  it('renders parent badge with parent title when parentTaskId exists', () => {
    const task = { ...mockTask, parentTaskId: 'parent-1' }
    const parentTask = { id: 'parent-1', title: '認証機能' }
    render(<TaskCard task={task} parentTask={parentTask} />)

    const badge = screen.getByTestId('parent-badge')
    expect(badge).toBeInTheDocument()
    expect(badge).toHaveTextContent('📁')
    expect(badge).toHaveTextContent('認証機能')
  })

  it('calls onParentClick when parent badge is clicked', async () => {
    const onParentClick = vi.fn()
    const task = { ...mockTask, parentTaskId: 'parent-1' }
    const parentTask = { id: 'parent-1', title: '認証機能' }

    render(
      <TaskCard
        task={task}
        parentTask={parentTask}
        onParentClick={onParentClick}
      />
    )

    await userEvent.click(screen.getByTestId('parent-badge'))
    expect(onParentClick).toHaveBeenCalledWith('parent-1')
  })
})
```

#### 実装

**RED** → **GREEN** → **REFACTOR**

---

### 1.3 依存数インジケーター

#### ユニットテスト

```typescript
describe('TaskCard - Dependency Indicators', () => {
  it('does not render upstream indicator when dependencies is empty', () => {
    const task = { ...mockTask, dependencies: [] }
    render(<TaskCard task={task} />)
    expect(screen.queryByTestId('upstream-indicator')).not.toBeInTheDocument()
  })

  it('renders upstream indicator with count when dependencies exist', () => {
    const task = { ...mockTask, dependencies: ['dep-1', 'dep-2'] }
    render(<TaskCard task={task} />)

    const indicator = screen.getByTestId('upstream-indicator')
    expect(indicator).toHaveTextContent('⬆️')
    expect(indicator).toHaveTextContent('2')
  })

  it('does not render downstream indicator when dependentTasks is empty', () => {
    const task = { ...mockTask, dependentTasks: [] }
    render(<TaskCard task={task} />)
    expect(screen.queryByTestId('downstream-indicator')).not.toBeInTheDocument()
  })

  it('renders downstream indicator with count when dependentTasks exist', () => {
    const task = { ...mockTask, dependentTasks: ['dep-1'] }
    render(<TaskCard task={task} />)

    const indicator = screen.getByTestId('downstream-indicator')
    expect(indicator).toHaveTextContent('⬇️')
    expect(indicator).toHaveTextContent('1')
  })

  it('shows tooltip with task titles on hover', async () => {
    const task = { ...mockTask, dependencies: ['dep-1', 'dep-2'] }
    const dependencyTasks = [
      { id: 'dep-1', title: 'DB設計' },
      { id: 'dep-2', title: 'API設計' },
    ]

    render(<TaskCard task={task} dependencyTasks={dependencyTasks} />)

    await userEvent.hover(screen.getByTestId('upstream-indicator'))

    expect(await screen.findByRole('tooltip')).toHaveTextContent('DB設計')
    expect(await screen.findByRole('tooltip')).toHaveTextContent('API設計')
  })
})
```

---

### 1.4 Blocked カラムでの理由表示

#### ユニットテスト

```typescript
describe('TaskCard - Blocked Reason', () => {
  it('does not render blocked reason for non-blocked tasks', () => {
    const task = { ...mockTask, status: 'in_progress' }
    render(<TaskCard task={task} />)
    expect(screen.queryByTestId('blocked-reason')).not.toBeInTheDocument()
  })

  it('renders blocked reason section for blocked tasks', () => {
    const task = {
      ...mockTask,
      status: 'blocked',
      dependencies: ['dep-1', 'dep-2'],
    }
    const blockingTasks = [
      { id: 'dep-1', title: '認証機能実装', status: 'in_progress' },
      { id: 'dep-2', title: 'API設計', status: 'todo' },
    ]

    render(<TaskCard task={task} blockingTasks={blockingTasks} showBlockedReason />)

    const blockedSection = screen.getByTestId('blocked-reason')
    expect(blockedSection).toHaveTextContent('⛔ Blocked by:')
    expect(blockedSection).toHaveTextContent('認証機能実装')
    expect(blockedSection).toHaveTextContent('(in_progress)')
    expect(blockedSection).toHaveTextContent('API設計')
    expect(blockedSection).toHaveTextContent('(todo)')
  })

  it('navigates to blocking task when clicked', async () => {
    const onTaskClick = vi.fn()
    const task = { ...mockTask, status: 'blocked', dependencies: ['dep-1'] }
    const blockingTasks = [{ id: 'dep-1', title: '認証機能実装', status: 'in_progress' }]

    render(
      <TaskCard
        task={task}
        blockingTasks={blockingTasks}
        showBlockedReason
        onTaskClick={onTaskClick}
      />
    )

    await userEvent.click(screen.getByText('認証機能実装'))
    expect(onTaskClick).toHaveBeenCalledWith('dep-1')
  })
})
```

---

## Phase 2: KanbanColumn のソート

### 2.1 親子ソートユーティリティ

**ファイル**: `web-ui/src/utils/taskSorting.ts`

#### ユニットテスト

**ファイル**: `web-ui/src/utils/taskSorting.test.ts`

```typescript
import { sortTasksWithHierarchy, calculateTaskDepth } from './taskSorting'

describe('calculateTaskDepth', () => {
  it('returns 0 for root task (no parent)', () => {
    const tasks = [{ id: 'task-1', parentTaskId: null }]
    expect(calculateTaskDepth('task-1', tasks)).toBe(0)
  })

  it('returns 1 for direct child of root', () => {
    const tasks = [
      { id: 'root', parentTaskId: null },
      { id: 'child', parentTaskId: 'root' },
    ]
    expect(calculateTaskDepth('child', tasks)).toBe(1)
  })

  it('returns correct depth for deeply nested task', () => {
    const tasks = [
      { id: 'l0', parentTaskId: null },
      { id: 'l1', parentTaskId: 'l0' },
      { id: 'l2', parentTaskId: 'l1' },
      { id: 'l3', parentTaskId: 'l2' },
    ]
    expect(calculateTaskDepth('l3', tasks)).toBe(3)
  })

  it('handles circular reference gracefully', () => {
    const tasks = [
      { id: 'a', parentTaskId: 'b' },
      { id: 'b', parentTaskId: 'a' },
    ]
    // Should not infinite loop, return max depth or throw
    expect(() => calculateTaskDepth('a', tasks)).not.toThrow()
  })
})

describe('sortTasksWithHierarchy', () => {
  it('places root tasks before their children', () => {
    const tasks = [
      { id: 'child', parentTaskId: 'root', title: 'Child' },
      { id: 'root', parentTaskId: null, title: 'Root' },
    ]

    const sorted = sortTasksWithHierarchy(tasks)

    expect(sorted[0].id).toBe('root')
    expect(sorted[1].id).toBe('child')
  })

  it('groups children under their parent', () => {
    const tasks = [
      { id: 'root1', parentTaskId: null },
      { id: 'root2', parentTaskId: null },
      { id: 'child1-of-root1', parentTaskId: 'root1' },
      { id: 'child2-of-root1', parentTaskId: 'root1' },
      { id: 'child1-of-root2', parentTaskId: 'root2' },
    ]

    const sorted = sortTasksWithHierarchy(tasks)
    const ids = sorted.map(t => t.id)

    // root1 の子は root1 の直後、root2 の前
    expect(ids.indexOf('child1-of-root1')).toBeLessThan(ids.indexOf('root2'))
    expect(ids.indexOf('child2-of-root1')).toBeLessThan(ids.indexOf('root2'))
  })

  it('sorts by depth within same tree', () => {
    const tasks = [
      { id: 'grandchild', parentTaskId: 'child' },
      { id: 'root', parentTaskId: null },
      { id: 'child', parentTaskId: 'root' },
    ]

    const sorted = sortTasksWithHierarchy(tasks)
    const ids = sorted.map(t => t.id)

    expect(ids).toEqual(['root', 'child', 'grandchild'])
  })

  it('handles tasks whose parent is in different column', () => {
    // 親が別カラムにいる場合、その子はルートタスクと同様に扱う
    const tasksInThisColumn = [
      { id: 'orphan-child', parentTaskId: 'parent-in-other-column' },
      { id: 'root', parentTaskId: null },
    ]
    const allTasks = [
      ...tasksInThisColumn,
      { id: 'parent-in-other-column', parentTaskId: null },
    ]

    const sorted = sortTasksWithHierarchy(tasksInThisColumn, allTasks)

    // orphan-child は親が同一カラムにいないので、ルート扱い
    expect(sorted.length).toBe(2)
  })
})
```

#### 実装

```typescript
// web-ui/src/utils/taskSorting.ts

export function calculateTaskDepth(
  taskId: string,
  allTasks: Task[],
  maxDepth = 10
): number {
  const taskMap = new Map(allTasks.map(t => [t.id, t]))
  let depth = 0
  let current = taskMap.get(taskId)
  const visited = new Set<string>()

  while (current?.parentTaskId && depth < maxDepth) {
    if (visited.has(current.id)) break // 循環参照対策
    visited.add(current.id)
    current = taskMap.get(current.parentTaskId)
    depth++
  }

  return depth
}

export function sortTasksWithHierarchy(
  tasksInColumn: Task[],
  allTasks?: Task[]
): Task[] {
  const all = allTasks || tasksInColumn
  const inColumnIds = new Set(tasksInColumn.map(t => t.id))

  // 深さを計算
  const tasksWithDepth = tasksInColumn.map(task => ({
    task,
    depth: calculateTaskDepth(task.id, all),
    // 親が同一カラムにいるかどうか
    parentInColumn: task.parentTaskId ? inColumnIds.has(task.parentTaskId) : false,
  }))

  // ツリー構造でソート
  return buildSortedTree(tasksWithDepth)
}
```

---

### 2.2 KanbanColumn への統合

#### ユニットテスト

**ファイル**: `web-ui/src/components/task/KanbanBoard/KanbanColumn.test.tsx`

```typescript
describe('KanbanColumn - Hierarchical Sorting', () => {
  it('renders tasks in hierarchical order', () => {
    const tasks = [
      { id: 'child', parentTaskId: 'root', title: 'Child Task' },
      { id: 'root', parentTaskId: null, title: 'Root Task' },
    ]

    render(<KanbanColumn status="todo" tasks={tasks} />)

    const cards = screen.getAllByTestId('task-card')
    expect(cards[0]).toHaveTextContent('Root Task')
    expect(cards[1]).toHaveTextContent('Child Task')
  })

  it('passes correct depth to TaskCard', () => {
    const tasks = [
      { id: 'root', parentTaskId: null, title: 'Root' },
      { id: 'child', parentTaskId: 'root', title: 'Child' },
      { id: 'grandchild', parentTaskId: 'child', title: 'Grandchild' },
    ]

    render(<KanbanColumn status="todo" tasks={tasks} />)

    const cards = screen.getAllByTestId('task-card')
    expect(cards[0]).toHaveClass('border-l-blue-500')   // depth 0
    expect(cards[1]).toHaveClass('border-l-green-500')  // depth 1
    expect(cards[2]).toHaveClass('border-l-yellow-500') // depth 2
  })
})
```

---

## Phase 3: TaskDetailPanel の拡張

### 3.1 階層パス表示

#### ユニットテスト

**ファイル**: `web-ui/src/components/task/TaskDetailPanel/TaskDetailPanel.test.tsx`

```typescript
describe('TaskDetailPanel - Hierarchy Path', () => {
  it('does not render hierarchy path for root task', () => {
    const task = { ...mockTask, parentTaskId: null }
    render(<TaskDetailPanel task={task} />)
    expect(screen.queryByTestId('hierarchy-path')).not.toBeInTheDocument()
  })

  it('renders hierarchy path with all ancestors', () => {
    const task = { ...mockTask, id: 'grandchild', parentTaskId: 'child' }
    const ancestors = [
      { id: 'root', title: '認証機能' },
      { id: 'child', title: 'ログイン機能' },
    ]

    render(<TaskDetailPanel task={task} ancestors={ancestors} />)

    const path = screen.getByTestId('hierarchy-path')
    expect(path).toHaveTextContent('認証機能')
    expect(path).toHaveTextContent('>')
    expect(path).toHaveTextContent('ログイン機能')
  })

  it('navigates to ancestor when clicked', async () => {
    const onTaskSelect = vi.fn()
    const task = { ...mockTask, id: 'child', parentTaskId: 'root' }
    const ancestors = [{ id: 'root', title: '認証機能' }]

    render(
      <TaskDetailPanel
        task={task}
        ancestors={ancestors}
        onTaskSelect={onTaskSelect}
      />
    )

    await userEvent.click(screen.getByText('認証機能'))
    expect(onTaskSelect).toHaveBeenCalledWith('root')
  })
})
```

### 3.2 子タスク一覧

```typescript
describe('TaskDetailPanel - Child Tasks', () => {
  it('does not render children section when no children', () => {
    const task = { ...mockTask }
    render(<TaskDetailPanel task={task} children={[]} />)
    expect(screen.queryByTestId('children-section')).not.toBeInTheDocument()
  })

  it('renders children section with task list', () => {
    const task = { ...mockTask }
    const children = [
      { id: 'child-1', title: 'ログイン画面', status: 'done' },
      { id: 'child-2', title: 'ログアウト処理', status: 'in_progress' },
    ]

    render(<TaskDetailPanel task={task} childTasks={children} />)

    const section = screen.getByTestId('children-section')
    expect(section).toHaveTextContent('子タスク (2件)')
    expect(section).toHaveTextContent('ログイン画面')
    expect(section).toHaveTextContent('[Done]')
    expect(section).toHaveTextContent('ログアウト処理')
    expect(section).toHaveTextContent('[In Progress]')
  })
})
```

### 3.3 依存関係セクション

```typescript
describe('TaskDetailPanel - Dependencies Section', () => {
  it('renders upstream dependencies with status', () => {
    const task = { ...mockTask, dependencies: ['dep-1', 'dep-2'] }
    const upstreamTasks = [
      { id: 'dep-1', title: 'DB設計', status: 'done' },
      { id: 'dep-2', title: 'API設計', status: 'in_progress' },
    ]

    render(<TaskDetailPanel task={task} upstreamTasks={upstreamTasks} />)

    const section = screen.getByTestId('upstream-dependencies')
    expect(section).toHaveTextContent('依存先')
    expect(section).toHaveTextContent('✅')  // done
    expect(section).toHaveTextContent('DB設計')
    expect(section).toHaveTextContent('🔴')  // in_progress
    expect(section).toHaveTextContent('API設計')
  })

  it('renders downstream dependencies', () => {
    const task = { ...mockTask, dependentTasks: ['dep-1'] }
    const downstreamTasks = [
      { id: 'dep-1', title: 'E2Eテスト', status: 'blocked' },
    ]

    render(<TaskDetailPanel task={task} downstreamTasks={downstreamTasks} />)

    const section = screen.getByTestId('downstream-dependencies')
    expect(section).toHaveTextContent('依存元')
    expect(section).toHaveTextContent('⏸️')  // blocked
    expect(section).toHaveTextContent('E2Eテスト')
  })
})
```

---

## Phase 4: E2E テスト

### 4.1 Page Object 拡張

**ファイル**: `web-ui/e2e/pages/task-board.page.ts`

```typescript
export class TaskBoardPage extends BasePage {
  // 既存メソッド...

  // 追加メソッド
  async getTaskCardDepthColor(taskId: string): Promise<string> {
    const card = this.page.locator(`[data-testid="task-card-${taskId}"]`)
    return card.evaluate(el => {
      const style = window.getComputedStyle(el)
      return style.borderLeftColor
    })
  }

  async getParentBadgeText(taskId: string): Promise<string | null> {
    const badge = this.page.locator(
      `[data-testid="task-card-${taskId}"] [data-testid="parent-badge"]`
    )
    if (await badge.isVisible()) {
      return badge.textContent()
    }
    return null
  }

  async clickParentBadge(taskId: string): Promise<void> {
    await this.page.locator(
      `[data-testid="task-card-${taskId}"] [data-testid="parent-badge"]`
    ).click()
  }

  async getTaskOrderInColumn(status: string): Promise<string[]> {
    const cards = this.page.locator(
      `[data-testid="column-${status}"] [data-testid^="task-card-"]`
    )
    const ids: string[] = []
    for (const card of await cards.all()) {
      const testId = await card.getAttribute('data-testid')
      ids.push(testId?.replace('task-card-', '') || '')
    }
    return ids
  }

  async getDependencyIndicators(taskId: string): Promise<{
    upstream: number | null
    downstream: number | null
  }> {
    const card = this.page.locator(`[data-testid="task-card-${taskId}"]`)

    const upstreamEl = card.locator('[data-testid="upstream-indicator"]')
    const downstreamEl = card.locator('[data-testid="downstream-indicator"]')

    const upstream = await upstreamEl.isVisible()
      ? parseInt(await upstreamEl.textContent() || '0', 10)
      : null
    const downstream = await downstreamEl.isVisible()
      ? parseInt(await downstreamEl.textContent() || '0', 10)
      : null

    return { upstream, downstream }
  }
}
```

### 4.2 E2E テストシナリオ

**ファイル**: `web-ui/e2e/tests/task-hierarchy.spec.ts`

```typescript
import { test, expect } from '@playwright/test'
import { TaskBoardPage } from '../pages/task-board.page'

test.describe('Task Hierarchy Display', () => {
  let taskBoard: TaskBoardPage

  test.beforeEach(async ({ page }) => {
    taskBoard = new TaskBoardPage(page)
    await taskBoard.goto('/projects/test-project/tasks')
  })

  test('displays depth indicator colors correctly', async () => {
    // L0 タスク（青）
    const rootColor = await taskBoard.getTaskCardDepthColor('root-task')
    expect(rootColor).toContain('59, 130, 246') // blue-500

    // L1 タスク（緑）
    const childColor = await taskBoard.getTaskCardDepthColor('child-task')
    expect(childColor).toContain('16, 185, 129') // green-500
  })

  test('displays parent badge for child tasks', async () => {
    const badge = await taskBoard.getParentBadgeText('child-task')
    expect(badge).toContain('📁')
    expect(badge).toContain('Root Task')
  })

  test('navigates to parent task when badge clicked', async ({ page }) => {
    await taskBoard.clickParentBadge('child-task')

    // 親タスクの詳細パネルが開く
    await expect(page.locator('[data-testid="task-detail-panel"]'))
      .toContainText('Root Task')
  })

  test('sorts tasks hierarchically within column', async () => {
    const order = await taskBoard.getTaskOrderInColumn('todo')

    // root が child より先
    const rootIndex = order.indexOf('root-task')
    const childIndex = order.indexOf('child-task')
    expect(rootIndex).toBeLessThan(childIndex)
  })

  test('displays dependency indicators', async () => {
    const indicators = await taskBoard.getDependencyIndicators('blocked-task')

    expect(indicators.upstream).toBe(2)  // 2つの依存先
    expect(indicators.downstream).toBe(1) // 1つの依存元
  })
})

test.describe('Blocked Task Display', () => {
  test('shows blocking reason in blocked column', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)
    await taskBoard.goto('/projects/test-project/tasks')

    const blockedCard = page.locator('[data-testid="task-card-blocked-task"]')

    await expect(blockedCard).toContainText('⛔ Blocked by:')
    await expect(blockedCard).toContainText('Dependency Task 1')
    await expect(blockedCard).toContainText('(in_progress)')
  })

  test('navigates to blocking task when clicked', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)
    await taskBoard.goto('/projects/test-project/tasks')

    await page.locator('[data-testid="task-card-blocked-task"]')
      .getByText('Dependency Task 1')
      .click()

    await expect(page.locator('[data-testid="task-detail-panel"]'))
      .toContainText('Dependency Task 1')
  })
})
```

### 4.3 E2E テスト用 MSW ハンドラー

**ファイル**: `web-ui/e2e/mocks/task-hierarchy-handlers.ts`

```typescript
import { http, HttpResponse } from 'msw'

export const taskHierarchyHandlers = [
  http.get('/api/v1/projects/:projectId/tasks', () => {
    return HttpResponse.json({
      tasks: [
        {
          id: 'root-task',
          title: 'Root Task',
          parentTaskId: null,
          dependencies: [],
          dependentTasks: ['child-task'],
          status: 'todo',
        },
        {
          id: 'child-task',
          title: 'Child Task',
          parentTaskId: 'root-task',
          dependencies: ['root-task'],
          dependentTasks: [],
          status: 'todo',
        },
        {
          id: 'blocked-task',
          title: 'Blocked Task',
          parentTaskId: null,
          dependencies: ['dep-1', 'dep-2'],
          dependentTasks: ['downstream-1'],
          status: 'blocked',
          blockedReason: 'Waiting for dependencies',
        },
        {
          id: 'dep-1',
          title: 'Dependency Task 1',
          parentTaskId: null,
          dependencies: [],
          dependentTasks: ['blocked-task'],
          status: 'in_progress',
        },
        {
          id: 'dep-2',
          title: 'Dependency Task 2',
          parentTaskId: null,
          dependencies: [],
          dependentTasks: ['blocked-task'],
          status: 'todo',
        },
      ],
    })
  }),
]
```

---

## Phase 5: TaskDetailPanel E2E テスト

**ファイル**: `web-ui/e2e/tests/task-detail-hierarchy.spec.ts`

```typescript
test.describe('Task Detail Panel - Hierarchy', () => {
  test('displays hierarchy path for nested task', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)
    await taskBoard.goto('/projects/test-project/tasks')

    // 深くネストされたタスクを選択
    await page.locator('[data-testid="task-card-grandchild-task"]').click()

    const path = page.locator('[data-testid="hierarchy-path"]')
    await expect(path).toContainText('Root Task')
    await expect(path).toContainText('>')
    await expect(path).toContainText('Child Task')
  })

  test('displays child tasks list', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)
    await taskBoard.goto('/projects/test-project/tasks')

    await page.locator('[data-testid="task-card-root-task"]').click()

    const childSection = page.locator('[data-testid="children-section"]')
    await expect(childSection).toContainText('子タスク')
    await expect(childSection).toContainText('Child Task')
  })

  test('displays upstream and downstream dependencies', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)
    await taskBoard.goto('/projects/test-project/tasks')

    await page.locator('[data-testid="task-card-blocked-task"]').click()

    // 依存先
    const upstream = page.locator('[data-testid="upstream-dependencies"]')
    await expect(upstream).toContainText('依存先')
    await expect(upstream).toContainText('Dependency Task 1')

    // 依存元
    const downstream = page.locator('[data-testid="downstream-dependencies"]')
    await expect(downstream).toContainText('依存元')
  })
})
```

---

## 実装順序サマリー

| Phase | 内容 | テスト数(目安) | 工数 |
|-------|------|---------------|------|
| 0 | 型定義同期 | 型チェック | 小 |
| 1.1 | 左ボーダー（深さ色） | 5 unit | 小 |
| 1.2 | 親バッジ | 3 unit | 小 |
| 1.3 | 依存数インジケーター | 5 unit | 小 |
| 1.4 | Blocked理由表示 | 3 unit | 小 |
| 2.1 | ソートユーティリティ | 5 unit | 中 |
| 2.2 | KanbanColumn統合 | 2 unit | 小 |
| 3.1 | 階層パス表示 | 3 unit | 中 |
| 3.2 | 子タスク一覧 | 2 unit | 小 |
| 3.3 | 依存関係セクション | 2 unit | 小 |
| 4 | E2E テスト | 6 e2e | 中 |
| 5 | DetailPanel E2E | 3 e2e | 小 |

**合計**: ユニットテスト約30件、E2Eテスト約9件

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-01-25 | 初版作成 |
