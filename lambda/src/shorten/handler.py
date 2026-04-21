"""POST /shorten create a short URL."""

from __future__ import annotations

import json
import logging
from datetime import UTC, datetime, timedelta
from typing import Any

from shared.config import Config
from shared.exceptions import ConflictError
from shared.models import ShortenRequest, ShortenResponse, URLRecord
from shared.shortcode.generator import generate
from shared.store.dynamo import DynamoStore

logger = logging.getLogger()
logger.setLevel(logging.INFO)

_MAX_RETRIES = 3


def handler(event: dict[str, Any], context: object) -> dict[str, Any]:
    """Lambda entry point for POST /shorten."""
    try:
        body = json.loads(event.get("body") or "{}")
        request = ShortenRequest(**body)
    except Exception as exc:
        return _response(400, {"error": "validation_error", "detail": str(exc)})

    cfg = Config.from_env()
    store = DynamoStore(table_name=cfg.dynamodb_table)

    code = request.custom_code or _generate_unique_code(store)
    expires_at = (
        datetime.now(UTC) + timedelta(days=request.expires_in_days)
        if request.expires_in_days
        else None
    )

    record = URLRecord(
        code=code,
        original_url=str(request.url),
        created_by=_get_api_key(event),
        created_at=datetime.now(UTC),
        expires_at=expires_at,
    )

    try:
        store.put(record)
    except ConflictError:
        return _response(409, {"error": "conflict", "detail": f"code '{code}' already exists"})

    resp = ShortenResponse(
        code=code,
        short_url=f"{cfg.base_url}/{code}",
        original_url=str(request.url),
        expires_at=expires_at,
    )

    logger.info("url shortened: %s -> %s", code, str(request.url))
    return _response(201, resp.model_dump(mode="json"))


def _generate_unique_code(store: DynamoStore) -> str:
    """Try up to _MAX_RETRIES times to find an unused code."""
    for _ in range(_MAX_RETRIES):
        code = generate()
        if store.get(code) is None:
            return code
    raise RuntimeError("failed to generate unique code after retries")


def _get_api_key(event: dict[str, Any]) -> str:
    """Extract API key from headers (case-insensitive)."""
    headers = event.get("headers") or {}
    return headers.get("x-api-key") or headers.get("X-Api-Key") or "anonymous"


def _response(status: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=str),
    }
