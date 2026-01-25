import { describe, it, expect, vi } from 'vitest'
import { render, screen, waitFor } from '../../../../tests/test-utils'
import { TaskDetailPanel } from './TaskDetailPanel'
import type { Task } from '@/types'

// Mock the hooks
vi.mock('@/hooks', () => ({
  useTaskPermissions: () => ({
    permissions: {
      canEdit: true,
      canChangeStatus: true,
      canReassign: true,
      validStatusTransitions: ['backlog', 'todo', 'in_progress', 'done'],
      reason: null,
    },
    isLoading: false,
  }),
  useTaskHandoffs: () => ({
    handoffs: [],
    isLoading: false,
  }),
  useCreateHandoff: () => ({
    mutate: vi.fn(),
    isPending: false,
  }),
  useAssignableAgents: () => ({
    agents: [
      { id: 'worker-1', name: 'Worker 1', role: 'Developer', agentType: 'ai', status: 'active', hierarchyType: 'worker' },
      { id: 'worker-2', name: 'Worker 2', role: 'Designer', agentType: 'ai', status: 'active', hierarchyType: 'worker' },
    ],
    isLoading: false,
  }),
}))

const createMockTask = (overrides: Partial<Task> = {}): Task => ({
  id: 'task-1',
  projectId: 'project-1',
  title: 'Test Task',
  description: 'Test description',
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
  ...overrides,
})

const mockTask = createMockTask()

const mockTaskUnassigned: Task = createMockTask({
  id: 'task-2',
  assigneeId: null,
})

describe('TaskDetailPanel', () => {
  it('displays task title when open', () => {
    render(<TaskDetailPanel task={mockTask} isOpen={true} onClose={() => {}} />)

    expect(screen.getByText('Test Task')).toBeInTheDocument()
  })

  it('does not render when isOpen is false', () => {
    render(<TaskDetailPanel task={mockTask} isOpen={false} onClose={() => {}} />)

    expect(screen.queryByText('Test Task')).not.toBeInTheDocument()
  })

  it('displays task description', () => {
    render(<TaskDetailPanel task={mockTask} isOpen={true} onClose={() => {}} />)

    expect(screen.getByText('Test description')).toBeInTheDocument()
  })

  it('displays priority badge', () => {
    render(<TaskDetailPanel task={mockTask} isOpen={true} onClose={() => {}} />)

    expect(screen.getByText('High')).toBeInTheDocument()
  })

  // TEST: Assignee display - this should FAIL initially (RED)
  it('displays assigned agent name', () => {
    render(<TaskDetailPanel task={mockTask} isOpen={true} onClose={() => {}} />)

    // Should show "Assignee" label and agent name
    expect(screen.getByText('Assignee')).toBeInTheDocument()
    expect(screen.getByText('Worker 1')).toBeInTheDocument()
  })

  it('displays "Unassigned" when no assignee', () => {
    render(<TaskDetailPanel task={mockTaskUnassigned} isOpen={true} onClose={() => {}} />)

    expect(screen.getByText('Assignee')).toBeInTheDocument()
    expect(screen.getByText('Unassigned')).toBeInTheDocument()
  })

  it('shows Edit button when user has edit permission', () => {
    render(<TaskDetailPanel task={mockTask} isOpen={true} onClose={() => {}} />)

    expect(screen.getByRole('button', { name: 'Edit' })).toBeInTheDocument()
  })
})

