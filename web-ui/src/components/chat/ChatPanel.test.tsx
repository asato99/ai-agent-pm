// web-ui/src/components/chat/ChatPanel.test.tsx
// ChatPanel component tests
// Reference: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 6

import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '../../../tests/test-utils'
import userEvent from '@testing-library/user-event'
import { ChatPanel } from './ChatPanel'
import type { Agent } from '@/types'

// Mock the useChat hook
const mockSendMessage = vi.fn()
const mockLoadMore = vi.fn()
const mockRefetch = vi.fn()

vi.mock('@/hooks/useChat', () => ({
  useChat: vi.fn(() => ({
    messages: [],
    isLoading: false,
    error: null,
    hasMore: false,
    sendMessage: mockSendMessage,
    isSending: false,
    refetch: mockRefetch,
    loadMore: mockLoadMore,
  })),
}))

// Mock the authStore
vi.mock('@/stores/authStore', () => ({
  useAuthStore: vi.fn(() => ({
    agent: { id: 'current-user-agent', name: 'Current User', role: 'Owner' },
    isAuthenticated: true,
  })),
}))

// Import the mocked module
import { useChat } from '@/hooks/useChat'
const mockUseChat = vi.mocked(useChat)

const mockAgent: Agent = {
  id: 'agent-1',
  name: 'Test Agent',
  role: 'Backend Developer',
  agentType: 'ai',
  status: 'active',
  hierarchyType: 'worker',
}

describe('ChatPanel', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mockUseChat.mockReturnValue({
      messages: [],
      isLoading: false,
      error: null,
      hasMore: false,
      sendMessage: mockSendMessage,
      isSending: false,
      refetch: mockRefetch,
      loadMore: mockLoadMore,
    })
  })

  describe('Header display', () => {
    it('displays agent name', () => {
      render(<ChatPanel projectId="project-1" agent={mockAgent} onClose={vi.fn()} />)

      expect(screen.getByText('Test Agent')).toBeInTheDocument()
    })

    it('displays agent role', () => {
      render(<ChatPanel projectId="project-1" agent={mockAgent} onClose={vi.fn()} />)

      expect(screen.getByText('Backend Developer')).toBeInTheDocument()
    })

    it('calls onClose when close button is clicked', async () => {
      const user = userEvent.setup()
      const mockOnClose = vi.fn()
      render(<ChatPanel projectId="project-1" agent={mockAgent} onClose={mockOnClose} />)

      const closeButton = screen.getByRole('button', { name: /close/i })
      await user.click(closeButton)

      expect(mockOnClose).toHaveBeenCalled()
    })
  })

  describe('Message display', () => {
    it('displays messages', () => {
      mockUseChat.mockReturnValue({
        messages: [
          { id: 'msg-1', senderId: 'current-user-agent', receiverId: 'agent-1', content: 'Hello', createdAt: '2026-01-21T10:00:00Z' },
          { id: 'msg-2', senderId: 'agent-1', content: 'Hi there!', createdAt: '2026-01-21T10:00:05Z' },
        ],
        isLoading: false,
        error: null,
        hasMore: false,
        sendMessage: mockSendMessage,
        isSending: false,
        refetch: mockRefetch,
        loadMore: mockLoadMore,
      })

      render(<ChatPanel projectId="project-1" agent={mockAgent} onClose={vi.fn()} />)

      expect(screen.getByText('Hello')).toBeInTheDocument()
      expect(screen.getByText('Hi there!')).toBeInTheDocument()
    })

    it('displays loading state', () => {
      mockUseChat.mockReturnValue({
        messages: [],
        isLoading: true,
        error: null,
        hasMore: false,
        sendMessage: mockSendMessage,
        isSending: false,
        refetch: mockRefetch,
        loadMore: mockLoadMore,
      })

      render(<ChatPanel projectId="project-1" agent={mockAgent} onClose={vi.fn()} />)

      expect(screen.getByTestId('chat-loading')).toBeInTheDocument()
    })

    it('displays empty state when no messages', () => {
      render(<ChatPanel projectId="project-1" agent={mockAgent} onClose={vi.fn()} />)

      expect(screen.getByText('No messages yet')).toBeInTheDocument()
    })
  })

  describe('Message sending', () => {
    it('sends message on form submit', async () => {
      const user = userEvent.setup()
      mockSendMessage.mockResolvedValue({
        id: 'msg-new',
        senderId: 'current-user-agent',
        receiverId: 'agent-1',
        content: 'Test message',
        createdAt: new Date().toISOString(),
      })

      render(<ChatPanel projectId="project-1" agent={mockAgent} onClose={vi.fn()} />)

      const input = screen.getByTestId('chat-input')
      await user.type(input, 'Test message')

      const sendButton = screen.getByTestId('chat-send-button')
      await user.click(sendButton)

      await waitFor(() => {
        expect(mockSendMessage).toHaveBeenCalledWith('Test message')
      })
    })

    it('does not send empty message', async () => {
      const user = userEvent.setup()
      render(<ChatPanel projectId="project-1" agent={mockAgent} onClose={vi.fn()} />)

      const sendButton = screen.getByTestId('chat-send-button')
      await user.click(sendButton)

      expect(mockSendMessage).not.toHaveBeenCalled()
    })

    it('disables button while sending', async () => {
      mockUseChat.mockReturnValue({
        messages: [],
        isLoading: false,
        error: null,
        hasMore: false,
        sendMessage: mockSendMessage,
        isSending: true,
        refetch: mockRefetch,
        loadMore: mockLoadMore,
      })

      render(<ChatPanel projectId="project-1" agent={mockAgent} onClose={vi.fn()} />)

      const sendButton = screen.getByTestId('chat-send-button')
      expect(sendButton).toBeDisabled()
    })
  })

  describe('Accessibility', () => {
    it('has chat-panel testId', () => {
      render(<ChatPanel projectId="project-1" agent={mockAgent} onClose={vi.fn()} />)

      expect(screen.getByTestId('chat-panel')).toBeInTheDocument()
    })

    it('input has label', () => {
      render(<ChatPanel projectId="project-1" agent={mockAgent} onClose={vi.fn()} />)

      expect(screen.getByLabelText('Chat message input')).toBeInTheDocument()
    })
  })
})
