from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pymongo.errors import DuplicateKeyError

from app.core.database import ingredients, recipes
from app.core.security import require_role
from app.schemas.recipe import RecipeCreate, RecipeUpdate
from app.utils.object_id import parse_object_id

router = APIRouter(prefix="/recipes", tags=["recipes"], dependencies=[Depends(require_role("admin"))])


def _oid(id_str: str):
    return parse_object_id(id_str, "recipe")


def _serialize(doc: dict) -> dict:
    doc["_id"] = str(doc["_id"])
    doc.pop("dish_name_lower", None)
    return doc


async def _validate_ingredient_ids(ingredient_ids: list[str]) -> None:
    object_ids = [parse_object_id(i, "ingredient") for i in ingredient_ids]
    existing_count = await ingredients.count_documents({"_id": {"$in": object_ids}})
    if existing_count != len(set(ingredient_ids)):
        raise HTTPException(
            status_code=400,
            detail="One or more ingredient_id values don't match a known ingredient.",
        )


@router.post("")
async def create_recipe(payload: RecipeCreate):
    await _validate_ingredient_ids([i.ingredient_id for i in payload.ingredients])
    now = datetime.now(timezone.utc)
    doc = payload.model_dump()
    doc["dish_name_lower"] = payload.dish_name.strip().lower()
    doc.update({"created_at": now, "updated_at": now})
    try:
        result = await recipes.insert_one(doc)
    except DuplicateKeyError:
        raise HTTPException(status_code=409, detail=f"A recipe for '{payload.dish_name}' already exists.")
    created = await recipes.find_one({"_id": result.inserted_id})
    return _serialize(created)


@router.get("")
async def list_recipes():
    docs = await recipes.find().sort("dish_name", 1).to_list(length=500)
    return [_serialize(d) for d in docs]


@router.patch("/{recipe_id}")
async def update_recipe(recipe_id: str, payload: RecipeUpdate):
    updates = payload.model_dump(exclude_unset=True)
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update.")

    if "ingredients" in updates:
        await _validate_ingredient_ids([i["ingredient_id"] for i in updates["ingredients"]])
    if "dish_name" in updates:
        updates["dish_name_lower"] = updates["dish_name"].strip().lower()
    updates["updated_at"] = datetime.now(timezone.utc)

    try:
        result = await recipes.update_one({"_id": _oid(recipe_id)}, {"$set": updates})
    except DuplicateKeyError:
        raise HTTPException(
            status_code=409, detail=f"A recipe for '{updates.get('dish_name')}' already exists."
        )
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Recipe not found.")

    doc = await recipes.find_one({"_id": _oid(recipe_id)})
    return _serialize(doc)


@router.delete("/{recipe_id}")
async def delete_recipe(recipe_id: str):
    result = await recipes.delete_one({"_id": _oid(recipe_id)})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Recipe not found.")
    return {"success": True}
