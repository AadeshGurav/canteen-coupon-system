from datetime import datetime

from pydantic import BaseModel, Field


class RecipeIngredient(BaseModel):
    ingredient_id: str
    # Free text rather than a strict quantity+unit-per-serving model — this
    # system doesn't track expected headcount per menu entry, so "500g per
    # ~50 servings" as a note is honest about what's actually known, instead
    # of a precise-looking number that isn't (CLAUDE.md: don't build for
    # scale/precision this project doesn't need yet).
    quantity_note: str = Field(min_length=1)


class RecipeCreate(BaseModel):
    # Matched case-insensitively against a menu entry's `items` strings (see
    # app/services/purchase_schedule_service.py) — this is deliberately a
    # free-text dish name, not a foreign key into menu_log, since the same
    # dish name recurs across many independent menu entries.
    dish_name: str = Field(min_length=1)
    ingredients: list[RecipeIngredient] = Field(min_length=1)


class RecipeUpdate(BaseModel):
    dish_name: str | None = Field(default=None, min_length=1)
    ingredients: list[RecipeIngredient] | None = Field(default=None, min_length=1)


class RecipeOut(BaseModel):
    id: str
    dish_name: str
    ingredients: list[RecipeIngredient]
    created_at: datetime
    updated_at: datetime
