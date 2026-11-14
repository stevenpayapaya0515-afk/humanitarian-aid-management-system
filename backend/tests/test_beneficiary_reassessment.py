"""Isolated tests: no database connection, email, or production records changed."""
import os
os.environ.setdefault('JWT_SECRET_KEY', 'isolated-unit-test-key')
import unittest
from unittest.mock import patch
from fastapi import HTTPException
from routes import beneficiaries as api
from schemas.beneficiaries import BeneficiaryReassessment

class Cursor:
    def __init__(self, answers):
        self.answers = iter(answers)
        self.calls = []
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def execute(self, sql, args=()):
        assert sql.count('%s') == len(args)
        self.calls.append((sql, args))
    def fetchone(self): return next(self.answers)

class Connection:
    def __init__(self, cursor): self.value = cursor
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def cursor(self, **kwargs): return self.value

class ReassessmentTests(unittest.TestCase):
    def run_case(self, *, status='Pending', current=4, latest=7, prediction=True, expected=4):
        old = dict(household_id=7, assessment_id=current, classification_id=10,
                   status=status, review_notes='Original staff note')
        answers = [{'household_id':7}, old, {'assessment_id':latest},
                   {'classification_id':15 if latest != current else 10,
                    'model_version':api.APIS_MODEL_VERSION} if prediction else None,
                   {'assessment_id':latest}]
        cursor = Cursor(answers)
        with patch.object(api, 'get_connection', return_value=Connection(cursor)):
            result = api.use_latest_assessment(3, BeneficiaryReassessment(
                expected_assessment_id=expected, expected_classification_id=10), {'user_id':1})
        return result, cursor.calls

    def test_relinks_and_preserves_audit_information(self):
        result, calls = self.run_case()
        self.assertEqual(result['assessment_id'], 7)
        updates = [(s,a) for s,a in calls if s.startswith('UPDATE')]
        self.assertEqual(len(updates), 1)
        self.assertEqual(updates[0][1][:2], (7,15))
        audit = [a for s,a in calls if s.startswith('INSERT')][0]
        self.assertIn('from #4 to #7', audit[2])
        self.assertIn('Original staff note', audit[2])
        self.assertIn("status = 'For Review'", updates[0][0])

    def test_repeating_same_link_does_not_duplicate_history(self):
        _, calls = self.run_case(current=7, latest=7, expected=7)
        self.assertFalse(any(s.startswith(('UPDATE','INSERT')) for s,a in calls))

    def test_missing_prediction_does_not_relink(self):
        with self.assertRaises(HTTPException) as ctx: self.run_case(prediction=False)
        self.assertEqual(ctx.exception.status_code,409)

    def test_stale_screen_is_rejected(self):
        with self.assertRaises(HTTPException) as ctx: self.run_case(expected=1)
        self.assertEqual(ctx.exception.status_code,409)

    def test_new_assessment_reopens_a_completed_review_with_history(self):
        for status in ['Approved', 'Rejected']:
            with self.subTest(status=status):
                _, calls = self.run_case(status=status)
                update = next(sql for sql, args in calls if sql.startswith('UPDATE'))
                self.assertIn("status = 'For Review'", update)
                audit = next(args for sql, args in calls if sql.startswith('INSERT'))
                self.assertEqual(audit[1], status)

    def test_only_staff_can_write(self):
        with self.assertRaises(HTTPException) as ctx: api.require_write({'role':'Admin'})
        self.assertEqual(ctx.exception.status_code,403)

if __name__ == '__main__': unittest.main()
