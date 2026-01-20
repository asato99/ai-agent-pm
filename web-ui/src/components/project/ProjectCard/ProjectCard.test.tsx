import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { ProjectCard } from './ProjectCard'
import type { ProjectSummary } from '@/types'

const mockProject: ProjectSummary = {
  id: 'project-1',
  name: 'EC Site Development',
  description: 'New EC site development project',
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
  it('displays the project name', () => {
    render(<ProjectCard project={mockProject} />)

    expect(screen.getByText('EC Site Development')).toBeInTheDocument()
  })

  it('displays the project description', () => {
    render(<ProjectCard project={mockProject} />)

    expect(screen.getByText('New EC site development project')).toBeInTheDocument()
  })

  it('displays task count', () => {
    render(<ProjectCard project={mockProject} />)

    expect(screen.getByText('Tasks: 12')).toBeInTheDocument()
  })

  it('displays my task count', () => {
    render(<ProjectCard project={mockProject} />)

    expect(screen.getByText('My Tasks: 3')).toBeInTheDocument()
  })

  it('displays progress bar', () => {
    render(<ProjectCard project={mockProject} />)

    const progressBar = screen.getByRole('progressbar')
    expect(progressBar).toBeInTheDocument()
    // 5/12 = 41.67%
    expect(progressBar).toHaveAttribute('aria-valuenow', '42')
  })

  it('calls onClick when clicked', () => {
    const handleClick = vi.fn()
    render(<ProjectCard project={mockProject} onClick={handleClick} />)

    fireEvent.click(screen.getByTestId('project-card'))

    expect(handleClick).toHaveBeenCalledWith('project-1')
  })

  it('has data-testid attribute', () => {
    render(<ProjectCard project={mockProject} />)

    expect(screen.getByTestId('project-card')).toBeInTheDocument()
  })

  it('displays warning when there are blocked tasks', () => {
    render(<ProjectCard project={mockProject} />)

    expect(screen.getByText(/Blocked: 1/)).toBeInTheDocument()
  })

  it('does not display warning when there are no blocked tasks', () => {
    const projectWithoutBlocked = { ...mockProject, blockedCount: 0 }
    render(<ProjectCard project={projectWithoutBlocked} />)

    expect(screen.queryByText(/Blocked/)).not.toBeInTheDocument()
  })
})
