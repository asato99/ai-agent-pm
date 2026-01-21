# src/aiagent_runner/platform.py
# Cross-platform path utilities for aiagent-runner
# Handles OS-specific default paths for data, logs, and sockets

import os
import sys
from pathlib import Path
from typing import Optional

# Application name for directory naming
APP_NAME = "aiagent-runner"
APP_NAME_MACOS = "AIAgentPM"  # macOS uses different naming convention


def get_platform() -> str:
    """Get current platform identifier.

    Returns:
        'windows', 'macos', or 'linux'
    """
    if sys.platform == "win32":
        return "windows"
    elif sys.platform == "darwin":
        return "macos"
    else:
        return "linux"


def get_data_directory() -> Path:
    """Get platform-specific application data directory.

    Returns:
        - Windows: %LOCALAPPDATA%\\aiagent-runner
        - macOS: ~/Library/Application Support/AIAgentPM
        - Linux: ~/.local/share/aiagent-runner
    """
    platform = get_platform()

    if platform == "windows":
        # Use LOCALAPPDATA on Windows
        local_app_data = os.environ.get("LOCALAPPDATA")
        if local_app_data:
            return Path(local_app_data) / APP_NAME
        # Fallback to user home
        return Path.home() / "AppData" / "Local" / APP_NAME

    elif platform == "macos":
        return Path.home() / "Library" / "Application Support" / APP_NAME_MACOS

    else:  # Linux and others
        # Follow XDG Base Directory Specification
        xdg_data = os.environ.get("XDG_DATA_HOME")
        if xdg_data:
            return Path(xdg_data) / APP_NAME
        return Path.home() / ".local" / "share" / APP_NAME


def get_log_directory() -> Path:
    """Get platform-specific log directory.

    Returns:
        - Windows: %LOCALAPPDATA%\\aiagent-runner\\logs
        - macOS: ~/Library/Logs/AIAgentPM
        - Linux: ~/.local/share/aiagent-runner/logs
    """
    platform = get_platform()

    if platform == "windows":
        return get_data_directory() / "logs"

    elif platform == "macos":
        return Path.home() / "Library" / "Logs" / APP_NAME_MACOS

    else:  # Linux
        return get_data_directory() / "logs"


def get_default_socket_path() -> str:
    """Get platform-specific default Unix socket path.

    Note: Unix sockets are not natively supported on Windows.
    For Windows, HTTP transport should be used instead.

    Returns:
        - macOS/Linux: Path to Unix socket
        - Windows: Empty string (use HTTP transport)
    """
    platform = get_platform()

    if platform == "windows":
        # Windows doesn't support Unix sockets in the same way
        # Return empty to indicate HTTP transport should be used
        return ""

    elif platform == "macos":
        return str(get_data_directory() / "mcp.sock")

    else:  # Linux
        # Use XDG_RUNTIME_DIR if available (more appropriate for sockets)
        xdg_runtime = os.environ.get("XDG_RUNTIME_DIR")
        if xdg_runtime:
            return str(Path(xdg_runtime) / APP_NAME / "mcp.sock")
        return str(get_data_directory() / "mcp.sock")


def get_lock_directory() -> Path:
    """Get platform-specific directory for lock files.

    Returns:
        - Windows: %LOCALAPPDATA%\\aiagent-runner
        - macOS: ~/Library/Application Support/AIAgentPM
        - Linux: ~/.local/share/aiagent-runner or XDG_RUNTIME_DIR
    """
    platform = get_platform()

    if platform == "linux":
        # Prefer XDG_RUNTIME_DIR for lock files on Linux
        xdg_runtime = os.environ.get("XDG_RUNTIME_DIR")
        if xdg_runtime:
            return Path(xdg_runtime) / APP_NAME

    return get_data_directory()


def ensure_directory(path: Path) -> Path:
    """Ensure directory exists, creating it if necessary.

    Args:
        path: Directory path to ensure exists

    Returns:
        The same path (for chaining)
    """
    path.mkdir(parents=True, exist_ok=True)
    return path


def is_windows() -> bool:
    """Check if running on Windows."""
    return get_platform() == "windows"


def is_macos() -> bool:
    """Check if running on macOS."""
    return get_platform() == "macos"


def is_linux() -> bool:
    """Check if running on Linux."""
    return get_platform() == "linux"
