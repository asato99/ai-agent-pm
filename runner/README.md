# AI Agent PM Runner

Runner for AI Agent PM - executes tasks via MCP protocol and CLI tools.

## Overview

The Runner is a Python application that:
1. Authenticates with the AI Agent PM MCP server
2. Polls for pending tasks assigned to the agent
3. Executes tasks using CLI tools (claude, gemini, etc.)
4. Reports execution results back to the server

## Installation

```bash
pip install -e .
```

## Configuration

Configuration can be provided via:

### Environment Variables

```bash
export AGENT_ID="your-agent-id"
export AGENT_PASSKEY="your-passkey"
export POLLING_INTERVAL=5
export CLI_COMMAND=claude
```

### YAML File

```yaml
agent_id: your-agent-id
passkey: your-passkey
polling_interval: 5
cli_command: claude
cli_args: --dangerously-skip-permissions
```

### CLI Arguments

```bash
aiagent-runner --agent-id your-agent-id --passkey your-passkey
```

## Usage

```bash
# Using environment variables
aiagent-runner

# Using config file
aiagent-runner -c config.yaml

# With CLI arguments
aiagent-runner --agent-id agent-001 --passkey secret --verbose
```

## Development

```bash
# Install with dev dependencies
pip install -e ".[dev]"

# Run tests
pytest

# Run tests with coverage
pytest --cov=aiagent_runner
```

## Architecture

- `config.py` - Configuration management
- `mcp_client.py` - MCP server communication
- `prompt_builder.py` - Prompt construction for CLI
- `executor.py` - CLI execution
- `runner.py` - Main polling loop
- `__main__.py` - Entry point

## Reference

See `docs/plan/PHASE3_PULL_ARCHITECTURE.md` for the full architecture design.
