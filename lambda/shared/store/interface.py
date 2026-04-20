"""Protocol classes defining the persistence and cache contracts.

Use ``Protocol`` not ABC so that any class with the right shape satisfies
the contract.  Tests pass fake implementations; production passes real ones.
"""

from typing import Protocol, runtime_checkable

from shared.models import URLRecord


@runtime_checkable
class URLStore(Protocol):
    """Persistence interface for URL records."""

    def put(self, record: URLRecord) -> None:
        """Persist a URL record. Raises ``ConflictError`` if code already exists."""
        ...

    def get(self, code: str) -> URLRecord | None:
        """Return the record for *code*, or ``None`` if not found."""
        ...

    def increment_hit_count(self, code: str) -> None:
        """Increment the hit counter.  Must not raise log and continue on failure."""
        ...


@runtime_checkable
class Cache(Protocol):
    """Read-through cache for redirect lookups."""

    def get(self, code: str) -> str | None:
        """Return the cached original URL, or ``None`` on miss."""
        ...

    def set(self, code: str, url: str, ttl_seconds: int = 300) -> None:
        """Store *code* → *url* with TTL.  Must not raise on Redis errors."""
        ...

    def delete(self, code: str) -> None:
        """Remove a code from the cache.  Must not raise on Redis errors."""
        ...
