---
name: parallel-task-dispatch
description: "Use when you are a manager agent coordinating multiple worker agents and need to assign tasks in parallel. Covers: (1) Assessing task independence for parallel vs sequential dispatch, (2) Structuring task assignments with scope/goal/constraints/output, (3) Parallel utilization rules to avoid file conflicts, (4) Handling worker questions and re-review loops."
---

# Parallel Task Dispatch

Assign tasks to multiple workers efficiently by maximizing parallelism while avoiding conflicts.

**Announce at start:** "I'm using the parallel-task-dispatch skill to coordinate task assignments."

## 1. Assess Independence

Before assigning, evaluate each task:

- Can each task be understood without context from other tasks?
- Are there shared state or dependencies between tasks?
- Will workers edit the same files?

**Independent** → Assign to multiple workers in parallel
**Dependent** → Assign sequentially (wait for prior task completion)

## 2. Structure Each Assignment

Every task assignment to a worker must include:

- **Scope**: What they are responsible for (clearly bounded)
- **Goal**: Expected deliverable
- **Constraints**: What they must NOT do
- **Output**: What to report upon completion

Example:
```
@worker-programmer-01:
- Scope: Implement weather data fetching module (src/api/weather.ts)
- Goal: Working API client with error handling and types
- Constraints: Do not modify shared config or UI components
- Output: Report implemented functions, test results, any blockers
```

## 3. Parallel Utilization Rules

- Assign independent tasks to different workers simultaneously
- Assign independent verifications to different QA workers simultaneously
- **Never** assign tasks editing the same file to different workers
- When in doubt, assign to the same worker sequentially

## 4. Handle Issues During Execution

- **Worker question** → Answer clearly before allowing them to continue
- **Review finds problem** → Assign fix to the same worker who implemented it
- **After fix** → Always re-review before marking complete
- **Blocked worker** → Reassess dependencies; unblock or reassign
