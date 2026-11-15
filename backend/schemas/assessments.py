"""Household assessment request and response formats for AidTrack."""

from decimal import Decimal
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field, StrictInt, model_validator
from ml_service.label_apis2022_vulnerability import V2_FEATURES


# APIS 2022 survey-code choices observed in the approved 43,517-household data.
# Blank means unknown / survey skip. Do not infer 'No' from a blank.
APIS2022_CATALOG = {'I7': {'name': 'I7',
        'label': 'Number of bedrooms',
        'section': 'Housing and electricity',
        'kind': 'number',
        'options': [],
        'max': 30},
 'I9A': {'name': 'I9A',
         'label': 'Car',
         'section': 'Transportation and livelihood assets',
         'kind': 'code',
         'options': ['1', '2']},
 'I9B': {'name': 'I9B',
         'label': 'Electric jeep',
         'section': 'Transportation and livelihood assets',
         'kind': 'code',
         'options': ['1', '2']},
 'I9C': {'name': 'I9C',
         'label': 'Motorcycle or tricycle',
         'section': 'Transportation and livelihood assets',
         'kind': 'code',
         'options': ['1', '2']},
 'I9D': {'name': 'I9D',
         'label': 'Electric tricycle',
         'section': 'Transportation and livelihood assets',
         'kind': 'code',
         'options': ['1', '2']},
 'I9E': {'name': 'I9E',
         'label': 'Motorboat or banca',
         'section': 'Transportation and livelihood assets',
         'kind': 'code',
         'options': ['1', '2']},
 'I9F': {'name': 'I9F',
         'label': 'Tractor',
         'section': 'Transportation and livelihood assets',
         'kind': 'code',
         'options': ['1', '2']},
 'I9G': {'name': 'I9G',
         'label': 'Washing machine',
         'section': 'Home appliances and equipment',
         'kind': 'code',
         'options': ['1', '2']},
 'I9H': {'name': 'I9H',
         'label': 'Stove with oven or range',
         'section': 'Home appliances and equipment',
         'kind': 'code',
         'options': ['1', '2']},
 'I9I': {'name': 'I9I',
         'label': 'Induction stove',
         'section': 'Home appliances and equipment',
         'kind': 'code',
         'options': ['1', '2']},
 'I9J': {'name': 'I9J',
         'label': 'Refrigerator or freezer',
         'section': 'Home appliances and equipment',
         'kind': 'code',
         'options': ['1', '2']},
 'I9K': {'name': 'I9K',
         'label': 'Personal computer',
         'section': 'Communication and technology',
         'kind': 'code',
         'options': ['1', '2']},
 'I9L': {'name': 'I9L',
         'label': 'Air conditioner',
         'section': 'Home appliances and equipment',
         'kind': 'code',
         'options': ['1', '2']},
 'I9M': {'name': 'I9M',
         'label': 'Basic mobile phone',
         'section': 'Communication and technology',
         'kind': 'code',
         'options': ['1', '2']},
 'I9N': {'name': 'I9N',
         'label': 'Smartphone',
         'section': 'Communication and technology',
         'kind': 'code',
         'options': ['1', '2']},
 'I9O': {'name': 'I9O',
         'label': 'Microwave or oven toaster',
         'section': 'Home appliances and equipment',
         'kind': 'code',
         'options': ['1', '2']},
 'I9P': {'name': 'I9P',
         'label': 'Landline telephone',
         'section': 'Communication and technology',
         'kind': 'code',
         'options': ['1', '2']},
 'I9Q': {'name': 'I9Q',
         'label': 'Video or game console',
         'section': 'Communication and technology',
         'kind': 'code',
         'options': ['1', '2']},
 'I9R': {'name': 'I9R',
         'label': 'Television',
         'section': 'Home appliances and equipment',
         'kind': 'code',
         'options': ['1', '2']},
 'I9S': {'name': 'I9S',
         'label': 'Radio',
         'section': 'Home appliances and equipment',
         'kind': 'code',
         'options': ['1', '2']},
 'I9T': {'name': 'I9T',
         'label': 'Draft animals',
         'section': 'Transportation and livelihood assets',
         'kind': 'code',
         'options': ['1', '2']},
 'I9BA': {'name': 'I9BA',
          'label': 'Cable television subscription',
          'section': 'Communication and technology',
          'kind': 'code',
          'options': ['1', '2']},
 'I9BB': {'name': 'I9BB',
          'label': 'Broadband internet connection',
          'section': 'Communication and technology',
          'kind': 'code',
          'options': ['1', '2']},
 'I9BC': {'name': 'I9BC',
          'label': 'Video streaming subscription',
          'section': 'Communication and technology',
          'kind': 'code',
          'options': ['1', '2']},
 'G13_PHEALTH': {'name': 'G13_PHEALTH',
                 'label': 'PhilHealth coverage',
                 'section': 'Social protection and services',
                 'kind': 'code',
                 'options': ['1', '2', '3']},
 'G13A_ASSISTANCE': {'name': 'G13A_ASSISTANCE',
                     'label': 'PhilHealth benefits received',
                     'section': 'Social protection and services',
                     'kind': 'code',
                     'options': ['1', '2']},
 'G14_AWARE': {'name': 'G14_AWARE',
               'label': 'Aware of LCPU/LSWDO',
               'section': 'Social protection and services',
               'kind': 'code',
               'options': ['1', '2']},
 'G14A_CONSULT': {'name': 'G14A_CONSULT',
                  'label': 'Used LCPU/LSWDO services',
                  'section': 'Social protection and services',
                  'kind': 'code',
                  'options': ['1', '2']},
 'G1_CODE1_COUNT': {'name': 'G1_CODE1_COUNT',
                    'label': 'Social-insurance programs recorded as received (0–5)',
                    'section': 'Social protection and services',
                    'kind': 'number',
                    'options': [],
                    'max': 5},
 'G5_CODE1_COUNT': {'name': 'G5_CODE1_COUNT',
                    'label': 'Social-assistance programs recorded as received (0–8)',
                    'section': 'Social protection and services',
                    'kind': 'number',
                    'options': [],
                    'max': 8},
 'G9_CODE1_COUNT': {'name': 'G9_CODE1_COUNT',
                    'label': 'Labor intervention programs recorded as received (0–4)',
                    'section': 'Social protection and services',
                    'kind': 'number',
                    'options': [],
                    'max': 4},
 'G11_CODE1_COUNT': {'name': 'G11_CODE1_COUNT',
                     'label': 'Government feeding programs recorded as received (0–2)',
                     'section': 'Social protection and services',
                     'kind': 'number',
                     'options': [],
                     'max': 2},
 'H1_CODE1_COUNT': {'name': 'H1_CODE1_COUNT',
                    'label': 'Government-services programs recorded as received (0–12)',
                    'section': 'Social protection and services',
                    'kind': 'number',
                    'options': [],
                    'max': 12}}
