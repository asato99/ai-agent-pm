// web-ui/src/components/chat/ChatMessage.tsx
// Individual chat message display component
// Reference: docs/design/CHAT_FEATURE.md - Section 11.8

import type { ChatMessage as ChatMessageType, Agent } from '@/types'

interface ChatMessageProps {
  message: ChatMessageType
  /** Current user's agent ID (used to determine if message is "mine") */
  currentAgentId: string
  /** Target agent ID (the chat partner) */
  targetAgentId: string
  /** Agent map for name resolution */
  agentMap: Record<string, Agent>
}

/**
 * Message sender type for styling purposes
 * - self: Current user's messages (right, blue)
 * - target: Chat partner's messages (left, gray)
 * - system: System notifications (left, yellow)
 * - thirdParty: Other agents' messages (right, green)
 */
type MessageSenderType = 'self' | 'target' | 'system' | 'thirdParty'

/**
 * Determine the sender type for styling purposes
 */
function getSenderType(
  senderId: string,
  currentAgentId: string,
  targetAgentId: string
): MessageSenderType {
  // Self-sent messages
  if (senderId === currentAgentId) {
    return 'self'
  }
  // System messages
  if (senderId === 'system') {
    return 'system'
  }
  // Self-chat mode: when viewing your own chat panel (currentAgentId === targetAgentId),
  // all messages from others should be treated as "target" (incoming, left side)
  if (currentAgentId === targetAgentId) {
    return 'target'
  }
  // Normal chat mode: messages from the chat partner
  if (senderId === targetAgentId) {
    return 'target'
  }
  // Third-party messages (in normal chat mode only)
  return 'thirdParty'
}

/**
 * Get styling based on sender type
 */
function getMessageStyle(senderType: MessageSenderType) {
  switch (senderType) {
    case 'self':
      return {
        position: 'justify-end',
        bubbleClass: 'bg-blue-500 text-white',
        timestampClass: 'text-blue-100',
        showSender: false,
      }
    case 'target':
      return {
        position: 'justify-start',
        bubbleClass: 'bg-gray-100 text-gray-900',
        timestampClass: 'text-gray-500',
        showSender: true,
      }
    case 'system':
      return {
        position: 'justify-start',
        bubbleClass: 'bg-yellow-100 text-yellow-800',
        timestampClass: 'text-yellow-600',
        showSender: true,
      }
    case 'thirdParty':
      return {
        position: 'justify-end',
        bubbleClass: 'bg-green-500 text-white',
        timestampClass: 'text-green-100',
        showSender: true,
      }
  }
}

/**
 * Get display name for a sender
 */
function getSenderDisplayName(
  senderId: string,
  senderType: MessageSenderType,
  agentMap: Record<string, Agent>
): string {
  if (senderType === 'system') {
    return 'System'
  }
  const agent = agentMap[senderId]
  return agent?.name ?? senderId
}

/**
 * Get recipient display name
 * - Self-chat mode: Show recipient on self messages (who am I sending to)
 * - Other's chat mode: Show recipient on target messages (who is the other agent sending to)
 */
function getRecipientDisplay(
  message: ChatMessageType,
  senderType: MessageSenderType,
  currentAgentId: string,
  targetAgentId: string,
  agentMap: Record<string, Agent>
): string | null {
  const isSelfChatMode = currentAgentId === targetAgentId

  // Self-chat mode: show recipient for self messages
  if (isSelfChatMode && senderType === 'self') {
    if (!message.receiverId) {
      return null
    }
    const recipient = agentMap[message.receiverId]
    const recipientName = recipient?.name ?? message.receiverId
    return `@${recipientName}`
  }

  // Other's chat mode: show recipient for target messages (the other agent's messages)
  if (!isSelfChatMode && senderType === 'target') {
    if (!message.receiverId) {
      return null
    }
    const recipient = agentMap[message.receiverId]
    const recipientName = recipient?.name ?? message.receiverId
    return `@${recipientName}`
  }

  return null
}

export function ChatMessage({ message, currentAgentId, targetAgentId, agentMap }: ChatMessageProps) {
  const senderType = getSenderType(message.senderId, currentAgentId, targetAgentId)
  const style = getMessageStyle(senderType)
  const senderName = getSenderDisplayName(message.senderId, senderType, agentMap)
  const recipientDisplay = getRecipientDisplay(message, senderType, currentAgentId, targetAgentId, agentMap)

  // Get formatted time
  const formatTime = (dateString: string) => {
    const date = new Date(dateString)
    return date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })
  }

  return (
    <div
      className={`flex mb-4 ${style.position}`}
      data-testid={`chat-message-${message.id}`}
      data-message-id={message.id}
      data-sender-id={message.senderId}
    >
      <div
        className={`max-w-[70%] rounded-lg px-4 py-2 ${style.bubbleClass}`}
      >
        {/* Sender label for non-self messages */}
        {style.showSender && (
          <div className="text-xs font-semibold mb-1 opacity-70">
            {senderName}
          </div>
        )}

        {/* Recipient label for self messages in self-chat mode */}
        {recipientDisplay && (
          <div className="text-xs font-semibold mb-1 opacity-70">
            {recipientDisplay}
          </div>
        )}

        {/* Message content */}
        <div className="whitespace-pre-wrap break-words">{message.content}</div>

        {/* Timestamp */}
        <div className={`text-xs mt-1 ${style.timestampClass}`}>
          {formatTime(message.createdAt)}
        </div>
      </div>
    </div>
  )
}
