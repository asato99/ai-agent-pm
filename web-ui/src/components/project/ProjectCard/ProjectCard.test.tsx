import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { ProjectCard } from './ProjectCard'
import type { ProjectSummary } from '@/types'

const mockProject: ProjectSummary = {
  id: 'project-1',
  name: 'ECサイト開発',
  description: 'ECサイトの新規開発プロジェクト',
  status: 'active',
  createdAt: '2024-01-01T00:00:00Z',
  updatedAt: '2024-01-15T10:00:00Z',
  taskCount: 12,
  completedCount: 5,
  inProgressCount: 3,
  blockedCount: 1,
  myTaskCount: 3,
}

describe('ProjectCard', () => {
  it('プロジェクト名を表示する', () => {
    render(<ProjectCard project={mockProject} />)

    expect(screen.getByText('ECサイト開発')).toBeInTheDocument()
  })

  it('プロジェクト説明を表示する', () => {
    render(<ProjectCard project={mockProject} />)

    expect(screen.getByText('ECサイトの新規開発プロジェクト')).toBeInTheDocument()
  })

  it('タスク数を表示する', () => {
    render(<ProjectCard project={mockProject} />)

    expect(screen.getByText('タスク: 12')).toBeInTheDocument()
  })

  it('担当タスク数を表示する', () => {
    render(<ProjectCard project={mockProject} />)

    expect(screen.getByText('あなたの担当: 3件')).toBeInTheDocument()
  })

  it('進捗バーを表示する', () => {
    render(<ProjectCard project={mockProject} />)

    const progressBar = screen.getByRole('progressbar')
    expect(progressBar).toBeInTheDocument()
    // 5/12 = 41.67%
    expect(progressBar).toHaveAttribute('aria-valuenow', '42')
  })

  it('クリック時にonClickが呼ばれる', () => {
    const handleClick = vi.fn()
    render(<ProjectCard project={mockProject} onClick={handleClick} />)

    fireEvent.click(screen.getByTestId('project-card'))

    expect(handleClick).toHaveBeenCalledWith('project-1')
  })

  it('data-testid属性を持つ', () => {
    render(<ProjectCard project={mockProject} />)

    expect(screen.getByTestId('project-card')).toBeInTheDocument()
  })

  it('blockedタスクがある場合は警告を表示する', () => {
    render(<ProjectCard project={mockProject} />)

    expect(screen.getByText(/ブロック中: 1/)).toBeInTheDocument()
  })

  it('blockedタスクがない場合は警告を表示しない', () => {
    const projectWithoutBlocked = { ...mockProject, blockedCount: 0 }
    render(<ProjectCard project={projectWithoutBlocked} />)

    expect(screen.queryByText(/ブロック中/)).not.toBeInTheDocument()
  })
})
