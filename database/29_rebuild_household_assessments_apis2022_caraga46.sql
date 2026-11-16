-- AidTrack migration 29 | APIS 2022 CARAGA 46-input assessment schema.
-- Generated from the Nov 16 CARAGA 51-column CSV and current training script.
-- This is a DEVELOPMENT-RESET migration. DO NOT USE ON PRODUCTION/LGU DATA.
-- Run ONLY on aidtrack_db, as database owner, with FastAPI stopped.
--
-- Scope:
--   * Delete prior unlinked assessment rows + prediction history.
--   * Replace prior assessment answer columns with exactly 46 named ML predictors.
--   * Keep assessment_id/household_id/assessment_date/recorded_by/created_at/data_origin.
--   * Preserve source monthly_income, 2 member-roster quality fields, and region_code.
--   * monthly_income_per_capita is STORED GENERATED from monthly_income / family_size.
--   * No Government Feeding or PWD columns.
--   * Does NOT import the APIS survey households into your LGU registration database.
--   * Does NOT delete users, household registrations, beneficiaries or aid distributions.
--   * Aborts BEFORE modifications if beneficiary/distribution records exist.
--   * This schema intentionally BREAKS older FastAPI/Flutter assessment handlers until updated.
--
-- BACK UP YOUR DATABASE FIRST. SQL changes are transactional: errors ROLLBACK.
-- Do NOT use TRUNCATE ... CASCADE.

BEGIN;
DO $$
DECLARE
    unexpected text;
BEGIN
    IF current_database() <> 'aidtrack_db' THEN
        RAISE EXCEPTION 'Wrong database: %. Select aidtrack_db.', current_database();
    END IF;
    IF to_regclass('public.household_assessments') IS NULL
       OR to_regclass('public.vulnerability_classifications') IS NULL
       OR to_regclass('public.beneficiaries') IS NULL
       OR to_regclass('public.aid_distributions') IS NULL THEN
        RAISE EXCEPTION 'Expected AidTrack tables missing; stop and inspect your database.';
    END IF;
    IF EXISTS(SELECT 1 FROM public.beneficiaries)
       OR EXISTS(SELECT 1 FROM public.aid_distributions) THEN
        RAISE EXCEPTION 'Migration stopped: beneficiary or aid-distribution records exist. These are NOT automatically deleted. Review dependencies first.';
    END IF;
    -- If your DB has acquired new columns since the inspected source snapshot,
    -- refuse to drop them without a review.
    SELECT string_agg(column_name, ', ' ORDER BY column_name)
      INTO unexpected
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name='household_assessments'
      AND column_name <> ALL (ARRAY[
          'assessment_id',
          'household_id',
          'assessment_date',
          'recorded_by',
          'created_at',
          'data_origin',
          'age_0_5_count',
          'age_6_17_count',
          'age_18_59_count',
          'age_60_plus_count',
          'senior_citizens_count',
          'pwd_count',
          'monthly_income_range',
          'employment_status',
          'livelihood_type',
          'previous_humanitarian_assistance',
          'beneficiary_status',
          'disaster_affected',
          'housing_damage_level',
          'displaced',
          'roof_material',
          'wall_material',
          'electricity',
          'drinking_water_source',
          'toilet_facility',
          'working_adult_present',
          'apis_single_family',
          'financial_reference_year',
          'financial_single_family',
          'average_family_size',
          'annual_family_income',
          'annual_family_expenditure',
          'annual_food_expenditure',
          'financial_residence_classification',
          'annual_housing_utilities_expenditure',
          'annual_health_expenditure',
          'annual_education_expenditure',
          'annual_transport_expenditure',
          'apis2022_i2',
          'apis2022_i3',
          'apis2022_i4',
          'apis2022_i8',
          'apis2022_ws1',
          'apis2022_ws11a',
          'apis2022_g15_kit',
          'apis2022_g16_nat_disas',
          'apis2022_g16a_evac',
          'apis2022_g16b_recov',
          'apis2022_mem_age_6_11',
          'apis2022_mem_age_12_17',
          'apis2022_monthly_household_income_php',
          'apis2022_extended_answers',
          'apis2022_social_answers',
          'apis2022_program_selections',
          'social_insurance',
          'social_assistance',
          'labor_market_support',
          'government_feeding',
          'philhealth_coverage',
          'government_services_access',
          'social_protection_updated_by',
          'social_protection_updated_at',
          'outer_wall_material',
          'floor_material',
          'electricity_available',
          'disaster_preparedness_kit',
          'experienced_natural_disaster',
          'disaster_evacuated_or_displaced',
          'recovered_from_disaster',
          'owns_car_jeep_van',
          'owns_electric_jeep',
          'owns_motorcycle_tricycle',
          'owns_electric_tricycle',
          'owns_motorized_boat',
          'owns_tractor',
          'owns_washing_machine',
          'owns_stove_with_oven_or_gas_range',
          'owns_induction_stove',
          'owns_refrigerator_freezer',
          'owns_personal_computer',
          'owns_air_conditioner',
          'owns_basic_cellphone',
          'owns_smartphone',
          'owns_microwave_or_oven_toaster',
          'owns_landline_or_wireless_telephone',
          'owns_videoke_magic_sing',
          'owns_television',
          'owns_radio',
          'owns_draft_animals',
          'has_cable_subscription',
          'has_broadband_internet_subscription',
          'has_video_streaming_subscription',
          'philhealth_membership_status',
          'received_philhealth_benefits',
          'family_size',
          'members_age_0_5',
          'members_age_6_11',
          'members_age_12_17',
          'members_age_60_plus',
          'monthly_income_per_capita',
          'bedroom_count',
          'social_insurance_program_count',
          'social_assistance_program_count',
          'labor_market_program_count',
          'government_services_accessed_count',
          'region_code',
          'monthly_income',
          'member_record_count',
          'member_roster_complete'
        ]::text[]);
    IF unexpected IS NOT NULL THEN
        RAISE EXCEPTION 'Unexpected existing assessment columns: %. No changes made; review before migration.', unexpected;
    END IF;
