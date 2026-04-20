"""GET /{code} Lambda handler using DynamoDB only."""

from __future__ import annotations

import json
import logging
from datetime import UTC, datetime
from typing import Any

from shared.config import Config
from shared.store.dynamo import DynamoStore

logger = logging.getLogger()
logger.setLevel(logging.INFO)

_store: DynamoStore | None = None


def _get_store() -> DynamoStore:
    """Create the DynamoDB store once per warm Lambda environment."""
    global _store
    if _store is None:
        config = Config.from_env()
        _store = DynamoStore(table_name=config.dynamodb_table)
    return _store


def handler(event: dict[str, Any], context: object) -> dict[str, Any]:
    """Resolve a short code from DynamoDB and return a redirect response."""
    code = _get_code(event)
    if not code:
        return _json_response(
            400,
            {
                "error": "validation_error",
                "detail": "missing path parameter 'code'",
            },
        )

    record = _get_store().get(code)
    if record is None:
        return _json_response(404, {"error": "not_found", "detail": f"code '{code}' not found"})

    if record.expires_at and record.expires_at < datetime.now(UTC):
        return _json_response(410, {"error": "expired", "detail": f"code '{code}' has expired"})

    _get_store().increment_hit_count(code)
    logger.info("redirect resolved: %s", code)

    return {
        "statusCode": 301,
        "headers": {
            "Location": record.original_url,
            "Cache-Control": "public, max-age=60",
        },
        "body": "",
    }


def _get_code(event: dict[str, Any]) -> str | None:
    """Extract the short code from an API Gateway proxy event."""
    path_parameters = event.get("pathParameters") or {}
    code = path_parameters.get("code")
    return str(code) if code else None


def _json_response(status: int, body: dict[str, Any]) -> dict[str, Any]:
    """Build a JSON API Gateway proxy response."""
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
