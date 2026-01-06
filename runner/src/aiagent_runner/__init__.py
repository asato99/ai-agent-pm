# aiagent_runner - Runner for AI Agent PM
# Executes tasks via MCP protocol and CLI tools (claude, gemini, etc.)

__version__ = "0.1.0"

from aiagent_runner.config import RunnerConfig
from aiagent_runner.runner import Runner, run, run_async

__all__ = ["RunnerConfig", "Runner", "run", "run_async", "__version__"]
