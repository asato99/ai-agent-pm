import { describe, it, expect } from 'vitest'
import {
  calculateTaskDepth,
  sortTasksWithHierarchy,
  getAncestorPath,
  getParentTask,
  getChildTasks,
  getBlockingTasks,
} from './taskSorting'
import type { Task } from '@/types'

// Helper to create minimal task objects
const createTask = (
  id: string,
  parentTaskId: string | null = null,
  title = `Task ${id}`
): Task =>
  ({
    id,
    parentTaskId,
    title,
    projectId: 'project-1',
    description: '',
    status: 'todo',
    priority: 'medium',
    assigneeId: null,
    creatorId: 'creator-1',
    dependencies: [],
    dependentTasks: [],
    blockedReason: null,
    estimatedMinutes: null,
    actualMinutes: null,
    approvalStatus: 'approved',
    requesterId: null,
    rejectedReason: null,
    contexts: [],
    createdAt: '2024-01-01T00:00:00Z',
    updatedAt: '2024-01-01T00:00:00Z',
  }) as Task

describe('calculateTaskDepth', () => {
  it('returns 0 for root task (no parent)', () => {
    const tasks = [createTask('task-1', null)]
    expect(calculateTaskDepth('task-1', tasks)).toBe(0)
  })

  it('returns 1 for direct child of root', () => {
    const tasks = [createTask('root', null), createTask('child', 'root')]
    expect(calculateTaskDepth('child', tasks)).toBe(1)
  })

  it('returns correct depth for deeply nested task', () => {
    const tasks = [
      createTask('l0', null),
      createTask('l1', 'l0'),
      createTask('l2', 'l1'),
      createTask('l3', 'l2'),
    ]
    expect(calculateTaskDepth('l3', tasks)).toBe(3)
  })

  it('handles circular reference gracefully', () => {
    const tasks = [createTask('a', 'b'), createTask('b', 'a')]
    // Should not infinite loop, return max depth or throw
    expect(() => calculateTaskDepth('a', tasks)).not.toThrow()
    // Depth should be limited by maxDepth
    expect(calculateTaskDepth('a', tasks)).toBeLessThanOrEqual(10)
  })

  it('returns 0 for non-existent task', () => {
    const tasks = [createTask('task-1', null)]
    expect(calculateTaskDepth('non-existent', tasks)).toBe(0)
  })
})

describe('sortTasksWithHierarchy', () => {
  it('places root tasks before their children', () => {
    const tasks = [
      createTask('child', 'root', 'Child Task'),
      createTask('root', null, 'Root Task'),
    ]

    const sorted = sortTasksWithHierarchy(tasks)

    expect(sorted[0].id).toBe('root')
    expect(sorted[1].id).toBe('child')
  })

  it('groups children under their parent', () => {
    const tasks = [
      createTask('root1', null, 'Root 1'),
      createTask('root2', null, 'Root 2'),
      createTask('child1-of-root1', 'root1', 'Child 1 of Root 1'),
      createTask('child2-of-root1', 'root1', 'Child 2 of Root 1'),
      createTask('child1-of-root2', 'root2', 'Child 1 of Root 2'),
    ]

    const sorted = sortTasksWithHierarchy(tasks)
    const ids = sorted.map((t) => t.id)

    // root1's children come before root2
    expect(ids.indexOf('child1-of-root1')).toBeLessThan(ids.indexOf('root2'))
    expect(ids.indexOf('child2-of-root1')).toBeLessThan(ids.indexOf('root2'))
  })

  it('sorts by depth within same tree', () => {
    const tasks = [
      createTask('grandchild', 'child', 'Grandchild'),
      createTask('root', null, 'Root'),
      createTask('child', 'root', 'Child'),
    ]

    const sorted = sortTasksWithHierarchy(tasks)
    const ids = sorted.map((t) => t.id)

    expect(ids).toEqual(['root', 'child', 'grandchild'])
  })

  it('handles tasks whose parent is in different column', () => {
    // In this column, we only have orphan-child and root
    // parent-in-other-column is in allTasks but not in column
    const tasksInThisColumn = [
      createTask('orphan-child', 'parent-in-other-column', 'Orphan Child'),
      createTask('root', null, 'Root'),
    ]
    const allTasks = [
      ...tasksInThisColumn,
      createTask('parent-in-other-column', null, 'Parent in Other Column'),
    ]

    const sorted = sortTasksWithHierarchy(tasksInThisColumn, allTasks)

    // orphan-child has parent not in this column, so treated as root-level
    expect(sorted.length).toBe(2)
    // Both are treated as "roots" in this column, sorted by depth then title
    // orphan-child has depth 1, root has depth 0, so root comes first
    expect(sorted[0].id).toBe('root')
    expect(sorted[1].id).toBe('orphan-child')
  })

  it('preserves order when no hierarchy exists', () => {
    const tasks = [
      createTask('task-a', null, 'A Task'),
      createTask('task-b', null, 'B Task'),
      createTask('task-c', null, 'C Task'),
    ]

    const sorted = sortTasksWithHierarchy(tasks)
    const ids = sorted.map((t) => t.id)

    // Should be sorted alphabetically by title
    expect(ids).toEqual(['task-a', 'task-b', 'task-c'])
  })
})

