"""Read-only deployment check. Run: python tests/check_operational_setup.py"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from database import get_connection
from ml_service.predict import load_model

def main():
    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute('SET TRANSACTION READ ONLY')
            cursor.execute('SELECT assessment_id, classification_id, assessment_data_origin, beneficiary_status_at_distribution FROM public.aid_distributions LIMIT 0')
            cursor.execute("SELECT COUNT(*) FROM pg_constraint WHERE conrelid='public.aid_distributions'::regclass AND conname IN ('distribution_delivery_source_check','distribution_snapshot_check')")
            if cursor.fetchone()[0] != 2:
                raise RuntimeError('Run database/19_enable_reviewed_distributions.sql first.')
            cursor.execute("SELECT has_table_privilege(current_user,'public.beneficiaries','SELECT') AND has_table_privilege(current_user,'public.beneficiaries','UPDATE'), has_table_privilege(current_user,'public.beneficiary_status_history','SELECT') AND has_table_privilege(current_user,'public.beneficiary_status_history','INSERT'), has_table_privilege(current_user,'public.aid_distributions','SELECT') AND has_table_privilege(current_user,'public.aid_distributions','INSERT')")
            if not all(cursor.fetchone()):
                raise RuntimeError('Application database role lacks required review/distribution permissions.')
    print('PASS: distribution migration and application table permissions')
    load_model()
    print('PASS: APIS model loads in this backend environment')
    print('No household records, reviews, or deliveries were changed.')

if __name__ == '__main__':
    main()
