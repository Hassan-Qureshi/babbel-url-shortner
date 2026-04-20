"""Cryptographically random base62 short code generation.

Uses ``secrets.choice`` which reads from the OS CSPRNG.
6 characters of base62 gives 62^6 ≈ 56 billion combinations.
"""

import secrets

_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
_DEFAULT_LENGTH = 6


def generate(length: int = _DEFAULT_LENGTH) -> str:
    """Return a cryptographically random base62 string of *length* characters."""
    if length < 1:
        msg = "length must be >= 1"
        raise ValueError(msg)
    return "".join(secrets.choice(_ALPHABET) for _ in range(length))
