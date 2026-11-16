"""APIS 2022 CARAGA household assessment API formats (Migration 29).

All survey codes use the original PSA PUF coding, not UI labels.
None means unknown/not answered; never turn missing answers into 0 or No.
"""
from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

APIS2022_CATEGORICAL_FEATURES = (
    "roof_material",
    "outer_wall_material",
    "floor_material",
    "electricity_available",
    "drinking_water_source",
    "toilet_facility",
    "disaster_preparedness_kit",
    "experienced_natural_disaster",
    "disaster_evacuated_or_displaced",
    "recovered_from_disaster",
    "owns_car_jeep_van",
    "owns_electric_jeep",
    "owns_motorcycle_tricycle",
    "owns_electric_tricycle",
    "owns_motorized_boat",
    "owns_tractor",
    "owns_washing_machine",
    "owns_stove_with_oven_or_gas_range",
    "owns_induction_stove",
    "owns_refrigerator_freezer",
    "owns_personal_computer",
    "owns_air_conditioner",
    "owns_basic_cellphone",
    "owns_smartphone",
    "owns_microwave_or_oven_toaster",
    "owns_landline_or_wireless_telephone",
    "owns_videoke_magic_sing",
    "owns_television",
    "owns_radio",
    "owns_draft_animals",
    "has_cable_subscription",
    "has_broadband_internet_subscription",
    "has_video_streaming_subscription",
    "philhealth_membership_status",
    "received_philhealth_benefits",
)
APIS2022_NUMERIC_FEATURES = (
    "family_size",
    "members_age_0_5",
    "members_age_6_11",
    "members_age_12_17",
    "members_age_60_plus",
    "monthly_income_per_capita",
    "bedroom_count",
    "social_insurance_program_count",
    "social_assistance_program_count",
    "labor_market_program_count",
    "government_services_accessed_count",
)
APIS2022_FEATURES = APIS2022_CATEGORICAL_FEATURES + APIS2022_NUMERIC_FEATURES
APIS2022_STORED_INPUT_FIELDS = tuple(x for x in APIS2022_FEATURES if x != "monthly_income_per_capita")
APIS2022_EXTRA_FIELDS = ("monthly_income",)
APIS2022_WRITE_FIELDS = APIS2022_STORED_INPUT_FIELDS + APIS2022_EXTRA_FIELDS
assert len(APIS2022_FEATURES) == 46 and len(set(APIS2022_FEATURES)) == 46

APIS2022_CODE_CHOICES = {
    "roof_material": (1, 2, 3, 4, 5, 6, 7, 8),
    "outer_wall_material": (1, 2, 3, 4, 5, 6, 7, 8, 9, 10),
    "floor_material": (1, 2, 3, 4, 5, 6, 7),
    "electricity_available": (1, 2),
    "drinking_water_source": (11, 12, 13, 14, 21, 31, 32, 41, 42, 51, 61, 71, 72, 81, 91, 96),
    "toilet_facility": (11, 12, 13, 14, 15, 21, 22, 23, 31, 41, 51, 71, 95, 96),
    "disaster_preparedness_kit": (1, 2),
    "experienced_natural_disaster": (1, 2),
    "disaster_evacuated_or_displaced": (1, 2),
    "recovered_from_disaster": (1, 2),
    "owns_car_jeep_van": (1, 2),
    "owns_electric_jeep": (1, 2),
    "owns_motorcycle_tricycle": (1, 2),
    "owns_electric_tricycle": (1, 2),
    "owns_motorized_boat": (1, 2),
    "owns_tractor": (1, 2),
    "owns_washing_machine": (1, 2),
    "owns_stove_with_oven_or_gas_range": (1, 2),
    "owns_induction_stove": (1, 2),
    "owns_refrigerator_freezer": (1, 2),
    "owns_personal_computer": (1, 2),
    "owns_air_conditioner": (1, 2),
    "owns_basic_cellphone": (1, 2),
    "owns_smartphone": (1, 2),
    "owns_microwave_or_oven_toaster": (1, 2),
    "owns_landline_or_wireless_telephone": (1, 2),
    "owns_videoke_magic_sing": (1, 2),
    "owns_television": (1, 2),
    "owns_radio": (1, 2),
    "owns_draft_animals": (1, 2),
    "has_cable_subscription": (1, 2),
    "has_broadband_internet_subscription": (1, 2),
    "has_video_streaming_subscription": (1, 2),
    "philhealth_membership_status": (1, 2, 3),
    "received_philhealth_benefits": (1, 2),
}

