# src/aiagent_runner/prompt_builder.py
# Build prompts for CLI execution from task information
# Reference: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-5

from typing import Optional
from aiagent_runner.mcp_client import TaskInfo


class PromptBuilder:
    """Builds prompts for CLI execution from task information."""

    def __init__(self, agent_id: str, agent_name: Optional[str] = None):
        """Initialize prompt builder.

        Args:
            agent_id: Agent ID executing the task
            agent_name: Human-readable agent name (optional)
        """
        self.agent_id = agent_id
        self.agent_name = agent_name or agent_id

    def build(
        self,
        task: TaskInfo,
        context: Optional[dict] = None,
        handoff: Optional[dict] = None
    ) -> str:
        """Build a prompt from task information.

        Args:
            task: Task information
            context: Previous context (optional, overrides task.context)
            handoff: Handoff information (optional, overrides task.handoff)

        Returns:
            Complete prompt string for CLI execution
        """
        # Use provided context/handoff or fall back to task's
        ctx = context or task.context
        ho = handoff or task.handoff

        sections = [
            self._build_header(task),
            self._build_identification(task),
            self._build_description(task),
        ]

        if task.working_directory:
            sections.append(self._build_working_directory(task))

        if ctx:
            sections.append(self._build_context(ctx))

        if ho:
            sections.append(self._build_handoff(ho))

        sections.append(self._build_instructions(task))

        return "\n\n".join(sections)

    def _build_header(self, task: TaskInfo) -> str:
        """Build header section."""
        return f"# Task: {task.title}"

    def _build_identification(self, task: TaskInfo) -> str:
        """Build identification section with IDs."""
        return f"""## Identification
- Task ID: {task.task_id}
- Project ID: {task.project_id}
- Agent ID: {self.agent_id}
- Agent Name: {self.agent_name}
- Priority: {task.priority}"""

    def _build_description(self, task: TaskInfo) -> str:
        """Build description section."""
        return f"""## Description
{task.description}"""

    def _build_working_directory(self, task: TaskInfo) -> str:
        """Build working directory section."""
        return f"""## Working Directory
Path: {task.working_directory}"""

    def _build_context(self, context: dict) -> str:
        """Build previous context section."""
        lines = ["## Previous Context"]
        if context.get("progress"):
            lines.append(f"**Progress**: {context['progress']}")
        if context.get("findings"):
            lines.append(f"**Findings**: {context['findings']}")
        if context.get("blockers"):
            lines.append(f"**Blockers**: {context['blockers']}")
        if context.get("next_steps"):
            lines.append(f"**Next Steps**: {context['next_steps']}")
        return "\n".join(lines)

    def _build_handoff(self, handoff: dict) -> str:
        """Build handoff information section."""
        lines = ["## Handoff Information"]
        if handoff.get("from_agent") or handoff.get("from_agent_id"):
            from_agent = handoff.get("from_agent") or handoff.get("from_agent_id")
            lines.append(f"**From Agent**: {from_agent}")
        if handoff.get("summary"):
            lines.append(f"**Summary**: {handoff['summary']}")
        if handoff.get("context"):
            lines.append(f"**Context**: {handoff['context']}")
        if handoff.get("recommendations"):
            lines.append(f"**Recommendations**: {handoff['recommendations']}")
        return "\n".join(lines)

    def _build_instructions(self, task: TaskInfo) -> str:
        """Build instructions section."""
        return f"""## Instructions
1. Complete the task as described above
2. Save your progress regularly using:
   save_context(task_id="{task.task_id}", progress="...", findings="...", next_steps="...")
3. When done, update the task status using:
   update_task_status(task_id="{task.task_id}", status="done")
4. If you need to hand off to another agent, use:
   create_handoff(task_id="{task.task_id}", from_agent_id="{self.agent_id}", summary="...", recommendations="...")"""
