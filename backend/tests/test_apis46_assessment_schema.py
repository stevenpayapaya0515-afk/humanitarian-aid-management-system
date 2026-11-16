"""Offline validation for the APIS 2022 CARAGA Migration 29 assessment schema.

Run in backend/: python -m unittest discover -s tests -p test_apis46_assessment_schema.py -v
No PostgreSQL connection required.
"""
import csv
import unittest
from datetime import date
from decimal import Decimal
from pathlib import Path

from pydantic import ValidationError
from schemas.assessments import (
    APIS2022_FEATURES,
    APIS2022_STORED_INPUT_FIELDS,
    APIS2022_WRITE_FIELDS,
    AssessmentCreate,
    AssessmentResponse,
    AssessmentSocialUpdate,
)


class APIS46AssessmentTests(unittest.TestCase):
    def setUp(self):
        self.base = {"household_id": 1, "assessment_date": "2026-11-16"}

    def test_exact_model_feature_count(self):
        self.assertEqual(len(APIS2022_FEATURES), 46)
        self.assertEqual(len(set(APIS2022_FEATURES)), 46)
        self.assertEqual(len(APIS2022_WRITE_FIELDS), 46)
        self.assertNotIn("monthly_income_per_capita", APIS2022_WRITE_FIELDS)
        self.assertIn("monthly_income", APIS2022_WRITE_FIELDS)

    def test_matches_csv_headers(self):
        csv_path = (Path(__file__).resolve().parents[1] / "ml_service" / "datasets"
                    / "apis2022_household_records.csv")
        with csv_path.open(encoding="utf-8-sig", newline="") as f:
            headers = csv.DictReader(f).fieldnames
        self.assertEqual(len(headers), 51)
        self.assertEqual(
            set(headers),
            set(APIS2022_FEATURES) | {
                "region_code", "household_id", "monthly_income",
                "member_record_count", "member_roster_complete"
            },
        )

    def test_named_inputs_and_income(self):
        value = AssessmentCreate.model_validate({
            **self.base, "roof_material": 7, "electricity_available": 2,
            "family_size": 3, "monthly_income": "10000.50",
        })
        self.assertEqual(value.monthly_income, Decimal("10000.50"))
        self.assertEqual(value.region_code, 16)
        self.assertEqual(value.roof_material, 7)

    def test_unknown_not_converted_to_no(self):
        obj = AssessmentCreate.model_validate(self.base)
        self.assertIsNone(obj.experienced_natural_disaster)
        self.assertIsNone(obj.monthly_income)
        self.assertIsNone(obj.disaster_preparedness_kit)

    def test_invalid_codes_rejected(self):
        for data in (
            {"roof_material": 10},
            {"drinking_water_source": 999},
            {"electricity_available": 0},
            {"philhealth_membership_status": "1"},
            {"experienced_natural_disaster": 2, "disaster_evacuated_or_displaced": 1},
        ):
            with self.subTest(data=data), self.assertRaises(ValidationError):
                AssessmentCreate.model_validate({**self.base, **data})

    def test_removed_fields_and_generated_field_rejected(self):
        for name in ("pwd_count", "government_feeding", "apis2022_i2",
                     "monthly_income_per_capita", "apis2022_social_answers"):
            with self.subTest(name=name), self.assertRaises(ValidationError):
                AssessmentCreate.model_validate({**self.base, name: 1})

    def test_social_input_validation(self):
        self.assertEqual(
            AssessmentSocialUpdate(social_assistance_program_count=2)
            .social_assistance_program_count,
            2,
        )
        with self.assertRaises(ValidationError):
            AssessmentSocialUpdate(philhealth_membership_status=5)


if __name__ == "__main__":
    unittest.main()
