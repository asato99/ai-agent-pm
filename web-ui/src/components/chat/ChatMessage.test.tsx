// web-ui/src/components/chat/ChatMessage.test.tsx
// ChatMessage component tests - Message display positioning and styling
// Reference: docs/design/CHAT_FEATURE.md - Section 11.8

import { describe, it, expect } from 'vitest'
import { render, screen } from '../../../tests/test-utils'
import { ChatMessage } from './ChatMessage'
import type { ChatMessage as ChatMessageType, Agent } from '@/types'

// Test data factory
const createMessage = (overrides: Partial<ChatMessageType> = {}): ChatMessageType => ({
  id: 'msg-1',
  senderId: 'agent-1',
  content: 'Test message',
  createdAt: '2026-01-21T10:00:00Z',
  ...overrides,
})

// Agent map for name resolution
const mockAgentMap: Record<string, Agent> = {
  'current-agent': {
    id: 'current-agent',
    name: 'Alice (Me)',
    role: 'Manager',
    agentType: 'human',
    status: 'active',
    hierarchyType: 'manager',
  },
  'target-agent': {
    id: 'target-agent',
    name: 'Bob',
    role: 'Backend Developer',
    agentType: 'ai',
    status: 'active',
    hierarchyType: 'worker',
  },
  'third-party-agent': {
    id: 'third-party-agent',
    name: 'Charlie',
    role: 'Frontend Developer',
    agentType: 'ai',
    status: 'active',
    hierarchyType: 'worker',
  },
}

