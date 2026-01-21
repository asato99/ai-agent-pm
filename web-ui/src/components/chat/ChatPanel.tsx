// web-ui/src/components/chat/ChatPanel.tsx
// Chat panel component
// Reference: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 6

import { useRef, useEffect } from 'react'
import { useChat } from '@/hooks/useChat'
import { ChatMessage } from './ChatMessage'
import { ChatInput } from './ChatInput'
import type { Agent } from '@/types'

interface ChatPanelProps {
  projectId: string
  agent: Agent
  onClose: () => void
}

export function ChatPanel({ projectId, agent, onClose }: ChatPanelProps) {
  const { messages, isLoading, sendMessage, isSending, hasMore, loadMore } = useChat(
    projectId,
    agent.id
  )
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const messagesContainerRef = useRef<HTMLDivElement>(null)

  // Scroll to bottom when new messages arrive
  useEffect(() => {
    // scrollIntoView may not be available in test environments (JSDOM)
    if (messagesEndRef.current && typeof messagesEndRef.current.scrollIntoView === 'function') {
      messagesEndRef.current.scrollIntoView({ behavior: 'smooth' })
    }
  }, [messages])

  // Handle send message
  const handleSend = async (content: string) => {
    await sendMessage(content)
  }

  // Handle scroll to load more messages
  const handleScroll = () => {
    const container = messagesContainerRef.current
    if (!container || !hasMore || isLoading) return

    // Load more when scrolled near the top
    if (container.scrollTop < 100) {
      loadMore()
    }
  }

  return (
    <div className="flex flex-col h-full bg-white border-l" data-testid="chat-panel">
      {/* Header */}
      <div className="flex items-center justify-between p-4 border-b">
        <div>
          <h3 className="font-semibold text-gray-900">{agent.name}</h3>
          <span className="text-sm text-gray-500">{agent.role}</span>
        </div>
        <button
          onClick={onClose}
          className="p-1 rounded-full hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-blue-500"
          aria-label="Close"
        >
          <svg className="w-6 h-6 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>

      {/* Messages */}
      <div
        ref={messagesContainerRef}
        className="flex-1 overflow-y-auto p-4"
        onScroll={handleScroll}
      >
        {isLoading ? (
          <div
            data-testid="chat-loading"
            className="flex items-center justify-center h-full text-gray-500"
          >
            <svg className="animate-spin h-6 w-6 mr-2" viewBox="0 0 24 24">
              <circle
                className="opacity-25"
                cx="12"
                cy="12"
                r="10"
                stroke="currentColor"
                strokeWidth="4"
                fill="none"
              />
              <path
                className="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
              />
            </svg>
            Loading...
          </div>
        ) : messages.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-gray-400">
            <svg className="w-12 h-12 mb-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={1}
                d="M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z"
              />
            </svg>
            <p>No messages yet</p>
            <p className="text-sm">Send the first message</p>
          </div>
        ) : (
          <>
            {hasMore && (
              <div className="text-center py-2">
                <button
                  onClick={() => loadMore()}
                  className="text-sm text-blue-500 hover:text-blue-700"
                >
                  Load more messages
                </button>
              </div>
            )}
            {messages.map((msg) => (
              <ChatMessage key={msg.id} message={msg} />
            ))}
            <div ref={messagesEndRef} />
          </>
        )}
      </div>

      {/* Input */}
      <ChatInput onSend={handleSend} disabled={isSending} />
    </div>
  )
}
