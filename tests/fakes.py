"""Minimal in-memory stand-ins for the subset of Motor's async collection API
used by app/services — enough to unit-test business logic without a real
MongoDB instance. Not a general-purpose mock; only implements what's used."""

from bson import ObjectId


class _Result:
    def __init__(self, **kwargs):
        for key, value in kwargs.items():
            setattr(self, key, value)


class FakeCollection:
    def __init__(self):
        self._docs: dict[ObjectId, dict] = {}

    async def find_one(self, query: dict) -> dict | None:
        for doc in self._docs.values():
            if _matches(doc, query):
                return dict(doc)
        return None

    async def insert_one(self, doc: dict) -> _Result:
        doc = dict(doc)
        doc.setdefault("_id", ObjectId())
        self._docs[doc["_id"]] = doc
        return _Result(inserted_id=doc["_id"])

    async def update_one(self, query: dict, update: dict) -> _Result:
        for doc in self._docs.values():
            if _matches(doc, query):
                _apply_update(doc, update)
                return _Result(matched_count=1)
        return _Result(matched_count=0)


def _get_nested(doc: dict, dotted_key: str):
    value = doc
    for part in dotted_key.split("."):
        if isinstance(value, dict) and part in value:
            value = value[part]
        else:
            return None
    return value


def _set_nested(doc: dict, dotted_key: str, value) -> None:
    parts = dotted_key.split(".")
    target = doc
    for part in parts[:-1]:
        target = target.setdefault(part, {})
    target[parts[-1]] = value


def _matches(doc: dict, query: dict) -> bool:
    for key, expected in query.items():
        actual = _get_nested(doc, key)
        if isinstance(expected, dict) and any(k.startswith("$") for k in expected):
            for op, operand in expected.items():
                if op == "$gte" and not (actual is not None and actual >= operand):
                    return False
                if op == "$lte" and not (actual is not None and actual <= operand):
                    return False
        elif actual != expected:
            return False
    return True


def _apply_update(doc: dict, update: dict) -> None:
    for op, fields in update.items():
        if op == "$set":
            for key, value in fields.items():
                _set_nested(doc, key, value)
