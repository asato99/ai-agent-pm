# aiagent_runner - Runner for AI Agent PM
# Executes tasks via MCP protocol and CLI tools (claude, gemini, etc.)

__version__ = "0.1.7"

from aiagent_runner.config import RunnerConfig
from aiagent_runner.runner import Runner, run, run_async
from aiagent_runner.platform import (
    get_platform,
    get_data_directory,
    get_log_directory,
    get_default_socket_path,
    get_lock_directory,
    is_windows,
    is_macos,
    is_linux,
)

__all__ = [
    "RunnerConfig",
    "Runner",
    "run",
    "run_async",
    "__version__",
    # Platform utilities
    "get_platform",
    "get_data_directory",
    "get_log_directory",
    "get_default_socket_path",
    "get_lock_directory",
    "is_windows",
    "is_macos",
    "is_linux",
]