APIS2022_FEATURE_CATALOG = (
    {'name': 'roof_material', 'label': 'Roof Material', 'description': 'I2 - Type of construction materials of the roof', 'kind': 'code', 'options': [1, 2, 3, 4, 5, 6, 7, 8]},
    {'name': 'outer_wall_material', 'label': 'Outer Wall Material', 'description': 'I3 - Type of construction materials of the outer wall', 'kind': 'code', 'options': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]},
    {'name': 'floor_material', 'label': 'Floor Material', 'description': 'I4 - Type of construction materials of the floor', 'kind': 'code', 'options': [1, 2, 3, 4, 5, 6, 7]},
    {'name': 'electricity_available', 'label': 'Electricity Available', 'description': 'I8 - Is there any electricity in the building/house', 'kind': 'code', 'options': [1, 2]},
    {'name': 'drinking_water_source', 'label': 'Drinking Water Source', 'description': "WS1 - Family's main source of drinking water", 'kind': 'code', 'options': [11, 12, 13, 14, 21, 31, 32, 41, 42, 51, 61, 71, 72, 81, 91, 96]},
    {'name': 'toilet_facility', 'label': 'Toilet Facility', 'description': 'WS11A - Kind of toilet facility', 'kind': 'code', 'options': [11, 12, 13, 14, 15, 21, 22, 23, 31, 41, 51, 71, 95, 96]},
    {'name': 'disaster_preparedness_kit', 'label': 'Disaster Preparedness Kit', 'description': 'G15 - Does your family have a disaster preparedness kit/emergency go bag?', 'kind': 'code', 'options': [1, 2]},
    {'name': 'experienced_natural_disaster', 'label': 'Experienced Natural Disaster', 'description': 'G16 - Experienced natural disasters', 'kind': 'code', 'options': [1, 2]},
    {'name': 'disaster_evacuated_or_displaced', 'label': 'Disaster Evacuated Or Displaced', 'description': 'G16a - Experienced displacements/evacuation due to natural disasters', 'kind': 'code', 'options': [1, 2]},
    {'name': 'recovered_from_disaster', 'label': 'Recovered From Disaster', 'description': 'G16b - Does your household recovered from natural disaster/calamity or armed conflict ?', 'kind': 'code', 'options': [1, 2]},
    {'name': 'owns_car_jeep_van', 'label': 'Owns Car Jeep Van', 'description': 'I9a - Own car, jeep, van', 'kind': 'code', 'options': [1, 2]},
    {'name': 'owns_electric_jeep', 'label': 'Owns Electric Jeep', 'description': 'I9b - Own e-jeep', 'kind': 'code', 'options': [1, 2]},
    {'name': 'owns_motorcycle_tricycle', 'label': 'Owns Motorcycle Tricycle', 'description': 'I9c - Own motorcycle, tricycle', 'kind': 'code', 'options': [1, 2]},
    {'name': 'owns_electric_tricycle', 'label': 'Owns Electric Tricycle', 'description': 'I9d - Own e-trike', 'kind': 'code', 'options': [1, 2]},
    {'name': 'owns_motorized_boat', 'label': 'Owns Motorized Boat', 'description': 'I9e - Own motorized boat/banca', 'kind': 'code', 'options': [1, 2]},
    {'name': 'owns_tractor', 'label': 'Owns Tractor', 'description': 'I9f - Own tractor', 'kind': 'code', 'options': [1, 2]},
    {'name': 'owns_washing_machine', 'label': 'Owns Washing Machine', 'description': 'I9g - Own washing machine', 'kind': 'code', 'options': [1, 2]},
    {'name': 'owns_stove_with_oven_or_gas_range', 'label': 'Owns Stove With Oven Or Gas Range', 'description': 'I9h - Own stove with oven/gas range', 'kind': 'code', 'options': [1, 2]},
    {'name': 'owns_induction_stove', 'label': 'Owns Induction Stove', 'description': 'I9i- Own induction stove', 'kind': 'code', 'options': [1, 2]},
    {'name': 'owns_refrigerator_freezer', 'label': 'Owns Refrigerator Freezer', 'description': 'I9j- Own refrigerator/freezer', 'kind': 'code', 'options': [1, 2]},
    {'name': 'owns_personal_computer', 'label': 'Owns Personal Computer', 'description': 'I9k - Own personal computer', 'kind': 'code', 'options': [1, 2]},
    {'name': 'owns_air_conditioner', 'label': 'Owns Air Conditioner', 'description': 'I9l - Own aircon', 'kind': 'code', 'options': [1, 2]},
    {'name': 'owns_basic_cellphone', 'label': 'Owns Basic Cellphone', 'description': 'I9m - Own basic cellphone', 'kind': 'code', 'options': [1, 2]},
    {'name': 'owns_smartphone', 'label': 'Owns Smartphone', 'description': 'I9n - Own smartphone', 'kind': 'code', 'options': [1, 2]},
    {'name': 'owns_microwave_or_oven_toaster', 'label': 'Owns Microwave Or Oven Toaster', 'description': 'I9o - Own microwave/oven toaster', 'kind': 'code', 'options': [1, 2]},
    {'name': 'owns_landline_or_wireless_telephone', 'label': 'Owns Landline Or Wireless Telephone', 'description': 'I9p - Own landline/wireless telephone', 'kind': 'code', 'options': [1, 2]},
    {'name': 'owns_videoke_magic_sing', 'label': 'Owns Videoke Magic Sing', 'description': 'I9q - Own videoke/magic sing', 'kind': 'code', 'options': [1, 2]},
    {'name': 'owns_television', 'label': 'Owns Television', 'description': 'I9r - Own television', 'kind': 'code', 'options': [1, 2]},
    {'name': 'owns_radio', 'label': 'Owns Radio', 'description': 'I9s - Own radio', 'kind': 'code', 'options': [1, 2]},
    {'name': 'owns_draft_animals', 'label': 'Owns Draft Animals', 'description': 'I9t - Own draft animals', 'kind': 'code', 'options': [1, 2]},
    {'name': 'has_cable_subscription', 'label': 'Has Cable Subscription', 'description': 'I9Ba - CABLE (e.g SKY cable, Destiny, Cignal, etc)', 'kind': 'code', 'options': [1, 2]},
    {'name': 'has_broadband_internet_subscription', 'label': 'Has Broadband Internet Subscription', 'description': 'I9Bb - BROADBAND INTERNET FIBER INTERNET/DSL', 'kind': 'code', 'options': [1, 2]},
    {'name': 'has_video_streaming_subscription', 'label': 'Has Video Streaming Subscription', 'description': 'I9Bc - VIDEO STREAMING SERVICES (e.g NETFLIX/IFLIX/HOOQ/iWant/Viu, etc)', 'kind': 'code', 'options': [1, 2]},
    {'name': 'philhealth_membership_status', 'label': 'Philhealth Membership Status', 'description': 'G13 - Philhealth member', 'kind': 'code', 'options': [1, 2, 3]},
    {'name': 'received_philhealth_benefits', 'label': 'Received Philhealth Benefits', 'description': 'G13a - Availed/received assistance/benefits/payments from Philhealth', 'kind': 'code', 'options': [1, 2]},
    {'name': 'family_size', 'label': 'Family Size', 'description': 'Family Size', 'kind': 'number', 'options': []},
    {'name': 'members_age_0_5', 'label': 'Members Age 0 5', 'description': 'Count of observed member records in this age band. Use only when member_roster_complete=1 for household-wide interpretation.', 'kind': 'number', 'options': []},
    {'name': 'members_age_6_11', 'label': 'Members Age 6 11', 'description': 'Count of observed member records in this age band. Use only when member_roster_complete=1 for household-wide interpretation.', 'kind': 'number', 'options': []},
    {'name': 'members_age_12_17', 'label': 'Members Age 12 17', 'description': 'Count of observed member records in this age band. Use only when member_roster_complete=1 for household-wide interpretation.', 'kind': 'number', 'options': []},
    {'name': 'members_age_60_plus', 'label': 'Members Age 60 Plus', 'description': 'Count of observed member records in this age band. Use only when member_roster_complete=1 for household-wide interpretation.', 'kind': 'number', 'options': []},
    {'name': 'monthly_income_per_capita', 'label': 'Monthly Income Per Capita', 'description': 'monthly_income / family_size; rounded to 6 decimal places; matches the previous model definition, not an official poverty label.', 'kind': 'derived', 'options': []},
    {'name': 'bedroom_count', 'label': 'Bedroom Count', 'description': 'I7 - Number of bedrooms', 'kind': 'number', 'options': []},
    {'name': 'social_insurance_program_count', 'label': 'Social Insurance Program Count', 'description': 'Count of distinct G1 categories answered 1 (Yes), not a count of people or payments. Blank if any category is missing/invalid. See APIS dictionary for program list.', 'kind': 'number', 'options': []},
    {'name': 'social_assistance_program_count', 'label': 'Social Assistance Program Count', 'description': 'Count of distinct G5 categories answered 1 (Yes), not a count of people or payments. Blank if any category is missing/invalid. See APIS dictionary for program list.', 'kind': 'number', 'options': []},
    {'name': 'labor_market_program_count', 'label': 'Labor Market Program Count', 'description': 'Count of distinct G9 categories answered 1 (Yes), not a count of people or payments. Blank if any category is missing/invalid. See APIS dictionary for program list.', 'kind': 'number', 'options': []},
    {'name': 'government_services_accessed_count', 'label': 'Government Services Accessed Count', 'description': 'Count of distinct H1 categories answered 1 (Yes), not a count of people or payments. Blank if any category is missing/invalid. See APIS dictionary for program list.', 'kind': 'number', 'options': []},
)

class AssessmentCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    household_id: int = Field(ge=1, strict=True)
    assessment_date: date
    # Default is test/prototype provenance; only claim LGU-authorized for verified LGU data.
    data_origin: Literal["synthetic", "lgu_authorized"] = "synthetic"
    region_code: Literal[16] = 16
    # If family_size is omitted, backend reads it from the household registration.
    family_size: int | None = Field(default=None, ge=1, strict=True)
    monthly_income: Decimal | None = Field(default=None, ge=0, max_digits=14, decimal_places=2)
    roof_material: int | None = Field(default=None, strict=True)
    outer_wall_material: int | None = Field(default=None, strict=True)
    floor_material: int | None = Field(default=None, strict=True)
    electricity_available: int | None = Field(default=None, strict=True)
    drinking_water_source: int | None = Field(default=None, strict=True)
    toilet_facility: int | None = Field(default=None, strict=True)
    disaster_preparedness_kit: int | None = Field(default=None, strict=True)
    experienced_natural_disaster: int | None = Field(default=None, strict=True)
    disaster_evacuated_or_displaced: int | None = Field(default=None, strict=True)
    recovered_from_disaster: int | None = Field(default=None, strict=True)
    owns_car_jeep_van: int | None = Field(default=None, strict=True)
    owns_electric_jeep: int | None = Field(default=None, strict=True)
    owns_motorcycle_tricycle: int | None = Field(default=None, strict=True)
    owns_electric_tricycle: int | None = Field(default=None, strict=True)
    owns_motorized_boat: int | None = Field(default=None, strict=True)
    owns_tractor: int | None = Field(default=None, strict=True)
    owns_washing_machine: int | None = Field(default=None, strict=True)
    owns_stove_with_oven_or_gas_range: int | None = Field(default=None, strict=True)
    owns_induction_stove: int | None = Field(default=None, strict=True)
    owns_refrigerator_freezer: int | None = Field(default=None, strict=True)
    owns_personal_computer: int | None = Field(default=None, strict=True)
    owns_air_conditioner: int | None = Field(default=None, strict=True)
    owns_basic_cellphone: int | None = Field(default=None, strict=True)
    owns_smartphone: int | None = Field(default=None, strict=True)
    owns_microwave_or_oven_toaster: int | None = Field(default=None, strict=True)
    owns_landline_or_wireless_telephone: int | None = Field(default=None, strict=True)
    owns_videoke_magic_sing: int | None = Field(default=None, strict=True)
    owns_television: int | None = Field(default=None, strict=True)
    owns_radio: int | None = Field(default=None, strict=True)
    owns_draft_animals: int | None = Field(default=None, strict=True)
    has_cable_subscription: int | None = Field(default=None, strict=True)
    has_broadband_internet_subscription: int | None = Field(default=None, strict=True)
    has_video_streaming_subscription: int | None = Field(default=None, strict=True)
    philhealth_membership_status: int | None = Field(default=None, strict=True)
    received_philhealth_benefits: int | None = Field(default=None, strict=True)
    members_age_0_5: int | None = Field(default=None, ge=0, strict=True)
    members_age_6_11: int | None = Field(default=None, ge=0, strict=True)
    members_age_12_17: int | None = Field(default=None, ge=0, strict=True)
    members_age_60_plus: int | None = Field(default=None, ge=0, strict=True)
    bedroom_count: int | None = Field(default=None, ge=0, strict=True)
    social_insurance_program_count: int | None = Field(default=None, ge=0, le=5, strict=True)
    social_assistance_program_count: int | None = Field(default=None, ge=0, le=8, strict=True)
    labor_market_program_count: int | None = Field(default=None, ge=0, le=4, strict=True)
    government_services_accessed_count: int | None = Field(default=None, ge=0, le=12, strict=True)

    @field_validator(*APIS2022_CATEGORICAL_FEATURES)
    @classmethod
    def validate_codes(cls, value: int | None, info):
        if value is not None and value not in APIS2022_CODE_CHOICES[info.field_name]:
            raise ValueError(f"Invalid APIS 2022 code for {info.field_name}")
        return value

    @model_validator(mode="after")
    def validate_household_details(self):
        age_fields = (self.members_age_0_5, self.members_age_6_11,
                      self.members_age_12_17, self.members_age_60_plus)
        if self.family_size is not None and all(x is not None for x in age_fields):
            if sum(age_fields) > self.family_size:
                raise ValueError("Recorded age bands cannot exceed family size")
        if self.experienced_natural_disaster == 2 and (
            self.disaster_evacuated_or_displaced == 1 or
            self.recovered_from_disaster == 1
        ):
            raise ValueError("Disaster follow-ups contradict 'No disaster experienced'")
        return self


