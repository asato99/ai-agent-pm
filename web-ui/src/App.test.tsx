import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '../tests/test-utils'
import App from './App'

// Mock useAuth
vi.mock('@/hooks/useAuth', () => ({
  useAuth: () => ({
    isAuthenticated: false,
    agent: null,
    isLoading: false,
    error: null,
    login: vi.fn(),
    logout: vi.fn(),
  }),
}))

describe('App', () => {
  it('renders login page by default', () => {
    render(<App />)
    expect(screen.getByText('AI Agent PM')).toBeInTheDocument()
    expect(screen.getByLabelText('Agent ID')).toBeInTheDocument()
  })
})