describe('getAncestorPath', () => {
  it('returns empty array for root task', () => {
    const tasks = [createTask('root', null, 'Root')]
    expect(getAncestorPath('root', tasks)).toEqual([])
  })

  it('returns parent title for first-level child', () => {
    const tasks = [createTask('root', null, 'Root'), createTask('child', 'root', 'Child')]
    expect(getAncestorPath('child', tasks)).toEqual(['Root'])
  })

  it('returns full ancestor path for deeply nested task', () => {
    const tasks = [
      createTask('l0', null, 'Level 0'),
      createTask('l1', 'l0', 'Level 1'),
      createTask('l2', 'l1', 'Level 2'),
      createTask('l3', 'l2', 'Level 3'),
    ]
    expect(getAncestorPath('l3', tasks)).toEqual(['Level 0', 'Level 1', 'Level 2'])
  })
})

describe('getParentTask', () => {
  it('returns null for root task', () => {
    const tasks = [createTask('root', null, 'Root')]
    expect(getParentTask('root', tasks)).toBeNull()
  })

  it('returns parent task for child', () => {
    const tasks = [createTask('parent', null, 'Parent'), createTask('child', 'parent', 'Child')]
    const parent = getParentTask('child', tasks)
    expect(parent?.id).toBe('parent')
    expect(parent?.title).toBe('Parent')
  })
})

describe('getChildTasks', () => {
  it('returns empty array for task with no children', () => {
    const tasks = [createTask('task-1', null)]
    expect(getChildTasks('task-1', tasks)).toEqual([])
  })

  it('returns all direct children', () => {
    const tasks = [
      createTask('parent', null, 'Parent'),
      createTask('child1', 'parent', 'Child 1'),
      createTask('child2', 'parent', 'Child 2'),
      createTask('grandchild', 'child1', 'Grandchild'),
    ]

    const children = getChildTasks('parent', tasks)
    expect(children).toHaveLength(2)
    expect(children.map((c) => c.id)).toContain('child1')
    expect(children.map((c) => c.id)).toContain('child2')
    // Grandchild should not be included
    expect(children.map((c) => c.id)).not.toContain('grandchild')
  })
})

describe('getBlockingTasks', () => {
  it('returns empty array for task with no dependencies', () => {
    const task = createTask('task-1')
    const allTasks = [task]
    expect(getBlockingTasks(task, allTasks)).toEqual([])
  })

  it('returns incomplete dependencies', () => {
    const dep1 = { ...createTask('dep-1', null, 'Dep 1'), status: 'in_progress' as const }
    const dep2 = { ...createTask('dep-2', null, 'Dep 2'), status: 'done' as const }
    const dep3 = { ...createTask('dep-3', null, 'Dep 3'), status: 'todo' as const }
    const task = {
      ...createTask('task-1'),
      dependencies: ['dep-1', 'dep-2', 'dep-3'],
    }
    const allTasks = [task, dep1, dep2, dep3]

    const blocking = getBlockingTasks(task, allTasks)

    // dep-2 is done, so should not be included
    expect(blocking).toHaveLength(2)
    expect(blocking.map((t) => t.id)).toContain('dep-1')
    expect(blocking.map((t) => t.id)).toContain('dep-3')
    expect(blocking.map((t) => t.id)).not.toContain('dep-2')
  })

  it('excludes cancelled dependencies', () => {
    const dep = { ...createTask('dep-1'), status: 'cancelled' as const }
    const task = { ...createTask('task-1'), dependencies: ['dep-1'] }
    const allTasks = [task, dep]

    expect(getBlockingTasks(task, allTasks)).toEqual([])
  })
})
