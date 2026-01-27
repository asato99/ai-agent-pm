// web-ui/src/components/chat/ChatInput.tsx
// Message input component
// Reference: docs/design/CHAT_SESSION_STATUS.md - Phase 3

import { useState, useCallback, type FormEvent, type KeyboardEvent } from 'react'
import type { ChatSessionStatus } from '@/hooks/useAgentSessions'

interface ChatInputProps {
  onSend: (content: string) => Promise<void>
  disabled?: boolean
  placeholder?: string
  maxLength?: number
  /**
   * Chat session status: 'connected' | 'connecting' | 'disconnected'
   * 参照: docs/design/CHAT_SESSION_STATUS.md
   */
  chatStatus?: ChatSessionStatus
  /** Called when user clicks reconnect button (only in disconnected state) */
  onReconnect?: () => void
  /** @deprecated Use chatStatus instead */
  sessionReady?: boolean
}

export function ChatInput({
  onSend,
  disabled = false,
  placeholder = 'Type a message...',
  maxLength = 4000,
  chatStatus = 'connected',
  onReconnect,
  sessionReady: _sessionReady, // deprecated, ignored
}: ChatInputProps) {
  const [content, setContent] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)

  const handleSubmit = useCallback(
    async (e: FormEvent) => {
      e.preventDefault()

      const trimmedContent = content.trim()
      if (!trimmedContent || isSubmitting || disabled || chatStatus !== 'connected') return

      setIsSubmitting(true)
      try {
        await onSend(trimmedContent)
        setContent('') // Clear input on success
      } finally {
        setIsSubmitting(false)
      }
    },
    [content, isSubmitting, disabled, chatStatus, onSend]
  )

  const handleKeyDown = useCallback(
    (e: KeyboardEvent<HTMLTextAreaElement>) => {
      // Ctrl+Enter or Cmd+Enter to send
      if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
        e.preventDefault()
        handleSubmit(e as unknown as FormEvent)
      }
    },
    [handleSubmit]
  )

  const handleReconnect = useCallback(() => {
    onReconnect?.()
  }, [onReconnect])

  // Input field: always enabled (unless explicitly disabled or submitting)
  const isInputDisabled = disabled || isSubmitting
  // Send button: disabled when not connected
  const isSendDisabled = disabled || isSubmitting || chatStatus !== 'connected'

  // Render appropriate button based on status
  const renderButton = () => {
    if (chatStatus === 'disconnected') {
      return (
        <button
          type="button"
          data-testid="chat-reconnect-button"
          className="rounded-lg bg-orange-500 px-4 py-2 text-sm font-medium text-white hover:bg-orange-600 focus:outline-none focus:ring-2 focus:ring-orange-500 focus:ring-offset-2"
          onClick={handleReconnect}
          aria-label="再接続"
        >
          再接続
        </button>
      )
    }

    if (chatStatus === 'connecting') {
      return (
        <button
          type="button"
          data-testid="chat-send-button"
          className="rounded-lg bg-gray-300 px-4 py-2 text-sm font-medium text-gray-500 cursor-not-allowed"
          disabled
          aria-label="接続中"
        >
          <span className="flex items-center gap-1">
            <svg data-testid="spinner" className="animate-spin h-4 w-4" viewBox="0 0 24 24">
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
            接続中...
          </span>
        </button>
      )
    }

    // Connected state
    return (
      <button
        type="submit"
        data-testid="chat-send-button"
        className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-medium text-white hover:bg-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 disabled:bg-gray-300 disabled:cursor-not-allowed"
        disabled={isSendDisabled || !content.trim()}
        aria-label="送信"
      >
        {isSubmitting ? (
          <span className="flex items-center gap-1">
            <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24">
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
            送信中
          </span>
        ) : (
          '送信'
        )}
      </button>
    )
  }

  return (
    <form onSubmit={handleSubmit} className="border-t p-4">
      <div className="flex gap-2">
        <textarea
          data-testid="chat-input"
          className="flex-1 resize-none rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500 disabled:bg-gray-50 disabled:text-gray-500"
          placeholder={placeholder}
          value={content}
          onChange={(e) => setContent(e.target.value)}
          onKeyDown={handleKeyDown}
          disabled={isInputDisabled}
          maxLength={maxLength}
          rows={2}
          aria-label="Chat message input"
        />
        {renderButton()}
      </div>
      <div className="mt-1 text-xs text-gray-400 text-right">
        {content.length}/{maxLength} characters (Ctrl+Enter to send)
      </div>
    </form>
  )
}