# Counts are model inputs; category selections are separately audited details.
APIS2022_PROGRAM_COUNT_MAX = {
    "G1_CODE1_COUNT": 5,
    "G5_CODE1_COUNT": 8,
    "G9_CODE1_COUNT": 4,
    "G11_CODE1_COUNT": 2,
    "H1_CODE1_COUNT": 12,
}
APIS2022_SOCIAL_KEYS = frozenset(['G11_CODE1_COUNT', 'G13A_ASSISTANCE', 'G13_PHEALTH', 'G14A_CONSULT', 'G14_AWARE', 'G1_CODE1_COUNT', 'G5_CODE1_COUNT', 'G9_CODE1_COUNT', 'H1_CODE1_COUNT'])
APIS2022_ASSESSMENT_KEYS = frozenset(["I7", *["I9" + key for key in "ABCDEFGHIJKLMNOPQRST"], "I9BA", "I9BB", "I9BC"])
assert set(APIS2022_CATALOG) | {
    "I2", "I3", "I4", "I8", "WS1", "WS11A", "G15_KIT", "G16_NAT_DISAS",
    "G16A_EVAC", "G16B_RECOV", "FSIZE", "MEM_AGE_0_5", "MEM_AGE_6_11",
    "MEM_AGE_12_17", "MEM_AGE_60_PLUS", "K5_PER_CAPITA",
} == set(V2_FEATURES)


