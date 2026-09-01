"""Minimal in-memory stand-ins for the subset of Motor's async collection API
used by app/services — enough to unit-test business logic without a real
MongoDB instance. Not a general-purpose mock; only implements what's used."""

from bson import ObjectId


class _Result:
    def __init__(self, **kwargs):
        for key, value in kwargs.items():
            setattr(self, key, value)


class FakeCursor:
    """Stands in for Motor's cursor — just enough of `.sort().to_list()` for
    the handful of services that need a filtered/sorted list rather than a
    single document."""

    def __init__(self, docs: list[dict]):
        self._docs = docs

    def sort(self, key: str, direction: int = 1) -> "FakeCursor":
        self._docs = sorted(self._docs, key=lambda d: _get_nested(d, key), reverse=(direction == -1))
        return self

    async def to_list(self, length: int | None = None) -> list[dict]:
        docs = self._docs if length is None else self._docs[:length]
        return [dict(d) for d in docs]


class FakeCollection:
    def __init__(self):
        self._docs: dict[ObjectId, dict] = {}

    async def find_one(self, query: dict) -> dict | None:
        for doc in self._docs.values():
            if _matches(doc, query):
                return dict(doc)
        return None

    def find(self, query: dict | None = None) -> FakeCursor:
        query = query or {}
        return FakeCursor([dict(doc) for doc in self._docs.values() if _matches(doc, query)])

    async def insert_one(self, doc: dict) -> _Result:
        doc = dict(doc)
        doc.setdefault("_id", ObjectId())
        self._docs[doc["_id"]] = doc
        return _Result(inserted_id=doc["_id"])

    async def update_one(self, query: dict, update: dict, upsert: bool = False) -> _Result:
        for doc in self._docs.values():
            if _matches(doc, query):
                _apply_update(doc, update, is_insert=False)
                return _Result(matched_count=1, upserted_id=None)

        if not upsert:
            return _Result(matched_count=0, upserted_id=None)

        # Mongo's upsert seeds the new doc from the query's equality fields,
        # then layers $setOnInsert and $set on top — enough for how this
        # codebase actually uses upsert (idempotent "create if missing" keyed
        # by a few plain-equality fields, never a query operator).
        new_doc = {k: v for k, v in query.items() if not isinstance(v, dict)}
        new_doc["_id"] = ObjectId()
        _apply_update(new_doc, update, is_insert=True)
        self._docs[new_doc["_id"]] = new_doc
        return _Result(matched_count=0, upserted_id=new_doc["_id"])

    async def delete_one(self, query: dict) -> _Result:
        for doc_id, doc in list(self._docs.items()):
            if _matches(doc, query):
                del self._docs[doc_id]
                return _Result(deleted_count=1)
        return _Result(deleted_count=0)

    async def count_documents(self, query: dict, limit: int | None = None) -> int:
        count = sum(1 for doc in self._docs.values() if _matches(doc, query))
        return min(count, limit) if limit is not None else count


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
                if op == "$in" and actual not in operand:
                    return False
                if op == "$ne" and _contains_or_equals(actual, operand):
                    return False
        elif not _contains_or_equals(actual, expected):
            return False
    return True


def _contains_or_equals(actual, expected) -> bool:
    """Mongo's own equality semantics: `{"tags": "x"}` matches a document
    whose `tags` field is either exactly "x" or a list containing "x" — used
    here for notifications' `visible_roles` array field."""
    if isinstance(actual, list):
        return expected in actual
    return actual == expected


def _apply_update(doc: dict, update: dict, is_insert: bool = False) -> None:
    for op, fields in update.items():
        # $setOnInsert only takes effect on the insert half of an upsert,
        # same as real Mongo — applying it on every matched update would
        # let it silently overwrite fields a real $set/$addToSet changed.
        if op == "$set" or (op == "$setOnInsert" and is_insert):
            for key, value in fields.items():
                _set_nested(doc, key, value)
        elif op == "$addToSet":
            for key, value in fields.items():
                current = doc.setdefault(key, [])
                if value not in current:
                    current.append(value)
