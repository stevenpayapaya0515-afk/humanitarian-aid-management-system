-- Run after migration 20, as the database owner, before deploying updated backend code.
-- Existing records keep NULL values. No rows or classifications are changed.
BEGIN;
ALTER TABLE public.household_assessments
    ADD COLUMN IF NOT EXISTS financial_residence_classification VARCHAR(5),
    ADD COLUMN IF NOT EXISTS annual_housing_utilities_expenditure NUMERIC(14,2),
    ADD COLUMN IF NOT EXISTS annual_health_expenditure NUMERIC(14,2),
    ADD COLUMN IF NOT EXISTS annual_education_expenditure NUMERIC(14,2),
    ADD COLUMN IF NOT EXISTS annual_transport_expenditure NUMERIC(14,2);
ALTER TABLE public.household_assessments
    DROP CONSTRAINT IF EXISTS assessment_detailed_finance_check;
ALTER TABLE public.household_assessments
    ADD CONSTRAINT assessment_detailed_finance_check CHECK (
        (financial_residence_classification IS NULL OR financial_residence_classification IN ('Urban', 'Rural'))
        AND (annual_housing_utilities_expenditure IS NULL OR (annual_housing_utilities_expenditure >= 0 AND annual_housing_utilities_expenditure <> 'NaN'::numeric))
        AND (annual_health_expenditure IS NULL OR (annual_health_expenditure >= 0 AND annual_health_expenditure <> 'NaN'::numeric))
        AND (annual_education_expenditure IS NULL OR (annual_education_expenditure >= 0 AND annual_education_expenditure <> 'NaN'::numeric))
        AND (annual_transport_expenditure IS NULL OR (annual_transport_expenditure >= 0 AND annual_transport_expenditure <> 'NaN'::numeric))
        AND ((financial_residence_classification IS NULL AND annual_housing_utilities_expenditure IS NULL AND annual_health_expenditure IS NULL AND annual_education_expenditure IS NULL AND annual_transport_expenditure IS NULL)
             OR (financial_reference_year IS NOT NULL AND financial_single_family IS TRUE
                 AND average_family_size IS NOT NULL))
        AND ((annual_housing_utilities_expenditure IS NULL AND annual_health_expenditure IS NULL AND annual_education_expenditure IS NULL AND annual_transport_expenditure IS NULL)
             OR (annual_family_expenditure IS NOT NULL
                 AND COALESCE(annual_food_expenditure, 0) + COALESCE(annual_housing_utilities_expenditure, 0) + COALESCE(annual_health_expenditure, 0) + COALESCE(annual_education_expenditure, 0) + COALESCE(annual_transport_expenditure, 0)
                 <= annual_family_expenditure))
    );
COMMIT;