def validate_apis2022_group(answers: dict, allowed: frozenset[str]) -> dict:
    if not isinstance(answers, dict):
        raise ValueError("APIS 2022 answers must be a mapping")
    unknown = set(answers) - allowed
    if unknown:
        raise ValueError(f"Unrecognized APIS 2022 answers: {sorted(unknown)}")
    result = {}
    for key, raw in answers.items():
        if raw is None or raw == "":
            continue  # Unknown remains absent, never a fabricated zero/no.
        spec = APIS2022_CATALOG[key]
        if spec["kind"] == "code":
            code = str(raw).strip().upper()
            if code not in spec["options"]:
                raise ValueError(f"Unsupported survey code for {key}: {code}")
            result[key] = code
        else:
            if isinstance(raw, bool):
                raise ValueError(f"Invalid numeric value for {key}")
            try:
                from decimal import Decimal, InvalidOperation
                number = Decimal(str(raw))
            except (InvalidOperation, ValueError, TypeError):
                raise ValueError(f"Invalid numeric value for {key}") from None
            if (not number.is_finite() or number < 0 or number > 1_000_000_000_000
                    or ("max" in spec and number > spec["max"])):
                raise ValueError(f"Out-of-range value for {key}")
            if key == "I7" and number > 30:
                raise ValueError("Unreasonable bedroom count")
            if number != number.to_integral_value():
                raise ValueError(f"{key} requires a whole number")
            result[key] = int(number)
    return result


