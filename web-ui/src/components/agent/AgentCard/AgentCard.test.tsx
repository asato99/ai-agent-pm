import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { AgentCard } from './AgentCard'
import type { Agent } from '@/types'

const mockAgent: Agent = {
  id: 'worker-1',
  name: 'Worker 1',
  role: 'Backend Developer',
  agentType: 'ai',
  status: 'active',
  hierarchyType: 'worker',
  parentAgentId: 'manager-1',
}

describe('AgentCard', () => {
  it('displays the agent name', () => {
    render(<AgentCard agent={mockAgent} />)

    expect(screen.getByText('Worker 1')).toBeInTheDocument()
  })

  it('displays the role', () => {
    render(<AgentCard agent={mockAgent} />)

    expect(screen.getByText('Backend Developer')).toBeInTheDocument()
  })

  it('displays AI agent icon', () => {
    render(<AgentCard agent={mockAgent} />)

    expect(screen.getByRole('img', { name: 'AI' })).toBeInTheDocument()
  })

  it('displays Human agent icon', () => {
    const humanAgent: Agent = { ...mockAgent, agentType: 'human' }
    render(<AgentCard agent={humanAgent} />)

    expect(screen.getByRole('img', { name: 'Human' })).toBeInTheDocument()
  })

  it('displays Active status', () => {
    render(<AgentCard agent={mockAgent} />)

    expect(screen.getByText('Active')).toBeInTheDocument()
  })

  it('displays Inactive status', () => {
    const inactiveAgent: Agent = { ...mockAgent, status: 'inactive' }
    render(<AgentCard agent={inactiveAgent} />)

    expect(screen.getByText('Inactive')).toBeInTheDocument()
  })

  it('displays Suspended status', () => {
    const suspendedAgent: Agent = { ...mockAgent, status: 'suspended' }
    render(<AgentCard agent={suspendedAgent} />)

    expect(screen.getByText('Suspended')).toBeInTheDocument()
  })

  it('displays Archived status', () => {
    const archivedAgent: Agent = { ...mockAgent, status: 'archived' }
    render(<AgentCard agent={archivedAgent} />)

    expect(screen.getByText('Archived')).toBeInTheDocument()
  })

  it('displays Worker hierarchy type', () => {
    render(<AgentCard agent={mockAgent} />)

    expect(screen.getByText('Worker')).toBeInTheDocument()
  })

  it('displays Manager hierarchy type', () => {
    const managerAgent: Agent = { ...mockAgent, hierarchyType: 'manager' }
    render(<AgentCard agent={managerAgent} />)

    expect(screen.getByText('Manager')).toBeInTheDocument()
  })

  it('displays Owner hierarchy type', () => {
    const ownerAgent: Agent = { ...mockAgent, hierarchyType: 'owner' }
    render(<AgentCard agent={ownerAgent} />)

    expect(screen.getByText('Owner')).toBeInTheDocument()
  })

  it('calls onClick when clicked', () => {
    const handleClick = vi.fn()
    render(<AgentCard agent={mockAgent} onClick={handleClick} />)

    fireEvent.click(screen.getByTestId('agent-card'))

    expect(handleClick).toHaveBeenCalledWith('worker-1')
  })

  it('has data-testid attribute', () => {
    render(<AgentCard agent={mockAgent} />)

    expect(screen.getByTestId('agent-card')).toBeInTheDocument()
  })

  it('does not throw error when onClick is not provided', () => {
    render(<AgentCard agent={mockAgent} />)

    // Should not throw
    fireEvent.click(screen.getByTestId('agent-card'))
  })
})
