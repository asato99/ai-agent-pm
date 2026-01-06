# src/aiagent_runner/__main__.py
# Entry point for AI Agent PM Runner
# Reference: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-5

import argparse
import logging
import sys
from pathlib import Path

from aiagent_runner.config import RunnerConfig
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
        description="Runner for AI Agent PM - executes tasks via MCP and CLI"
    )

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
    parser.add_argument(
        "--agent-id",
        help="Agent ID (overrides config/env)"
    )
    parser.add_argument(
        "--passkey",
        help="Agent passkey (overrides config/env)"
    )
    parser.add_argument(
        "--polling-interval",
        type=int,
        help="Polling interval in seconds (default: 5)"
    )
    parser.add_argument(
        "--cli-command",
        help="CLI command to use (default: claude)"
    )
    parser.add_argument(
        "--working-directory",
        type=Path,
        help="Working directory for CLI execution"
    )
    parser.add_argument(
        "--log-directory",
        type=Path,
        help="Directory for execution logs"
    )

    return parser.parse_args()


def load_config(args: argparse.Namespace) -> RunnerConfig:
    """Load configuration from file, env, and CLI args.

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
            if args.agent_id and args.passkey:
                config = RunnerConfig(
                    agent_id=args.agent_id,
                    passkey=args.passkey
                )
            else:
                raise e

    # Override with CLI arguments
    if args.agent_id:
        config.agent_id = args.agent_id
    if args.passkey:
        config.passkey = args.passkey
    if args.polling_interval:
        config.polling_interval = args.polling_interval
    if args.cli_command:
        config.cli_command = args.cli_command
    if args.working_directory:
        config.working_directory = str(args.working_directory)
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

    try:
        config = load_config(args)
    except ValueError as e:
        logger.error(f"Configuration error: {e}")
        print(f"Error: {e}", file=sys.stderr)
        print(
            "\nProvide configuration via:\n"
            "  1. YAML config file (-c/--config)\n"
            "  2. Environment variables (AGENT_ID, AGENT_PASSKEY)\n"
            "  3. CLI arguments (--agent-id, --passkey)",
            file=sys.stderr
        )
        return 1

    logger.info(f"Starting runner for agent: {config.agent_id}")
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
