// web-ui/src/hooks/useChat.ts
// チャット機能用カスタムフック
// 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 5

import { useCallback } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { chatApi } from '@/api/chatApi'
import type { ChatMessage, GetChatMessagesOptions } from '@/types'

interface UseChatOptions {
  /** ポーリング有効化（デフォルト: true） */
  polling?: boolean
  /** ポーリング間隔（ミリ秒、デフォルト: 5000） */
  pollingInterval?: number
  /** 取得上限数 */
  limit?: number
}

interface UseChatResult {
  /** メッセージ一覧 */
  messages: ChatMessage[]
  /** 読み込み中フラグ */
  isLoading: boolean
  /** エラー情報 */
  error: Error | null
  /** 追加メッセージがあるかどうか */
  hasMore: boolean
  /** メッセージ送信関数 */
  sendMessage: (content: string, relatedTaskId?: string) => Promise<ChatMessage>
  /** 送信中フラグ */
  isSending: boolean
  /** 手動リフレッシュ */
  refetch: () => void
  /** 古いメッセージを追加で読み込む */
  loadMore: () => Promise<void>
}

/**
 * チャット機能を提供するカスタムフック
 * @param projectId プロジェクトID
 * @param agentId エージェントID
 * @param options オプション設定
 * @returns チャット操作用のインターフェース
 */
export function useChat(
  projectId: string,
  agentId: string,
  options?: UseChatOptions
): UseChatResult {
  const { polling = true, pollingInterval = 5000, limit } = options ?? {}
  const queryClient = useQueryClient()
  const queryKey = ['chat', projectId, agentId]

  // メッセージ取得クエリ
  const queryOptions: GetChatMessagesOptions = {}
  if (limit !== undefined) {
    queryOptions.limit = limit
  }

  const {
    data,
    isLoading,
    error,
    refetch,
  } = useQuery({
    queryKey,
    queryFn: async () => {
      return chatApi.getMessages(projectId, agentId, queryOptions)
    },
    enabled: !!projectId && !!agentId,
    // ポーリング設定（新しいメッセージを検出するため）
    refetchInterval: polling ? pollingInterval : false,
    refetchOnWindowFocus: false,
  })

  // メッセージ送信ミューテーション
  const sendMutation = useMutation({
    mutationFn: async ({
      content,
      relatedTaskId,
    }: {
      content: string
      relatedTaskId?: string
    }) => {
      return chatApi.sendMessage(projectId, agentId, content, relatedTaskId)
    },
    onSuccess: (newMessage) => {
      // 送信成功時、キャッシュを更新してメッセージを即座に表示
      queryClient.setQueryData(queryKey, (oldData: typeof data) => {
        if (!oldData) {
          return {
            messages: [newMessage],
            hasMore: false,
          }
        }
        return {
          ...oldData,
          messages: [...oldData.messages, newMessage],
        }
      })
    },
  })

  // メッセージ送信関数
  const sendMessage = useCallback(
    async (content: string, relatedTaskId?: string): Promise<ChatMessage> => {
      return sendMutation.mutateAsync({ content, relatedTaskId })
    },
    [sendMutation]
  )

  // 古いメッセージを読み込む
  const loadMore = useCallback(async () => {
    if (!data?.messages.length || !data.hasMore) return

    const oldestMessage = data.messages[0]
    const moreMessages = await chatApi.getMessages(projectId, agentId, {
      before: oldestMessage.id,
      limit: limit ?? 50,
    })

    queryClient.setQueryData(queryKey, (oldData: typeof data) => {
      if (!oldData) return moreMessages
      return {
        ...moreMessages,
        messages: [...moreMessages.messages, ...oldData.messages],
      }
    })
  }, [data, projectId, agentId, limit, queryClient, queryKey])

  return {
    messages: data?.messages ?? [],
    isLoading,
    error: error as Error | null,
    hasMore: data?.hasMore ?? false,
    sendMessage,
    isSending: sendMutation.isPending,
    refetch,
    loadMore,
  }
}
