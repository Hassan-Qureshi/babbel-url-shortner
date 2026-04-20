"""Custom exception hierarchy for the URL shortener."""


class URLShortenerError(Exception):
    """Base exception for all URL shortener errors."""


class NotFoundError(URLShortenerError):
    """Raised when a short code does not exist."""

    def __init__(self, code: str) -> None:
        super().__init__(f"short code not found: {code!r}")
        self.code = code


class ConflictError(URLShortenerError):
    """Raised when a requested custom code is already taken."""

    def __init__(self, code: str) -> None:
        super().__init__(f"short code already exists: {code!r}")
        self.code = code


class ExpiredError(URLShortenerError):
    """Raised when a short code exists but has passed its expiry."""

    def __init__(self, code: str) -> None:
        super().__init__(f"short code has expired: {code!r}")
        self.code = code


class ValidationError(URLShortenerError):
    """Raised when input validation fails."""

    def __init__(self, message: str) -> None:
        super().__init__(message)
