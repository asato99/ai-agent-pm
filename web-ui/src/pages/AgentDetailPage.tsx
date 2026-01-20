import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { AppHeader } from '@/components/layout'
import { useAgent, useUpdateAgent } from '@/hooks'
import type { AgentStatus, UpdateAgentRequest } from '@/types'

const statusOptions: { value: AgentStatus; label: string }[] = [
  { value: 'active', label: 'Active' },
  { value: 'inactive', label: 'Inactive' },
]

export function AgentDetailPage() {
  const { agentId } = useParams<{ agentId: string }>()
  const navigate = useNavigate()
  const { agent, isLoading, error } = useAgent(agentId ?? null)
  const updateAgent = useUpdateAgent()

  const [name, setName] = useState('')
  const [role, setRole] = useState('')
  const [status, setStatus] = useState<AgentStatus>('active')
  const [maxParallelTasks, setMaxParallelTasks] = useState(1)
  const [systemPrompt, setSystemPrompt] = useState('')
  const [formError, setFormError] = useState<string | null>(null)
  const [saveSuccess, setSaveSuccess] = useState(false)

  // Initialize form when agent data is loaded
  useEffect(() => {
    if (agent) {
      setName(agent.name)
      setRole(agent.role)
      setStatus(agent.status)
      setMaxParallelTasks(agent.maxParallelTasks)
      setSystemPrompt(agent.systemPrompt ?? '')
    }
  }, [agent])

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!agent || !agentId) return

    const updates: UpdateAgentRequest = {}

    if (name !== agent.name) updates.name = name
    if (role !== agent.role) updates.role = role
    if (status !== agent.status) updates.status = status
    if (maxParallelTasks !== agent.maxParallelTasks) updates.maxParallelTasks = maxParallelTasks
    if ((systemPrompt || null) !== agent.systemPrompt) updates.systemPrompt = systemPrompt || undefined

    if (Object.keys(updates).length === 0) {
      // No changes
      setSaveSuccess(true)
      setTimeout(() => setSaveSuccess(false), 2000)
      return
    }

    updateAgent.mutate(
      { agentId, data: updates },
      {
        onSuccess: () => {
          setFormError(null)
          setSaveSuccess(true)
          setTimeout(() => setSaveSuccess(false), 2000)
        },
        onError: (err) => {
          setFormError(err.message)
        },
      }
    )
  }

  const handleBack = () => {
    navigate('/projects')
  }

  if (isLoading) {
    return (
      <div className="min-h-screen bg-gray-100">
        <AppHeader />
        <main className="max-w-3xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
          <p className="text-gray-500">Loading...</p>
        </main>
      </div>
    )
  }

  if (error) {
    return (
      <div className="min-h-screen bg-gray-100">
        <AppHeader />
        <main className="max-w-3xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
          <p className="text-red-500">An error occurred: {error.message}</p>
          <button
            onClick={handleBack}
            className="mt-4 text-blue-600 hover:underline"
          >
            ← Back
          </button>
        </main>
      </div>
    )
  }

  if (!agent) {
    return (
      <div className="min-h-screen bg-gray-100">
        <AppHeader />
        <main className="max-w-3xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
          <p className="text-gray-500">Agent not found</p>
          <button
            onClick={handleBack}
            className="mt-4 text-blue-600 hover:underline"
          >
            ← Back
          </button>
        </main>
      </div>
    )
  }

  const isLocked = agent.isLocked
  const isFormDisabled = isLocked || updateAgent.isPending

  return (
    <div className="min-h-screen bg-gray-100">
      <AppHeader />

      <main className="max-w-3xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
        <button
          onClick={handleBack}
          className="mb-6 text-blue-600 hover:underline flex items-center gap-1"
        >
          ← Back to Projects
        </button>

        <div className="bg-white rounded-lg shadow p-6">
          <h1 className="text-2xl font-bold text-gray-900 mb-6">Agent Detail</h1>

          {isLocked && (
            <div className="mb-4 p-3 bg-yellow-50 border border-yellow-200 rounded-md">
              <p className="text-sm text-yellow-700">
                This agent is currently locked and cannot be edited
              </p>
            </div>
          )}

          {formError && (
            <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-md">
              <p className="text-sm text-red-700">{formError}</p>
            </div>
          )}

          {saveSuccess && (
            <div className="mb-4 p-3 bg-green-50 border border-green-200 rounded-md">
              <p className="text-sm text-green-700">Saved successfully</p>
            </div>
          )}

          <form onSubmit={handleSubmit}>
            <div className="space-y-6">
              {/* Name */}
              <div>
                <label htmlFor="name" className="block text-sm font-medium text-gray-700 mb-1">
                  Name
                </label>
                <input
                  type="text"
                  id="name"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  disabled={isFormDisabled}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:bg-gray-100 disabled:cursor-not-allowed"
                  required
                />
              </div>

              {/* Role */}
              <div>
                <label htmlFor="role" className="block text-sm font-medium text-gray-700 mb-1">
                  Role
                </label>
                <input
                  type="text"
                  id="role"
                  value={role}
                  onChange={(e) => setRole(e.target.value)}
                  disabled={isFormDisabled}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:bg-gray-100 disabled:cursor-not-allowed"
                />
              </div>

              {/* Status */}
              <div>
                <label htmlFor="status" className="block text-sm font-medium text-gray-700 mb-1">
                  Status
                </label>
                <select
                  id="status"
                  value={status}
                  onChange={(e) => setStatus(e.target.value as AgentStatus)}
                  disabled={isFormDisabled}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:bg-gray-100 disabled:cursor-not-allowed"
                >
                  {statusOptions.map((opt) => (
                    <option key={opt.value} value={opt.value}>
                      {opt.label}
                    </option>
                  ))}
                </select>
              </div>

              {/* Max Parallel Tasks */}
              <div>
                <label htmlFor="maxParallelTasks" className="block text-sm font-medium text-gray-700 mb-1">
                  Max Parallel Tasks
                </label>
                <input
                  type="number"
                  id="maxParallelTasks"
                  value={maxParallelTasks}
                  onChange={(e) => setMaxParallelTasks(parseInt(e.target.value, 10) || 1)}
                  min={1}
                  max={10}
                  disabled={isFormDisabled}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:bg-gray-100 disabled:cursor-not-allowed"
                />
              </div>

              {/* System Prompt */}
              <div>
                <label htmlFor="systemPrompt" className="block text-sm font-medium text-gray-700 mb-1">
                  System Prompt
                </label>
                <textarea
                  id="systemPrompt"
                  value={systemPrompt}
                  onChange={(e) => setSystemPrompt(e.target.value)}
                  rows={6}
                  disabled={isFormDisabled}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:bg-gray-100 disabled:cursor-not-allowed"
                />
              </div>

              {/* Read-only Info */}
              <div className="border-t pt-6 mt-6">
                <h3 className="text-sm font-medium text-gray-700 mb-4">Additional Info</h3>
                <dl className="grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <dt className="text-gray-500">Type</dt>
                    <dd className="font-medium">{agent.agentType === 'ai' ? 'AI' : 'Human'}</dd>
                  </div>
                  <div>
                    <dt className="text-gray-500">Hierarchy</dt>
                    <dd className="font-medium">
                      {agent.hierarchyType === 'owner' && 'Owner'}
                      {agent.hierarchyType === 'manager' && 'Manager'}
                      {agent.hierarchyType === 'worker' && 'Worker'}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-gray-500">Role Type</dt>
                    <dd className="font-medium">
                      {agent.roleType === 'owner' && 'Owner'}
                      {agent.roleType === 'manager' && 'Manager'}
                      {agent.roleType === 'general' && 'General'}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-gray-500">Kick Method</dt>
                    <dd className="font-medium">{agent.kickMethod.toUpperCase()}</dd>
                  </div>
                  {agent.provider && (
                    <div>
                      <dt className="text-gray-500">Provider</dt>
                      <dd className="font-medium">{agent.provider}</dd>
                    </div>
                  )}
                  {agent.modelId && (
                    <div>
                      <dt className="text-gray-500">Model ID</dt>
                      <dd className="font-medium">{agent.modelId}</dd>
                    </div>
                  )}
                  <div>
                    <dt className="text-gray-500">Created At</dt>
                    <dd className="font-medium">{new Date(agent.createdAt).toLocaleString()}</dd>
                  </div>
                  <div>
                    <dt className="text-gray-500">Updated At</dt>
                    <dd className="font-medium">{new Date(agent.updatedAt).toLocaleString()}</dd>
                  </div>
                </dl>
              </div>
            </div>

            {/* Actions */}
            <div className="flex justify-end gap-3 mt-8 pt-6 border-t">
              <button
                type="button"
                onClick={handleBack}
                className="px-4 py-2 text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={isFormDisabled}
                className="px-4 py-2 text-white bg-blue-600 rounded-md hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {updateAgent.isPending ? 'Saving...' : 'Save'}
              </button>
            </div>
          </form>
        </div>
      </main>
    </div>
  )
}
