"""Immutable application configuration loaded once from environment variables."""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Config:
    """Immutable configuration for the URL shortener Lambda functions.

    Loaded once at module level via ``Config.from_env()``.  Business logic
    never reads ``os.environ`` directly it receives a ``Config`` instance.
    """

    dynamodb_table: str
    redis_endpoint: str | None
    base_url: str
    environment: str
    log_level: str

    @classmethod
    def from_env(cls) -> "Config":
        """Build a ``Config`` from the current process environment."""
        return cls(
            dynamodb_table=os.environ["DYNAMODB_TABLE"],
            redis_endpoint=os.environ.get("REDIS_ENDPOINT"),
            base_url=os.environ["BASE_URL"],
            environment=os.environ["ENVIRONMENT"],
            log_level=os.environ.get("LOG_LEVEL", "INFO"),
        )
