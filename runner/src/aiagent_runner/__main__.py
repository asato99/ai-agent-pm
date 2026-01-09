# src/aiagent_runner/__main__.py
# Entry point for AI Agent PM Runner/Coordinator
# Reference: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-5 (legacy Runner)
# Reference: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md (Coordinator)

import argparse
import logging
import sys
from pathlib import Path

from aiagent_runner.config import RunnerConfig
from aiagent_runner.coordinator import run_coordinator
from aiagent_runner.coordinator_config import CoordinatorConfig
from aiagent_runner.runner import run


def setup_logging(verbose: bool = False) -> None:
    """Configure logging.

    Args:
        verbose: If True, enable debug logging
    """
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )


def parse_args() -> argparse.Namespace:
    """Parse command line arguments.

    Returns:
        Parsed arguments
    """
    parser = argparse.ArgumentParser(
        prog="aiagent-runner",
        description="Runner/Coordinator for AI Agent PM - executes tasks via MCP and CLI"
    )

    # Mode selection
    parser.add_argument(
        "--coordinator",
        action="store_true",
        help="Run in Coordinator mode (Phase 4: single orchestrator for all agents)"
    )

    # Common arguments
    parser.add_argument(
        "-c", "--config",
        type=Path,
        help="Path to YAML configuration file"
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Enable verbose (debug) logging"
    )

    # Legacy Runner arguments (deprecated, use Coordinator mode instead)
    parser.add_argument(
        "--agent-id",
        help="[Legacy Runner] Agent ID (overrides config/env)"
    )
    parser.add_argument(
        "--passkey",
        help="[Legacy Runner] Agent passkey (overrides config/env)"
    )
    parser.add_argument(
        "--project-id",
        help="[Legacy Runner] Project ID (Phase 4 required)"
    )
    parser.add_argument(
        "--polling-interval",
        type=int,
        help="Polling interval in seconds (default: 5 for Runner, 10 for Coordinator)"
    )
    parser.add_argument(
        "--cli-command",
        help="[Legacy Runner] CLI command to use (default: claude)"
    )
    parser.add_argument(
        "--working-directory",
        type=Path,
        help="[Legacy Runner] Working directory for CLI execution"
    )
    parser.add_argument(
        "--log-directory",
        type=Path,
        help="Directory for execution logs"
    )

    return parser.parse_args()


def load_runner_config(args: argparse.Namespace) -> RunnerConfig:
    """Load configuration for legacy Runner mode.

    Priority (highest to lowest):
    1. CLI arguments
    2. Config file
    3. Environment variables

    Args:
        args: Parsed CLI arguments

    Returns:
        RunnerConfig instance
    """
    # Start with config file or environment
    if args.config and args.config.exists():
        config = RunnerConfig.from_yaml(args.config)
    else:
        try:
            config = RunnerConfig.from_env()
        except ValueError as e:
            # If no config file and env vars missing, check CLI args
            if args.agent_id and args.passkey and args.project_id:
                config = RunnerConfig(
                    agent_id=args.agent_id,
                    passkey=args.passkey,
                    project_id=args.project_id
                )
            else:
                raise e

    # Override with CLI arguments
    if args.agent_id:
        config.agent_id = args.agent_id
    if args.passkey:
        config.passkey = args.passkey
    if args.project_id:
        config.project_id = args.project_id
    if args.polling_interval:
        config.polling_interval = args.polling_interval
    if args.cli_command:
        config.cli_command = args.cli_command
    if args.working_directory:
        config.working_directory = str(args.working_directory)
    if args.log_directory:
        config.log_directory = str(args.log_directory)

    return config


def get_default_config_path() -> Path:
    """Get the default configuration file path.

    The default config is located at:
    runner/config/coordinator_default.yaml

    Returns:
        Path to default config file
    """
    # Find the runner package root (where config/ directory is)
    # __file__ is runner/src/aiagent_runner/__main__.py
    # parent = runner/src/aiagent_runner/
    # parent.parent = runner/src/
    # parent.parent.parent = runner/
    runner_root = Path(__file__).parent.parent.parent
    return runner_root / "config" / "coordinator_default.yaml"


def load_coordinator_config(args: argparse.Namespace) -> CoordinatorConfig:
    """Load configuration for Coordinator mode.

    Configuration loading priority:
    1. User-specified config file (-c/--config) - full override
    2. Default config file (runner/config/coordinator_default.yaml)

    Note: When using default config, agents must be configured via
    environment variables or a separate config file.

    Args:
        args: Parsed CLI arguments

    Returns:
        CoordinatorConfig instance
    """
    logger = logging.getLogger(__name__)

    if args.config and args.config.exists():
        # User specified a config file - use it directly
        logger.info(f"Loading config from: {args.config}")
        config = CoordinatorConfig.from_yaml(args.config)
    else:
        # Try to load default config
        default_config_path = get_default_config_path()
        if default_config_path.exists():
            logger.info(f"Loading default config from: {default_config_path}")
            config = CoordinatorConfig.from_yaml(default_config_path)
        else:
            # No config available - use built-in defaults
            logger.warning(
                "No config file found. Using built-in defaults.\n"
                f"Expected default config at: {default_config_path}\n"
                "Note: Agents must be configured to run tasks."
            )
            config = CoordinatorConfig()

    # Override with CLI arguments
    if args.polling_interval:
        config.polling_interval = args.polling_interval
    if args.log_directory:
        config.log_directory = str(args.log_directory)

    return config


def main() -> int:
    """Main entry point.

    Returns:
        Exit code (0 for success)
    """
    args = parse_args()
    setup_logging(args.verbose)

    logger = logging.getLogger(__name__)

    if args.coordinator:
        # Phase 4: Coordinator mode
        logger.info("Running in Coordinator mode (Phase 4)")
        try:
            config = load_coordinator_config(args)
        except ValueError as e:
            logger.error(f"Configuration error: {e}")
            print(f"Error: {e}", file=sys.stderr)
            return 1

        logger.info(f"Configured agents: {list(config.agents.keys())}")
        logger.info(f"Polling interval: {config.polling_interval}s")
        logger.info(f"Max concurrent: {config.max_concurrent}")

        try:
            run_coordinator(config)
        except KeyboardInterrupt:
            logger.info("Coordinator stopped by user")
            return 0
        except Exception as e:
            logger.exception(f"Coordinator failed: {e}")
            return 1
    else:
        # Legacy Runner mode (deprecated)
        logger.warning(
            "Running in legacy Runner mode. "
            "Consider using --coordinator mode for Phase 4 architecture."
        )
        try:
            config = load_runner_config(args)
        except ValueError as e:
            logger.error(f"Configuration error: {e}")
            print(f"Error: {e}", file=sys.stderr)
            print(
                "\nProvide configuration via:\n"
                "  1. YAML config file (-c/--config)\n"
                "  2. Environment variables (AGENT_ID, AGENT_PASSKEY, PROJECT_ID)\n"
                "  3. CLI arguments (--agent-id, --passkey, --project-id)",
                file=sys.stderr
            )
            return 1

        logger.info(f"Starting runner for agent: {config.agent_id}")
        logger.info(f"Project: {config.project_id}")
        logger.info(f"CLI command: {config.cli_command}")
        logger.info(f"Polling interval: {config.polling_interval}s")

        try:
            run(config)
        except KeyboardInterrupt:
            logger.info("Runner stopped by user")
            return 0
        except Exception as e:
            logger.exception(f"Runner failed: {e}")
            return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
