# tests/test_coordinator.py
# Tests for Coordinator log directory functionality

import os
from pathlib import Path

import pytest

from aiagent_runner.coordinator import Coordinator
from aiagent_runner.coordinator_config import CoordinatorConfig


class TestCoordinatorGetLogDirectory:
    """Tests for Coordinator._get_log_directory()."""

    @pytest.fixture
    def minimal_config(self):
        """Create a minimal CoordinatorConfig for testing."""
        return CoordinatorConfig(
            agents={},
            mcp_socket_path="/tmp/test.sock",
            polling_interval=5,
            max_concurrent=1
        )

    def test_get_log_directory_with_working_dir(self, minimal_config, tmp_path):
        """Should return {working_dir}/.aiagent/logs/{agent_id}/ when working_dir is provided."""
        coordinator = Coordinator(minimal_config)
        working_dir = str(tmp_path / "my-project")
        agent_id = "agt_test123"

        log_dir = coordinator._get_log_directory(working_dir, agent_id)

        expected = Path(working_dir) / ".aiagent" / "logs" / agent_id
        assert log_dir == expected
        assert log_dir.exists()

    def test_get_log_directory_without_working_dir(self, minimal_config):
        """Should return App Support path when working_dir is None."""
        coordinator = Coordinator(minimal_config)
        agent_id = "agt_test456"

        log_dir = coordinator._get_log_directory(None, agent_id)

        expected = (
            Path.home()
            / "Library" / "Application Support" / "AIAgentPM"
            / "agent_logs" / agent_id
        )
        assert log_dir == expected
        assert log_dir.exists()

    def test_get_log_directory_creates_parent_dirs(self, minimal_config, tmp_path):
        """Should create parent directories if they don't exist."""
        coordinator = Coordinator(minimal_config)
        working_dir = str(tmp_path / "new-project" / "deeply" / "nested")
        agent_id = "agt_nested"

        log_dir = coordinator._get_log_directory(working_dir, agent_id)

        assert log_dir.exists()
        assert log_dir.is_dir()

    def test_get_log_directory_with_empty_working_dir(self, minimal_config):
        """Should treat empty string as None (use fallback)."""
        coordinator = Coordinator(minimal_config)
        agent_id = "agt_empty"

        log_dir = coordinator._get_log_directory("", agent_id)

        expected = (
            Path.home()
            / "Library" / "Application Support" / "AIAgentPM"
            / "agent_logs" / agent_id
        )
        assert log_dir == expected
