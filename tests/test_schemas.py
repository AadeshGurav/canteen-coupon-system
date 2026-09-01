"""Boundary-validation tests for the Pydantic schemas — the decision
branches that reject bad input before it ever reaches business logic."""

import pytest
from pydantic import ValidationError

from app.routers.menu import MenuEntryCreate
from app.schemas.member import MemberCreate, MemberUpdate, validate_type_specific_fields
from app.schemas.refund import RefundCreate
from app.schemas.topup import TopupCreate


class TestMemberTypeSpecificFields:
    def test_student_with_staff_id_is_rejected(self):
        with pytest.raises(ValidationError):
            MemberCreate(type="student", name="X", staff_id="S1")

    def test_staff_with_class_name_is_rejected(self):
        with pytest.raises(ValidationError):
            MemberCreate(type="staff", name="X", class_name="5A")

    def test_staff_with_roll_number_is_rejected(self):
        with pytest.raises(ValidationError):
            MemberCreate(type="staff", name="X", roll_number="12")

    def test_valid_student_is_accepted(self):
        member = MemberCreate(type="student", name="X", class_name="5A", roll_number="12")
        assert member.class_name == "5A"

    def test_valid_staff_is_accepted(self):
        member = MemberCreate(type="staff", name="X", staff_id="S1")
        assert member.staff_id == "S1"

    def test_shared_validator_used_by_update_path_too(self):
        # This is the same function app/routers/members.py calls before a
        # PATCH, since MemberUpdate has no `type` field of its own to
        # validate against — see update_member's docstring.
        with pytest.raises(ValueError):
            validate_type_specific_fields("student", None, None, "S1")
        validate_type_specific_fields("student", "5A", "12", None)  # no error


class TestNoOpTransactionsAreRejected:
    def test_zero_amount_zero_units_topup_is_rejected(self):
        with pytest.raises(ValidationError):
            TopupCreate(member_id="x", amount=0, payment_method="cash", created_by="a")

    def test_topup_with_only_units_is_accepted(self):
        topup = TopupCreate(member_id="x", lunch_units=1, amount=0, payment_method="cash", created_by="a")
        assert topup.lunch_units == 1

    def test_topup_with_only_amount_is_accepted(self):
        topup = TopupCreate(member_id="x", amount=50, payment_method="cash", created_by="a")
        assert topup.amount == 50

    def test_zero_amount_zero_units_refund_is_rejected(self):
        with pytest.raises(ValidationError):
            RefundCreate(member_id="x", refund_amount=0, processed_by="a")

    def test_refund_with_only_units_is_accepted(self):
        refund = RefundCreate(member_id="x", lunch_units=2, refund_amount=0, processed_by="a")
        assert refund.lunch_units == 2


class TestMenuEntryValidation:
    def test_empty_categories_is_rejected(self):
        with pytest.raises(ValidationError):
            MenuEntryCreate(
                date="2026-01-01", meal_type="lunch", categories=[], items=["Dal"], created_by="a"
            )

    def test_empty_items_is_rejected(self):
        with pytest.raises(ValidationError):
            MenuEntryCreate(
                date="2026-01-01", meal_type="lunch", categories=["Normal"], items=[], created_by="a"
            )

    def test_valid_entry_is_accepted(self):
        entry = MenuEntryCreate(
            date="2026-01-01", meal_type="lunch", categories=["Normal"], items=["Dal"], created_by="a"
        )
        assert entry.items == ["Dal"]


class TestFieldConstraints:
    def test_negative_credit_units_are_rejected(self):
        from app.schemas.member import CreditUpdate

        with pytest.raises(ValidationError):
            CreditUpdate(lunch_units=-1)

    def test_blank_name_is_rejected(self):
        with pytest.raises(ValidationError):
            MemberCreate(type="student", name="")

    def test_member_update_allows_partial_fields(self):
        update = MemberUpdate(status="inactive")
        assert update.status == "inactive"
        assert update.name is None
