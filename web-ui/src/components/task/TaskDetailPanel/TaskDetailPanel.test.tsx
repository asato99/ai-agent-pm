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

const mockTask: Task = {
  id: 'task-1',
  projectId: 'project-1',
  title: 'Test Task',
  description: 'Test description',
  status: 'in_progress',
  priority: 'high',
  assigneeId: 'worker-1',
  creatorId: 'manager-1',
  dependencies: [],
  contexts: [],
  createdAt: '2024-01-10T00:00:00Z',
  updatedAt: '2024-01-15T10:00:00Z',
}

const mockTaskUnassigned: Task = {
  ...mockTask,
  id: 'task-2',
  assigneeId: null,
}

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
