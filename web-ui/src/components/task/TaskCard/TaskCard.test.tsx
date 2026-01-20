import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
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
  dependencies: [],
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
