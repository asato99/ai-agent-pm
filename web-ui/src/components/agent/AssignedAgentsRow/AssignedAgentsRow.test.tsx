// web-ui/src/components/agent/AssignedAgentsRow/AssignedAgentsRow.test.tsx
// TDD RED: AssignedAgentsRow 未読バッジのテスト
// Reference: docs/design/CHAT_FEATURE.md - Unread count feature

import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { AssignedAgentsRow } from './AssignedAgentsRow'
import type { Agent } from '@/types'

// Mock agents for testing
const mockAgents: Agent[] = [
  {
    id: 'worker-1',
    name: 'Worker One',
    role: 'Backend Developer',
    agentType: 'ai',
    status: 'active',
    hierarchyType: 'worker',
  },
  {
    id: 'worker-2',
    name: 'Worker Two',
    role: 'Frontend Developer',
    agentType: 'ai',
    status: 'active',
    hierarchyType: 'worker',
  },
  {
    id: 'worker-3',
    name: 'Worker Three',
    role: 'Designer',
    agentType: 'human',
    status: 'active',
    hierarchyType: 'worker',
  },
]

describe('AssignedAgentsRow unread badge', () => {
  const defaultProps = {
    agents: mockAgents,
    sessionCounts: {},
    currentAgentId: 'manager-1',
    subordinateIds: ['worker-1', 'worker-2', 'worker-3'],
    isLoading: false,
    onAgentClick: vi.fn(),
  }

  describe('未読バッジの表示', () => {
    it('unreadCount > 0 の場合、未読バッジが表示される', () => {
      render(
        <AssignedAgentsRow
          {...defaultProps}
          unreadCounts={{ 'worker-1': 3, 'worker-2': 1 }}
        />
      )

      // worker-1 に未読バッジ "3" が表示される
      const badge1 = screen.getByTestId('unread-badge-worker-1')
      expect(badge1).toBeInTheDocument()
      expect(badge1).toHaveTextContent('3')

      // worker-2 に未読バッジ "1" が表示される
      const badge2 = screen.getByTestId('unread-badge-worker-2')
      expect(badge2).toBeInTheDocument()
      expect(badge2).toHaveTextContent('1')
    })

    it('unreadCount = 0 の場合、未読バッジは表示されない', () => {
      render(
        <AssignedAgentsRow
          {...defaultProps}
          unreadCounts={{ 'worker-1': 0 }}
        />
      )

      // worker-1 のバッジは存在しない
      expect(screen.queryByTestId('unread-badge-worker-1')).not.toBeInTheDocument()
    })

    it('unreadCounts が undefined の場合、バッジは表示されない', () => {
      render(<AssignedAgentsRow {...defaultProps} />)

      // どのエージェントにもバッジは存在しない
      expect(screen.queryByTestId('unread-badge-worker-1')).not.toBeInTheDocument()
      expect(screen.queryByTestId('unread-badge-worker-2')).not.toBeInTheDocument()
      expect(screen.queryByTestId('unread-badge-worker-3')).not.toBeInTheDocument()
    })

    it('unreadCount > 9 の場合、"9+" と表示される', () => {
      render(
        <AssignedAgentsRow
          {...defaultProps}
          unreadCounts={{ 'worker-1': 15 }}
        />
      )

      const badge = screen.getByTestId('unread-badge-worker-1')
      expect(badge).toBeInTheDocument()
      expect(badge).toHaveTextContent('9+')
    })
  })

  describe('バッジのスタイル', () => {
    it('バッジは右上に配置される', () => {
      render(
        <AssignedAgentsRow
          {...defaultProps}
          unreadCounts={{ 'worker-1': 3 }}
        />
      )

      const badge = screen.getByTestId('unread-badge-worker-1')
      // Tailwind classes check: absolute, -top-1, -right-1
      expect(badge.className).toContain('absolute')
      expect(badge.className).toMatch(/-top-/)
      expect(badge.className).toMatch(/-right-/)
    })

    it('バッジは赤い背景で白文字である', () => {
      render(
        <AssignedAgentsRow
          {...defaultProps}
          unreadCounts={{ 'worker-1': 3 }}
        />
      )

      const badge = screen.getByTestId('unread-badge-worker-1')
      // Tailwind classes check: bg-red-500, text-white
      expect(badge.className).toContain('bg-red-')
      expect(badge.className).toContain('text-white')
    })
  })

  describe('セッション状態との共存', () => {
    it('セッション表示（左下）と未読バッジ（右上）が同時に表示される', () => {
      render(
        <AssignedAgentsRow
          {...defaultProps}
          sessionCounts={{ 'worker-1': 1 }}
          unreadCounts={{ 'worker-1': 3 }}
        />
      )

      // 未読バッジが存在する
      const unreadBadge = screen.getByTestId('unread-badge-worker-1')
      expect(unreadBadge).toBeInTheDocument()

      // アバターも存在する（セッション状態のインジケーターを含む）
      const avatar = screen.getByTestId('agent-avatar-worker-1')
      expect(avatar).toBeInTheDocument()
    })
  })
})
