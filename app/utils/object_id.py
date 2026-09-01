from bson import ObjectId
from bson.errors import InvalidId
from fastapi import HTTPException


def parse_object_id(id_str: str, entity_name: str = "record") -> ObjectId:
    """Parse a Mongo ObjectId from a path/body string, raising a clear 400
    instead of letting an InvalidId bubble up as an unhandled 500."""
    try:
        return ObjectId(id_str)
    except InvalidId:
        raise HTTPException(status_code=400, detail=f"Invalid {entity_name} id.")
