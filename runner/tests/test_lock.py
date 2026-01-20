"""Tests for coordinator lock management."""

import os
import tempfile
from pathlib import Path
from unittest.mock import patch

import pytest

from aiagent_runner.lock import (
    CoordinatorAlreadyRunningError,
    CoordinatorLock,
    CoordinatorLockError,
    get_runtime_dir,
)


class TestGetRuntimeDir:
    """Tests for get_runtime_dir function."""

    def test_runtime_dir_darwin(self):
        """Test runtime directory on macOS (darwin)."""
        with patch("sys.platform", "darwin"), \
             patch.dict(os.environ, {}, clear=True), \
             patch("os.getuid", return_value=501):
            result = get_runtime_dir()
            assert result == Path("/tmp/aiagent-runner-501")

    def test_runtime_dir_linux_with_xdg(self):
        """Test runtime directory on Linux with XDG_RUNTIME_DIR."""
        with patch("sys.platform", "linux"), \
             patch.dict(os.environ, {"XDG_RUNTIME_DIR": "/run/user/1000"}):
            result = get_runtime_dir()
            assert result == Path("/run/user/1000/aiagent-runner")

    def test_runtime_dir_linux_without_xdg(self):
        """Test runtime directory on Linux without XDG_RUNTIME_DIR."""
        with patch("sys.platform", "linux"), \
             patch.dict(os.environ, {}, clear=True), \
             patch("os.getuid", return_value=1000):
            result = get_runtime_dir()
            assert result == Path("/tmp/aiagent-runner-1000")

    def test_runtime_dir_windows(self):
        """Test runtime directory on Windows."""
        with patch("sys.platform", "win32"), \
             patch.dict(os.environ, {"LOCALAPPDATA": "C:\\Users\\Test\\AppData\\Local"}):
            result = get_runtime_dir()
            assert result == Path("C:\\Users\\Test\\AppData\\Local") / "aiagent-runner"

    def test_runtime_dir_windows_fallback(self):
        """Test runtime directory on Windows without LOCALAPPDATA."""
        with patch("sys.platform", "win32"), \
             patch.dict(os.environ, {}, clear=True), \
             patch("os.path.expanduser", return_value="/home/test"):
            result = get_runtime_dir()
            assert result == Path("/home/test/aiagent-runner")


class TestCoordinatorLock:
    """Tests for CoordinatorLock class."""

    def test_lock_file_path_deterministic(self):
        """Test that lock file path is deterministic for same config."""
        lock1 = CoordinatorLock("/path/to/config.yaml")
        lock2 = CoordinatorLock("/path/to/config.yaml")
        assert lock1.lock_file_path == lock2.lock_file_path

    def test_lock_file_path_different_configs(self):
        """Test that different configs get different lock files."""
        lock1 = CoordinatorLock("/path/to/config1.yaml")
        lock2 = CoordinatorLock("/path/to/config2.yaml")
        assert lock1.lock_file_path != lock2.lock_file_path

    def test_acquire_and_release(self):
        """Test basic acquire and release."""
        with tempfile.TemporaryDirectory() as tmpdir:
            lock = CoordinatorLock(
                "/path/to/config.yaml",
                lock_dir=Path(tmpdir)
            )
            assert not lock.is_locked

            lock.acquire()
            assert lock.is_locked
            assert lock.lock_file_path.exists()

            lock.release()
            assert not lock.is_locked
            # Lock files cleaned up on normal release
            assert not lock.lock_file_path.exists()

    def test_double_acquire_fails(self):
        """Test that second acquire fails when lock is held."""
        with tempfile.TemporaryDirectory() as tmpdir:
            lock1 = CoordinatorLock(
                "/path/to/config.yaml",
                lock_dir=Path(tmpdir)
            )
            lock2 = CoordinatorLock(
                "/path/to/config.yaml",
                lock_dir=Path(tmpdir)
            )

            lock1.acquire()
            try:
                with pytest.raises(CoordinatorAlreadyRunningError):
                    lock2.acquire()
            finally:
                lock1.release()

    def test_different_configs_no_conflict(self):
        """Test that different configs don't conflict."""
        with tempfile.TemporaryDirectory() as tmpdir:
            lock1 = CoordinatorLock(
                "/path/to/config1.yaml",
                lock_dir=Path(tmpdir)
            )
            lock2 = CoordinatorLock(
                "/path/to/config2.yaml",
                lock_dir=Path(tmpdir)
            )

            lock1.acquire()
            try:
                # Should not raise - different config paths
                lock2.acquire()
                lock2.release()
            finally:
                lock1.release()

    def test_context_manager(self):
        """Test context manager usage."""
        with tempfile.TemporaryDirectory() as tmpdir:
            lock = CoordinatorLock(
                "/path/to/config.yaml",
                lock_dir=Path(tmpdir)
            )

            with lock:
                assert lock.is_locked
                assert lock.lock_file_path.exists()

            assert not lock.is_locked

    def test_context_manager_cleanup_on_exception(self):
        """Test that lock is released even on exception."""
        with tempfile.TemporaryDirectory() as tmpdir:
            lock = CoordinatorLock(
                "/path/to/config.yaml",
                lock_dir=Path(tmpdir)
            )

            try:
                with lock:
                    assert lock.is_locked
                    raise ValueError("Test exception")
            except ValueError:
                pass

            assert not lock.is_locked

    def test_info_file_created(self):
        """Test that .info file is created with diagnostics."""
        with tempfile.TemporaryDirectory() as tmpdir:
            lock = CoordinatorLock(
                "/path/to/config.yaml",
                lock_dir=Path(tmpdir)
            )

            lock.acquire()
            try:
                info_file = lock.lock_file_path.with_suffix(".info")
                assert info_file.exists()

                content = info_file.read_text()
                assert "pid:" in content
                assert "hostname:" in content
                assert "started:" in content
                assert "config:" in content
            finally:
                lock.release()

    def test_release_idempotent(self):
        """Test that release can be called multiple times safely."""
        with tempfile.TemporaryDirectory() as tmpdir:
            lock = CoordinatorLock(
                "/path/to/config.yaml",
                lock_dir=Path(tmpdir)
            )

            lock.acquire()
            lock.release()
            lock.release()  # Should not raise
            lock.release()  # Should not raise

    def test_repr(self):
        """Test string representation."""
        lock = CoordinatorLock("/path/to/config.yaml")
        assert "config.yaml" in repr(lock)
        assert "unlocked" in repr(lock)


class TestCoordinatorLockExceptions:
    """Tests for lock exception classes."""

    def test_coordinator_lock_error_inheritance(self):
        """Test that CoordinatorLockError is an Exception."""
        assert issubclass(CoordinatorLockError, Exception)

    def test_coordinator_already_running_error_inheritance(self):
        """Test that CoordinatorAlreadyRunningError inherits from CoordinatorLockError."""
        assert issubclass(CoordinatorAlreadyRunningError, CoordinatorLockError)