END $$;

-- Delete *only* the existing local assessment and prediction history.
-- Beneficiaries and distributions are verified empty above.
DELETE FROM public.vulnerability_classifications;
DELETE FROM public.household_assessments;

-- Remove legacy synthetic/FIES/APIS-code/JSON/social-protection fields;
-- drop no unrelated tables or columns.
ALTER TABLE public.household_assessments
    DROP COLUMN IF EXISTS monthly_income_per_capita,
    DROP COLUMN IF EXISTS age_0_5_count,
    DROP COLUMN IF EXISTS age_6_17_count,
    DROP COLUMN IF EXISTS age_18_59_count,
    DROP COLUMN IF EXISTS age_60_plus_count,
    DROP COLUMN IF EXISTS senior_citizens_count,
    DROP COLUMN IF EXISTS pwd_count,
    DROP COLUMN IF EXISTS monthly_income_range,
    DROP COLUMN IF EXISTS employment_status,
    DROP COLUMN IF EXISTS livelihood_type,
    DROP COLUMN IF EXISTS previous_humanitarian_assistance,
    DROP COLUMN IF EXISTS beneficiary_status,
    DROP COLUMN IF EXISTS disaster_affected,
    DROP COLUMN IF EXISTS housing_damage_level,
    DROP COLUMN IF EXISTS displaced,
    DROP COLUMN IF EXISTS roof_material,
    DROP COLUMN IF EXISTS wall_material,
    DROP COLUMN IF EXISTS electricity,
    DROP COLUMN IF EXISTS drinking_water_source,
    DROP COLUMN IF EXISTS toilet_facility,
    DROP COLUMN IF EXISTS working_adult_present,
    DROP COLUMN IF EXISTS apis_single_family,
    DROP COLUMN IF EXISTS financial_reference_year,
    DROP COLUMN IF EXISTS financial_single_family,
    DROP COLUMN IF EXISTS average_family_size,
    DROP COLUMN IF EXISTS annual_family_income,
    DROP COLUMN IF EXISTS annual_family_expenditure,
    DROP COLUMN IF EXISTS annual_food_expenditure,
    DROP COLUMN IF EXISTS financial_residence_classification,
    DROP COLUMN IF EXISTS annual_housing_utilities_expenditure,
    DROP COLUMN IF EXISTS annual_health_expenditure,
    DROP COLUMN IF EXISTS annual_education_expenditure,
    DROP COLUMN IF EXISTS annual_transport_expenditure,
    DROP COLUMN IF EXISTS apis2022_i2,
    DROP COLUMN IF EXISTS apis2022_i3,
    DROP COLUMN IF EXISTS apis2022_i4,
    DROP COLUMN IF EXISTS apis2022_i8,
    DROP COLUMN IF EXISTS apis2022_ws1,
    DROP COLUMN IF EXISTS apis2022_ws11a,
    DROP COLUMN IF EXISTS apis2022_g15_kit,
    DROP COLUMN IF EXISTS apis2022_g16_nat_disas,
    DROP COLUMN IF EXISTS apis2022_g16a_evac,
    DROP COLUMN IF EXISTS apis2022_g16b_recov,
    DROP COLUMN IF EXISTS apis2022_mem_age_6_11,
    DROP COLUMN IF EXISTS apis2022_mem_age_12_17,
    DROP COLUMN IF EXISTS apis2022_monthly_household_income_php,
    DROP COLUMN IF EXISTS apis2022_extended_answers,
    DROP COLUMN IF EXISTS apis2022_social_answers,
    DROP COLUMN IF EXISTS apis2022_program_selections,
    DROP COLUMN IF EXISTS social_insurance,
    DROP COLUMN IF EXISTS social_assistance,
    DROP COLUMN IF EXISTS labor_market_support,
    DROP COLUMN IF EXISTS government_feeding,
    DROP COLUMN IF EXISTS philhealth_coverage,
    DROP COLUMN IF EXISTS government_services_access,
    DROP COLUMN IF EXISTS social_protection_updated_by,
    DROP COLUMN IF EXISTS social_protection_updated_at,
    DROP COLUMN IF EXISTS outer_wall_material,
    DROP COLUMN IF EXISTS floor_material,
    DROP COLUMN IF EXISTS electricity_available,
    DROP COLUMN IF EXISTS disaster_preparedness_kit,
    DROP COLUMN IF EXISTS experienced_natural_disaster,
    DROP COLUMN IF EXISTS disaster_evacuated_or_displaced,
    DROP COLUMN IF EXISTS recovered_from_disaster,
    DROP COLUMN IF EXISTS owns_car_jeep_van,
    DROP COLUMN IF EXISTS owns_electric_jeep,
    DROP COLUMN IF EXISTS owns_motorcycle_tricycle,
    DROP COLUMN IF EXISTS owns_electric_tricycle,
    DROP COLUMN IF EXISTS owns_motorized_boat,
    DROP COLUMN IF EXISTS owns_tractor,
    DROP COLUMN IF EXISTS owns_washing_machine,
    DROP COLUMN IF EXISTS owns_stove_with_oven_or_gas_range,
    DROP COLUMN IF EXISTS owns_induction_stove,
    DROP COLUMN IF EXISTS owns_refrigerator_freezer,
    DROP COLUMN IF EXISTS owns_personal_computer,
    DROP COLUMN IF EXISTS owns_air_conditioner,
    DROP COLUMN IF EXISTS owns_basic_cellphone,
    DROP COLUMN IF EXISTS owns_smartphone,
    DROP COLUMN IF EXISTS owns_microwave_or_oven_toaster,
    DROP COLUMN IF EXISTS owns_landline_or_wireless_telephone,
    DROP COLUMN IF EXISTS owns_videoke_magic_sing,
    DROP COLUMN IF EXISTS owns_television,
    DROP COLUMN IF EXISTS owns_radio,
    DROP COLUMN IF EXISTS owns_draft_animals,
    DROP COLUMN IF EXISTS has_cable_subscription,
    DROP COLUMN IF EXISTS has_broadband_internet_subscription,
    DROP COLUMN IF EXISTS has_video_streaming_subscription,
    DROP COLUMN IF EXISTS philhealth_membership_status,
    DROP COLUMN IF EXISTS received_philhealth_benefits,
    DROP COLUMN IF EXISTS family_size,
    DROP COLUMN IF EXISTS members_age_0_5,
    DROP COLUMN IF EXISTS members_age_6_11,
    DROP COLUMN IF EXISTS members_age_12_17,
    DROP COLUMN IF EXISTS members_age_60_plus,
    DROP COLUMN IF EXISTS bedroom_count,
    DROP COLUMN IF EXISTS social_insurance_program_count,
    DROP COLUMN IF EXISTS social_assistance_program_count,
    DROP COLUMN IF EXISTS labor_market_program_count,
    DROP COLUMN IF EXISTS government_services_accessed_count,
    DROP COLUMN IF EXISTS region_code,
    DROP COLUMN IF EXISTS monthly_income,
    DROP COLUMN IF EXISTS member_record_count,
    DROP COLUMN IF EXISTS member_roster_complete;

