# tests/test_prompt_builder.py
# Tests for PromptBuilder

import pytest

from aiagent_runner.prompt_builder import PromptBuilder


class TestPromptBuilderInit:
    """Tests for PromptBuilder initialization."""

    def test_init_with_agent_id(self):
        """Should initialize with agent ID."""
        builder = PromptBuilder("agent-001")
        assert builder.agent_id == "agent-001"
        assert builder.agent_name == "agent-001"  # defaults to agent_id

    def test_init_with_agent_name(self):
        """Should initialize with agent name."""
        builder = PromptBuilder("agent-001", "Test Agent")
        assert builder.agent_id == "agent-001"
        assert builder.agent_name == "Test Agent"


class TestPromptBuilderBuild:
    """Tests for PromptBuilder.build()."""

    def test_build_minimal_task(self, sample_task_minimal):
        """Should build prompt for minimal task."""
        builder = PromptBuilder("agent-001", "Test Agent")

        prompt = builder.build(sample_task_minimal)

        assert "# Task: Minimal Task" in prompt
        assert "Task ID: task-002" in prompt
        assert "Project ID: project-001" in prompt
        assert "Agent ID: agent-001" in prompt
        assert "Agent Name: Test Agent" in prompt
        assert "Priority: medium" in prompt
        assert "A simple task" in prompt
        assert "Previous Context" not in prompt  # no context
        assert "Handoff Information" not in prompt  # no handoff

    def test_build_full_task(self, sample_task):
        """Should build prompt with all sections."""
        builder = PromptBuilder("agent-001", "Test Agent")

        prompt = builder.build(sample_task)

        # Header
        assert "# Task: Test Task" in prompt

        # Identification
        assert "Task ID: task-001" in prompt
        assert "Project ID: project-001" in prompt
        assert "Agent ID: agent-001" in prompt
        assert "Agent Name: Test Agent" in prompt
        assert "Priority: high" in prompt

        # Description
        assert "This is a test task description" in prompt

        # Working directory
        assert "Working Directory" in prompt
        assert "/tmp/test-workspace" in prompt

        # Context
        assert "Previous Context" in prompt
        assert "50% complete" in prompt
        assert "Found issue in auth module" in prompt

        # Handoff
        assert "Handoff Information" in prompt
        assert "other-agent" in prompt
        assert "Previous work completed" in prompt
        assert "Focus on testing" in prompt

        # Instructions
        assert "Instructions" in prompt
        assert 'save_context(task_id="task-001"' in prompt
        assert 'update_task_status(task_id="task-001"' in prompt

    def test_build_with_context_override(self, sample_task):
        """Should use provided context over task context."""
        builder = PromptBuilder("agent-001")

        custom_context = {
            "progress": "75% complete",
            "findings": "Custom findings"
        }

        prompt = builder.build(sample_task, context=custom_context)

        assert "75% complete" in prompt
        assert "Custom findings" in prompt
        assert "50% complete" not in prompt  # original context not used

    def test_build_with_handoff_override(self, sample_task):
        """Should use provided handoff over task handoff."""
        builder = PromptBuilder("agent-001")

        custom_handoff = {
            "from_agent": "new-agent",
            "summary": "New summary"
        }

        prompt = builder.build(sample_task, handoff=custom_handoff)

        assert "new-agent" in prompt
        assert "New summary" in prompt
        assert "other-agent" not in prompt  # original handoff not used


class TestPromptBuilderSections:
    """Tests for individual section builders."""

    def test_build_context_section(self, sample_task):
        """Should build context section correctly."""
        builder = PromptBuilder("agent-001")

        context = {
            "progress": "Progress info",
            "findings": "Findings info",
            "blockers": "Blocker info",
            "next_steps": "Next steps info"
        }

        section = builder._build_context(context)

        assert "Previous Context" in section
        assert "**Progress**: Progress info" in section
        assert "**Findings**: Findings info" in section
        assert "**Blockers**: Blocker info" in section
        assert "**Next Steps**: Next steps info" in section

    def test_build_context_partial(self, sample_task):
        """Should handle partial context."""
        builder = PromptBuilder("agent-001")

        context = {
            "progress": "Only progress"
        }

        section = builder._build_context(context)

        assert "**Progress**: Only progress" in section
        assert "Findings" not in section

    def test_build_handoff_section(self, sample_task):
        """Should build handoff section correctly."""
        builder = PromptBuilder("agent-001")

        handoff = {
            "from_agent": "previous-agent",
            "summary": "Work summary",
            "context": "Additional context",
            "recommendations": "Recommendations"
        }

        section = builder._build_handoff(handoff)

        assert "Handoff Information" in section
        assert "**From Agent**: previous-agent" in section
        assert "**Summary**: Work summary" in section
        assert "**Context**: Additional context" in section
        assert "**Recommendations**: Recommendations" in section

    def test_build_handoff_with_from_agent_id(self):
        """Should handle from_agent_id in handoff."""
        builder = PromptBuilder("agent-001")

        handoff = {
            "from_agent_id": "agent-002",  # alternative key
            "summary": "Summary"
        }

        section = builder._build_handoff(handoff)

        assert "**From Agent**: agent-002" in section

    def test_build_instructions_section(self, sample_task):
        """Should build instructions with correct task ID."""
        builder = PromptBuilder("agent-001")

        section = builder._build_instructions(sample_task)

        assert "Instructions" in section
        assert 'task_id="task-001"' in section
        assert 'from_agent_id="agent-001"' in section
