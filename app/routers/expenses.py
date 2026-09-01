import logging
from datetime import date, datetime
from typing import Optional

from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.core.database import expenses, topups

router = APIRouter(prefix="/expenses", tags=["expenses"])
logger = logging.getLogger(__name__)


class ExpenseCreate(BaseModel):
    category: str = Field(min_length=1)
    description: str = Field(min_length=1)
    amount: float = Field(ge=0)
    date: date
    created_by: str = Field(min_length=1)


@router.post("")
async def add_expense(payload: ExpenseCreate):
    doc = payload.model_dump()
    doc["date"] = datetime.combine(payload.date, datetime.min.time())
    result = await expenses.insert_one(doc)
    doc["_id"] = str(result.inserted_id)
    logger.info(
        "expense.logged category=%s amount=%.2f date=%s by=%s",
        payload.category,
        payload.amount,
        payload.date,
        payload.created_by,
    )
    return doc


@router.get("")
async def list_expenses(start: Optional[date] = None, end: Optional[date] = None):
    query = {}
    if start or end:
        query["date"] = {}
        if start:
            query["date"]["$gte"] = datetime.combine(start, datetime.min.time())
        if end:
            query["date"]["$lte"] = datetime.combine(end, datetime.min.time())
    docs = await expenses.find(query).sort("date", 1).to_list(length=5000)
    for d in docs:
        d["_id"] = str(d["_id"])
    return docs


@router.get("/summary")
async def profit_summary(start: Optional[date] = None, end: Optional[date] = None):
    """Simple revenue (confirmed topups) vs expense summary for a date range."""
    topup_query = {"payment_status": "confirmed"}
    expense_query = {}
    if start or end:
        topup_query["created_at"] = {}
        expense_query["date"] = {}
        if start:
            start_dt = datetime.combine(start, datetime.min.time())
            topup_query["created_at"]["$gte"] = start_dt
            expense_query["date"]["$gte"] = start_dt
        if end:
            end_dt = datetime.combine(end, datetime.min.time())
            topup_query["created_at"]["$lte"] = end_dt
            expense_query["date"]["$lte"] = end_dt

    revenue = 0.0
    async for t in topups.find(topup_query):
        revenue += t["amount"]

    spend = 0.0
    async for e in expenses.find(expense_query):
        spend += e["amount"]

    return {"revenue": revenue, "expenses": spend, "profit": revenue - spend}
