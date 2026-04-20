"""Pydantic v2 models for the URL shortener."""

import re
from datetime import datetime

from pydantic import BaseModel, HttpUrl, field_validator


type Code = str
"""Type alias for a short code string."""


class URLRecord(BaseModel):
    """Immutable record representing a shortened URL in DynamoDB."""

    model_config = {"frozen": True}

    code: Code
    original_url: str
    created_by: str
    created_at: datetime
    expires_at: datetime | None = None
    hit_count: int = 0


class ShortenRequest(BaseModel):
    """Incoming request to create a shortened URL."""

    url: HttpUrl
    custom_code: str | None = None
    expires_in_days: int | None = None

    @field_validator("custom_code")
    @classmethod
    def validate_custom_code(cls, v: str | None) -> str | None:
        """Custom code must be 4–20 alphanumeric chars or hyphens."""
        if v is not None and not re.fullmatch(r"[a-zA-Z0-9-]{4,20}", v):
            msg = "custom_code must be 4–20 alphanumeric chars or hyphens"
            raise ValueError(msg)
        return v

    @field_validator("expires_in_days")
    @classmethod
    def validate_expiry(cls, v: int | None) -> int | None:
        """Expiry must be between 1 and 3650 days."""
        if v is not None and not (1 <= v <= 3650):
            msg = "expires_in_days must be between 1 and 3650"
            raise ValueError(msg)
        return v


class ShortenResponse(BaseModel):
    """Response returned after creating a shortened URL."""

    model_config = {"frozen": True}

    code: Code
    short_url: str
    original_url: str
    expires_at: datetime | None = None
