// web-ui/src/components/chat/ChatPanel.test.tsx
// ChatPanelコンポーネントのテスト
// 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 6

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

  describe('ヘッダー表示', () => {
    it('エージェント名を表示する', () => {
      render(<ChatPanel projectId="project-1" agent={mockAgent} onClose={vi.fn()} />)

      expect(screen.getByText('Test Agent')).toBeInTheDocument()
    })

    it('エージェントロールを表示する', () => {
      render(<ChatPanel projectId="project-1" agent={mockAgent} onClose={vi.fn()} />)

      expect(screen.getByText('Backend Developer')).toBeInTheDocument()
    })

    it('閉じるボタンをクリックするとonCloseが呼ばれる', async () => {
      const user = userEvent.setup()
      const mockOnClose = vi.fn()
      render(<ChatPanel projectId="project-1" agent={mockAgent} onClose={mockOnClose} />)

      const closeButton = screen.getByRole('button', { name: /閉じる/i })
      await user.click(closeButton)

      expect(mockOnClose).toHaveBeenCalled()
    })
  })

  describe('メッセージ表示', () => {
    it('メッセージを表示する', () => {
      mockUseChat.mockReturnValue({
        messages: [
          { id: 'msg-1', sender: 'user', content: 'Hello', createdAt: '2026-01-21T10:00:00Z' },
          { id: 'msg-2', sender: 'agent', content: 'Hi there!', createdAt: '2026-01-21T10:00:05Z' },
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

    it('読み込み中状態を表示する', () => {
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

    it('メッセージがない場合は空状態を表示する', () => {
      render(<ChatPanel projectId="project-1" agent={mockAgent} onClose={vi.fn()} />)

      expect(screen.getByText('メッセージはまだありません')).toBeInTheDocument()
    })
  })

  describe('メッセージ送信', () => {
    it('フォーム送信でメッセージを送信する', async () => {
      const user = userEvent.setup()
      mockSendMessage.mockResolvedValue({
        id: 'msg-new',
        sender: 'user',
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

    it('空のメッセージは送信しない', async () => {
      const user = userEvent.setup()
      render(<ChatPanel projectId="project-1" agent={mockAgent} onClose={vi.fn()} />)

      const sendButton = screen.getByTestId('chat-send-button')
      await user.click(sendButton)

      expect(mockSendMessage).not.toHaveBeenCalled()
    })

    it('送信中はボタンが無効化される', async () => {
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

  describe('アクセシビリティ', () => {
    it('chat-panel testIdを持つ', () => {
      render(<ChatPanel projectId="project-1" agent={mockAgent} onClose={vi.fn()} />)

      expect(screen.getByTestId('chat-panel')).toBeInTheDocument()
    })

    it('入力欄にラベルがある', () => {
      render(<ChatPanel projectId="project-1" agent={mockAgent} onClose={vi.fn()} />)

      expect(screen.getByLabelText('チャットメッセージ入力')).toBeInTheDocument()
    })
  })
})
