---
name: phased-workflow-management
description: >
  Use when you are a manager agent orchestrating a multi-phase development workflow
  (planning → implementation → review). Covers:
  (1) Three-phase progression with clear entry/exit criteria,
  (2) Two-stage review process with document-based feedback (see project-docs skill),
  (3) Fix-and-re-review loops until all checks pass.
---

# Phased Workflow Management

Orchestrate development through three sequential phases with review gates.

**Announce at start:** "I'm using the phased-workflow-management skill to coordinate the development phases."

## Phase 1: Planning

1. Analyze requirements from the owner/stakeholder
2. Assign design and planning to the planner worker
3. Review and approve the plan before proceeding

**Exit criteria:** Approved plan with tasks decomposed to independently executable granularity.

## Phase 2: Implementation

4. Extract independent tasks from the approved plan
5. Assign implementation tasks to programmer workers (use parallel-task-dispatch skill if multiple workers)
6. Once implementation is complete, assign verification tasks to QA workers

**Exit criteria:** All implementation tasks reported complete by workers.

## Phase 3: Review

Two-stage review — do not proceed to stage 2 until stage 1 passes.

Reviewers create report documents following the project-docs skill. Use report documents as the basis for phase gate decisions — do not rely on verbal confirmation alone.

### Stage 1: Spec Compliance

1. Assign review to the reviewer
2. Reviewer creates a report document with findings
3. Check the reviewer's report
4. **If APPROVED** → Proceed to stage 2
5. **If CHANGES_REQUESTED** → Send specific fix instructions to the implementing worker

### Stage 2: Quality

1. Assign quality review to the reviewer
2. Reviewer updates or creates a report document
3. Check the reviewer's report
4. **If APPROVED** → Phase complete, archive the report (see project-docs skill)
5. **If CHANGES_REQUESTED** → Send specific fix instructions to the implementing worker

### Fix-and-Re-review Loop

```
CHANGES_REQUESTED の報告あり
         ↓
Same worker fixes → Reviewer re-reviews → Report updated
         ↑                                       |
         ├── CHANGES_REQUESTED → repeat ─────────┘
         └── APPROVED → Complete
```

- After fix, always re-review from stage 1 (not just the failed stage)
- Fixes always go to the same worker who implemented the original task
- Reviewer updates the same report document (does not create a new one)

### Loop Escalation

If the same report goes through 3+ fix cycles, the reviewer may flag potential root causes.
Assess whether the issue is in the plan itself, not just in the implementation.
If the plan needs revision, return to Phase 1.

**Exit criteria:** All review reports are APPROVED.

## Phase Progression Rules

- Never skip phases — planning must complete before implementation begins
- Never skip review stages — spec compliance must pass before quality review
- Always check report documents at phase gates — do not rely on verbal confirmation alone
- Fixes always go to the same worker who implemented the original task
- After fix, always re-review from stage 1 (not just the failed stage)