describe('ChatMessage', () => {
  const currentAgentId = 'current-agent'
  const targetAgentId = 'target-agent'

  describe('Message positioning and styling by sender type', () => {
    describe('Self messages (currentAgent)', () => {
      it('displays self messages on the right side with blue background', () => {
        const message = createMessage({
          senderId: currentAgentId,
          content: 'My message',
        })

        render(
          <ChatMessage
            message={message}
            currentAgentId={currentAgentId}
            targetAgentId={targetAgentId}
            agentMap={mockAgentMap}
          />
        )

        const messageElement = screen.getByTestId('chat-message-msg-1')
        // Should be positioned on right (justify-end)
        expect(messageElement).toHaveClass('justify-end')

        // Should have blue background
        const bubble = messageElement.querySelector('[class*="bg-blue"]')
        expect(bubble).toBeInTheDocument()
      })

      it('does not display sender name for self messages', () => {
        const message = createMessage({
          senderId: currentAgentId,
          content: 'My message',
        })

        render(
          <ChatMessage
            message={message}
            currentAgentId={currentAgentId}
            targetAgentId={targetAgentId}
            agentMap={mockAgentMap}
          />
        )

        // Should NOT display sender name for self
        expect(screen.queryByText('Alice (Me)')).not.toBeInTheDocument()
      })
    })

    describe('Target agent messages (chat partner)', () => {
      it('displays target agent messages on the left side with gray background', () => {
        const message = createMessage({
          senderId: targetAgentId,
          content: 'Partner message',
        })

        render(
          <ChatMessage
            message={message}
            currentAgentId={currentAgentId}
            targetAgentId={targetAgentId}
            agentMap={mockAgentMap}
          />
        )

        const messageElement = screen.getByTestId('chat-message-msg-1')
        // Should be positioned on left (justify-start)
        expect(messageElement).toHaveClass('justify-start')

        // Should have gray background
        const bubble = messageElement.querySelector('[class*="bg-gray-100"]')
        expect(bubble).toBeInTheDocument()
      })

      it('displays agent name (not ID) for target agent messages', () => {
        const message = createMessage({
          senderId: targetAgentId,
          content: 'Partner message',
        })

        render(
          <ChatMessage
            message={message}
            currentAgentId={currentAgentId}
            targetAgentId={targetAgentId}
            agentMap={mockAgentMap}
          />
        )

        // Should display agent name, not ID
        expect(screen.getByText('Bob')).toBeInTheDocument()
        expect(screen.queryByText('target-agent')).not.toBeInTheDocument()
      })
    })

    describe('Third-party messages (neither self nor target)', () => {
      it('displays third-party messages on the right side with green background', () => {
        const message = createMessage({
          senderId: 'third-party-agent',
          content: 'Third party message',
        })

        render(
          <ChatMessage
            message={message}
            currentAgentId={currentAgentId}
            targetAgentId={targetAgentId}
            agentMap={mockAgentMap}
          />
        )

        const messageElement = screen.getByTestId('chat-message-msg-1')
        // Third-party should be on right side
        expect(messageElement).toHaveClass('justify-end')

        // Should have green background (different from blue for self)
        const bubble = messageElement.querySelector('[class*="bg-green"]')
        expect(bubble).toBeInTheDocument()
      })

      it('displays agent name for third-party messages', () => {
        const message = createMessage({
          senderId: 'third-party-agent',
          content: 'Third party message',
        })

        render(
          <ChatMessage
            message={message}
            currentAgentId={currentAgentId}
            targetAgentId={targetAgentId}
            agentMap={mockAgentMap}
          />
        )

        // Should display agent name
        expect(screen.getByText('Charlie')).toBeInTheDocument()
      })
    })

    describe('System messages', () => {
      it('displays system messages on the left side with yellow background', () => {
        const message = createMessage({
          senderId: 'system',
          content: 'Error: Connection failed',
        })

        render(
          <ChatMessage
            message={message}
            currentAgentId={currentAgentId}
            targetAgentId={targetAgentId}
            agentMap={mockAgentMap}
          />
        )

        const messageElement = screen.getByTestId('chat-message-msg-1')
        // System messages should be on left side
        expect(messageElement).toHaveClass('justify-start')

        // Should have yellow background
        const bubble = messageElement.querySelector('[class*="bg-yellow"]')
        expect(bubble).toBeInTheDocument()
      })

      it('displays "System" label for system messages', () => {
        const message = createMessage({
          senderId: 'system',
          content: 'Error: Connection failed',
        })

        render(
          <ChatMessage
            message={message}
            currentAgentId={currentAgentId}
            targetAgentId={targetAgentId}
            agentMap={mockAgentMap}
          />
        )

        // Should display "System" as sender
        expect(screen.getByText('System')).toBeInTheDocument()
      })
    })
  })

  describe('Agent name resolution', () => {
    it('falls back to senderId when agent is not found in agentMap', () => {
      const message = createMessage({
        senderId: 'unknown-agent',
        content: 'Unknown agent message',
      })

      render(
        <ChatMessage
          message={message}
          currentAgentId={currentAgentId}
          targetAgentId={targetAgentId}
          agentMap={mockAgentMap}
        />
      )

      // Should display the ID when name is not available
      expect(screen.getByText('unknown-agent')).toBeInTheDocument()
    })

    it('handles empty agentMap gracefully', () => {
      const message = createMessage({
        senderId: targetAgentId,
        content: 'Partner message',
      })

      render(
        <ChatMessage
          message={message}
          currentAgentId={currentAgentId}
          targetAgentId={targetAgentId}
          agentMap={{}}
        />
      )

      // Should fall back to ID
      expect(screen.getByText('target-agent')).toBeInTheDocument()
    })
  })

  describe('Self-chat mode (currentAgentId === targetAgentId)', () => {
    // When viewing your own chat panel, targetAgentId equals currentAgentId
    const selfChatCurrentAgentId = 'current-agent'
    const selfChatTargetAgentId = 'current-agent' // Same as current

    it('displays own messages on the right side with blue background in self-chat', () => {
      const message = createMessage({
        senderId: selfChatCurrentAgentId,
        content: 'My own message',
      })

      render(
        <ChatMessage
          message={message}
          currentAgentId={selfChatCurrentAgentId}
          targetAgentId={selfChatTargetAgentId}
          agentMap={mockAgentMap}
        />
      )

      const messageElement = screen.getByTestId('chat-message-msg-1')
      expect(messageElement).toHaveClass('justify-end')
      const bubble = messageElement.querySelector('[class*="bg-blue"]')
      expect(bubble).toBeInTheDocument()
    })

    it('displays recipient name (@name) for self-sent messages in self-chat mode', () => {
      // In self-chat mode, my own messages should show who they were sent to
      const message = createMessage({
        senderId: selfChatCurrentAgentId,
        receiverId: 'target-agent', // Sent to Bob
        content: 'Message to Bob',
      })

      render(
        <ChatMessage
          message={message}
          currentAgentId={selfChatCurrentAgentId}
          targetAgentId={selfChatTargetAgentId}
          agentMap={mockAgentMap}
        />
      )

      // Should display "@Bob" to indicate recipient
      expect(screen.getByText(/@Bob/)).toBeInTheDocument()
    })

    it('displays messages from others on the left side in self-chat (not as third-party)', () => {
      // In self-chat mode, messages from other agents should appear on the LEFT
      // (as "incoming" messages), NOT on the right as third-party
      const message = createMessage({
        senderId: 'third-party-agent', // Another agent sending to me
        content: 'Message from another agent',
      })

      render(
        <ChatMessage
          message={message}
          currentAgentId={selfChatCurrentAgentId}
          targetAgentId={selfChatTargetAgentId}
          agentMap={mockAgentMap}
        />
      )

      const messageElement = screen.getByTestId('chat-message-msg-1')
      // Should be on LEFT side (incoming message), NOT right side
      expect(messageElement).toHaveClass('justify-start')

      // Should have gray background (like target messages), NOT green (third-party)
      const bubble = messageElement.querySelector('[class*="bg-gray-100"]')
      expect(bubble).toBeInTheDocument()
    })

    it('displays system messages on the left side with yellow background in self-chat', () => {
      const message = createMessage({
        senderId: 'system',
        content: 'System notification',
      })

      render(
        <ChatMessage
          message={message}
          currentAgentId={selfChatCurrentAgentId}
          targetAgentId={selfChatTargetAgentId}
          agentMap={mockAgentMap}
        />
      )

      const messageElement = screen.getByTestId('chat-message-msg-1')
      expect(messageElement).toHaveClass('justify-start')
      const bubble = messageElement.querySelector('[class*="bg-yellow"]')
      expect(bubble).toBeInTheDocument()
    })
  })

  describe('Message content and timestamp', () => {
    it('displays message content', () => {
      const message = createMessage({
        senderId: targetAgentId,
        content: 'Hello, this is a test message!',
      })

      render(
        <ChatMessage
          message={message}
          currentAgentId={currentAgentId}
          targetAgentId={targetAgentId}
          agentMap={mockAgentMap}
        />
      )

      expect(screen.getByText('Hello, this is a test message!')).toBeInTheDocument()
    })

    it('displays formatted timestamp', () => {
      const message = createMessage({
        senderId: targetAgentId,
        createdAt: '2026-01-21T14:30:00Z',
      })

      render(
        <ChatMessage
          message={message}
          currentAgentId={currentAgentId}
          targetAgentId={targetAgentId}
          agentMap={mockAgentMap}
        />
      )

      // Should display time in HH:MM format
      // Note: actual format depends on locale
      const timeElement = screen.getByText(/\d{1,2}:\d{2}/)
      expect(timeElement).toBeInTheDocument()
    })
  })
})
