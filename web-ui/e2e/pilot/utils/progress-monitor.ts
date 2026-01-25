/**
 * Progress monitoring utility for pilot tests
 *
 * Tracks events during pilot test execution for:
 * - Progress reporting
 * - Stale/stuck detection
 * - Loop detection
 * - Post-test analysis
 */

export type ProgressEventType =
  | 'task_created'
  | 'status_change'
  | 'context_added'
  | 'chat_message'
  | 'agent_started'
  | 'agent_completed'
  | 'error'
  | 'warning'

export interface ProgressEvent {
  timestamp: Date
  type: ProgressEventType
  details: Record<string, unknown>
}

export class ProgressMonitor {
  private events: ProgressEvent[] = []
  private lastEventTime: Date = new Date()
  private startTime: Date = new Date()

  constructor() {
    this.startTime = new Date()
    this.lastEventTime = this.startTime
  }

  /**
   * Record a progress event
   */
  recordEvent(
    type: ProgressEventType,
    details: Record<string, unknown>
  ): void {
    const event: ProgressEvent = {
      timestamp: new Date(),
      type,
      details,
    }
    this.events.push(event)
    this.lastEventTime = event.timestamp

    // Log to console with timestamp
    const elapsed = Math.round(
      (event.timestamp.getTime() - this.startTime.getTime()) / 1000
    )
    console.log(`[Monitor +${elapsed}s] ${type}: ${JSON.stringify(details)}`)
  }

  /**
   * Get time since last event in milliseconds
   */
  getTimeSinceLastEvent(): number {
    return Date.now() - this.lastEventTime.getTime()
  }

  /**
   * Get total elapsed time in milliseconds
   */
  getTotalElapsed(): number {
    return Date.now() - this.startTime.getTime()
  }

  /**
   * Get all events of a specific type
   */
  getEventsByType(type: ProgressEventType): ProgressEvent[] {
    return this.events.filter((e) => e.type === type)
  }

  /**
   * Detect loops - same pattern of events repeating
   *
   * @param windowSize Number of events to compare (default: 5)
   * @returns true if a loop pattern is detected
   */
  detectLoop(windowSize: number = 5): boolean {
    if (this.events.length < windowSize * 2) {
      return false
    }

    const recent = this.events.slice(-windowSize)
    const previous = this.events.slice(-windowSize * 2, -windowSize)

    const recentPattern = recent
      .map((e) => `${e.type}:${JSON.stringify(e.details)}`)
      .join('|')
    const previousPattern = previous
      .map((e) => `${e.type}:${JSON.stringify(e.details)}`)
      .join('|')

    if (recentPattern === previousPattern) {
      console.warn('[Monitor] LOOP DETECTED: Same event pattern repeating')
      return true
    }

    return false
  }

  /**
   * Detect repeated errors
   *
   * @param threshold Number of same errors to trigger detection
   * @returns true if repeated errors detected
   */
  detectRepeatedErrors(threshold: number = 3): boolean {
    const errors = this.getEventsByType('error')
    if (errors.length < threshold) {
      return false
    }

    // Check if last N errors are the same
    const recentErrors = errors.slice(-threshold)
    const firstErrorMsg = JSON.stringify(recentErrors[0].details)
    const allSame = recentErrors.every(
      (e) => JSON.stringify(e.details) === firstErrorMsg
    )

    if (allSame) {
      console.warn(
        `[Monitor] REPEATED ERROR: Same error occurred ${threshold} times`
      )
      return true
    }

    return false
  }

  /**
   * Generate a summary report of the pilot test execution
   */
  generateReport(): string {
    const lines: string[] = []
    const totalSeconds = Math.round(this.getTotalElapsed() / 1000)

    lines.push('='.repeat(60))
    lines.push('PILOT TEST PROGRESS REPORT')
    lines.push('='.repeat(60))
    lines.push('')
    lines.push(`Total Duration: ${totalSeconds}s`)
    lines.push(`Total Events: ${this.events.length}`)
    lines.push('')

    // Event counts by type
    lines.push('Event Summary:')
    const typeCounts: Record<string, number> = {}
    for (const event of this.events) {
      typeCounts[event.type] = (typeCounts[event.type] || 0) + 1
    }
    for (const type of Object.keys(typeCounts)) {
      lines.push(`  ${type}: ${typeCounts[type]}`)
    }
    lines.push('')

    // Timeline
    lines.push('Event Timeline:')
    lines.push('-'.repeat(60))
    for (const event of this.events) {
      const elapsed = Math.round(
        (event.timestamp.getTime() - this.startTime.getTime()) / 1000
      )
      const timestamp = event.timestamp.toISOString().substr(11, 8)
      lines.push(
        `[${timestamp}] (+${elapsed.toString().padStart(4)}s) ${event.type}`
      )
      lines.push(`         ${JSON.stringify(event.details)}`)
    }
    lines.push('-'.repeat(60))

    // Warnings and errors
    const warnings = this.getEventsByType('warning')
    const errors = this.getEventsByType('error')
    if (warnings.length > 0 || errors.length > 0) {
      lines.push('')
      lines.push('Issues:')
      for (const w of warnings) {
        lines.push(`  [WARNING] ${JSON.stringify(w.details)}`)
      }
      for (const e of errors) {
        lines.push(`  [ERROR] ${JSON.stringify(e.details)}`)
      }
    }

    lines.push('')
    lines.push('='.repeat(60))

    return lines.join('\n')
  }

  /**
   * Get metrics for analysis
   */
  getMetrics(): {
    totalDuration: number
    eventCount: number
    taskCreatedCount: number
    statusChangeCount: number
    errorCount: number
    warningCount: number
  } {
    return {
      totalDuration: this.getTotalElapsed(),
      eventCount: this.events.length,
      taskCreatedCount: this.getEventsByType('task_created').length,
      statusChangeCount: this.getEventsByType('status_change').length,
      errorCount: this.getEventsByType('error').length,
      warningCount: this.getEventsByType('warning').length,
    }
  }

  /**
   * Reset the monitor for a new test
   */
  reset(): void {
    this.events = []
    this.startTime = new Date()
    this.lastEventTime = this.startTime
  }
}
