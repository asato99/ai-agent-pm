import { useState, type FormEvent } from 'react'
import { useAuth } from '@/hooks/useAuth'

export function LoginForm() {
  const [agentId, setAgentId] = useState('')
  const [passkey, setPasskey] = useState('')
  const { login, isLoading, error } = useAuth()

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault()
    await login(agentId, passkey)
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div>
        <label htmlFor="agentId" className="block text-sm font-medium text-gray-700">
          Agent ID
        </label>
        <input
          type="text"
          id="agentId"
          value={agentId}
          onChange={(e) => setAgentId(e.target.value)}
          className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
          required
        />
      </div>

      <div>
        <label htmlFor="passkey" className="block text-sm font-medium text-gray-700">
          Passkey
        </label>
        <input
          type="password"
          id="passkey"
          value={passkey}
          onChange={(e) => setPasskey(e.target.value)}
          className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
          required
        />
      </div>

      {error && (
        <div role="alert" className="text-red-600 text-sm">
          {error}
        </div>
      )}

      <button
        type="submit"
        disabled={isLoading}
        className="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {isLoading ? 'Logging in...' : 'Log in'}
      </button>
    </form>
  )
}
