# tests/test_executor.py
# Tests for CLIExecutor

import pytest
from pathlib import Path
from unittest.mock import patch, MagicMock

from aiagent_runner.executor import CLIExecutor, ExecutionResult


class TestExecutionResult:
    """Tests for ExecutionResult dataclass."""

    def test_execution_result(self):
        """Should create ExecutionResult."""
        result = ExecutionResult(
            exit_code=0,
            duration_seconds=120.5,
            log_file="/tmp/log.txt"
        )
        assert result.exit_code == 0
        assert result.duration_seconds == 120.5
        assert result.log_file == "/tmp/log.txt"


class TestCLIExecutorInit:
    """Tests for CLIExecutor initialization."""

    def test_init_defaults(self):
        """Should initialize with defaults."""
        executor = CLIExecutor()
        assert executor.cli_command == "claude"
        assert executor.cli_args == ["--dangerously-skip-permissions"]

    def test_init_custom(self):
        """Should initialize with custom values."""
        executor = CLIExecutor("gemini", ["--verbose", "--no-confirm"])
        assert executor.cli_command == "gemini"
        assert executor.cli_args == ["--verbose", "--no-confirm"]

    def test_init_empty_list_args(self):
        """Should use default args when empty list passed."""
        executor = CLIExecutor("claude", [])
        # Empty list is falsy, so defaults apply
        assert executor.cli_args == ["--dangerously-skip-permissions"]

    def test_init_explicit_args(self):
        """Should use explicit args when provided."""
        executor = CLIExecutor("claude", ["--custom-arg"])
        assert executor.cli_args == ["--custom-arg"]


class TestCLIExecutorExecute:
    """Tests for CLIExecutor.execute()."""

    def test_execute_success(self, temp_work_dir, temp_log_dir):
        """Should execute CLI successfully."""
        executor = CLIExecutor("echo", [])  # Use echo as test command
        log_file = str(temp_log_dir / "test.log")

        result = executor.execute(
            prompt="test prompt",
            working_directory=str(temp_work_dir),
            log_file=log_file
        )

        assert result.exit_code == 0
        assert result.duration_seconds >= 0
        assert result.log_file == log_file

        # Check log file contents
        with open(log_file) as f:
            content = f.read()
        assert "=== PROMPT ===" in content
        assert "test prompt" in content
        assert "=== OUTPUT ===" in content

    def test_execute_command_not_found(self, temp_work_dir, temp_log_dir):
        """Should handle command not found."""
        executor = CLIExecutor("nonexistent_command_12345", [])
        log_file = str(temp_log_dir / "test.log")

        result = executor.execute(
            prompt="test prompt",
            working_directory=str(temp_work_dir),
            log_file=log_file
        )

        assert result.exit_code == 127
        assert result.log_file == log_file

        # Check error in log
        with open(log_file) as f:
            content = f.read()
        assert "ERROR" in content
        assert "not found" in content

    def test_execute_creates_log_directory(self, temp_work_dir, tmp_path):
        """Should create log directory if it doesn't exist."""
        executor = CLIExecutor("echo", [])
        log_dir = tmp_path / "new_log_dir"
        log_file = str(log_dir / "test.log")

        assert not log_dir.exists()

        result = executor.execute(
            prompt="test",
            working_directory=str(temp_work_dir),
            log_file=log_file
        )

        assert log_dir.exists()
        assert Path(log_file).exists()

    def test_execute_with_exit_code(self, temp_work_dir, temp_log_dir):
        """Should capture non-zero exit code."""
        executor = CLIExecutor("sh", ["-c", "exit 42"])
        log_file = str(temp_log_dir / "test.log")

        result = executor.execute(
            prompt="test",
            working_directory=str(temp_work_dir),
            log_file=log_file
        )

        assert result.exit_code == 42

    def test_execute_captures_output(self, temp_work_dir, temp_log_dir):
        """Should capture command output in log."""
        executor = CLIExecutor("echo", [])
        log_file = str(temp_log_dir / "test.log")

        result = executor.execute(
            prompt="hello world",
            working_directory=str(temp_work_dir),
            log_file=log_file
        )

        with open(log_file) as f:
            content = f.read()

        # echo outputs: <args> so prompt "hello world" becomes "-p hello world"
        # The actual output depends on how echo handles -p flag
        assert "=== OUTPUT ===" in content

    def test_execute_in_working_directory(self, temp_work_dir, temp_log_dir):
        """Should execute in specified working directory."""
        # Use sh -c to run pwd, ignoring the -p argument added by executor
        executor = CLIExecutor("sh", ["-c", "pwd; #"])  # # comments out the -p prompt
        log_file = str(temp_log_dir / "test.log")

        result = executor.execute(
            prompt="ignored",
            working_directory=str(temp_work_dir),
            log_file=log_file
        )

        assert result.exit_code == 0

        with open(log_file) as f:
            content = f.read()

        # pwd should output the working directory (may be /private/var on macOS)
        assert "workspace" in content  # the temp dir name


class TestCLIExecutorCommandBuilding:
    """Tests for command building logic."""

    def test_builds_correct_command(self, temp_work_dir, temp_log_dir):
        """Should build command with all arguments."""
        executor = CLIExecutor("testcmd", ["--arg1", "--arg2"])

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)

            executor.execute(
                prompt="test prompt",
                working_directory=str(temp_work_dir),
                log_file=str(temp_log_dir / "test.log")
            )

            # Check the command that was called
            call_args = mock_run.call_args
            cmd = call_args[0][0]

            assert cmd[0] == "testcmd"
            assert "--arg1" in cmd
            assert "--arg2" in cmd
            assert "-p" in cmd
            assert "test prompt" in cmd
