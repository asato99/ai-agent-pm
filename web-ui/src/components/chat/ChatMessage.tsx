// web-ui/src/components/chat/ChatMessage.tsx
// Individual chat message display component
// Reference: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 6

import type { ChatMessage as ChatMessageType } from '@/types'

interface ChatMessageProps {
  message: ChatMessageType
  /** Current user's agent ID (used to determine if message is "mine") */
  currentAgentId: string
}

export function ChatMessage({ message, currentAgentId }: ChatMessageProps) {
  // Message is "mine" if I sent it (senderId matches currentAgentId)
  const isMine = message.senderId === currentAgentId
  const isSystem = false // System messages not yet implemented

  // Get formatted time
  const formatTime = (dateString: string) => {
    const date = new Date(dateString)
    return date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })
  }

  return (
    <div
      className={`flex mb-4 ${isMine ? 'justify-end' : 'justify-start'}`}
      data-testid="chat-message"
      data-message-id={message.id}
      data-sender-id={message.senderId}
    >
      <div
        className={`max-w-[70%] rounded-lg px-4 py-2 ${
          isMine
            ? 'bg-blue-500 text-white'
            : isSystem
              ? 'bg-gray-200 text-gray-600 italic'
              : 'bg-gray-100 text-gray-900'
        }`}
      >
        {/* Sender label for received messages */}
        {!isMine && (
          <div className="text-xs font-semibold mb-1 opacity-70">
            {isSystem ? 'System' : message.senderId}
          </div>
        )}

        {/* Message content */}
        <div className="whitespace-pre-wrap break-words">{message.content}</div>

        {/* Timestamp */}
        <div className={`text-xs mt-1 ${isMine ? 'text-blue-100' : 'text-gray-500'}`}>
          {formatTime(message.createdAt)}
        </div>
      </div>
    </div>
  )
}
