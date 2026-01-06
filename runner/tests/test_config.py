# tests/test_config.py
# Tests for RunnerConfig

import os
import pytest
from pathlib import Path

from aiagent_runner.config import RunnerConfig


class TestRunnerConfigInit:
    """Tests for RunnerConfig initialization."""

    def test_init_with_required_fields(self):
        """Should create config with required fields."""
        config = RunnerConfig(
            agent_id="agent-001",
            passkey="passkey-123"
        )
        assert config.agent_id == "agent-001"
        assert config.passkey == "passkey-123"
        assert config.polling_interval == 5  # default
        assert config.cli_command == "claude"  # default

    def test_init_with_all_fields(self):
        """Should create config with all fields."""
        config = RunnerConfig(
            agent_id="agent-001",
            passkey="passkey-123",
            polling_interval=10,
            cli_command="gemini",
            cli_args=["--verbose"],
            working_directory="/home/user",
            log_directory="/var/log",
            mcp_socket_path="/tmp/mcp.sock"
        )
        assert config.polling_interval == 10
        assert config.cli_command == "gemini"
        assert config.cli_args == ["--verbose"]
        assert config.working_directory == "/home/user"
        assert config.log_directory == "/var/log"
        assert config.mcp_socket_path == "/tmp/mcp.sock"

    def test_init_validates_polling_interval(self):
        """Should reject non-positive polling interval."""
        with pytest.raises(ValueError, match="polling_interval must be positive"):
            RunnerConfig(
                agent_id="agent-001",
                passkey="passkey-123",
                polling_interval=0
            )

        with pytest.raises(ValueError, match="polling_interval must be positive"):
            RunnerConfig(
                agent_id="agent-001",
                passkey="passkey-123",
                polling_interval=-5
            )

    def test_init_validates_agent_id(self):
        """Should reject empty agent_id."""
        with pytest.raises(ValueError, match="agent_id is required"):
            RunnerConfig(
                agent_id="",
                passkey="passkey-123"
            )

    def test_init_validates_passkey(self):
        """Should reject empty passkey."""
        with pytest.raises(ValueError, match="passkey is required"):
            RunnerConfig(
                agent_id="agent-001",
                passkey=""
            )


class TestRunnerConfigFromEnv:
    """Tests for RunnerConfig.from_env()."""

    def test_from_env_with_required_vars(self, monkeypatch):
        """Should load config from environment variables."""
        monkeypatch.setenv("AGENT_ID", "env-agent")
        monkeypatch.setenv("AGENT_PASSKEY", "env-passkey")

        config = RunnerConfig.from_env()

        assert config.agent_id == "env-agent"
        assert config.passkey == "env-passkey"
        assert config.polling_interval == 5

    def test_from_env_with_all_vars(self, monkeypatch):
        """Should load all config from environment variables."""
        monkeypatch.setenv("AGENT_ID", "env-agent")
        monkeypatch.setenv("AGENT_PASSKEY", "env-passkey")
        monkeypatch.setenv("POLLING_INTERVAL", "15")
        monkeypatch.setenv("CLI_COMMAND", "gemini")
        monkeypatch.setenv("CLI_ARGS", "--verbose --no-confirm")
        monkeypatch.setenv("WORKING_DIRECTORY", "/home/user")
        monkeypatch.setenv("LOG_DIRECTORY", "/var/log")
        monkeypatch.setenv("MCP_SOCKET_PATH", "/tmp/mcp.sock")

        config = RunnerConfig.from_env()

        assert config.polling_interval == 15
        assert config.cli_command == "gemini"
        assert config.cli_args == ["--verbose", "--no-confirm"]
        assert config.working_directory == "/home/user"
        assert config.log_directory == "/var/log"
        assert config.mcp_socket_path == "/tmp/mcp.sock"

    def test_from_env_missing_agent_id(self, monkeypatch):
        """Should raise error when AGENT_ID is missing."""
        monkeypatch.delenv("AGENT_ID", raising=False)
        monkeypatch.setenv("AGENT_PASSKEY", "passkey")

        with pytest.raises(ValueError, match="AGENT_ID environment variable is required"):
            RunnerConfig.from_env()

    def test_from_env_missing_passkey(self, monkeypatch):
        """Should raise error when AGENT_PASSKEY is missing."""
        monkeypatch.setenv("AGENT_ID", "agent")
        monkeypatch.delenv("AGENT_PASSKEY", raising=False)

        with pytest.raises(ValueError, match="AGENT_PASSKEY environment variable is required"):
            RunnerConfig.from_env()


class TestRunnerConfigFromYaml:
    """Tests for RunnerConfig.from_yaml()."""

    def test_from_yaml(self, temp_yaml_config):
        """Should load config from YAML file."""
        config = RunnerConfig.from_yaml(temp_yaml_config)

        assert config.agent_id == "yaml-agent"
        assert config.passkey == "yaml-passkey"
        assert config.polling_interval == 10
        assert config.cli_command == "gemini"
        assert config.cli_args == ["--verbose", "--no-confirm"]
        assert config.working_directory == "/home/user/projects"
        assert config.log_directory == "/var/log/aiagent"

    def test_from_yaml_minimal(self, tmp_path):
        """Should load minimal YAML config."""
        config_file = tmp_path / "minimal.yaml"
        config_file.write_text("""
agent_id: minimal-agent
passkey: minimal-passkey
""")

        config = RunnerConfig.from_yaml(config_file)

        assert config.agent_id == "minimal-agent"
        assert config.passkey == "minimal-passkey"
        assert config.polling_interval == 5  # default
        assert config.cli_command == "claude"  # default

    def test_from_yaml_cli_args_as_list(self, tmp_path):
        """Should handle cli_args as list in YAML."""
        config_file = tmp_path / "list_args.yaml"
        config_file.write_text("""
agent_id: agent
passkey: passkey
cli_args:
  - --verbose
  - --no-confirm
""")

        config = RunnerConfig.from_yaml(config_file)

        assert config.cli_args == ["--verbose", "--no-confirm"]
