"""Configuration for the infra SSH MCP server."""

import os
from dataclasses import dataclass


@dataclass
class Config:
    host: str
    port: int
    user: str
    key_path: str
    client_label: str

    @classmethod
    def from_env(cls) -> "Config":
        host = os.getenv("SSH_HOST", "")
        client_label = os.getenv("CLIENT_LABEL", "")
        if not host:
            raise ValueError("SSH_HOST is required")
        if not client_label:
            raise ValueError("CLIENT_LABEL is required")
        return cls(
            host=host,
            port=int(os.getenv("SSH_PORT", "22")),
            user=os.getenv("SSH_USER", "administrator"),
            key_path=os.path.expanduser(
                os.getenv("SSH_KEY_PATH", "~/.ssh/id_ed25519_infra")
            ),
            client_label=client_label,
        )


config = Config.from_env()
