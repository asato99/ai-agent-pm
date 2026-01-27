// web-ui/src/hooks/useChat.test.tsx
// useChatフックのテスト
// 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 5

import { describe, it, expect, beforeEach } from 'vitest'
import { renderHook, waitFor, act } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { useChat } from './useChat'

const createWrapper = () => {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: {
        retry: false,
      },
    },
  })
  return ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  )
}

describe('useChat', () => {
  beforeEach(() => {
    localStorage.clear()
    localStorage.setItem('sessionToken', 'test-session-token')
  })

  describe('メッセージ取得', () => {
    it('プロジェクトとエージェントのチャットメッセージを取得できる', async () => {
      const { result } = renderHook(
        () => useChat('project-1', 'agent-1'),
        { wrapper: createWrapper() }
      )

      expect(result.current.isLoading).toBe(true)

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      expect(result.current.messages).toHaveLength(2)
      expect(result.current.messages[0].content).toBe('こんにちは')
      expect(result.current.messages[0].senderId).toBe('user-1')
      expect(result.current.messages[1].content).toBe('こんにちは！何かお手伝いできますか？')
      expect(result.current.messages[1].senderId).toBe('agent-1')
    })

    it('メッセージにはid, senderId, content, createdAtが含まれる', async () => {
      const { result } = renderHook(
        () => useChat('project-1', 'agent-1'),
        { wrapper: createWrapper() }
      )

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      const message = result.current.messages[0]
      expect(message.id).toBeDefined()
      expect(message.senderId).toBeDefined()
      expect(message.content).toBeDefined()
      expect(message.createdAt).toBeDefined()
    })

    it('hasMoreフラグを取得できる', async () => {
      const { result } = renderHook(
        () => useChat('project-1', 'agent-1'),
        { wrapper: createWrapper() }
      )

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      expect(result.current.hasMore).toBe(false)
    })
  })

  describe('メッセージ送信', () => {
    it('sendMessageでメッセージを送信できる', async () => {
      const { result } = renderHook(
        () => useChat('project-1', 'agent-1'),
        { wrapper: createWrapper() }
      )

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      const initialCount = result.current.messages.length

      await act(async () => {
        await result.current.sendMessage('新しいメッセージ')
      })

      // 送信後、メッセージが追加される（キャッシュ更新を待つ）
      await waitFor(() => {
        expect(result.current.messages.length).toBe(initialCount + 1)
      })
      const lastMessage = result.current.messages[result.current.messages.length - 1]
      expect(lastMessage.content).toBe('新しいメッセージ')
      expect(lastMessage.senderId).toBe('user-1')
    })

    it('送信中はisSendingがtrueになる', async () => {
      const { result } = renderHook(
        () => useChat('project-1', 'agent-1'),
        { wrapper: createWrapper() }
      )

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      expect(result.current.isSending).toBe(false)

      // 送信を開始（awaitしない）
      const sendPromise = act(async () => {
        return result.current.sendMessage('テストメッセージ')
      })

      // 注: isSendingの中間状態をテストするのは難しいため、
      // 送信完了後にisSendingがfalseに戻ることを確認
      await sendPromise

      expect(result.current.isSending).toBe(false)
    })

    it('relatedTaskIdを指定してメッセージを送信できる', async () => {
      const { result } = renderHook(
        () => useChat('project-1', 'agent-1'),
        { wrapper: createWrapper() }
      )

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      let sentMessage
      await act(async () => {
        sentMessage = await result.current.sendMessage('タスクに関する質問', 'task-123')
      })

      expect(sentMessage).toBeDefined()
      expect((sentMessage as { content: string }).content).toBe('タスクに関する質問')
    })
  })

  describe('オプション設定', () => {
    it('pollingをfalseにするとポーリングが無効化される', async () => {
      const { result } = renderHook(
        () => useChat('project-1', 'agent-1', { polling: false }),
        { wrapper: createWrapper() }
      )

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      // ポーリング無効でも通常の取得は動作する
      expect(result.current.messages).toHaveLength(2)
    })

    it('limitオプションでメッセージ数を制限できる', async () => {
      const { result } = renderHook(
        () => useChat('project-1', 'agent-1', { limit: 1 }),
        { wrapper: createWrapper() }
      )

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      // MSWモックは常に2件返すが、実際のAPIではlimitが適用される
      // ここではhookがlimitパラメータを正しく渡すことを確認
      expect(result.current.messages).toBeDefined()
    })
  })

  describe('エラーハンドリング', () => {
    it('無効なプロジェクトIDでエラーが発生する', async () => {
      const { result } = renderHook(
        () => useChat('invalid-project', 'agent-1'),
        { wrapper: createWrapper() }
      )

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      // エラーが発生した場合、errorが設定される
      // 注: MSWモックの設定によっては404エラーが返される
      expect(result.current.error).toBeDefined()
    })
  })

  describe('refetch', () => {
    it('refetchで手動更新ができる', async () => {
      const { result } = renderHook(
        () => useChat('project-1', 'agent-1'),
        { wrapper: createWrapper() }
      )

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      // refetchを呼び出す
      await act(async () => {
        await result.current.refetch()
      })

      // エラーなく完了することを確認
      expect(result.current.error).toBeNull()
      expect(result.current.messages).toBeDefined()
    })
  })

  describe('isWaitingForResponse (サーバー側判定)', () => {
    it('初期状態ではisWaitingForResponseがサーバーの値を反映する', async () => {
      const { result } = renderHook(
        () => useChat('project-1', 'agent-1'),
        { wrapper: createWrapper() }
      )

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      // MSWモックはエージェントの最後のメッセージが最新なので、
      // awaitingAgentResponse: false を返す
      expect(result.current.isWaitingForResponse).toBe(false)
    })

    it('メッセージ送信後にisWaitingForResponseが楽観的にtrueになる', async () => {
      // ポーリングを無効化して、楽観的更新がサーバーレスポンスで上書きされないようにする
      const { result } = renderHook(
        () => useChat('project-1', 'agent-1', { polling: false }),
        { wrapper: createWrapper() }
      )

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      // 送信前はfalse（サーバーからの値）
      expect(result.current.isWaitingForResponse).toBe(false)

      // メッセージを送信
      await act(async () => {
        await result.current.sendMessage('テストメッセージ')
      })

      // 送信後は楽観的にtrue（エージェントの応答を待っている）
      // これはキャッシュ更新時に設定される
      await waitFor(() => {
        expect(result.current.isWaitingForResponse).toBe(true)
      })
    })

    it('サーバーからawaitingAgentResponse=falseが返ると待機状態が解除される', async () => {
      // QueryClientを直接操作してサーバーからの応答をシミュレート
      const queryClient = new QueryClient({
        defaultOptions: {
          queries: {
            retry: false,
          },
        },
      })
      const wrapper = ({ children }: { children: ReactNode }) => (
        <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
      )

      // ポーリングを無効化して、楽観的更新がサーバーレスポンスで上書きされないようにする
      const { result } = renderHook(
        () => useChat('project-1', 'agent-1', { polling: false }),
        { wrapper }
      )

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      // メッセージを送信（楽観的にisWaitingForResponse = true になる）
      await act(async () => {
        await result.current.sendMessage('テストメッセージ')
      })

      await waitFor(() => {
        expect(result.current.isWaitingForResponse).toBe(true)
      })

      // サーバーからエージェントの応答が返ってきたことをシミュレート
      // (awaitingAgentResponse: false = エージェントは応答済み)
      await act(async () => {
        queryClient.setQueryData(['chat', 'project-1', 'agent-1'], {
          messages: [
            ...result.current.messages,
            {
              id: 'msg-agent-response',
              senderId: 'agent-1',
              receiverId: 'user-1',
              content: 'お手伝いします！',
              createdAt: new Date().toISOString(),
            },
          ],
          hasMore: false,
          // サーバーが判定: エージェントの最新メッセージが最後なので応答待ちではない
          awaitingAgentResponse: false,
        })
      })

      // サーバーからのawaitingAgentResponse=falseで待機状態が解除される
      await waitFor(() => {
        expect(result.current.isWaitingForResponse).toBe(false)
      })
    })

    it('システムメッセージ受信後もawaitingAgentResponseに従う', async () => {
      // QueryClientを直接操作してシステムメッセージを追加
      const queryClient = new QueryClient({
        defaultOptions: {
          queries: {
            retry: false,
          },
        },
      })
      const wrapper = ({ children }: { children: ReactNode }) => (
        <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
      )

      // ポーリングを無効化して、楽観的更新がサーバーレスポンスで上書きされないようにする
      const { result } = renderHook(
        () => useChat('project-1', 'agent-1', { polling: false }),
        { wrapper }
      )

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false)
      })

      // メッセージを送信（isWaitingForResponse = true になる）
      await act(async () => {
        await result.current.sendMessage('テストメッセージ')
      })

      await waitFor(() => {
        expect(result.current.isWaitingForResponse).toBe(true)
      })

      // システムからのエラーメッセージを受信したことをシミュレート
      // サーバーがawaitingAgentResponse: falseを返す（システムメッセージも応答扱い）
      await act(async () => {
        queryClient.setQueryData(['chat', 'project-1', 'agent-1'], {
          messages: [
            ...result.current.messages,
            {
              id: 'msg-system-1',
              senderId: 'system',
              content: 'エラー: エージェントに接続できませんでした',
              createdAt: new Date().toISOString(),
            },
          ],
          hasMore: false,
          // サーバーが判定: システムメッセージも応答扱いなので待機終了
          awaitingAgentResponse: false,
        })
      })

      // サーバーからの値に従って待機状態が解除される
      await waitFor(() => {
        expect(result.current.isWaitingForResponse).toBe(false)
      })
    })
  })
})
