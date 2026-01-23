// web-ui/src/components/chat/ChatInput.tsx
// Message input component
// Reference: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 6

import { useState, useCallback, type FormEvent, type KeyboardEvent } from 'react'

interface ChatInputProps {
  onSend: (content: string) => Promise<void>
  disabled?: boolean
  placeholder?: string
  maxLength?: number
  /** Whether the chat session is ready for sending messages */
  sessionReady?: boolean
}

export function ChatInput({
  onSend,
  disabled = false,
  placeholder = 'Type a message...',
  maxLength = 4000,
  sessionReady = true,
}: ChatInputProps) {
  const [content, setContent] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)

  const handleSubmit = useCallback(
    async (e: FormEvent) => {
      e.preventDefault()

      const trimmedContent = content.trim()
      if (!trimmedContent || isSubmitting || disabled) return

      setIsSubmitting(true)
      try {
        await onSend(trimmedContent)
        setContent('') // Clear input on success
      } finally {
        setIsSubmitting(false)
      }
    },
    [content, isSubmitting, disabled, onSend]
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

  const isDisabled = disabled || isSubmitting || !sessionReady

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
          disabled={isDisabled}
          maxLength={maxLength}
          rows={2}
          aria-label="Chat message input"
        />
        <button
          type="submit"
          data-testid="chat-send-button"
          className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-medium text-white hover:bg-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 disabled:bg-gray-300 disabled:cursor-not-allowed"
          disabled={isDisabled || !content.trim()}
          aria-label={sessionReady ? '送信' : '準備中'}
        >
          {!sessionReady ? (
            '準備中...'
          ) : isSubmitting ? (
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
      </div>
      <div className="mt-1 text-xs text-gray-400 text-right">
        {content.length}/{maxLength} characters (Ctrl+Enter to send)
      </div>
    </form>
  )
}