class AssessmentCreate(BaseModel):
    household_id: int = Field(ge=1, strict=True)
    assessment_date: date

    age_0_5_count: int = Field(ge=0, strict=True)
    age_6_17_count: int = Field(ge=0, strict=True)
    age_18_59_count: int = Field(ge=0, strict=True)
    age_60_plus_count: int = Field(ge=0, strict=True)
    senior_citizens_count: int = Field(ge=0, strict=True)
    pwd_count: int | None = Field(default=None, ge=0, strict=True)

    monthly_income_range: str | None = Field(default=None, max_length=30)
    employment_status: str | None = Field(default=None, max_length=40)
    livelihood_type: str | None = Field(default=None, max_length=50)
    previous_humanitarian_assistance: bool | None = None
    beneficiary_status: str | None = Field(default=None, max_length=30)

    disaster_affected: bool | None = None
    housing_damage_level: Literal["None", "Minor", "Major", "Destroyed"] | None = None
    displaced: bool | None = None
    data_origin: Literal["synthetic", "lgu_authorized"] = "synthetic"

    roof_material: int | None = Field(default=None, strict=True)
    wall_material: int | None = Field(default=None, strict=True)
    electricity: int | None = Field(default=None, strict=True)
    drinking_water_source: int | None = Field(default=None, strict=True)
    toilet_facility: int | None = Field(default=None, strict=True)
    working_adult_present: int | None = Field(default=None, strict=True)
    apis_single_family: bool | None = Field(default=None, strict=True)

    # Verified APIS 2022-style answers for the current model; not PSA PUF identifiers.
    apis2022_i2: int | None = Field(default=None, strict=True)
    apis2022_i3: int | None = Field(default=None, strict=True)
    apis2022_i4: int | None = Field(default=None, strict=True)
    apis2022_i8: int | None = Field(default=None, strict=True)
    apis2022_ws1: int | None = Field(default=None, strict=True)
    apis2022_ws11a: int | None = Field(default=None, strict=True)
    apis2022_g15_kit: int | None = Field(default=None, strict=True)
    apis2022_g16_nat_disas: int | None = Field(default=None, strict=True)
    apis2022_g16a_evac: int | None = Field(default=None, strict=True)
    apis2022_g16b_recov: int | None = Field(default=None, strict=True)
    apis2022_mem_age_6_11: int | None = Field(default=None, ge=0, strict=True)
    apis2022_mem_age_12_17: int | None = Field(default=None, ge=0, strict=True)
    apis2022_monthly_household_income_php: Decimal | None = Field(
        default=None, ge=0, max_digits=14, decimal_places=2
    )

    apis2022_extended_answers: dict[str, str | int | float | None] = Field(default_factory=dict)
    apis2022_social_answers: dict[str, str | int | float | None] = Field(default_factory=dict)
    # The five original numeric counts remain the Random Forest inputs.
    # Detailed selected categories are persisted for editing and audit only.
    apis2022_program_selections: dict[str, list[StrictInt]] = Field(default_factory=dict)

    @model_validator(mode="after")
    def validate_extended_survey_answers(self):
        self.apis2022_extended_answers = validate_apis2022_group(
            self.apis2022_extended_answers, APIS2022_ASSESSMENT_KEYS)
        # Reuse the existing social schema: same values, rules and survey skips
        # whether entered during assessment creation or edited later.
        from schemas.vulnerability import APIS2022SocialInputs
        self.apis2022_social_answers = APIS2022SocialInputs.model_validate(
            {"answers": self.apis2022_social_answers}
        ).answers
        for key, choices in self.apis2022_program_selections.items():
            maximum = APIS2022_PROGRAM_COUNT_MAX.get(key)
            if maximum is None:
                raise ValueError(f"Unknown program selection category: {key}")
            if (len(choices) != len(set(choices)) or
                    any(choice < 1 or choice > maximum for choice in choices)):
                raise ValueError(f"Invalid or duplicate selected category for {key}")
            if self.apis2022_social_answers.get(key) != len(choices):
                raise ValueError(f"Program selection total does not match {key}")
        return self

    # Optional financial history adapted from FIES concepts, not an imported PSA record.
    financial_reference_year: int | None = Field(default=None, ge=1900, strict=True)
    financial_single_family: bool | None = Field(default=None, strict=True)
    average_family_size: Decimal | None = Field(default=None, ge=1, max_digits=7, decimal_places=2)
    annual_family_income: Decimal | None = Field(default=None, max_digits=14, decimal_places=2)
    annual_family_expenditure: Decimal | None = Field(default=None, ge=0, max_digits=14, decimal_places=2)
    annual_food_expenditure: Decimal | None = Field(default=None, ge=0, max_digits=14, decimal_places=2)

    # Residence classification and spending refer to the same financial year.
    financial_residence_classification: Literal["Urban", "Rural"] | None = None
    annual_housing_utilities_expenditure: Decimal | None = Field(default=None, ge=0, max_digits=14, decimal_places=2)
    annual_health_expenditure: Decimal | None = Field(default=None, ge=0, max_digits=14, decimal_places=2)
    annual_education_expenditure: Decimal | None = Field(default=None, ge=0, max_digits=14, decimal_places=2)
    annual_transport_expenditure: Decimal | None = Field(default=None, ge=0, max_digits=14, decimal_places=2)

    @model_validator(mode="after")
    def validate_apis2022_inputs(self):
        required = (
            "i2", "i3", "i4", "i8", "ws1", "ws11a", "g15_kit",
            "g16_nat_disas", "mem_age_6_11", "mem_age_12_17",
            "monthly_household_income_php",
        )
        all_fields = (*required, "g16a_evac", "g16b_recov")
        supplied = any(getattr(self, f"apis2022_{name}") is not None for name in all_fields)
        if not supplied:
            return self
        missing = [name for name in required if getattr(self, f"apis2022_{name}") is None]
        if missing:
            raise ValueError(f"APIS 2022 input is incomplete: {', '.join(missing)}")
        if self.apis_single_family is not True:
            raise ValueError("Confirm a single family before recording APIS 2022 monthly income.")
        if self.apis2022_mem_age_6_11 + self.apis2022_mem_age_12_17 != self.age_6_17_count:
            raise ValueError("APIS ages 6–11 and 12–17 must match the saved age 6–17 total.")
        # Apply the same code validation as the prediction endpoint.
        from schemas.vulnerability import APIS2022PredictionRequest
        APIS2022PredictionRequest.model_validate({
            "I2": self.apis2022_i2,
            "I3": self.apis2022_i3,
            "I4": self.apis2022_i4,
            "I8": self.apis2022_i8,
            "WS1": self.apis2022_ws1,
            "WS11A": self.apis2022_ws11a,
            "G15_KIT": self.apis2022_g15_kit,
            "G16_NAT_DISAS": self.apis2022_g16_nat_disas,
            "G16A_EVAC": self.apis2022_g16a_evac,
            "G16B_RECOV": self.apis2022_g16b_recov,
            "MEM_AGE_0_5": self.age_0_5_count,
            "MEM_AGE_6_11": self.apis2022_mem_age_6_11,
            "MEM_AGE_12_17": self.apis2022_mem_age_12_17,
            "MEM_AGE_18_59": self.age_18_59_count,
            "MEM_AGE_60_PLUS": self.age_60_plus_count,
            "monthly_household_income_php": self.apis2022_monthly_household_income_php,
        })
        return self

    @model_validator(mode="after")
    def check_financial_history(self):
        values = (self.average_family_size, self.annual_family_income,
                  self.annual_family_expenditure, self.annual_food_expenditure)
        detailed = (self.annual_housing_utilities_expenditure, self.annual_health_expenditure, self.annual_education_expenditure, self.annual_transport_expenditure)
        supplied = self.financial_residence_classification is not None or any(v is not None for v in detailed) or self.financial_reference_year is not None or self.financial_single_family is not None or any(v is not None for v in values)
        if not supplied:
            return self  # Legacy assessments remain readable; unknown is not zero.
        if self.financial_reference_year is None or self.financial_reference_year >= self.assessment_date.year:
            raise ValueError("Financial history must identify a completed calendar year before the assessment year.")
        if self.financial_single_family is not True:
            raise ValueError("Financial amounts must refer to one family sharing income and expenses during that year.")
        if self.average_family_size is None:
            raise ValueError("Enter the average family size for the reference year.")
        if all(v is None for v in values[1:]):
            raise ValueError("Enter at least one known annual financial amount, or omit financial history.")
        if self.annual_food_expenditure is not None and self.annual_family_expenditure is not None and self.annual_food_expenditure > self.annual_family_expenditure:
            raise ValueError("Food expenditure cannot exceed total expenditure for the same year.")
        if any(v is not None for v in detailed):
            if self.annual_family_expenditure is None:
                raise ValueError("Enter total annual expenditure when recording spending categories.")
            # Missing components remain NULL; sum only the known disjoint categories.
            known = [v for v in (self.annual_food_expenditure, *detailed) if v is not None]
            if sum(known, Decimal("0")) > self.annual_family_expenditure:
                raise ValueError("Known food, housing/utilities, health, education and transport expenses cannot exceed total annual expenditure.")
        return self

    @model_validator(mode="after")
    def check_apis_codes(self):
        # Historical assessment codes; never reinterpret as APIS 2022 inputs.
        VALID = {
            "roof_material": {1, 2, 3, 4, 5, 6},
            "wall_material": {1, 2, 3, 4, 5, 6},
            "electricity": {1, 2},
            "drinking_water_source": {11, 12, 13, 14, 21, 31, 32, 41, 42, 51, 61, 71, 72, 81, 91, 92},
            "toilet_facility": {11, 12, 13, 14, 21, 22, 23, 31, 41, 51, 95},
            "working_adult_present": {0, 1},
        }
        for name, codes in VALID.items():
            value = getattr(self, name)
            if value is not None and value not in codes:
                raise ValueError(f"Unsupported {name} code; use null for unknown/not applicable.")
        if self.working_adult_present == 1 and self.age_18_59_count + self.age_60_plus_count == 0:
            raise ValueError("A working adult requires at least one member aged 18 or above.")
        return self

    @model_validator(mode="after")
    def check_age_and_pwd_counts(self):
        total = (
            self.age_0_5_count + self.age_6_17_count
            + self.age_18_59_count + self.age_60_plus_count
        )
        if total < 1:
            raise ValueError("An assessment must include at least one person.")
        if self.senior_citizens_count != self.age_60_plus_count:
            raise ValueError("Senior citizen count must match the age 60+ count.")
        if self.pwd_count is not None and self.pwd_count > total:
            raise ValueError("PWD count cannot exceed household population.")
        return self


class AssessmentResponse(AssessmentCreate):
    has_classification: bool = False
    assessment_id: int
    household_head: str
    barangay: str
    recorded_by: int
    created_at: datetime
