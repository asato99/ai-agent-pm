"""Coordinator lock management for preventing multiple instances.

This module provides cross-platform file locking to ensure only one
Coordinator instance runs per configuration file at a time.
"""

import hashlib
import os
import socket
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

from filelock import FileLock, Timeout


def get_runtime_dir() -> Path:
    """Get platform-appropriate runtime directory for lock files.

    Returns:
        Path to runtime directory, created if necessary.

    Platform behavior:
        - Linux: $XDG_RUNTIME_DIR/aiagent-runner or /tmp/aiagent-runner-{uid}
        - macOS: /tmp/aiagent-runner-{uid}
        - Windows: %LOCALAPPDATA%\\aiagent-runner
    """
    if sys.platform == "win32":
        # Windows: Use LOCALAPPDATA
        base = os.environ.get("LOCALAPPDATA")
        if not base:
            base = os.path.expanduser("~")
        return Path(base) / "aiagent-runner"
    else:
        # Unix-like: Prefer XDG_RUNTIME_DIR, fallback to /tmp with user isolation
        xdg_runtime = os.environ.get("XDG_RUNTIME_DIR")
        if xdg_runtime:
            return Path(xdg_runtime) / "aiagent-runner"
        # Fallback: /tmp with user ID for multi-user isolation
        return Path(f"/tmp/aiagent-runner-{os.getuid()}")


class CoordinatorLockError(Exception):
    """Base exception for coordinator lock errors."""
    pass


class CoordinatorAlreadyRunningError(CoordinatorLockError):
    """Raised when another Coordinator instance is already running."""
    pass


class CoordinatorLock:
    """Cross-platform lock to prevent multiple Coordinator instances.

    Uses file-based locking that works on Windows, macOS, and Linux.
    The lock is automatically released when the process terminates,
    even on abnormal termination (crash, SIGKILL, etc.).

    Each configuration file gets its own lock, allowing multiple
    Coordinators with different configurations to run simultaneously.

    Args:
        config_path: Path to coordinator config file. Used to generate
                     a unique lock file name.
        lock_dir: Optional override for lock file directory. If not
                  specified, uses platform-appropriate default.

    Example:
        >>> lock = CoordinatorLock("/path/to/config.yaml")
        >>> try:
        ...     lock.acquire()
        ...     # Run coordinator
        ... finally:
        ...     lock.release()

        # Or using context manager:
        >>> with CoordinatorLock("/path/to/config.yaml") as lock:
        ...     # Run coordinator
    """

    def __init__(
        self,
        config_path: str,
        lock_dir: Optional[Path] = None
    ):
        self._config_path = config_path
        self._lock_dir = lock_dir or get_runtime_dir()
        self._lock: Optional[FileLock] = None
        self._info_file: Optional[Path] = None

    @property
    def lock_file_path(self) -> Path:
        """Generate unique lock file path based on config path.

        Uses SHA-256 hash of the absolute config path to generate
        a unique but deterministic lock file name.
        """
        abs_path = os.path.abspath(self._config_path)
        config_hash = hashlib.sha256(abs_path.encode()).hexdigest()[:12]
        return self._lock_dir / f"coordinator-{config_hash}.lock"

    def acquire(self, timeout: float = 0) -> None:
        """Acquire the coordinator lock.

        Args:
            timeout: Seconds to wait for lock acquisition.
                     0 means non-blocking (fail immediately if locked).
                     -1 means wait indefinitely.

        Raises:
            CoordinatorAlreadyRunningError: If another Coordinator instance
                is already running with the same configuration.
            CoordinatorLockError: If lock cannot be acquired for other reasons.
        """
        # Ensure lock directory exists
        self._lock_dir.mkdir(parents=True, exist_ok=True)

        lock_file = self.lock_file_path
        self._lock = FileLock(lock_file)
        self._info_file = lock_file.with_suffix(".info")

        try:
            self._lock.acquire(timeout=timeout)
        except Timeout:
            # Read existing lock info for better error message
            info = self._read_lock_info()
            raise CoordinatorAlreadyRunningError(
                f"Another Coordinator instance is already running.\n"
                f"  Lock file: {lock_file}\n"
                f"  {info}\n"
                f"If the previous instance crashed, the lock should have been "
                f"automatically released. If this error persists, manually remove "
                f"the lock file."
            )

        # Write lock info for debugging and diagnostics
        self._write_lock_info()

    def release(self) -> None:
        """Release the coordinator lock and clean up.

        Safe to call multiple times. Removes both lock file and info file
        on clean shutdown.
        """
        if self._lock is None:
            return

        try:
            self._lock.release()
        except Exception:
            pass  # Ignore errors during release

        # Clean up lock and info files on normal shutdown
        for file_path in [self.lock_file_path, self._info_file]:
            if file_path and file_path.exists():
                try:
                    file_path.unlink()
                except OSError:
                    pass  # May fail on Windows if still locked

        self._lock = None
        self._info_file = None

    def _write_lock_info(self) -> None:
        """Write diagnostic info to companion .info file."""
        if self._info_file is None:
            return

        try:
            self._info_file.write_text(
                f"pid: {os.getpid()}\n"
                f"hostname: {socket.gethostname()}\n"
                f"started: {datetime.now().isoformat()}\n"
                f"config: {self._config_path}\n"
            )
        except OSError:
            pass  # Non-critical, ignore errors

    def _read_lock_info(self) -> str:
        """Read existing lock info for error messages."""
        if self._info_file and self._info_file.exists():
            try:
                return self._info_file.read_text().strip()
            except OSError:
                pass
        return "(no lock info available)"

    @property
    def is_locked(self) -> bool:
        """Check if the lock is currently held by this instance."""
        return self._lock is not None and self._lock.is_locked

    def __enter__(self) -> "CoordinatorLock":
        """Context manager entry - acquires lock."""
        self.acquire()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        """Context manager exit - releases lock."""
        self.release()

    def __repr__(self) -> str:
        status = "locked" if self.is_locked else "unlocked"
        return f"CoordinatorLock({self._config_path!r}, {status})"
