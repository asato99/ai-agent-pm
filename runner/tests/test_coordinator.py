# tests/test_coordinator.py
# Tests for Coordinator log directory functionality

import base64
import io
import os
import zipfile
from pathlib import Path

import pytest

from aiagent_runner.coordinator import Coordinator
from aiagent_runner.coordinator_config import CoordinatorConfig


def create_test_zip_archive(skill_md_content: str, extra_files: dict[str, str] | None = None) -> str:
    """Create a Base64-encoded ZIP archive for testing.

    Args:
        skill_md_content: Content for SKILL.md
        extra_files: Optional dict of {filename: content} for additional files

    Returns:
        Base64-encoded ZIP archive string
    """
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_DEFLATED) as zf:
        zf.writestr('SKILL.md', skill_md_content)
        if extra_files:
            for filename, content in extra_files.items():
                zf.writestr(filename, content)
    return base64.b64encode(buffer.getvalue()).decode('utf-8')


class TestCoordinatorConfig:
    """Tests for CoordinatorConfig multi-device features."""

    def test_config_with_root_agent_id(self):
        """Should accept root_agent_id for multi-device operation."""
        config = CoordinatorConfig(
            agents={},
            mcp_socket_path="/tmp/test.sock",
            root_agent_id="human-frontend-lead",
            polling_interval=5,
            max_concurrent=1
        )
        assert config.root_agent_id == "human-frontend-lead"

    def test_config_without_root_agent_id(self):
        """Should allow root_agent_id to be None (local operation)."""
        config = CoordinatorConfig(
            agents={},
            mcp_socket_path="/tmp/test.sock",
            polling_interval=5,
            max_concurrent=1
        )
        assert config.root_agent_id is None


class TestCoordinatorGetLogDirectory:
    """Tests for Coordinator._get_log_directory()."""

    @pytest.fixture
    def minimal_config(self):
        """Create a minimal CoordinatorConfig for testing."""
        return CoordinatorConfig(
            agents={},
            mcp_socket_path="/tmp/test.sock",
            polling_interval=5,
            max_concurrent=1
        )

    def test_get_log_directory_with_working_dir(self, minimal_config, tmp_path):
        """Should return {working_dir}/.aiagent/logs/{agent_id}/ when working_dir is provided."""
        coordinator = Coordinator(minimal_config)
        working_dir = str(tmp_path / "my-project")
        agent_id = "agt_test123"

        log_dir = coordinator._get_log_directory(working_dir, agent_id)

        expected = Path(working_dir) / ".aiagent" / "logs" / agent_id
        assert log_dir == expected
        assert log_dir.exists()

    def test_get_log_directory_without_working_dir(self, minimal_config):
        """Should return App Support path when working_dir is None."""
        coordinator = Coordinator(minimal_config)
        agent_id = "agt_test456"

        log_dir = coordinator._get_log_directory(None, agent_id)

        expected = (
            Path.home()
            / "Library" / "Application Support" / "AIAgentPM"
            / "agent_logs" / agent_id
        )
        assert log_dir == expected
        assert log_dir.exists()

    def test_get_log_directory_creates_parent_dirs(self, minimal_config, tmp_path):
        """Should create parent directories if they don't exist."""
        coordinator = Coordinator(minimal_config)
        working_dir = str(tmp_path / "new-project" / "deeply" / "nested")
        agent_id = "agt_nested"

        log_dir = coordinator._get_log_directory(working_dir, agent_id)

        assert log_dir.exists()
        assert log_dir.is_dir()

    def test_get_log_directory_with_empty_working_dir(self, minimal_config):
        """Should treat empty string as None (use fallback)."""
        coordinator = Coordinator(minimal_config)
        agent_id = "agt_empty"

        log_dir = coordinator._get_log_directory("", agent_id)

        expected = (
            Path.home()
            / "Library" / "Application Support" / "AIAgentPM"
            / "agent_logs" / agent_id
        )
        assert log_dir == expected


