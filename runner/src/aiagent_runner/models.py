# src/aiagent_runner/models.py
# Shared type definitions for aiagent_runner
# Reference: docs/design/SPAWN_ERROR_PROTECTION.md

from dataclasses import dataclass


@dataclass
class AgentInstanceKey:
    """Unique key for an Agent Instance: (agent_id, project_id)."""
    agent_id: str
    project_id: str

    def __hash__(self):
        return hash((self.agent_id, self.project_id))

    def __eq__(self, other):
        if not isinstance(other, AgentInstanceKey):
            return False
        return self.agent_id == other.agent_id and self.project_id == other.project_id