-- Explicitly recreate exact 46 model inputs and the four source/quality fields.
-- The fifth CSV audit field, household_id, is already the LGU foreign key and
-- is NOT the string household ID from the APIS public-use dataset.
ALTER TABLE public.household_assessments
    ADD COLUMN region_code SMALLINT NOT NULL DEFAULT 16 CHECK (region_code = 16),
    ADD COLUMN monthly_income NUMERIC(14,2) CHECK (monthly_income >= 0),
    ADD COLUMN member_record_count INTEGER CHECK (member_record_count >= 0),
    ADD COLUMN member_roster_complete SMALLINT CHECK (member_roster_complete IN (0,1)),
    ADD COLUMN family_size INTEGER CHECK (family_size >= 1),
    ADD COLUMN members_age_0_5 INTEGER CHECK (members_age_0_5 >= 0),
    ADD COLUMN members_age_6_11 INTEGER CHECK (members_age_6_11 >= 0),
    ADD COLUMN members_age_12_17 INTEGER CHECK (members_age_12_17 >= 0),
    ADD COLUMN members_age_60_plus INTEGER CHECK (members_age_60_plus >= 0),
    ADD COLUMN roof_material SMALLINT CHECK (roof_material BETWEEN 1 AND 8),
    ADD COLUMN outer_wall_material SMALLINT CHECK (outer_wall_material BETWEEN 1 AND 10),
    ADD COLUMN floor_material SMALLINT CHECK (floor_material BETWEEN 1 AND 7),
    ADD COLUMN bedroom_count INTEGER CHECK (bedroom_count >= 0),
    ADD COLUMN electricity_available SMALLINT CHECK (electricity_available IN (1,2)),
    ADD COLUMN drinking_water_source SMALLINT CHECK (drinking_water_source IN (11,12,13,14,21,31,32,41,42,51,61,71,72,81,91,96)),
    ADD COLUMN toilet_facility SMALLINT CHECK (toilet_facility IN (11,12,13,14,15,21,22,23,31,41,51,71,95,96)),
    ADD COLUMN disaster_preparedness_kit SMALLINT CHECK (disaster_preparedness_kit IN (1,2)),
    ADD COLUMN experienced_natural_disaster SMALLINT CHECK (experienced_natural_disaster IN (1,2)),
    ADD COLUMN disaster_evacuated_or_displaced SMALLINT CHECK (disaster_evacuated_or_displaced IN (1,2)),
    ADD COLUMN recovered_from_disaster SMALLINT CHECK (recovered_from_disaster IN (1,2)),
    ADD COLUMN philhealth_membership_status SMALLINT CHECK (philhealth_membership_status IN (1,2,3)),
    ADD COLUMN received_philhealth_benefits SMALLINT CHECK (received_philhealth_benefits IN (1,2)),
    ADD COLUMN owns_car_jeep_van SMALLINT CHECK (owns_car_jeep_van IN (1,2)),
    ADD COLUMN owns_electric_jeep SMALLINT CHECK (owns_electric_jeep IN (1,2)),
    ADD COLUMN owns_motorcycle_tricycle SMALLINT CHECK (owns_motorcycle_tricycle IN (1,2)),
    ADD COLUMN owns_electric_tricycle SMALLINT CHECK (owns_electric_tricycle IN (1,2)),
    ADD COLUMN owns_motorized_boat SMALLINT CHECK (owns_motorized_boat IN (1,2)),
    ADD COLUMN owns_tractor SMALLINT CHECK (owns_tractor IN (1,2)),
    ADD COLUMN owns_washing_machine SMALLINT CHECK (owns_washing_machine IN (1,2)),
    ADD COLUMN owns_stove_with_oven_or_gas_range SMALLINT CHECK (owns_stove_with_oven_or_gas_range IN (1,2)),
    ADD COLUMN owns_induction_stove SMALLINT CHECK (owns_induction_stove IN (1,2)),
    ADD COLUMN owns_refrigerator_freezer SMALLINT CHECK (owns_refrigerator_freezer IN (1,2)),
    ADD COLUMN owns_personal_computer SMALLINT CHECK (owns_personal_computer IN (1,2)),
    ADD COLUMN owns_air_conditioner SMALLINT CHECK (owns_air_conditioner IN (1,2)),
    ADD COLUMN owns_basic_cellphone SMALLINT CHECK (owns_basic_cellphone IN (1,2)),
    ADD COLUMN owns_smartphone SMALLINT CHECK (owns_smartphone IN (1,2)),
    ADD COLUMN owns_microwave_or_oven_toaster SMALLINT CHECK (owns_microwave_or_oven_toaster IN (1,2)),
    ADD COLUMN owns_landline_or_wireless_telephone SMALLINT CHECK (owns_landline_or_wireless_telephone IN (1,2)),
    ADD COLUMN owns_videoke_magic_sing SMALLINT CHECK (owns_videoke_magic_sing IN (1,2)),
    ADD COLUMN owns_television SMALLINT CHECK (owns_television IN (1,2)),
    ADD COLUMN owns_radio SMALLINT CHECK (owns_radio IN (1,2)),
    ADD COLUMN owns_draft_animals SMALLINT CHECK (owns_draft_animals IN (1,2)),
    ADD COLUMN has_cable_subscription SMALLINT CHECK (has_cable_subscription IN (1,2)),
    ADD COLUMN has_broadband_internet_subscription SMALLINT CHECK (has_broadband_internet_subscription IN (1,2)),
    ADD COLUMN has_video_streaming_subscription SMALLINT CHECK (has_video_streaming_subscription IN (1,2)),
    ADD COLUMN social_insurance_program_count INTEGER CHECK (social_insurance_program_count >= 0),
    ADD COLUMN social_assistance_program_count INTEGER CHECK (social_assistance_program_count >= 0),
    ADD COLUMN labor_market_program_count INTEGER CHECK (labor_market_program_count >= 0),
    ADD COLUMN government_services_accessed_count INTEGER CHECK (government_services_accessed_count >= 0),
    ADD COLUMN monthly_income_per_capita NUMERIC(16,6) GENERATED ALWAYS AS (CASE WHEN monthly_income IS NULL OR family_size IS NULL OR family_size <= 0 THEN NULL ELSE ROUND(monthly_income / NULLIF(family_size, 0), 6) END) STORED;

