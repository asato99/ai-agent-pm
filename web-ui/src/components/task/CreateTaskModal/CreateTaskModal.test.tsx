import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '../../../../tests/test-utils'
import { CreateTaskModal } from './CreateTaskModal'

// Mock useAssignableAgents hook
vi.mock('@/hooks', () => ({
  useAssignableAgents: () => ({
    agents: [
      { id: 'worker-1', name: 'Worker 1', role: 'Developer', agentType: 'ai', status: 'active', hierarchyType: 'worker' },
      { id: 'worker-2', name: 'Worker 2', role: 'Designer', agentType: 'ai', status: 'active', hierarchyType: 'worker' },
    ],
    isLoading: false,
  }),
}))

describe('CreateTaskModal', () => {
  const mockOnClose = vi.fn()
  const mockOnSubmit = vi.fn()
  const projectId = 'project-1'

  beforeEach(() => {
    mockOnClose.mockClear()
    mockOnSubmit.mockClear()
  })

  it('does not render when isOpen is false', () => {
    render(
      <CreateTaskModal
        projectId={projectId}
        isOpen={false}
        onClose={mockOnClose}
        onSubmit={mockOnSubmit}
      />
    )

    expect(screen.queryByText('Create Task')).not.toBeInTheDocument()
  })

  it('renders form fields including Assignee when open', () => {
    render(
      <CreateTaskModal
        projectId={projectId}
        isOpen={true}
        onClose={mockOnClose}
        onSubmit={mockOnSubmit}
      />
    )

    expect(screen.getByText('Create Task')).toBeInTheDocument()
    expect(screen.getByLabelText('Title')).toBeInTheDocument()
    expect(screen.getByLabelText('Description')).toBeInTheDocument()
    expect(screen.getByLabelText('Priority')).toBeInTheDocument()
    // RED: This should fail - Assignee field does not exist yet
    expect(screen.getByLabelText('Assignee')).toBeInTheDocument()
  })

  it('displays assignable agents in dropdown', () => {
    render(
      <CreateTaskModal
        projectId={projectId}
        isOpen={true}
        onClose={mockOnClose}
        onSubmit={mockOnSubmit}
      />
    )

    // RED: This should fail - Assignee dropdown does not exist yet
    const select = screen.getByLabelText('Assignee')
    expect(select).toBeInTheDocument()

    // Check options are present
    expect(screen.getByRole('option', { name: 'Unassigned' })).toBeInTheDocument()
    expect(screen.getByRole('option', { name: 'Worker 1' })).toBeInTheDocument()
    expect(screen.getByRole('option', { name: 'Worker 2' })).toBeInTheDocument()
  })

  it('submits form with assigneeId', () => {
    render(
      <CreateTaskModal
        projectId={projectId}
        isOpen={true}
        onClose={mockOnClose}
        onSubmit={mockOnSubmit}
      />
    )

    // Fill in required fields
    fireEvent.change(screen.getByLabelText('Title'), { target: { value: 'New Task' } })
    fireEvent.change(screen.getByLabelText('Description'), { target: { value: 'Task description' } })
    fireEvent.change(screen.getByLabelText('Priority'), { target: { value: 'high' } })

    // RED: This should fail - Assignee field does not exist yet
    fireEvent.change(screen.getByLabelText('Assignee'), { target: { value: 'worker-1' } })

    // Submit the form
    fireEvent.click(screen.getByRole('button', { name: 'Create' }))

    // RED: onSubmit should include assigneeId
    expect(mockOnSubmit).toHaveBeenCalledWith({
      title: 'New Task',
      description: 'Task description',
      priority: 'high',
      assigneeId: 'worker-1',
    })
  })

  it('submits form without assigneeId when unassigned', () => {
    render(
      <CreateTaskModal
        projectId={projectId}
        isOpen={true}
        onClose={mockOnClose}
        onSubmit={mockOnSubmit}
      />
    )

    // Fill in required fields
    fireEvent.change(screen.getByLabelText('Title'), { target: { value: 'New Task' } })
    fireEvent.change(screen.getByLabelText('Description'), { target: { value: 'Task description' } })

    // Submit without selecting assignee
    fireEvent.click(screen.getByRole('button', { name: 'Create' }))

    // assigneeId should be undefined when unassigned
    expect(mockOnSubmit).toHaveBeenCalledWith({
      title: 'New Task',
      description: 'Task description',
      priority: 'medium',
      assigneeId: undefined,
    })
  })
})
