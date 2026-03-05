import { useState } from 'react'
import type { AppSettings } from '@/types'

interface Props {
  settings: AppSettings
  onToggleRemoteAccess: (allow: boolean) => void
  onRegenerateToken: () => void
  onClearToken: () => void
  isUpdating: boolean
  isRegenerating: boolean
  isClearing: boolean
}

export function CoordinatorSettings({
  settings,
  onToggleRemoteAccess,
  onRegenerateToken,
  onClearToken,
  isUpdating,
  isRegenerating,
  isClearing,
}: Props) {
  const [showConfirmClear, setShowConfirmClear] = useState(false)

  return (
    <div className="space-y-6">
      {/* Coordinator Token */}
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Coordinator Token
        </label>
        <p className="text-xs text-gray-500 mb-2">
          Used to authenticate Runner and MCP connections. Keep this secret.
        </p>

        <div className="flex items-center gap-3 mb-3">
          <span className="font-mono text-sm bg-gray-100 px-3 py-1.5 rounded border border-gray-200">
            {settings.coordinatorTokenSet
              ? settings.coordinatorTokenMasked
              : '(not set)'}
          </span>
          {settings.coordinatorTokenSet && (
            <span className="text-xs text-green-600 font-medium">Active</span>
          )}
        </div>

        <div className="flex gap-2">
          <button
            onClick={onRegenerateToken}
            disabled={isRegenerating}
            className="px-3 py-1.5 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700 disabled:opacity-50"
          >
            {isRegenerating
              ? 'Generating...'
              : settings.coordinatorTokenSet
                ? 'Regenerate Token'
                : 'Generate Token'}
          </button>

          {settings.coordinatorTokenSet && !showConfirmClear && (
            <button
              onClick={() => setShowConfirmClear(true)}
              className="px-3 py-1.5 text-sm font-medium text-red-600 border border-red-300 rounded-md hover:bg-red-50"
            >
              Clear Token
            </button>
          )}

          {showConfirmClear && (
            <div className="flex items-center gap-2">
              <span className="text-xs text-red-600">
                This will disconnect all runners.
              </span>
              <button
                onClick={() => {
                  onClearToken()
                  setShowConfirmClear(false)
                }}
                disabled={isClearing}
                className="px-3 py-1.5 text-sm font-medium text-white bg-red-600 rounded-md hover:bg-red-700 disabled:opacity-50"
              >
                {isClearing ? 'Clearing...' : 'Confirm Clear'}
              </button>
              <button
                onClick={() => setShowConfirmClear(false)}
                className="px-3 py-1.5 text-sm font-medium text-gray-600 border border-gray-300 rounded-md hover:bg-gray-50"
              >
                Cancel
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Remote Access */}
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Remote Access
        </label>
        <p className="text-xs text-gray-500 mb-2">
          Allow connections from other devices on the local network. When disabled, only localhost connections are accepted.
        </p>

        <div className="flex items-center gap-3">
          <button
            onClick={() => onToggleRemoteAccess(!settings.allowRemoteAccess)}
            disabled={isUpdating}
            className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
              settings.allowRemoteAccess ? 'bg-blue-600' : 'bg-gray-300'
            } ${isUpdating ? 'opacity-50' : ''}`}
          >
            <span
              className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                settings.allowRemoteAccess ? 'translate-x-6' : 'translate-x-1'
              }`}
            />
          </button>
          <span className="text-sm text-gray-700">
            {settings.allowRemoteAccess ? 'Enabled' : 'Disabled'}
          </span>
        </div>

        {settings.allowRemoteAccess && (
          <div className="mt-2 p-2 bg-yellow-50 border border-yellow-200 rounded text-xs text-yellow-700">
            Remote access is enabled. The server is accessible from other devices on the network.
            A server restart is required for this change to take effect.
          </div>
        )}
      </div>
    </div>
  )
}
