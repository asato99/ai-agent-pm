import type { Task } from '@/types'

/**
 * Calculate the depth of a task in the hierarchy tree
 * @param taskId - ID of the task to calculate depth for
 * @param allTasks - Array of all tasks to traverse the hierarchy
 * @param maxDepth - Maximum depth to prevent infinite loops (default: 10)
 * @returns Depth level (0 = root, 1 = first level, etc.)
 */
export function calculateTaskDepth(
  taskId: string,
  allTasks: Pick<Task, 'id' | 'parentTaskId'>[],
  maxDepth = 10
): number {
  const taskMap = new Map(allTasks.map((t) => [t.id, t]))
  let depth = 0
  let current = taskMap.get(taskId)
  const visited = new Set<string>()

  while (current?.parentTaskId && depth < maxDepth) {
    if (visited.has(current.id)) break // Circular reference protection
    visited.add(current.id)
    current = taskMap.get(current.parentTaskId)
    depth++
  }

  return depth
}

/**
 * Build ancestor path for a task (from root to parent, not including self)
 * @param taskId - ID of the task
 * @param allTasks - Array of all tasks
 * @returns Array of ancestor task titles from root to direct parent
 */
export function getAncestorPath(
  taskId: string,
  allTasks: Pick<Task, 'id' | 'parentTaskId' | 'title'>[]
): string[] {
  const taskMap = new Map(allTasks.map((t) => [t.id, t]))
  const task = taskMap.get(taskId)
  if (!task?.parentTaskId) return []

  const ancestors: string[] = []
  let current = taskMap.get(task.parentTaskId)
  const visited = new Set<string>()

  while (current) {
    if (visited.has(current.id)) break
    visited.add(current.id)
    ancestors.unshift(current.title)
    current = current.parentTaskId ? taskMap.get(current.parentTaskId) : undefined
  }

  return ancestors
}

interface TaskWithDepth {
  task: Task
  depth: number
  parentInColumn: boolean
}

/**
 * Sort tasks hierarchically for display in a Kanban column
 * Tasks are sorted so that parents come before their children,
 * with children appearing directly after their parent.
 *
 * @param tasksInColumn - Tasks in the current column to sort
 * @param allTasks - All tasks (for calculating depth when parent is in different column)
 * @returns Sorted array of tasks
 */
export function sortTasksWithHierarchy(
  tasksInColumn: Task[],
  allTasks?: Task[]
): Task[] {
  const all = allTasks || tasksInColumn
  const inColumnIds = new Set(tasksInColumn.map((t) => t.id))

  // Calculate depth and check if parent is in same column
  const tasksWithDepth: TaskWithDepth[] = tasksInColumn.map((task) => ({
    task,
    depth: calculateTaskDepth(task.id, all),
    parentInColumn: task.parentTaskId ? inColumnIds.has(task.parentTaskId) : false,
  }))

  // Build sorted tree structure
  return buildSortedTree(tasksWithDepth, inColumnIds)
}

/**
 * Build a sorted tree structure from tasks with depth info
 */
function buildSortedTree(
  tasksWithDepth: TaskWithDepth[],
  inColumnIds: Set<string>
): Task[] {
  // Create a map for quick lookup
  const taskMap = new Map(tasksWithDepth.map((t) => [t.task.id, t]))

  // Find root tasks (either no parent, or parent not in this column)
  const rootTasks = tasksWithDepth.filter((t) => !t.parentInColumn)

  // Build children map (only for children whose parent is in this column)
  const childrenMap = new Map<string, TaskWithDepth[]>()
  for (const t of tasksWithDepth) {
    if (t.parentInColumn && t.task.parentTaskId) {
      const siblings = childrenMap.get(t.task.parentTaskId) || []
      siblings.push(t)
      childrenMap.set(t.task.parentTaskId, siblings)
    }
  }

  // DFS to build sorted list
  const result: Task[] = []

  function addTaskAndChildren(taskWithDepth: TaskWithDepth) {
    result.push(taskWithDepth.task)
    const children = childrenMap.get(taskWithDepth.task.id) || []
    // Sort children by depth (should be same) then by title
    children.sort((a, b) => a.task.title.localeCompare(b.task.title))
    for (const child of children) {
      addTaskAndChildren(child)
    }
  }

  // Sort root tasks by depth (for orphaned children whose parent is elsewhere)
  // then by title
  rootTasks.sort((a, b) => {
    if (a.depth !== b.depth) return a.depth - b.depth
    return a.task.title.localeCompare(b.task.title)
  })

  for (const root of rootTasks) {
    addTaskAndChildren(root)
  }

  return result
}

/**
 * Get the direct parent of a task
 * @param taskId - ID of the task
 * @param allTasks - Array of all tasks
 * @returns Parent task or null
 */
export function getParentTask(taskId: string, allTasks: Task[]): Task | null {
  const task = allTasks.find((t) => t.id === taskId)
  if (!task?.parentTaskId) return null
  return allTasks.find((t) => t.id === task.parentTaskId) || null
}

/**
 * Get all child tasks of a task
 * @param taskId - ID of the parent task
 * @param allTasks - Array of all tasks
 * @returns Array of child tasks
 */
export function getChildTasks(taskId: string, allTasks: Task[]): Task[] {
  return allTasks.filter((t) => t.parentTaskId === taskId)
}

/**
 * Get blocking tasks (incomplete dependencies) for a task
 * @param task - The task to check
 * @param allTasks - Array of all tasks
 * @returns Array of incomplete dependency tasks
 */
export function getBlockingTasks(task: Task, allTasks: Task[]): Task[] {
  if (!task.dependencies || task.dependencies.length === 0) return []

  return allTasks.filter(
    (t) => task.dependencies.includes(t.id) && t.status !== 'done' && t.status !== 'cancelled'
  )
}
