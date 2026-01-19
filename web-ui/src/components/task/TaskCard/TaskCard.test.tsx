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
  it('タスクタイトルを表示する', () => {
    render(<TaskCard task={mockTask} />)

    expect(screen.getByText('API実装')).toBeInTheDocument()
  })

  it('優先度に応じたバッジを表示する', () => {
    render(<TaskCard task={mockTask} />)

    expect(screen.getByText('High')).toBeInTheDocument()
  })

  it('data-testid属性を持つ', () => {
    render(<TaskCard task={mockTask} />)

    expect(screen.getByTestId('task-card')).toBeInTheDocument()
  })

  it('data-task-id属性を持つ', () => {
    render(<TaskCard task={mockTask} />)

    expect(screen.getByTestId('task-card')).toHaveAttribute('data-task-id', 'task-1')
  })

  it('クリック時にonClickが呼ばれる', () => {
    const handleClick = vi.fn()
    render(<TaskCard task={mockTask} onClick={handleClick} />)

    fireEvent.click(screen.getByTestId('task-card'))

    expect(handleClick).toHaveBeenCalledWith('task-1')
  })

  it('Low優先度のスタイルが適用される', () => {
    const lowPriorityTask = { ...mockTask, priority: 'low' as const }
    render(<TaskCard task={lowPriorityTask} />)

    expect(screen.getByText('Low')).toBeInTheDocument()
  })

  it('urgent優先度のスタイルが適用される', () => {
    const urgentTask = { ...mockTask, priority: 'urgent' as const }
    render(<TaskCard task={urgentTask} />)

    expect(screen.getByText('Urgent')).toBeInTheDocument()
  })
})
