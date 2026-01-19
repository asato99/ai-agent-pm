import { describe, it, expect } from 'vitest'
import { render, screen } from '../tests/test-utils'
import App from './App'

describe('App', () => {
  it('renders login page by default', () => {
    render(<App />)
    expect(screen.getByText('Login Page (TODO)')).toBeInTheDocument()
  })
})
