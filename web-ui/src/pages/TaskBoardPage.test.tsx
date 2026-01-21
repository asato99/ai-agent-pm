import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '../../tests/test-utils'
import { TaskBoardPage } from './TaskBoardPage'
import type { Task, Project } from '@/types'

// Mock react-router-dom
vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom')
  return {
    ...actual,
    useParams: () => ({ id: 'project-1' }),
    Link: ({ children, to }: { children: React.ReactNode; to: string }) => (
      <a href={to}>{children}</a>
    ),
  }
})

const mockProject: Project = {
  id: 'project-1',
  name: 'Test Project',
  description: 'Test description',
  status: 'active',
  createdAt: '2024-01-01T00:00:00Z',
  updatedAt: '2024-01-01T00:00:00Z',
}

const mockTasks: Task[] = [
  {
    id: 'task-1',
    projectId: 'project-1',
    title: 'Test Task',
    description: 'Test description',
    status: 'todo',
    priority: 'medium',
    assigneeId: 'worker-1',
    creatorId: 'manager-1',
    dependencies: [],
    contexts: [],
    createdAt: '2024-01-10T00:00:00Z',
    updatedAt: '2024-01-15T10:00:00Z',
  },
]

// Track current mock data that can be updated
let currentTasks = [...mockTasks]

// Mock the hooks
vi.mock('@/hooks/useProject', () => ({
  useProject: () => ({
    project: mockProject,
    isLoading: false,
  }),
}))

vi.mock('@/hooks/useTasks', () => ({
  useTasks: () => ({
    tasks: currentTasks,
    isLoading: false,
  }),
}))

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
    ],
    isLoading: false,
  }),
}))

// Mock mutation for updating task
const mockMutate = vi.fn()
vi.mock('@tanstack/react-query', async () => {
  const actual = await vi.importActual('@tanstack/react-query')
  return {
    ...actual,
    useMutation: () => ({
      mutate: mockMutate,
      isPending: false,
    }),
    useQueryClient: () => ({
      invalidateQueries: vi.fn(),
    }),
  }
})

describe('TaskBoardPage', () => {
  beforeEach(() => {
    currentTasks = [...mockTasks]
    mockMutate.mockClear()
  })

  it('renders project name and task board', () => {
    render(<TaskBoardPage />)

    expect(screen.getByText('Test Project')).toBeInTheDocument()
    expect(screen.getByText('Test Task')).toBeInTheDocument()
  })

  // TEST: Reactivity - Detail panel should update when task data changes (RED expected)
  it('updates detail panel when underlying task data changes', async () => {
    const { rerender } = render(<TaskBoardPage />)

    // Click on task to open detail panel
    fireEvent.click(screen.getByText('Test Task'))

    // Verify detail panel shows original title
    await waitFor(() => {
      expect(screen.getByRole('dialog')).toBeInTheDocument()
    })
    // Check title in dialog (h2 inside dialog)
    const dialog = screen.getByRole('dialog')
    expect(dialog.querySelector('h2')).toHaveTextContent('Test Task')

    // Simulate task data being updated (e.g., after edit and query invalidation)
    currentTasks = [
      {
        ...mockTasks[0],
        title: 'Updated Task Title',
      },
    ]

    // Re-render to simulate React Query refetch
    rerender(<TaskBoardPage />)

    // Detail panel should show updated title (this should FAIL if not reactive)
    await waitFor(() => {
      expect(dialog.querySelector('h2')).toHaveTextContent('Updated Task Title')
    })
  })
})
