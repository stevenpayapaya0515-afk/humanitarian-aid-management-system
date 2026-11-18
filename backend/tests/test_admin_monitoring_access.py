"""Isolated Admin read-only monitoring permission and list endpoint tests."""

import unittest
from datetime import datetime, timezone
from unittest.mock import patch

from fastapi import HTTPException
from routes import assessments, beneficiaries, distributions, vulnerability


class _Cursor:
    def __init__(self, rows):
        self.rows = rows
        self.query = ""

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def execute(self, query):
        self.query = query

    def fetchall(self):
        return self.rows


class _Connection:
    def __init__(self, cursor):
        self._cursor = cursor

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def cursor(self, **_kwargs):
        return self._cursor


class AdminMonitoringAccessTests(unittest.TestCase):
    def test_admin_read_permissions(self):
        guards = (
            assessments.require_assessment_read,
            beneficiaries.require_read,
            distributions.require_distribution_read,
            vulnerability.require_vulnerability_read,
        )
        for guard in guards:
            with self.subTest(guard=guard.__name__):
                self.assertEqual(guard({"role": "Admin"})["role"], "Admin")
                self.assertEqual(guard({"role": "Staff"})["role"], "Staff")

    def test_admin_cannot_write(self):
        guards = (
            assessments.require_assessment_write,
            beneficiaries.require_write,
            distributions.require_distribution_write,
            vulnerability.require_vulnerability_write,
        )
        for guard in guards:
            with self.subTest(guard=guard.__name__):
                with self.assertRaises(HTTPException) as caught:
                    guard({"role": "Admin"})
                self.assertEqual(caught.exception.status_code, 403)
                self.assertEqual(guard({"role": "Staff"})["role"], "Staff")

    def test_classification_list_is_read_only(self):
        row = {
            "classification_id": 31,
            "assessment_id": 14,
            "household_id": 2,
            "predicted_class": "High",
            "predicted_class_score": 0.72,
            "class_scores": {"Low": 0.02, "Medium": 0.26, "High": 0.72},
            "model_version": "test-version",
            "model_training_data_origin": "psa_apis2022",
            "assessment_data_origin": "lgu_authorized",
            "prediction_status": "preliminary",
            "proxy_details": {"requires_staff_review": True},
            "created_at": datetime.now(timezone.utc),
        }
        cursor = _Cursor([row])
        with patch.object(vulnerability, "get_connection", return_value=_Connection(cursor)):
            result = vulnerability.list_vulnerability_classifications(
                current_user={"role": "Admin"}
            )
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["classification_id"], 31)
        self.assertIn("Staff review", result[0]["warning"])
        self.assertIn("ORDER BY", cursor.query)
        self.assertNotIn("INSERT", cursor.query)
        self.assertNotIn("UPDATE", cursor.query)


if __name__ == "__main__":
    unittest.main()
