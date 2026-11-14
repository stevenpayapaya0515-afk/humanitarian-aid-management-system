"""Operational flow contract tests. Uses isolated scripted cursors, never live records.
Run from backend: python -m unittest discover -s tests -p test_operational_flow.py
"""
import os
os.environ.setdefault('JWT_SECRET_KEY', 'isolated-test-key')
import unittest
from unittest.mock import patch
from datetime import date, timedelta
from fastapi import HTTPException
from pydantic import ValidationError
from routes import beneficiaries as reviews, distributions as deliveries, reports, dashboard
from schemas.beneficiaries import BeneficiaryUpdate
from schemas.distributions import DistributionCreate

class Cursor:
    def __init__(self, answers): self.answers=iter(answers); self.calls=[]
    def __enter__(self): return self
    def __exit__(self,*args): pass
    def execute(self,sql,args=()):
        assert sql.count('%s') == len(args), (sql,args)
        self.calls.append((sql,args))
    def fetchone(self): return next(self.answers)
    def fetchall(self): return next(self.answers)
class Connection:
    def __init__(self,cursor): self.value=cursor
    def __enter__(self): return self
    def __exit__(self,*args): pass
    def cursor(self,**kwargs): return self.value

class OperationalFlowTests(unittest.TestCase):
    def setUp(self):
        self.record=dict(household_id=7,assessment_id=7,classification_id=15,
            status='For Review', review_notes='', assessment_data_origin='synthetic',
            model_training_data_origin='psa_apis2019', model_version=reviews.APIS_MODEL_VERSION,
            prediction_status='preliminary', data_origin='synthetic')
        self.decision=dict(status='Approved',review_notes='Reviewed household information and assistance needs.',
            expected_assessment_id=7,expected_classification_id=15,expected_status='For Review',review_confirmed=True)
        self.delivery=dict(beneficiary_id=3,expected_assessment_id=7,expected_classification_id=15,
            aid_type='Food Packs',quantity=2,unit='packs',distribution_date='2026-01-01',batch_code='BATCH-1',notes='')
    def approve(self,record=None,decision=None,latest=7):
        c=Cursor([{'household_id':7},record or self.record,{'assessment_id':latest},
                  {'classification_id':15},{'status':'Approved'}])
        with patch.object(reviews,'get_connection',return_value=Connection(c)):
            value=reviews.update_beneficiary(3,BeneficiaryUpdate(**(decision or self.decision)),{'user_id':1})
        return value,c.calls
    def distribute(self,record=None,data=None,latest=7,prediction=15,duplicate=False):
        c=Cursor([{'household_id':7},record or (self.record|{'status':'Approved'}),
                  {'assessment_id':latest},{'classification_id':prediction},
                  None if duplicate else {'distribution_id':4},{'distribution_id':4}])
        with patch.object(deliveries,'get_connection',return_value=Connection(c)):
            value=deliveries.create_distribution(DistributionCreate(**(data or self.delivery)),{'user_id':1})
        return value,c.calls
    def test_manual_approval_does_not_require_falsely_validating_model(self):
        result,calls=self.approve()
        self.assertEqual(result['status'],'Approved')
        self.assertTrue(any('beneficiary_status_history' in s and 'INSERT' in s for s,a in calls))
        self.assertFalse(any('UPDATE public.vulnerability_classifications' in s for s,a in calls))
    def test_approval_requires_notes_and_review_confirmation(self):
        for patch_values in [{'review_notes':''},{'review_confirmed':False}]:
            with self.subTest(values=patch_values),self.assertRaises(HTTPException) as ctx:
                self.approve(decision=self.decision|patch_values)
            self.assertEqual(ctx.exception.status_code,422)
    def test_approval_rejects_stale_model_assessment_or_screen(self):
        cases=[dict(record=self.record|{'model_version':'old'}),dict(latest=8),
               dict(decision=self.decision|{'expected_status':'Pending'})]
        for case in cases:
            with self.subTest(case=case),self.assertRaises(HTTPException) as ctx:self.approve(**case)
            self.assertEqual(ctx.exception.status_code,409)
    def test_rejection_is_an_explicit_staff_decision(self):
        _,calls=self.approve(decision=self.decision|{'status':'Rejected'})
        update=next(args for sql,args in calls if 'UPDATE public.beneficiaries' in sql)
        self.assertEqual(update[0],'Rejected')
    def test_practice_input_can_never_become_actual_delivery(self):
        _,calls=self.distribute(data=self.delivery|{'delivery_confirmed':True})
        args=next(a for s,a in calls if 'INSERT INTO public.aid_distributions' in s)
        self.assertIs(args[7],True)
        self.assertEqual(args[9:12],(7,15,'synthetic'))
    def test_actual_delivery_needs_confirmation_and_keeps_snapshot(self):
        record=self.record|{'status':'Approved','data_origin':'lgu_authorized'}
        with self.assertRaises(HTTPException) as ctx:self.distribute(record=record)
        self.assertEqual(ctx.exception.status_code,422)
        _,calls=self.distribute(record=record,data=self.delivery|{'delivery_confirmed':True})
        args=next(a for s,a in calls if 'INSERT INTO public.aid_distributions' in s)
        self.assertIs(args[7],False)
        self.assertEqual(args[9:12],(7,15,'lgu_authorized'))
    def test_pending_rejected_and_stale_reviews_cannot_distribute(self):
        cases=[dict(record=self.record|{'status':s}) for s in ['Pending','For Review','Rejected']]
        cases += [dict(latest=8),dict(prediction=16),dict(data=self.delivery|{'expected_classification_id':10})]
        for case in cases:
            with self.subTest(case=case),self.assertRaises(HTTPException) as ctx:self.distribute(**case)
            self.assertEqual(ctx.exception.status_code,409)
    def test_duplicate_batch_returns_conflict(self):
        with self.assertRaises(HTTPException) as ctx:self.distribute(duplicate=True)
        self.assertEqual(ctx.exception.status_code,409)
    def test_future_dates_and_noninteger_quantities_rejected(self):
        for patch_values in [{'distribution_date':(date.today()+timedelta(days=10)).isoformat()},{'quantity':True},{'quantity':1.5}]:
            with self.subTest(values=patch_values),self.assertRaises(ValidationError):
                DistributionCreate(**(self.delivery|patch_values))
    def test_read_and_write_permissions(self):
        for role in ['Admin','Public']:
            with self.subTest(role=role),self.assertRaises(HTTPException):
                deliveries.require_distribution_write({'role':role})
        self.assertEqual(deliveries.require_distribution_read({'role':'Admin'})['role'],'Admin')
    def test_reports_keep_delivery_and_practice_totals_separate(self):
        row={field:0 for field in reports.COUNT_FIELDS}
        row.update(barangay='Test',aid_distributions=2,simulated_distributions=3)
        c=Cursor([[row]])
        with patch.object(reports,'get_connection',return_value=Connection(c)):
            result=reports.get_reports_summary(barangay=None,current_user={'role':'Staff'})
        self.assertEqual(result['totals']['aid_distributions'],2)
        self.assertEqual(result['totals']['simulated_distributions'],3)
        self.assertIn('WHERE d.is_simulation = FALSE',c.calls[0][0])
    def test_history_joins_saved_classification_not_current_beneficiary(self):
        self.assertIn('v.classification_id = d.classification_id',deliveries.DISTRIBUTION_SELECT)
        self.assertNotIn('v.classification_id = b.classification_id',deliveries.DISTRIBUTION_SELECT)

if __name__=='__main__': unittest.main()
