import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent, waitFor } from '../../../../tests/test-utils'
import { TaskEditForm } from './TaskEditForm'
import type { Task } from '@/types'

// Mock the hooks
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
  useAssignableAgents: () => ({
    agents: [
      { id: 'worker-1', name: 'Worker 1', role: 'Developer', agentType: 'ai', status: 'active', hierarchyType: 'worker' },
      { id: 'worker-2', name: 'Worker 2', role: 'Designer', agentType: 'ai', status: 'active', hierarchyType: 'worker' },
    ],
    isLoading: false,
  }),
}))

const mockTask: Task = {
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
}

describe('TaskEditForm', () => {
  beforeEach(() => {
    mockMutate.mockClear()
  })

  it('does not render when isOpen is false', () => {
    render(<TaskEditForm task={mockTask} isOpen={false} onClose={() => {}} />)

    expect(screen.queryByText('Edit Task')).not.toBeInTheDocument()
  })

  it('renders form fields when open', () => {
    render(<TaskEditForm task={mockTask} isOpen={true} onClose={() => {}} />)

    expect(screen.getByText('Edit Task')).toBeInTheDocument()
    expect(screen.getByLabelText('Title')).toBeInTheDocument()
    expect(screen.getByLabelText('Description')).toBeInTheDocument()
    expect(screen.getByLabelText('Priority')).toBeInTheDocument()
    expect(screen.getByLabelText('Assignee')).toBeInTheDocument()
  })

  it('displays current task values', () => {
    render(<TaskEditForm task={mockTask} isOpen={true} onClose={() => {}} />)

    expect(screen.getByLabelText('Title')).toHaveValue('Test Task')
    expect(screen.getByLabelText('Description')).toHaveValue('Test description')
    expect(screen.getByLabelText('Priority')).toHaveValue('medium')
    expect(screen.getByLabelText('Assignee')).toHaveValue('worker-1')
  })

  it('displays assignable agents in dropdown', () => {
    render(<TaskEditForm task={mockTask} isOpen={true} onClose={() => {}} />)

    const select = screen.getByLabelText('Assignee')
    expect(select).toBeInTheDocument()

    // Check options are present
    expect(screen.getByRole('option', { name: 'Unassigned' })).toBeInTheDocument()
    expect(screen.getByRole('option', { name: 'Worker 1' })).toBeInTheDocument()
    expect(screen.getByRole('option', { name: 'Worker 2' })).toBeInTheDocument()
  })

  it('allows changing assignee', () => {
    render(<TaskEditForm task={mockTask} isOpen={true} onClose={() => {}} />)

    const select = screen.getByLabelText('Assignee')
    fireEvent.change(select, { target: { value: 'worker-2' } })

    expect(select).toHaveValue('worker-2')
  })

  it('allows setting assignee to unassigned', () => {
    render(<TaskEditForm task={mockTask} isOpen={true} onClose={() => {}} />)

    const select = screen.getByLabelText('Assignee')
    fireEvent.change(select, { target: { value: '' } })

    expect(select).toHaveValue('')
  })
})
