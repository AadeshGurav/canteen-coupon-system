from datetime import datetime, timedelta, timezone

import pytest

from app.services import auth_service
from tests.fakes import FakeCollection


@pytest.fixture
def fake_db(monkeypatch):
    users = FakeCollection()
    sessions = FakeCollection()
    monkeypatch.setattr(auth_service, "users", users)
    monkeypatch.setattr(auth_service, "sessions", sessions)
    return users, sessions


async def create_user(users: FakeCollection, **overrides) -> dict:
    doc = {
        "username": "alice",
        "password_hash": auth_service.hash_password("correct-horse"),
        "role": "admin",
        "status": "active",
    }
    doc.update(overrides)
    result = await users.insert_one(doc)
    doc["_id"] = result.inserted_id
    return doc


class TestPasswordHashing:
    def test_correct_password_verifies(self):
        stored = auth_service.hash_password("correct-horse")
        assert auth_service.verify_password("correct-horse", stored) is True

    def test_wrong_password_fails(self):
        stored = auth_service.hash_password("correct-horse")
        assert auth_service.verify_password("wrong-password", stored) is False

    def test_two_hashes_of_the_same_password_differ(self):
        # Each hash uses a fresh random salt — this is what defeats a
        # rainbow-table attack against the stored hashes.
        assert auth_service.hash_password("x") != auth_service.hash_password("x")

    def test_malformed_stored_hash_fails_closed(self):
        assert auth_service.verify_password("anything", "not-a-valid-hash") is False


@pytest.mark.asyncio
class TestAuthenticate:
    async def test_correct_credentials_succeed(self, fake_db):
        users, _ = fake_db
        await create_user(users)
        result = await auth_service.authenticate("alice", "correct-horse")
        assert result is not None
        assert result["username"] == "alice"

    async def test_wrong_password_fails(self, fake_db):
        users, _ = fake_db
        await create_user(users)
        assert await auth_service.authenticate("alice", "wrong") is None

    async def test_unknown_username_fails(self, fake_db):
        assert await auth_service.authenticate("nobody", "anything") is None

    async def test_inactive_user_cannot_authenticate(self, fake_db):
        users, _ = fake_db
        await create_user(users, status="inactive")
        assert await auth_service.authenticate("alice", "correct-horse") is None


@pytest.mark.asyncio
class TestSessions:
    async def test_created_session_is_retrievable(self, fake_db):
        users, _ = fake_db
        user = await create_user(users)
        token = await auth_service.create_session(user)
        session = await auth_service.get_session(token)
        assert session is not None
        assert session["username"] == "alice"
        assert session["role"] == "admin"

    async def test_unknown_token_returns_none(self, fake_db):
        assert await auth_service.get_session("not-a-real-token") is None

    async def test_expired_session_is_rejected(self, fake_db):
        users, sessions = fake_db
        user = await create_user(users)
        token = await auth_service.create_session(user)
        # Backdate it past expiry, same technique as the scan reversal-window test.
        sessions._docs[token]["expires_at"] = datetime.now(timezone.utc) - timedelta(seconds=1)
        assert await auth_service.get_session(token) is None

    async def test_deleted_session_is_no_longer_valid(self, fake_db):
        users, _ = fake_db
        user = await create_user(users)
        token = await auth_service.create_session(user)
        await auth_service.delete_session(token)
        assert await auth_service.get_session(token) is None


@pytest.mark.asyncio
class TestBootstrapInitialAdmin:
    async def test_creates_admin_when_no_users_exist(self, fake_db, monkeypatch):
        users, _ = fake_db
        monkeypatch.setattr(auth_service.settings, "initial_admin_username", "admin")
        monkeypatch.setattr(auth_service.settings, "initial_admin_password", "set-in-env")

        await auth_service.bootstrap_initial_admin()

        created = await users.find_one({"username": "admin"})
        assert created is not None
        assert created["role"] == "admin"
        assert auth_service.verify_password("set-in-env", created["password_hash"])

    async def test_does_nothing_if_a_user_already_exists(self, fake_db):
        users, _ = fake_db
        await create_user(users, username="someone_else")

        await auth_service.bootstrap_initial_admin()

        count = await users.count_documents({})
        assert count == 1  # no second (bootstrap) user was created
