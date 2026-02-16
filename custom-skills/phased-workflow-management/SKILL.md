---
name: phased-workflow-management
description: "Use when you are a manager agent orchestrating a multi-phase development workflow (planning → implementation → review). Covers: (1) Three-phase progression with clear entry/exit criteria, (2) Two-stage review process (spec compliance before quality), (3) Fix-and-re-review loops until all checks pass."
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

### Stage 1: Spec Compliance
- Verify all requirements are met
- Check that deliverables match the approved plan
- **If fail** → Send specific fix instructions to the implementing worker

### Stage 2: Quality
- Review code quality, test coverage, edge cases
- **If fail** → Send specific fix instructions to the implementing worker

### Fix-and-Re-review Loop

```
Review fails → Same worker fixes → Re-review (both stages)
         ↑                                    |
         └────── repeat until pass ───────────┘
```

**Exit criteria:** All verifications pass both stages.

## Phase Progression Rules

- Never skip phases — planning must complete before implementation begins
- Never skip review stages — spec compliance must pass before quality review
- Fixes always go to the same worker who implemented the original task
- After fix, always re-review from stage 1 (not just the failed stage)
