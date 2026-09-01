"""Integration tests that need a real MongoDB — everything else in this
suite runs against tests/fakes.py precisely so it doesn't need one (see the
README's "Running tests" section). This file is the deliberate exception:
the bug it guards against is a genuine race condition in MongoDB's own
concurrency semantics, which an in-memory fake can't reproduce (asyncio only
switches tasks at a real await point, and the fake's methods have none).

Skips itself cleanly if MONGO_URI isn't reachable, rather than failing the
whole suite in an environment with no MongoDB (e.g. the standard CI lint/test
job) — run explicitly with MONGO_URI set against a real instance to exercise
it, e.g. via `docker compose up -d mongo` locally.
"""

import asyncio
import os

import pytest
import pytest_asyncio
from motor.motor_asyncio import AsyncIOMotorClient

pytestmark = pytest.mark.asyncio


async def _mongo_reachable(uri: str) -> bool:
    try:
        client = AsyncIOMotorClient(uri, serverSelectionTimeoutMS=500)
        await client.admin.command("ping")
        client.close()
        return True
    except Exception:  # noqa: BLE001 — any connection failure means "not reachable"
        return False


@pytest_asyncio.fixture
async def real_settings_collection():
    uri = os.environ.get("MONGO_URI", "mongodb://localhost:27017")
    if not await _mongo_reachable(uri):
        pytest.skip(f"No MongoDB reachable at {uri} — set MONGO_URI to run this test.")

    client = AsyncIOMotorClient(uri, tz_aware=True)
    db = client["canteen_coupon_test_race_condition"]
    collection = db["settings"]
    await collection.delete_many({})  # start from a genuinely empty collection
    yield collection
    await collection.delete_many({})
    client.close()


async def test_concurrent_first_calls_do_not_race(real_settings_collection, monkeypatch):
    """Regression test: gunicorn runs multiple worker processes, each running
    FastAPI's lifespan startup independently — on a genuinely fresh database,
    more than one worker calls get_global_settings() at once. This used to
    race a plain find-then-insert, crashing every worker but one with
    DuplicateKeyError on _id. See app/core/database.py's get_global_settings
    docstring for the fix (an atomic find_one_and_update upsert)."""
    from app.core import database

    monkeypatch.setattr(database, "settings_collection", real_settings_collection)

    results = await asyncio.gather(
        *[database.get_global_settings() for _ in range(20)], return_exceptions=True
    )

    errors = [r for r in results if isinstance(r, Exception)]
    assert errors == [], f"get_global_settings() raised under concurrency: {errors[:1]}"

    document_count = await real_settings_collection.count_documents({"_id": "global"})
    assert document_count == 1
