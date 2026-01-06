# tests/conftest.py
# Shared test fixtures for aiagent_runner tests

import pytest
from pathlib import Path
from aiagent_runner.config import RunnerConfig
from aiagent_runner.mcp_client import TaskInfo


@pytest.fixture
def sample_config():
    """Create a sample configuration for testing."""
    return RunnerConfig(
        agent_id="test-agent-001",
        passkey="test-passkey-12345",
        polling_interval=5,
        cli_command="claude",
        cli_args=["--dangerously-skip-permissions"],
        working_directory="/tmp/test-workspace",
        log_directory="/tmp/test-logs"
    )


@pytest.fixture
def sample_task():
    """Create a sample task for testing."""
    return TaskInfo(
        task_id="task-001",
        project_id="project-001",
        title="Test Task",
        description="This is a test task description",
        priority="high",
        working_directory="/tmp/test-workspace",
        context={
            "progress": "50% complete",
            "findings": "Found issue in auth module"
        },
        handoff={
            "from_agent": "other-agent",
            "summary": "Previous work completed",
            "recommendations": "Focus on testing"
        }
    )


@pytest.fixture
def sample_task_minimal():
    """Create a minimal task without optional fields."""
    return TaskInfo(
        task_id="task-002",
        project_id="project-001",
        title="Minimal Task",
        description="A simple task",
        priority="medium"
    )


@pytest.fixture
def temp_yaml_config(tmp_path):
    """Create a temporary YAML config file."""
    config_content = """
agent_id: yaml-agent
passkey: yaml-passkey
polling_interval: 10
cli_command: gemini
cli_args: --verbose --no-confirm
working_directory: /home/user/projects
log_directory: /var/log/aiagent
"""
    config_file = tmp_path / "config.yaml"
    config_file.write_text(config_content)
    return config_file


@pytest.fixture
def temp_log_dir(tmp_path):
    """Create a temporary log directory."""
    log_dir = tmp_path / "logs"
    log_dir.mkdir()
    return log_dir


@pytest.fixture
def temp_work_dir(tmp_path):
    """Create a temporary working directory."""
    work_dir = tmp_path / "workspace"
    work_dir.mkdir()
    return work_dir
