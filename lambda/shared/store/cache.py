"""Redis implementation of the ``Cache`` protocol.

All Redis errors are swallowed with a warning log the cache is an
optimisation, not a hard dependency.  A Redis outage must never fail a
redirect.
"""

from __future__ import annotations

from typing import Any

import redis
from aws_lambda_powertools import Logger

logger = Logger(child=True)

_CACHE_KEY_PREFIX = "url:"
_DEFAULT_TTL = 300  # seconds


class RedisCache:
    """``Cache`` backed by ElastiCache Redis with TLS."""

    def __init__(self, host: str, port: int = 6379, ssl: bool = True) -> None:
        self._client: Any = redis.Redis(
            host=host,
            port=port,
            ssl=ssl,
            decode_responses=True,
        )

    @classmethod
    def from_client(cls, client) -> RedisCache:
        """Create a ``RedisCache`` wrapping an existing Redis client (for tests)."""
        instance = cls.__new__(cls)
        instance._client = client
        return instance

    # ------------------------------------------------------------------
    # Cache protocol
    # ------------------------------------------------------------------

    def get(self, code: str) -> str | None:
        """Return the cached original URL, or ``None`` on miss / error."""
        try:
            value: str | None = self._client.get(_CACHE_KEY_PREFIX + code)
            return value
        except redis.RedisError:
            logger.warning(
                "redis get failed, falling through to DynamoDB",
                extra={"code": code},
                exc_info=True,
            )
            return None

    def set(self, code: str, url: str, ttl_seconds: int = _DEFAULT_TTL) -> None:
        """Store *code* → *url* with TTL.  Never raises on Redis errors."""
        try:
            self._client.setex(_CACHE_KEY_PREFIX + code, ttl_seconds, url)
        except redis.RedisError:
            logger.warning("redis set failed", extra={"code": code}, exc_info=True)

    def delete(self, code: str) -> None:
        """Remove *code* from the cache.  Never raises on Redis errors."""
        try:
            self._client.delete(_CACHE_KEY_PREFIX + code)
        except redis.RedisError:
            logger.warning("redis delete failed", extra={"code": code}, exc_info=True)
