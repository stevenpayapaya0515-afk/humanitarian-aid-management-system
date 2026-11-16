"""Focused tests for Household Registration after PostgreSQL Migration 30."""

import unittest
from datetime import datetime, timezone
from unittest.mock import patch

from fastapi import HTTPException
from pydantic import ValidationError

from schemas.households import (
    HouseholdCreate,
    HouseholdResponse,
    format_household_address,
)
from routes import households


class FakeCursor:
    def __init__(self, *, one=None, all_rows=None):
        self.one = list(one or [])
        self.all_rows = list(all_rows or [])
        self.executed = []

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def execute(self, query, values=None):
        self.executed.append((query, values))

    def fetchone(self):
        return self.one.pop(0)

    def fetchall(self):
        return self.all_rows


class FakeConnection:
    def __init__(self, cursor):
        self.fake_cursor = cursor

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def cursor(self, **kwargs):
        return self.fake_cursor


class HouseholdLocationTests(unittest.TestCase):
    def payload(self, **overrides):
        fields = dict(
            household_head="Head One",
            province="Agusan del Norte",
            city_municipality="Cabadbaran City",
            barangay="Barangay 2",
            purok="Purok 1",
            household_size=2,
            household_member="Member Two",
        )
        fields.update(overrides)
        return fields

    def returned_row(self, **overrides):
        now = datetime(2026, 11, 16, tzinfo=timezone.utc)
        fields = dict(
            household_id=101,
            household_head="Head One",
            province="Agusan del Norte",
            city_municipality="Cabadbaran City",
            barangay="Barangay 2",
            purok="Purok 1",
            household_size=2,
            household_member="Member Two",
            registered_by=7,
            created_at=now,
            updated_at=now,
        )
        fields.update(overrides)
        return fields

    def test_full_address_is_derived_not_stored(self):
        address = format_household_address(
            "Agusan del Norte", "Cabadbaran City", "Barangay 2", "Purok 1"
        )
        self.assertEqual(
            address, "Purok 1, Barangay 2, Cabadbaran City, Agusan del Norte"
        )
        self.assertNotIn("address", HouseholdCreate.model_fields)
        self.assertNotIn("full_address", HouseholdCreate.model_fields)

    def test_optional_purok_and_whitespace_cleaning(self):
        body = HouseholdCreate(**self.payload(
            province=" Agusan del Norte ", purok="   ",
            household_member=" Member Two \r\n\n",
        ))
        self.assertEqual(body.province, "Agusan del Norte")
        self.assertIsNone(body.purok)
        self.assertEqual(body.household_member, "Member Two")
        self.assertEqual(
            format_household_address(body.province, body.city_municipality,
                                     body.barangay, body.purok),
            "Barangay 2, Cabadbaran City, Agusan del Norte",
        )

    def test_blank_required_location_rejected(self):
        for key in ("province", "city_municipality", "barangay"):
            with self.subTest(key=key):
                with self.assertRaises(ValidationError):
                    HouseholdCreate(**self.payload(**{key: "  "}))

    def test_missing_location_rejected(self):
        for key in ("province", "city_municipality"):
            with self.subTest(key=key):
                body = self.payload()
                del body[key]
                with self.assertRaises(ValidationError):
                    HouseholdCreate(**body)

    def test_old_address_input_rejected(self):
        with self.assertRaises(ValidationError):
            HouseholdCreate(**self.payload(address="Old free text"))

    def test_household_size_must_match_member_list(self):
        with self.assertRaises(ValidationError):
            HouseholdCreate(**self.payload(household_size=3))

    def test_read_response_contains_formatted_address(self):
        output = households.prepare_household(self.returned_row())
        self.assertTrue(output["members_complete"])
        self.assertEqual(output["full_address"],
                         "Purok 1, Barangay 2, Cabadbaran City, Agusan del Norte")
        HouseholdResponse.model_validate(output)

    def test_list_reads_only_actual_database_columns(self):
        fake = FakeCursor(all_rows=[self.returned_row()])
        with patch.object(households, "get_connection", return_value=FakeConnection(fake)):
            rows = households.list_households(current_user={"role": "Staff"})
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["full_address"],
                         "Purok 1, Barangay 2, Cabadbaran City, Agusan del Norte")
        self.assertIn("city_municipality", fake.executed[0][0])
        self.assertNotIn(" address", fake.executed[0][0])

    def test_create_inserts_structured_columns(self):
        fake = FakeCursor(one=[self.returned_row()])
        with patch.object(households, "get_connection", return_value=FakeConnection(fake)):
            result = households.create_household(
                HouseholdCreate(**self.payload()), {"role": "Staff", "user_id": 7}
            )
        sql, values = fake.executed[0]
        self.assertIn("province", sql)
        self.assertIn("city_municipality", sql)
        self.assertNotIn(" address", sql)
        self.assertEqual(values, (
            "Head One", "Agusan del Norte", "Cabadbaran City", "Barangay 2",
            "Purok 1", 2, "Member Two", 7,
        ))
        HouseholdResponse.model_validate(result)

    def test_update_rejects_household_size_change_after_assessment(self):
        fake = FakeCursor(one=[{"household_size": 2}, {"has_assessment": True}])
        data = HouseholdCreate(**self.payload(household_size=3,
                                               household_member="Member Two\nMember Three"))
        with patch.object(households, "get_connection", return_value=FakeConnection(fake)):
            with self.assertRaises(HTTPException) as error:
                households.update_household(101, data, {"role": "Staff", "user_id": 7})
        self.assertEqual(error.exception.status_code, 409)
        self.assertNotIn("UPDATE public.households", "\n".join(sql for sql, _ in fake.executed))

    def test_update_location_without_size_change_allowed(self):
        fake = FakeCursor(one=[{"household_size": 2}, self.returned_row(purok="Purok 3")])
        body = HouseholdCreate(**self.payload(purok="Purok 3"))
        with patch.object(households, "get_connection", return_value=FakeConnection(fake)):
            result = households.update_household(101, body,
                                                  {"role": "Staff", "user_id": 7})
        self.assertIn("Purok 3", result["full_address"])
        sql, values = fake.executed[1]
        self.assertIn("province = %s", sql)
        self.assertNotIn("address = %s", sql)
        self.assertEqual(values[-1], 101)
        self.assertEqual(len(fake.executed), 2)

    def test_roles_unchanged(self):
        self.assertEqual(
            households.require_household_access({"role": "Admin"})["role"],
            "Admin",
        )
        with self.assertRaises(HTTPException) as error:
            households.require_household_write({"role": "Admin"})
        self.assertEqual(error.exception.status_code, 403)
        self.assertEqual(
            households.require_household_write({"role": "Staff"})["role"],
            "Staff",
        )


if __name__ == "__main__":
    unittest.main()