class AssessmentResponse(AssessmentCreate):
    assessment_id: int
    household_head: str
    barangay: str
    recorded_by: int
    created_at: datetime
    monthly_income_per_capita: Decimal | None = None  # PostgreSQL generated field
    member_record_count: int | None = None
    member_roster_complete: int | None = None
    has_classification: bool = False


class AssessmentSocialUpdate(BaseModel):
    """Update only social-protection ML inputs; no removed JSON columns."""
    model_config = ConfigDict(extra="forbid")
    philhealth_membership_status: int | None = Field(default=None, strict=True)
    received_philhealth_benefits: int | None = Field(default=None, strict=True)
    social_insurance_program_count: int | None = Field(default=None, ge=0, le=5, strict=True)
    social_assistance_program_count: int | None = Field(default=None, ge=0, le=8, strict=True)
    labor_market_program_count: int | None = Field(default=None, ge=0, le=4, strict=True)
    government_services_accessed_count: int | None = Field(default=None, ge=0, le=12, strict=True)

    @model_validator(mode="after")
    def check_choices(self):
        if self.philhealth_membership_status is not None and self.philhealth_membership_status not in (1,2,3):
            raise ValueError("Invalid PhilHealth membership survey code")
        if self.received_philhealth_benefits is not None and self.received_philhealth_benefits not in (1,2):
            raise ValueError("Invalid PhilHealth benefits survey code")
        return self
