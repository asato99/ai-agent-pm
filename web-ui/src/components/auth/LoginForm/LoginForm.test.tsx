import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen } from '../../../../tests/test-utils'
import userEvent from '@testing-library/user-event'
import { LoginForm } from './LoginForm'

// Mock useAuth
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

  it('displays Agent ID and Passkey input fields', () => {
    render(<LoginForm />)

    expect(screen.getByLabelText('Agent ID')).toBeInTheDocument()
    expect(screen.getByLabelText('Passkey')).toBeInTheDocument()
  })

  it('displays login button', () => {
    render(<LoginForm />)

    expect(screen.getByRole('button', { name: 'Log in' })).toBeInTheDocument()
  })

  it('calls login function on form submit', async () => {
    render(<LoginForm />)

    const user = userEvent.setup()
    await user.type(screen.getByLabelText('Agent ID'), 'manager-1')
    await user.type(screen.getByLabelText('Passkey'), 'test-passkey')
    await user.click(screen.getByRole('button', { name: 'Log in' }))

    expect(mockLogin).toHaveBeenCalledWith('manager-1', 'test-passkey')
  })

  it('disables button while loading', () => {
    vi.mocked(useAuth).mockReturnValue({
      isAuthenticated: false,
      agent: null,
      isLoading: true,
      error: null,
      login: mockLogin,
      logout: mockLogout,
    })

    render(<LoginForm />)

    expect(screen.getByRole('button', { name: 'Logging in...' })).toBeDisabled()
  })

  it('displays error message when error exists', () => {
    vi.mocked(useAuth).mockReturnValue({
      isAuthenticated: false,
      agent: null,
      isLoading: false,
      error: 'Authentication failed',
      login: mockLogin,
      logout: mockLogout,
    })

    render(<LoginForm />)

    expect(screen.getByRole('alert')).toHaveTextContent('Authentication failed')
  })
})
