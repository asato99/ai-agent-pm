import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { TaskCard } from './TaskCard'
import type { Task } from '@/types'

const mockTask: Task = {
  id: 'task-1',
  projectId: 'project-1',
  title: 'API実装',
  description: 'REST APIエンドポイントの実装',
  status: 'in_progress',
  priority: 'high',
  assigneeId: 'worker-1',
  creatorId: 'manager-1',
  parentTaskId: null,
  dependencies: [],
  dependentTasks: [],
  blockedReason: null,
  estimatedMinutes: null,
  actualMinutes: null,
  approvalStatus: 'approved',
  requesterId: null,
  rejectedReason: null,
  contexts: [],
  createdAt: '2024-01-10T00:00:00Z',
  updatedAt: '2024-01-15T10:00:00Z',
}

describe('TaskCard', () => {
  it('displays task title', () => {
    render(<TaskCard task={mockTask} />)

    expect(screen.getByText('API実装')).toBeInTheDocument()
  })

  it('displays priority badge', () => {
    render(<TaskCard task={mockTask} />)

    expect(screen.getByText('High')).toBeInTheDocument()
  })

  it('has data-testid attribute', () => {
    render(<TaskCard task={mockTask} />)

    expect(screen.getByTestId('task-card')).toBeInTheDocument()
  })

  it('has data-task-id attribute', () => {
    render(<TaskCard task={mockTask} />)

    expect(screen.getByTestId('task-card')).toHaveAttribute('data-task-id', 'task-1')
  })

  it('calls onClick when clicked', () => {
    const handleClick = vi.fn()
    render(<TaskCard task={mockTask} onClick={handleClick} />)

    fireEvent.click(screen.getByTestId('task-card'))

    expect(handleClick).toHaveBeenCalledWith('task-1')
  })

  it('applies Low priority style', () => {
    const lowPriorityTask = { ...mockTask, priority: 'low' as const }
    render(<TaskCard task={lowPriorityTask} />)

    expect(screen.getByText('Low')).toBeInTheDocument()
  })

  it('applies Urgent priority style', () => {
    const urgentTask = { ...mockTask, priority: 'urgent' as const }
    render(<TaskCard task={urgentTask} />)

    expect(screen.getByText('Urgent')).toBeInTheDocument()
  })
})

describe('TaskCard - Depth Indicator', () => {
  it('renders blue left border for root task (depth 0)', () => {
    render(<TaskCard task={mockTask} depth={0} />)
    const card = screen.getByTestId('task-card')
    expect(card).toHaveClass('border-l-blue-500')
  })

  it('renders green left border for depth 1', () => {
    render(<TaskCard task={mockTask} depth={1} />)
    const card = screen.getByTestId('task-card')
    expect(card).toHaveClass('border-l-green-500')
  })

  it('renders yellow left border for depth 2', () => {
    render(<TaskCard task={mockTask} depth={2} />)
    const card = screen.getByTestId('task-card')
    expect(card).toHaveClass('border-l-yellow-500')
  })

  it('renders orange left border for depth 3', () => {
    render(<TaskCard task={mockTask} depth={3} />)
    const card = screen.getByTestId('task-card')
    expect(card).toHaveClass('border-l-orange-500')
  })

  it('renders red left border for depth 4+', () => {
    render(<TaskCard task={mockTask} depth={5} />)
    const card = screen.getByTestId('task-card')
    expect(card).toHaveClass('border-l-red-500')
  })

  it('renders blue left border when depth is not provided (defaults to 0)', () => {
    render(<TaskCard task={mockTask} />)
    const card = screen.getByTestId('task-card')
    expect(card).toHaveClass('border-l-blue-500')
  })
})

describe('TaskCard - Parent Badge', () => {
  it('does not render parent badge when parentTaskId is null', () => {
    const task = { ...mockTask, parentTaskId: null }
    render(<TaskCard task={task} />)
    expect(screen.queryByTestId('parent-badge')).not.toBeInTheDocument()
  })

  it('renders parent badge with parent title when parentTask is provided', () => {
    const task = { ...mockTask, parentTaskId: 'parent-1' }
    const parentTask = { ...mockTask, id: 'parent-1', title: '認証機能' }
    render(<TaskCard task={task} parentTask={parentTask} />)

    const badge = screen.getByTestId('parent-badge')
    expect(badge).toBeInTheDocument()
    expect(badge).toHaveTextContent('📁')
    expect(badge).toHaveTextContent('認証機能')
  })

  it('calls onParentClick when parent badge is clicked', async () => {
    const onParentClick = vi.fn()
    const task = { ...mockTask, parentTaskId: 'parent-1' }
    const parentTask = { ...mockTask, id: 'parent-1', title: '認証機能' }

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
})

describe('TaskCard - Blocked Reason', () => {
  it('does not render blocked reason for non-blocked tasks', () => {
    const task = { ...mockTask, status: 'in_progress' as const }
    render(<TaskCard task={task} />)
    expect(screen.queryByTestId('blocked-reason')).not.toBeInTheDocument()
  })

  it('renders blocked reason section for blocked tasks with showBlockedReason', () => {
    const task = {
      ...mockTask,
      status: 'blocked' as const,
      dependencies: ['dep-1', 'dep-2'],
    }
    const blockingTasks = [
      { ...mockTask, id: 'dep-1', title: '認証機能実装', status: 'in_progress' as const },
      { ...mockTask, id: 'dep-2', title: 'API設計', status: 'todo' as const },
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
    const task = { ...mockTask, status: 'blocked' as const, dependencies: ['dep-1'] }
    const blockingTasks = [{ ...mockTask, id: 'dep-1', title: '認証機能実装', status: 'in_progress' as const }]

    render(
      <TaskCard
        task={task}
        blockingTasks={blockingTasks}
        showBlockedReason
        onTaskClick={onTaskClick}
      />
    )

    // Find the blocking task item by its text content (partial match)
    const blockedSection = screen.getByTestId('blocked-reason')
    const blockingTaskItem = blockedSection.querySelector('li')
    expect(blockingTaskItem).not.toBeNull()
    await userEvent.click(blockingTaskItem!)
    expect(onTaskClick).toHaveBeenCalledWith('dep-1')
  })
})
