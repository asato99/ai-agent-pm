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
  it('エージェント名を表示する', () => {
    render(<AgentCard agent={mockAgent} />)

    expect(screen.getByText('Worker 1')).toBeInTheDocument()
  })

  it('役割を表示する', () => {
    render(<AgentCard agent={mockAgent} />)

    expect(screen.getByText('Backend Developer')).toBeInTheDocument()
  })

  it('AIエージェントのアイコンを表示する', () => {
    render(<AgentCard agent={mockAgent} />)

    expect(screen.getByRole('img', { name: 'AI' })).toBeInTheDocument()
  })

  it('Humanエージェントのアイコンを表示する', () => {
    const humanAgent: Agent = { ...mockAgent, agentType: 'human' }
    render(<AgentCard agent={humanAgent} />)

    expect(screen.getByRole('img', { name: 'Human' })).toBeInTheDocument()
  })

  it('アクティブステータスを表示する', () => {
    render(<AgentCard agent={mockAgent} />)

    expect(screen.getByText('アクティブ')).toBeInTheDocument()
  })

  it('非アクティブステータスを表示する', () => {
    const inactiveAgent: Agent = { ...mockAgent, status: 'inactive' }
    render(<AgentCard agent={inactiveAgent} />)

    expect(screen.getByText('非アクティブ')).toBeInTheDocument()
  })

  it('停止中ステータスを表示する', () => {
    const suspendedAgent: Agent = { ...mockAgent, status: 'suspended' }
    render(<AgentCard agent={suspendedAgent} />)

    expect(screen.getByText('停止中')).toBeInTheDocument()
  })

  it('アーカイブステータスを表示する', () => {
    const archivedAgent: Agent = { ...mockAgent, status: 'archived' }
    render(<AgentCard agent={archivedAgent} />)

    expect(screen.getByText('アーカイブ')).toBeInTheDocument()
  })

  it('ワーカー階層タイプを表示する', () => {
    render(<AgentCard agent={mockAgent} />)

    expect(screen.getByText('ワーカー')).toBeInTheDocument()
  })

  it('マネージャー階層タイプを表示する', () => {
    const managerAgent: Agent = { ...mockAgent, hierarchyType: 'manager' }
    render(<AgentCard agent={managerAgent} />)

    expect(screen.getByText('マネージャー')).toBeInTheDocument()
  })

  it('オーナー階層タイプを表示する', () => {
    const ownerAgent: Agent = { ...mockAgent, hierarchyType: 'owner' }
    render(<AgentCard agent={ownerAgent} />)

    expect(screen.getByText('オーナー')).toBeInTheDocument()
  })

  it('クリック時にonClickが呼ばれる', () => {
    const handleClick = vi.fn()
    render(<AgentCard agent={mockAgent} onClick={handleClick} />)

    fireEvent.click(screen.getByTestId('agent-card'))

    expect(handleClick).toHaveBeenCalledWith('worker-1')
  })

  it('data-testid属性を持つ', () => {
    render(<AgentCard agent={mockAgent} />)

    expect(screen.getByTestId('agent-card')).toBeInTheDocument()
  })

  it('onClickが未指定でもエラーにならない', () => {
    render(<AgentCard agent={mockAgent} />)

    // Should not throw
    fireEvent.click(screen.getByTestId('agent-card'))
  })
})
