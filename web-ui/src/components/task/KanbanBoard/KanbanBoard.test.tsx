import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { KanbanBoard } from './KanbanBoard'
import type { Task } from '@/types'

const createMockTask = (overrides: Partial<Task>): Task => ({
  id: 'task-default',
  projectId: 'project-1',
  title: 'Default Task',
  description: '',
  status: 'todo',
  priority: 'medium',
  assigneeId: null,
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

const mockTasks: Task[] = [
  createMockTask({
    id: 'task-1',
    title: 'API実装',
    description: 'REST APIエンドポイントの実装',
    status: 'in_progress',
    priority: 'high',
    assigneeId: 'worker-1',
  }),
  createMockTask({
    id: 'task-2',
    title: 'DB設計',
    description: 'データベーススキーマの設計',
    status: 'done',
    priority: 'medium',
    assigneeId: 'worker-2',
    createdAt: '2024-01-08T00:00:00Z',
    updatedAt: '2024-01-12T14:00:00Z',
  }),
  createMockTask({
    id: 'task-3',
    title: 'UI設計',
    description: '画面設計',
    status: 'backlog',
    priority: 'low',
    createdAt: '2024-01-05T00:00:00Z',
    updatedAt: '2024-01-05T00:00:00Z',
  }),
]

describe('KanbanBoard', () => {
  it('displays 5 columns', () => {
    render(<KanbanBoard tasks={mockTasks} onTaskMove={vi.fn()} onTaskClick={vi.fn()} />)

    expect(screen.getByText('Backlog')).toBeInTheDocument()
    expect(screen.getByText('Todo')).toBeInTheDocument()
    expect(screen.getByText('In Progress')).toBeInTheDocument()
    expect(screen.getByText('Done')).toBeInTheDocument()
    expect(screen.getByText('Blocked')).toBeInTheDocument()
  })

  it('displays tasks in correct columns', () => {
    const { container } = render(<KanbanBoard tasks={mockTasks} onTaskMove={vi.fn()} onTaskClick={vi.fn()} />)

    // UI設計 task is in Backlog column
    const backlogColumn = container.querySelector('[data-column="backlog"]')
    expect(backlogColumn).toContainElement(screen.getByText('UI設計'))

    // API実装 task is in In Progress column
    const inProgressColumn = container.querySelector('[data-column="in_progress"]')
    expect(inProgressColumn).toContainElement(screen.getByText('API実装'))

    // DB設計 task is in Done column
    const doneColumn = container.querySelector('[data-column="done"]')
    expect(doneColumn).toContainElement(screen.getByText('DB設計'))
  })

  it('displays task count for each column', () => {
    const { container } = render(<KanbanBoard tasks={mockTasks} onTaskMove={vi.fn()} onTaskClick={vi.fn()} />)

    // Backlog: 1, Todo: 0, In Progress: 1, Done: 1, Blocked: 0
    const backlogColumn = container.querySelector('[data-column="backlog"]')
    expect(backlogColumn).toHaveTextContent('(1)')

    const todoColumn = container.querySelector('[data-column="todo"]')
    expect(todoColumn).toHaveTextContent('(0)')

    const inProgressColumn = container.querySelector('[data-column="in_progress"]')
    expect(inProgressColumn).toHaveTextContent('(1)')

    const doneColumn = container.querySelector('[data-column="done"]')
    expect(doneColumn).toHaveTextContent('(1)')
  })

  it('task cards are draggable', () => {
    render(<KanbanBoard tasks={mockTasks} onTaskMove={vi.fn()} onTaskClick={vi.fn()} />)

    const taskCards = screen.getAllByTestId('task-card')
    expect(taskCards.length).toBe(3)
  })
})

describe('KanbanBoard - Hierarchical Sorting', () => {
  it('renders tasks in hierarchical order within a column', () => {
    const hierarchicalTasks = [
      createMockTask({
        id: 'child',
        title: 'Child Task',
        status: 'todo',
        parentTaskId: 'root',
      }),
      createMockTask({
        id: 'root',
        title: 'Root Task',
        status: 'todo',
        parentTaskId: null,
      }),
    ]

    const { container } = render(
      <KanbanBoard tasks={hierarchicalTasks} onTaskMove={vi.fn()} onTaskClick={vi.fn()} />
    )

    // Get cards in todo column
    const todoColumn = container.querySelector('[data-column="todo"]')
    const cards = todoColumn?.querySelectorAll('[data-testid="task-card"]')

    expect(cards).toHaveLength(2)
    // Root should come before Child
    expect(cards?.[0]).toHaveTextContent('Root Task')
    expect(cards?.[1]).toHaveTextContent('Child Task')
  })

  it('passes correct depth to TaskCard (visible via left border color)', () => {
    const hierarchicalTasks = [
      createMockTask({
        id: 'root',
        title: 'Root',
        status: 'todo',
        parentTaskId: null,
      }),
      createMockTask({
        id: 'child',
        title: 'Child',
        status: 'todo',
        parentTaskId: 'root',
      }),
      createMockTask({
        id: 'grandchild',
        title: 'Grandchild',
        status: 'todo',
        parentTaskId: 'child',
      }),
    ]

    const { container } = render(
      <KanbanBoard tasks={hierarchicalTasks} onTaskMove={vi.fn()} onTaskClick={vi.fn()} />
    )

    const todoColumn = container.querySelector('[data-column="todo"]')
    const cards = todoColumn?.querySelectorAll('[data-testid="task-card"]')

    expect(cards).toHaveLength(3)
    // Check depth colors: blue (L0), green (L1), yellow (L2)
    expect(cards?.[0]).toHaveClass('border-l-blue-500')   // Root (depth 0)
    expect(cards?.[1]).toHaveClass('border-l-green-500')  // Child (depth 1)
    expect(cards?.[2]).toHaveClass('border-l-yellow-500') // Grandchild (depth 2)
  })
})
