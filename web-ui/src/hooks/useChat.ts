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
  /** ポーリング間隔（ミリ秒、デフォルト: 2000） */
  pollingInterval?: number
  /** 応答待ち時のポーリング間隔（ミリ秒、デフォルト: 1000） */
  waitingPollingInterval?: number
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
  /** エージェント応答待ちフラグ（サーバー側で判定） */
  isWaitingForResponse: boolean
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
  const {
    polling = true,
    pollingInterval = 2000,
    waitingPollingInterval = 1000,
    limit
  } = options ?? {}
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
    // 応答待ち時は1秒、それ以外は2秒間隔でポーリング
    // Note: isWaitingForResponse はサーバーから取得するため、
    // データ取得後に次回のポーリング間隔が決まる
    refetchInterval: (query) => {
      if (!polling) return false
      const awaitingResponse = query.state.data?.awaitingAgentResponse ?? false
      return awaitingResponse ? waitingPollingInterval : pollingInterval
    },
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
      // awaitingAgentResponse はサーバーからの次回レスポンスで更新されるが、
      // 楽観的に true を設定することで即座に待機状態を反映
      queryClient.setQueryData(queryKey, (oldData: typeof data) => {
        if (!oldData) {
          return {
            messages: [newMessage],
            hasMore: false,
            awaitingAgentResponse: true, // 送信後は応答待ち状態
          }
        }
        return {
          ...oldData,
          messages: [...oldData.messages, newMessage],
          awaitingAgentResponse: true, // 送信後は応答待ち状態
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
    // サーバーから判定された応答待ち状態を使用
    // Reference: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md
    isWaitingForResponse: data?.awaitingAgentResponse ?? false,
    refetch,
    loadMore,
  }
}
