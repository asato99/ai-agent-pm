# src/aiagent_runner/config.py
# Runner configuration management
# Reference: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-5

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import yaml


@dataclass
class RunnerConfig:
    """Runner configuration.

    Can be loaded from environment variables or YAML file.

    Phase 4: project_id is required for (agent_id, project_id) management unit.
    """
    agent_id: str
    passkey: str
    project_id: str  # Phase 4: Required for authenticate
    polling_interval: int = 5
    cli_command: str = "claude"
    cli_args: list[str] = field(default_factory=lambda: ["--dangerously-skip-permissions"])
    working_directory: Optional[str] = None
    log_directory: Optional[str] = None
    mcp_socket_path: Optional[str] = None

    def __post_init__(self):
        """Validate configuration after initialization."""
        if self.polling_interval <= 0:
            raise ValueError("polling_interval must be positive")
        if not self.agent_id:
            raise ValueError("agent_id is required")
        if not self.passkey:
            raise ValueError("passkey is required")
        if not self.project_id:
            raise ValueError("project_id is required (Phase 4)")

    @classmethod
    def from_env(cls) -> "RunnerConfig":
        """Load configuration from environment variables.

        Environment variables:
            AGENT_ID: Agent ID (required)
            AGENT_PASSKEY: Agent passkey (required)
            PROJECT_ID: Project ID (required, Phase 4)
            POLLING_INTERVAL: Polling interval in seconds (default: 5)
            CLI_COMMAND: CLI command to use (default: claude)
            WORKING_DIRECTORY: Default working directory
            LOG_DIRECTORY: Directory for log files
            MCP_SOCKET_PATH: Path to MCP socket
        """
        agent_id = os.environ.get("AGENT_ID")
        passkey = os.environ.get("AGENT_PASSKEY")
        project_id = os.environ.get("PROJECT_ID")

        if not agent_id:
            raise ValueError("AGENT_ID environment variable is required")
        if not passkey:
            raise ValueError("AGENT_PASSKEY environment variable is required")
        if not project_id:
            raise ValueError("PROJECT_ID environment variable is required (Phase 4)")

        cli_args_str = os.environ.get("CLI_ARGS", "--dangerously-skip-permissions")
        cli_args = cli_args_str.split() if cli_args_str else ["--dangerously-skip-permissions"]

        return cls(
            agent_id=agent_id,
            passkey=passkey,
            project_id=project_id,
            polling_interval=int(os.environ.get("POLLING_INTERVAL", "5")),
            cli_command=os.environ.get("CLI_COMMAND", "claude"),
            cli_args=cli_args,
            working_directory=os.environ.get("WORKING_DIRECTORY"),
            log_directory=os.environ.get("LOG_DIRECTORY"),
            mcp_socket_path=os.environ.get("MCP_SOCKET_PATH"),
        )

    @classmethod
    def from_yaml(cls, path: Path) -> "RunnerConfig":
        """Load configuration from YAML file.

        Args:
            path: Path to YAML configuration file

        Returns:
            RunnerConfig instance
        """
        with open(path) as f:
            data = yaml.safe_load(f)

        # Handle cli_args which might be a string in YAML
        if "cli_args" in data and isinstance(data["cli_args"], str):
            data["cli_args"] = data["cli_args"].split()

        return cls(**data)
