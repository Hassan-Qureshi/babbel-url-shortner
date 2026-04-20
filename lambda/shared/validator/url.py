"""URL validation beyond what Pydantic's ``HttpUrl`` provides.

This module adds scheme allow-listing, length caps, and a private/reserved
IP blocklist to defend against SSRF-style abuse.
"""

from urllib.parse import urlparse

_ALLOWED_SCHEMES = frozenset({"http", "https"})
_MAX_URL_LENGTH = 2048

# Reserved / private-use IPv4 prefixes that must not appear in the host.
_BLOCKED_HOSTS = frozenset(
    {
        "localhost",
        "127.0.0.1",
        "0.0.0.0",  # noqa: S104 intentionally blocking this address
        "169.254.169.254",  # EC2 metadata endpoint
    }
)


def validate_url(url: str) -> str:
    """Return *url* unchanged if it passes all safety checks.

    Raises ``ValueError`` with a human-readable message on failure.
    """
    if len(url) > _MAX_URL_LENGTH:
        msg = f"URL exceeds maximum length of {_MAX_URL_LENGTH} characters"
        raise ValueError(msg)

    parsed = urlparse(url)

    if parsed.scheme not in _ALLOWED_SCHEMES:
        msg = f"scheme {parsed.scheme!r} is not allowed; use http or https"
        raise ValueError(msg)

    host = (parsed.hostname or "").lower()

    if not host:
        msg = "URL must contain a valid hostname"
        raise ValueError(msg)

    if host in _BLOCKED_HOSTS:
        msg = f"host {host!r} is not allowed"
        raise ValueError(msg)

    # Block private IPv4 ranges
    if _is_private_ip(host):
        msg = f"host {host!r} resolves to a private IP range"
        raise ValueError(msg)

    return url


def _is_private_ip(host: str) -> bool:
    """Return ``True`` if *host* looks like a private IPv4 address."""
    private_prefixes = (
        "10.",
        "172.16.",
        "172.17.",
        "172.18.",
        "172.19.",
        "172.20.",
        "172.21.",
        "172.22.",
        "172.23.",
        "172.24.",
        "172.25.",
        "172.26.",
        "172.27.",
        "172.28.",
        "172.29.",
        "172.30.",
        "172.31.",
        "192.168.",
    )
    return any(host.startswith(prefix) for prefix in private_prefixes)
