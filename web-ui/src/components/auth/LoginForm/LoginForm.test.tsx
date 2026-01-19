import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen } from '../../../../tests/test-utils'
import userEvent from '@testing-library/user-event'
import { LoginForm } from './LoginForm'

// useAuth をモック
const mockLogin = vi.fn()
const mockLogout = vi.fn()

vi.mock('@/hooks/useAuth', () => ({
  useAuth: vi.fn(() => ({
    isAuthenticated: false,
    agent: null,
    isLoading: false,
    error: null,
    login: mockLogin,
    logout: mockLogout,
  })),
}))

import { useAuth } from '@/hooks/useAuth'

describe('LoginForm', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(useAuth).mockReturnValue({
      isAuthenticated: false,
      agent: null,
      isLoading: false,
      error: null,
      login: mockLogin,
      logout: mockLogout,
    })
  })

  it('Agent IDとPasskeyの入力フィールドを表示する', () => {
    render(<LoginForm />)

    expect(screen.getByLabelText('Agent ID')).toBeInTheDocument()
    expect(screen.getByLabelText('Passkey')).toBeInTheDocument()
  })

  it('ログインボタンを表示する', () => {
    render(<LoginForm />)

    expect(screen.getByRole('button', { name: 'ログイン' })).toBeInTheDocument()
  })

  it('フォーム送信時にlogin関数を呼び出す', async () => {
    render(<LoginForm />)

    const user = userEvent.setup()
    await user.type(screen.getByLabelText('Agent ID'), 'manager-1')
    await user.type(screen.getByLabelText('Passkey'), 'test-passkey')
    await user.click(screen.getByRole('button', { name: 'ログイン' }))

    expect(mockLogin).toHaveBeenCalledWith('manager-1', 'test-passkey')
  })

  it('ローディング中はボタンを無効化する', () => {
    vi.mocked(useAuth).mockReturnValue({
      isAuthenticated: false,
      agent: null,
      isLoading: true,
      error: null,
      login: mockLogin,
      logout: mockLogout,
    })

    render(<LoginForm />)

    expect(screen.getByRole('button', { name: 'ログイン中...' })).toBeDisabled()
  })

  it('エラーがある場合はエラーメッセージを表示する', () => {
    vi.mocked(useAuth).mockReturnValue({
      isAuthenticated: false,
      agent: null,
      isLoading: false,
      error: '認証に失敗しました',
      login: mockLogin,
      logout: mockLogout,
    })

    render(<LoginForm />)

    expect(screen.getByRole('alert')).toHaveTextContent('認証に失敗しました')
  })
})