class TestCoordinatorWriteSkills:
    """Tests for Coordinator._write_skills() - Phase 6 integration tests."""

    @pytest.fixture
    def coordinator(self):
        """Create a Coordinator instance for testing."""
        config = CoordinatorConfig(
            agents={},
            mcp_socket_path="/tmp/test.sock",
            polling_interval=5,
            max_concurrent=1
        )
        return Coordinator(config)

    def test_write_skills_creates_directory_and_file(self, coordinator, tmp_path):
        """Should create skills directory and extract ZIP contents."""
        from aiagent_runner.mcp_client import SkillDefinition

        config_dir = tmp_path / ".claude"
        config_dir.mkdir()

        skill_content = "---\nname: code-review\n---\n\n# Code Review Steps\n\n1. Check style\n2. Check logic"
        archive_base64 = create_test_zip_archive(skill_content)

        skills = [
            SkillDefinition(
                id="skill_001",
                name="Code Review",
                directory_name="code-review",
                archive_base64=archive_base64
            )
        ]

        coordinator._write_skills(config_dir, skills)

        skill_file = config_dir / "skills" / "code-review" / "SKILL.md"
        assert skill_file.exists()
        content = skill_file.read_text()
        assert "# Code Review Steps" in content
        assert "name: code-review" in content

    def test_write_skills_creates_multiple_skills(self, coordinator, tmp_path):
        """Should create multiple skill directories and extract ZIP contents."""
        from aiagent_runner.mcp_client import SkillDefinition

        config_dir = tmp_path / ".gemini"
        config_dir.mkdir()

        skills = [
            SkillDefinition(
                id="skill_001",
                name="Code Review",
                directory_name="code-review",
                archive_base64=create_test_zip_archive("# Code Review")
            ),
            SkillDefinition(
                id="skill_002",
                name="Testing",
                directory_name="testing",
                archive_base64=create_test_zip_archive("# Testing Guidelines")
            ),
            SkillDefinition(
                id="skill_003",
                name="Documentation",
                directory_name="documentation",
                archive_base64=create_test_zip_archive("# Documentation Style")
            )
        ]

        coordinator._write_skills(config_dir, skills)

        skills_dir = config_dir / "skills"
        assert (skills_dir / "code-review" / "SKILL.md").exists()
        assert (skills_dir / "testing" / "SKILL.md").exists()
        assert (skills_dir / "documentation" / "SKILL.md").exists()

        # Verify content
        assert "# Code Review" in (skills_dir / "code-review" / "SKILL.md").read_text()
        assert "# Testing Guidelines" in (skills_dir / "testing" / "SKILL.md").read_text()
        assert "# Documentation Style" in (skills_dir / "documentation" / "SKILL.md").read_text()

    def test_write_skills_clears_existing_skills(self, coordinator, tmp_path):
        """Should clear existing skills directory before writing new skills."""
        from aiagent_runner.mcp_client import SkillDefinition

        config_dir = tmp_path / ".claude"
        config_dir.mkdir()

        # Create existing skill directory
        old_skill_dir = config_dir / "skills" / "old-skill"
        old_skill_dir.mkdir(parents=True)
        old_skill_file = old_skill_dir / "SKILL.md"
        old_skill_file.write_text("# Old Skill Content")

        # Write new skills
        new_skills = [
            SkillDefinition(
                id="skill_new",
                name="New Skill",
                directory_name="new-skill",
                archive_base64=create_test_zip_archive("# New Skill Content")
            )
        ]

        coordinator._write_skills(config_dir, new_skills)

        # Old skill should be removed
        assert not (config_dir / "skills" / "old-skill").exists()
        # New skill should exist
        assert (config_dir / "skills" / "new-skill" / "SKILL.md").exists()
        assert "# New Skill Content" in (config_dir / "skills" / "new-skill" / "SKILL.md").read_text()

    def test_write_skills_empty_list_does_not_create_directory(self, coordinator, tmp_path):
        """Should not create skills directory when skills list is empty."""
        config_dir = tmp_path / ".claude"
        config_dir.mkdir()

        coordinator._write_skills(config_dir, [])

        # Skills directory should not exist
        assert not (config_dir / "skills").exists()

    def test_write_skills_empty_list_clears_existing(self, coordinator, tmp_path):
        """Should clear existing skills when new skills list is empty."""
        from aiagent_runner.mcp_client import SkillDefinition

        config_dir = tmp_path / ".claude"
        config_dir.mkdir()

        # First, write some skills
        initial_skills = [
            SkillDefinition(
                id="skill_001",
                name="Skill",
                directory_name="test-skill",
                archive_base64=create_test_zip_archive("content")
            )
        ]
        coordinator._write_skills(config_dir, initial_skills)
        assert (config_dir / "skills" / "test-skill" / "SKILL.md").exists()

        # Now write empty list
        coordinator._write_skills(config_dir, [])

        # Skills directory should be cleared
        assert not (config_dir / "skills").exists()

    def test_write_skills_preserves_other_config_files(self, coordinator, tmp_path):
        """Should not affect other files in config directory."""
        config_dir = tmp_path / ".claude"
        config_dir.mkdir()

        # Create other config file
        claude_md = config_dir / "CLAUDE.md"
        claude_md.write_text("# Agent Instructions")

        settings_json = config_dir / "settings.json"
        settings_json.write_text('{"key": "value"}')

        from aiagent_runner.mcp_client import SkillDefinition
        skills = [
            SkillDefinition(
                id="skill_001",
                name="Test",
                directory_name="test-skill",
                archive_base64=create_test_zip_archive("# Test")
            )
        ]

        coordinator._write_skills(config_dir, skills)

        # Other files should be preserved
        assert claude_md.exists()
        assert "# Agent Instructions" in claude_md.read_text()
        assert settings_json.exists()
        assert '{"key": "value"}' in settings_json.read_text()

        # Skill should also exist
        assert (config_dir / "skills" / "test-skill" / "SKILL.md").exists()

    def test_write_skills_extracts_zip_with_extra_files(self, coordinator, tmp_path):
        """Should extract all files from ZIP archive including scripts and templates."""
        from aiagent_runner.mcp_client import SkillDefinition

        config_dir = tmp_path / ".claude"
        config_dir.mkdir()

        # Create ZIP with extra files (scripts and templates)
        extra_files = {
            "scripts/build.sh": "#!/bin/bash\necho 'Building...'",
            "templates/report.md": "# Report Template\n\n## Summary",
        }
        archive_base64 = create_test_zip_archive(
            "# Complex Skill\n\nThis skill has extra files.",
            extra_files=extra_files
        )

        skills = [
            SkillDefinition(
                id="skill_complex",
                name="Complex Skill",
                directory_name="complex-skill",
                archive_base64=archive_base64
            )
        ]

        coordinator._write_skills(config_dir, skills)

        skill_dir = config_dir / "skills" / "complex-skill"
        # Verify SKILL.md
        assert (skill_dir / "SKILL.md").exists()
        assert "# Complex Skill" in (skill_dir / "SKILL.md").read_text()

        # Verify extra files were extracted
        assert (skill_dir / "scripts" / "build.sh").exists()
        assert "Building" in (skill_dir / "scripts" / "build.sh").read_text()

        assert (skill_dir / "templates" / "report.md").exists()
        assert "Report Template" in (skill_dir / "templates" / "report.md").read_text()
