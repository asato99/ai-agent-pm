# src/aiagent_runner/executor.py
# CLI executor for running AI assistants
# Reference: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-5

import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


@dataclass
class ExecutionResult:
    """Result of CLI execution."""
    exit_code: int
    duration_seconds: float
    log_file: str


class CLIExecutor:
    """Executes CLI tools (claude, gemini, etc.) with prompts."""

    def __init__(
        self,
        cli_command: str = "claude",
        cli_args: Optional[list[str]] = None
    ):
        """Initialize CLI executor.

        Args:
            cli_command: CLI command to run (claude, gemini, etc.)
            cli_args: Additional arguments for the CLI
        """
        self.cli_command = cli_command
        self.cli_args = cli_args or ["--dangerously-skip-permissions"]

    def execute(
        self,
        prompt: str,
        working_directory: str,
        log_file: str
    ) -> ExecutionResult:
        """Execute CLI with the given prompt.

        Args:
            prompt: Prompt string to pass to CLI
            working_directory: Directory to run CLI in
            log_file: Path to log file for output

        Returns:
            ExecutionResult with exit code, duration, and log path
        """
        # Ensure log directory exists
        Path(log_file).parent.mkdir(parents=True, exist_ok=True)

        # Build command
        cmd = [self.cli_command] + self.cli_args + ["-p", prompt]

        start_time = time.time()

        try:
            with open(log_file, "w") as log:
                # Write prompt to log for reference
                log.write(f"=== PROMPT ===\n{prompt}\n\n=== OUTPUT ===\n")
                log.flush()

                result = subprocess.run(
                    cmd,
                    cwd=working_directory,
                    stdout=log,
                    stderr=subprocess.STDOUT,
                    text=True
                )
        except FileNotFoundError:
            # CLI command not found
            with open(log_file, "a") as log:
                log.write(f"\nERROR: Command '{self.cli_command}' not found\n")
            return ExecutionResult(
                exit_code=127,
                duration_seconds=time.time() - start_time,
                log_file=log_file
            )
        except Exception as e:
            # Other execution error
            with open(log_file, "a") as log:
                log.write(f"\nERROR: {e}\n")
            return ExecutionResult(
                exit_code=1,
                duration_seconds=time.time() - start_time,
                log_file=log_file
            )

        end_time = time.time()

        return ExecutionResult(
            exit_code=result.returncode,
            duration_seconds=end_time - start_time,
            log_file=log_file
        )