// Phase 3.1: Hierarchy Path Display
describe('TaskDetailPanel - Hierarchy Path', () => {
  it('does not render hierarchy path for root task', () => {
    const task = createMockTask({ parentTaskId: null })
    render(<TaskDetailPanel task={task} isOpen={true} onClose={() => {}} />)
    expect(screen.queryByTestId('hierarchy-path')).not.toBeInTheDocument()
  })

  it('renders hierarchy path with all ancestors', () => {
    const task = createMockTask({ id: 'grandchild', parentTaskId: 'child' })
    const ancestors = [
      { id: 'root', title: '認証機能', status: 'in_progress' as const },
      { id: 'child', title: 'ログイン機能', status: 'todo' as const },
    ]

    render(<TaskDetailPanel task={task} ancestors={ancestors} isOpen={true} onClose={() => {}} />)

    const path = screen.getByTestId('hierarchy-path')
    expect(path).toHaveTextContent('認証機能')
    expect(path).toHaveTextContent('>')
    expect(path).toHaveTextContent('ログイン機能')
  })

  it('navigates to ancestor when clicked', async () => {
    const onTaskSelect = vi.fn()
    const task = createMockTask({ id: 'child', parentTaskId: 'root' })
    const ancestors = [{ id: 'root', title: '認証機能', status: 'in_progress' as const }]

    render(
      <TaskDetailPanel
        task={task}
        ancestors={ancestors}
        onTaskSelect={onTaskSelect}
        isOpen={true}
        onClose={() => {}}
      />
    )

    const ancestorLink = screen.getByTestId('hierarchy-path').querySelector('button')
    expect(ancestorLink).toBeInTheDocument()
    await ancestorLink?.click()
    expect(onTaskSelect).toHaveBeenCalledWith('root')
  })
})

// Phase 3.2: Child Tasks
describe('TaskDetailPanel - Child Tasks', () => {
  it('does not render children section when no children', () => {
    const task = createMockTask()
    render(<TaskDetailPanel task={task} childTasks={[]} isOpen={true} onClose={() => {}} />)
    expect(screen.queryByTestId('children-section')).not.toBeInTheDocument()
  })

  it('renders children section with task list', () => {
    const task = createMockTask()
    const childTasks = [
      { id: 'child-1', title: 'ログイン画面', status: 'done' as const },
      { id: 'child-2', title: 'ログアウト処理', status: 'in_progress' as const },
    ]

    render(<TaskDetailPanel task={task} childTasks={childTasks} isOpen={true} onClose={() => {}} />)

    const section = screen.getByTestId('children-section')
    expect(section).toHaveTextContent('子タスク (2件)')
    expect(section).toHaveTextContent('ログイン画面')
    expect(section).toHaveTextContent('Done')
    expect(section).toHaveTextContent('ログアウト処理')
    expect(section).toHaveTextContent('In Progress')
  })
})

// Phase 3.3: Dependencies Section
describe('TaskDetailPanel - Dependencies Section', () => {
  it('renders upstream dependencies with status', () => {
    const task = createMockTask({ dependencies: ['dep-1', 'dep-2'] })
    const upstreamTasks = [
      { id: 'dep-1', title: 'DB設計', status: 'done' as const },
      { id: 'dep-2', title: 'API設計', status: 'in_progress' as const },
    ]

    render(<TaskDetailPanel task={task} upstreamTasks={upstreamTasks} isOpen={true} onClose={() => {}} />)

    const section = screen.getByTestId('upstream-dependencies')
    expect(section).toHaveTextContent('依存先')
    expect(section).toHaveTextContent('✅')  // done
    expect(section).toHaveTextContent('DB設計')
    expect(section).toHaveTextContent('🔴')  // in_progress
    expect(section).toHaveTextContent('API設計')
  })

  it('renders downstream dependencies', () => {
    const task = createMockTask({ dependentTasks: ['dep-1'] })
    const downstreamTasks = [
      { id: 'dep-1', title: 'E2Eテスト', status: 'blocked' as const },
    ]

    render(<TaskDetailPanel task={task} downstreamTasks={downstreamTasks} isOpen={true} onClose={() => {}} />)

    const section = screen.getByTestId('downstream-dependencies')
    expect(section).toHaveTextContent('依存元')
    expect(section).toHaveTextContent('⏸️')  // blocked
    expect(section).toHaveTextContent('E2Eテスト')
  })
})
