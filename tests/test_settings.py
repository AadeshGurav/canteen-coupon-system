"""Validation tests for SettingsUpdate — local_timezone, upi_id, and
upi_payee_name are admin-editable settings, not env config (see
app/routers/settings.py), so their validation is the actual boundary."""

import pytest
from pydantic import ValidationError

from app.routers.settings import SettingsUpdate


def test_valid_iana_timezone_is_accepted():
    update = SettingsUpdate(local_timezone="Asia/Kolkata")
    assert update.local_timezone == "Asia/Kolkata"


def test_utc_is_accepted():
    update = SettingsUpdate(local_timezone="UTC")
    assert update.local_timezone == "UTC"


def test_garbage_timezone_name_is_rejected():
    with pytest.raises(ValidationError):
        SettingsUpdate(local_timezone="Not/A_Real_Zone")


def test_upi_fields_are_plain_optional_strings():
    update = SettingsUpdate(upi_id="canteen@upi", upi_payee_name="School Canteen")
    assert update.upi_id == "canteen@upi"
    assert update.upi_payee_name == "School Canteen"


def test_partial_update_leaves_other_fields_unset():
    update = SettingsUpdate(upi_id="canteen@upi")
    assert update.local_timezone is None
    assert update.upi_payee_name is None
