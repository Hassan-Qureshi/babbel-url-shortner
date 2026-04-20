"""DynamoDB store."""

from datetime import UTC, datetime
from decimal import Decimal
from typing import Any

import boto3
from boto3.dynamodb.conditions import Attr
from botocore.exceptions import ClientError

from shared.exceptions import ConflictError
from shared.models import URLRecord

import logging

logger = logging.getLogger()


class DynamoStore:
    def __init__(self, table_name: str, client: Any = None) -> None:
        resource = client or boto3.resource("dynamodb")
        self._table = resource.Table(table_name)

    def put(self, record: URLRecord) -> None:
        try:
            self._table.put_item(
                Item=_to_item(record),
                ConditionExpression=Attr("code").not_exists(),
            )
        except ClientError as exc:
            if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
                raise ConflictError(record.code) from exc
            raise

    def get(self, code: str) -> URLRecord | None:
        response = self._table.get_item(Key={"code": code})
        item = response.get("Item")
        return _from_item(item) if item else None

    def increment_hit_count(self, code: str) -> None:
        try:
            self._table.update_item(
                Key={"code": code},
                UpdateExpression="ADD hit_count :one",
                ExpressionAttributeValues={":one": 1},
            )
        except Exception:
            logger.warning("failed to increment hit count for %s", code, exc_info=True)


def _to_item(record: URLRecord) -> dict[str, Any]:
    item: dict[str, Any] = {
        "code": record.code,
        "original_url": record.original_url,
        "created_by": record.created_by,
        "created_at": record.created_at.isoformat(),
        "hit_count": Decimal(record.hit_count),
    }
    if record.expires_at is not None:
        item["expires_at"] = int(record.expires_at.timestamp())
    return item


def _from_item(item: dict[str, Any]) -> URLRecord:
    expires_at = (
        datetime.fromtimestamp(int(item["expires_at"]), tz=UTC) if "expires_at" in item else None
    )
    return URLRecord(
        code=str(item["code"]),
        original_url=str(item["original_url"]),
        created_by=str(item["created_by"]),
        created_at=datetime.fromisoformat(str(item["created_at"])),
        expires_at=expires_at,
        hit_count=int(item.get("hit_count", 0)),
    )