ALTER TABLE public.household_assessments
    ADD CONSTRAINT apis46_roster_consistency CHECK (
        member_roster_complete IS DISTINCT FROM 1 OR
        (member_record_count IS NOT NULL AND family_size IS NOT NULL
         AND member_record_count = family_size)
    ),
    ADD CONSTRAINT apis46_member_ages_fit_family CHECK (
        family_size IS NULL OR
        members_age_0_5 IS NULL OR members_age_6_11 IS NULL OR
        members_age_12_17 IS NULL OR members_age_60_plus IS NULL OR
        (members_age_0_5 + members_age_6_11 + members_age_12_17 +
         members_age_60_plus <= family_size)
    );

-- Original table grants, PK, foreign keys, date uniqueness, and identity survive.
-- Replace the old default that named synthetic data for newly captured LGU assessments
-- ONLY after the backend's provenance policy is updated and agreed with your adviser.

-- Verify all 46 trained feature columns are present and no legacy columns remain.
DO $$
DECLARE
    count_present integer;
    unexpected text;
BEGIN
    SELECT count(*) INTO count_present
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name='household_assessments'
      AND column_name = ANY (ARRAY[
          'roof_material',
          'outer_wall_material',
          'floor_material',
          'electricity_available',
          'drinking_water_source',
          'toilet_facility',
          'disaster_preparedness_kit',
          'experienced_natural_disaster',
          'disaster_evacuated_or_displaced',
          'recovered_from_disaster',
          'owns_car_jeep_van',
          'owns_electric_jeep',
          'owns_motorcycle_tricycle',
          'owns_electric_tricycle',
          'owns_motorized_boat',
          'owns_tractor',
          'owns_washing_machine',
          'owns_stove_with_oven_or_gas_range',
          'owns_induction_stove',
          'owns_refrigerator_freezer',
          'owns_personal_computer',
          'owns_air_conditioner',
          'owns_basic_cellphone',
          'owns_smartphone',
          'owns_microwave_or_oven_toaster',
          'owns_landline_or_wireless_telephone',
          'owns_videoke_magic_sing',
          'owns_television',
          'owns_radio',
          'owns_draft_animals',
          'has_cable_subscription',
          'has_broadband_internet_subscription',
          'has_video_streaming_subscription',
          'philhealth_membership_status',
          'received_philhealth_benefits',
          'family_size',
          'members_age_0_5',
          'members_age_6_11',
          'members_age_12_17',
          'members_age_60_plus',
          'monthly_income_per_capita',
          'bedroom_count',
          'social_insurance_program_count',
          'social_assistance_program_count',
          'labor_market_program_count',
          'government_services_accessed_count'
        ]::text[]);
    IF count_present <> 46 THEN
        RAISE EXCEPTION 'Expected 46 predictor columns; found %', count_present;
    END IF;
    SELECT string_agg(column_name, ', ' ORDER BY column_name)
      INTO unexpected
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name='household_assessments'
      AND column_name <> ALL (ARRAY[
          'assessment_id',
          'household_id',
          'assessment_date',
          'recorded_by',
          'created_at',
          'data_origin',
          'region_code',
          'family_size',
          'members_age_0_5',
          'members_age_6_11',
          'members_age_12_17',
          'members_age_60_plus',
          'monthly_income',
          'monthly_income_per_capita',
          'roof_material',
          'outer_wall_material',
          'floor_material',
          'bedroom_count',
          'electricity_available',
          'drinking_water_source',
          'toilet_facility',
          'disaster_preparedness_kit',
          'experienced_natural_disaster',
          'disaster_evacuated_or_displaced',
          'recovered_from_disaster',
          'philhealth_membership_status',
          'received_philhealth_benefits',
          'owns_car_jeep_van',
          'owns_electric_jeep',
          'owns_motorcycle_tricycle',
          'owns_electric_tricycle',
          'owns_motorized_boat',
          'owns_tractor',
          'owns_washing_machine',
          'owns_stove_with_oven_or_gas_range',
          'owns_induction_stove',
          'owns_refrigerator_freezer',
          'owns_personal_computer',
          'owns_air_conditioner',
          'owns_basic_cellphone',
          'owns_smartphone',
          'owns_microwave_or_oven_toaster',
          'owns_landline_or_wireless_telephone',
          'owns_videoke_magic_sing',
          'owns_television',
          'owns_radio',
          'owns_draft_animals',
          'has_cable_subscription',
          'has_broadband_internet_subscription',
          'has_video_streaming_subscription',
          'social_insurance_program_count',
          'social_assistance_program_count',
          'labor_market_program_count',
          'government_services_accessed_count',
          'member_record_count',
          'member_roster_complete'
        ]::text[]);
    IF unexpected IS NOT NULL THEN
        RAISE EXCEPTION 'Old/unexpected columns remain: %', unexpected;
    END IF;
END $$;

COMMIT;

-- Expect: 0 assessment rows, exactly 56 total columns including metadata,
-- 46 named predictors, and a stored-generated monthly_income_per_capita.
SELECT count(*) AS assessments_after_reset FROM public.household_assessments;
SELECT count(*) AS prior_predictions_after_reset FROM public.vulnerability_classifications;
SELECT count(*) AS columns_after_reset FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'household_assessments';
SELECT column_name, data_type, is_generated
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'household_assessments'
ORDER BY ordinal_position;
