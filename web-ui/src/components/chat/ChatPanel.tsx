// web-ui/src/components/chat/ChatPanel.tsx
// Chat panel component
// Reference: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 6

import { useRef, useEffect, useMemo } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useChat } from '@/hooks/useChat'
import { useAuthStore } from '@/stores/authStore'
import { useAssignableAgents } from '@/hooks/useAssignableAgents'
import { useAgentSessions } from '@/hooks/useAgentSessions'
import { chatApi } from '@/api/chatApi'
import { ChatMessage } from './ChatMessage'
import { ChatInput } from './ChatInput'
import type { Agent } from '@/types'

interface ChatPanelProps {
  projectId: string
  agent: Agent
  onClose: () => void
}

export function ChatPanel({ projectId, agent, onClose }: ChatPanelProps) {
  const { agent: currentAgent } = useAuthStore()
  const currentAgentId = currentAgent?.id ?? ''
  const queryClient = useQueryClient()
  const { messages, isLoading, sendMessage, isSending, isWaitingForResponse, hasMore, loadMore } = useChat(
    projectId,
    agent.id
  )
  const { agents: projectAgents } = useAssignableAgents(projectId)
  const { hasChatSession } = useAgentSessions(projectId)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const messagesContainerRef = useRef<HTMLDivElement>(null)

  // Build agent map for name resolution
  const agentMap = useMemo(() => {
    const map: Record<string, Agent> = {}
    // Add project agents
    for (const a of projectAgents) {
      map[a.id] = a
    }
    // Add current agent (in case not in project agents)
    if (currentAgent) {
      map[currentAgent.id] = currentAgent
    }
    // Add target agent (in case not in project agents)
    map[agent.id] = agent
    return map
  }, [projectAgents, currentAgent, agent])

  // Mark messages as read when chat panel opens
  useEffect(() => {
    const markAsRead = async () => {
      try {
        await chatApi.markAsRead(projectId, agent.id)
        // Invalidate unread counts to update the badge
        queryClient.invalidateQueries({ queryKey: ['unreadCounts', projectId] })
      } catch (error) {
        console.error('Failed to mark chat as read:', error)
      }
    }
    markAsRead()
  }, [projectId, agent.id, queryClient])

  // Start chat session when chat panel opens
  // Reference: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md - Phase 5
  useEffect(() => {
    const startSession = async () => {
      try {
        await chatApi.startSession(projectId, agent.id)
      } catch (error) {
        console.error('Failed to start chat session:', error)
      }
    }
    startSession()
  }, [projectId, agent.id])

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
              <ChatMessage
                key={msg.id}
                message={msg}
                currentAgentId={currentAgentId}
                targetAgentId={agent.id}
                agentMap={agentMap}
              />
            ))}
            {/* Waiting for response indicator */}
            {isWaitingForResponse && (
              <div className="flex mb-4 justify-start" data-testid="chat-waiting-indicator">
                <div className="bg-gray-100 rounded-lg px-4 py-2 max-w-[70%]">
                  <div className="text-xs font-semibold mb-1 text-gray-500">
                    {agent.name}
                  </div>
                  <div className="flex items-center text-gray-600">
                    <svg className="animate-spin h-4 w-4 mr-2" viewBox="0 0 24 24">
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
                    <span>応答を待っています...</span>
                  </div>
                </div>
              </div>
            )}
            <div ref={messagesEndRef} />
          </>
        )}
      </div>

      {/* Input */}
      <ChatInput
        onSend={handleSend}
        disabled={isSending}
        sessionReady={hasChatSession(agent.id)}
      />
    </div>
  )
}
