import { useState, useEffect } from 'react'
import type { AppSettings, UpdateSettingsRequest } from '@/types'

interface Props {
  settings: AppSettings
  onUpdate: (data: UpdateSettingsRequest) => void
  isUpdating: boolean
}

export function GeneralSettings({ settings, onUpdate, isUpdating }: Props) {
  const [agentBasePrompt, setAgentBasePrompt] = useState(settings.agentBasePrompt ?? '')
  const [ttl, setTtl] = useState(String(settings.pendingPurposeTTLSeconds))
  const [dirty, setDirty] = useState(false)

  useEffect(() => {
    setAgentBasePrompt(settings.agentBasePrompt ?? '')
    setTtl(String(settings.pendingPurposeTTLSeconds))
    setDirty(false)
  }, [settings])

  const handleSave = () => {
    const updates: UpdateSettingsRequest = {}
    if (agentBasePrompt !== (settings.agentBasePrompt ?? '')) {
      updates.agentBasePrompt = agentBasePrompt
    }
    const ttlNum = parseInt(ttl, 10)
    if (!isNaN(ttlNum) && ttlNum > 0 && ttlNum !== settings.pendingPurposeTTLSeconds) {
      updates.pendingPurposeTTLSeconds = ttlNum
    }
    onUpdate(updates)
    setDirty(false)
  }

  return (
    <div className="space-y-6">
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Agent Base Prompt
        </label>
        <p className="text-xs text-gray-500 mb-2">
          All AI agents will receive this prompt as part of their system instructions.
        </p>
        <textarea
          value={agentBasePrompt}
          onChange={(e) => {
            setAgentBasePrompt(e.target.value)
            setDirty(true)
          }}
          rows={8}
          className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
          placeholder="Enter base prompt for all agents..."
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Pending Purpose TTL (seconds)
        </label>
        <p className="text-xs text-gray-500 mb-2">
          How long an agent startup purpose (chat/task) remains valid.
        </p>
        <input
          type="number"
          min={1}
          value={ttl}
          onChange={(e) => {
            setTtl(e.target.value)
            setDirty(true)
          }}
          className="w-32 rounded-md border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
        />
      </div>

      <div>
        <button
          onClick={handleSave}
          disabled={!dirty || isUpdating}
          className="px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {isUpdating ? 'Saving...' : 'Save Changes'}
        </button>
      </div>
    </div>
  )
}
