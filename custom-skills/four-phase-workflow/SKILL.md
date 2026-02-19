---
name: four-phase-workflow
description: >
  Use when you are a manager agent orchestrating a multi-phase development workflow.
  Covers:
  (1) Four-phase progression: Plan → Design → Implementation → Test,
  (2) Inner review loop in each phase: work → review → revise until approved,
  (3) Phase 4 (Test) as quality gate with backward phase progression,
  (4) Three-role coordination: work worker, review worker, manager.
---

# Four-Phase Workflow

Orchestrate development through four phases, each with an inner review loop.

**Announce at start:** "I'm using the four-phase-workflow skill to coordinate the development phases."

## Overview

```
Phase 1: Plan ←──────────────────────────────┐
  [Planner works → Reviewer reviews → loop]  │
         ↓ APPROVED                           │
Phase 2: Design                               │
  [Designer works → Reviewer reviews → loop]  │
         ↓ APPROVED                           │
Phase 3: Implementation ←─────────┐           │
  [Programmer works → Reviewer reviews → loop]│
         ↓ APPROVED               │           │
Phase 4: Test (Quality Gate)      │           │
  [QA works → Reviewer reviews]   │           │
         ↓                        │           │
    APPROVED → Complete           │           │
    CHANGES_REQUESTED ────────────┘ (default) │
    CHANGES_REQUESTED (major) ────────────────┘ (manager discretion)
```

## Your Role as Manager

- You do NOT do the work. You orchestrate and judge.
- Assign work to the appropriate worker for each phase.
- Assign review to a **different** worker (reviewer).
- When reviewer creates a report, pass the **report filename** explicitly to the work worker.
- Judge phase completion based on review report documents, not verbal confirmation.

## Phase Definitions

### Phase 1: Plan

- **Work worker**: Planner
- **Deliverable**: Plan document (Markdown)
- **Review focus**: Completeness, feasibility, clarity of task decomposition

### Phase 2: Design

- **Work worker**: Designer
- **Deliverable**: Design document / UI mockups
- **Review focus**: Plan compliance, user experience, visual consistency

### Phase 3: Implementation

- **Work worker**: Programmer(s)
- **Deliverable**: Working code
- **Review focus**: Plan/design compliance, code correctness, no excess/missing items
- Use parallel-task-dispatch skill if assigning to multiple programmers

### Phase 4: Test (Quality Gate)

- **Work worker**: QA
- **Deliverable**: Test execution results and bug reports
- **Review focus**: Test coverage, found issues, overall quality assessment

## Inner Review Loop (applies to every phase)

```
1. Manager assigns work to Work Worker
         ↓
2. Work Worker completes → reports done
         ↓
3. Manager assigns review to Review Worker
         ↓
4. Review Worker creates report document
         ↓
5. Manager reads report
         ↓
   ┌─ APPROVED → Phase complete, proceed to next phase
   └─ CHANGES_REQUESTED:
         ↓
      6. Manager passes fix instructions to Work Worker
         - Include: review report filename
         - Include: specific items to fix
         ↓
      7. Work Worker fixes → reports done
         ↓
      8. → Go to step 3 (re-review)
```

### Critical: Report Handoff

When passing a review report to the work worker for fixes:

```
@work-worker:
- Review report: <report-filename> ← MUST include filename
- Fix items: [list specific CHANGES_REQUESTED items from report]
- Do NOT change anything not mentioned in the report
```

### Loop Escalation

If the same report goes through 3+ fix cycles, assess whether the issue is in a prior phase's deliverable.

## Phase 4: Quality Gate Rules

Phase 4 determines whether the project meets quality standards.

**APPROVED** → Project complete.

**CHANGES_REQUESTED** (default) → Return to Phase 3.
- Assign fixes to the same programmer who implemented the relevant code
- After fixes, re-execute Phase 4 from the beginning

**CHANGES_REQUESTED** (major, manager discretion) → Return to Phase 1.
- Use when test failures indicate fundamental plan or design problems
- Examples: missing requirements, wrong architecture, misunderstood scope

## Phase Progression Rules

- Never skip phases
- Never skip the inner review loop within any phase
- Always base phase gate decisions on review report documents
- Fixes go to the same worker who did the original work
- After fix, reviewer updates the same report (does not create a new one)
- Review reports follow the project-docs skill format
