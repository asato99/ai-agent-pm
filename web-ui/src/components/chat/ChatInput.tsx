// web-ui/src/components/chat/ChatInput.tsx
// Message input component
// Reference: docs/design/CHAT_SESSION_STATUS.md - Phase 3

import { useState, useCallback, useRef, type FormEvent, type KeyboardEvent, type MouseEvent } from 'react'
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

const MIN_INPUT_HEIGHT = 60
const DEFAULT_INPUT_HEIGHT = 60
// MAX_INPUT_HEIGHT is calculated dynamically based on window height (2/3 of screen)

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
  const [inputHeight, setInputHeight] = useState(DEFAULT_INPUT_HEIGHT)
  const isResizingRef = useRef(false)
  const startYRef = useRef(0)
  const startHeightRef = useRef(0)

  // Handle resize drag
  const handleResizeMouseDown = useCallback((e: MouseEvent) => {
    e.preventDefault()
    isResizingRef.current = true
    startYRef.current = e.clientY
    startHeightRef.current = inputHeight
    // Calculate max height as 2/3 of window height
    const maxInputHeight = Math.floor(window.innerHeight * 0.66)

    const handleMouseMove = (moveEvent: globalThis.MouseEvent) => {
      if (!isResizingRef.current) return
      // Dragging up = negative deltaY = increase height
      const deltaY = startYRef.current - moveEvent.clientY
      const newHeight = Math.max(MIN_INPUT_HEIGHT, Math.min(maxInputHeight, startHeightRef.current + deltaY))
      setInputHeight(newHeight)
    }

    const handleMouseUp = () => {
      isResizingRef.current = false
      document.removeEventListener('mousemove', handleMouseMove)
      document.removeEventListener('mouseup', handleMouseUp)
    }

    document.addEventListener('mousemove', handleMouseMove)
    document.addEventListener('mouseup', handleMouseUp)
  }, [inputHeight])

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
    <form onSubmit={handleSubmit} className="border-t">
      {/* Resize handle for input height */}
      <div
        className="h-2 cursor-ns-resize bg-gray-100 hover:bg-gray-200 flex items-center justify-center group"
        onMouseDown={handleResizeMouseDown}
        title="ドラッグして入力欄の高さを変更"
      >
        <div className="w-8 h-0.5 bg-gray-300 group-hover:bg-gray-400 rounded" />
      </div>

      <div className="p-4">
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
            style={{ height: `${inputHeight}px` }}
            aria-label="Chat message input"
          />
          {renderButton()}
        </div>
        <div className="mt-1 text-xs text-gray-400 text-right">
          {content.length}/{maxLength} characters (Ctrl+Enter to send)
        </div>
      </div>
    </form>
  )
}
