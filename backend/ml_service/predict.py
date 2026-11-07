from functools import lru_cache
from pathlib import Path

import joblib
import pandas as pd


# ==========================================
# MODEL CONFIGURATION
# ==========================================

MODEL_PATH = (
    Path(__file__).resolve().parent
    / "models"
    / "aidtrack_random_forest.joblib"
)

MODEL_VERSION = "aidtrack-rf-synthetic-v1"

MODEL_TRAINING_DATA_ORIGIN = "synthetic"


# ==========================================
# MODEL INPUT FEATURES
# ==========================================

FEATURE_COLUMNS = [
    "household_size",
    "age_0_5_count",
    "age_6_17_count",
    "age_18_59_count",
    "age_60_plus_count",
    "pwd_count",
    "monthly_income_range",
    "employment_status",
    "livelihood_type",
    "disaster_affected",
    "housing_damage_level",
    "displaced",
]


# ==========================================
# LOAD TRAINED MODEL
# ==========================================

@lru_cache(maxsize=1)
def load_model():

    if not MODEL_PATH.is_file():
        raise FileNotFoundError(
            f"Trained Random Forest model not found: {MODEL_PATH}"
        )

    model = joblib.load(MODEL_PATH)

    if not hasattr(model, "predict_proba"):
        raise RuntimeError(
            "The loaded model does not support predict_proba."
        )

    return model


# ==========================================
# PREDICT HOUSEHOLD VULNERABILITY
# ==========================================

def predict_vulnerability(assessment: dict) -> dict:

    disaster_affected = bool(
        assessment["disaster_affected"]
    )

    displaced = bool(
        assessment["displaced"]
    )

    # Match the preprocessing used during training.
    housing_damage_level = (
        assessment["housing_damage_level"]
        if disaster_affected
        else "None"
    )

    features = {
        "household_size": int(assessment["household_size"]),

        "age_0_5_count": int(assessment["age_0_5_count"]),

        "age_6_17_count": int(assessment["age_6_17_count"]),

        "age_18_59_count": int(assessment["age_18_59_count"]),

        "age_60_plus_count": int(assessment["age_60_plus_count"]),

        "pwd_count": int(assessment["pwd_count"]),

        "monthly_income_range": assessment["monthly_income_range"],

        "employment_status": assessment["employment_status"],

        "livelihood_type": assessment["livelihood_type"],

        "disaster_affected": (
            "Yes" if disaster_affected else "No"
        ),

        "housing_damage_level": housing_damage_level,

        "displaced": (
            "Yes" if displaced else "No"
        ),
    }

    # Keep the exact training feature order.
    input_data = pd.DataFrame(
        [features],
        columns=FEATURE_COLUMNS
    )

    model = load_model()

    # Random Forest class prediction uses ensemble voting.
    predicted_class = str(
        model.predict(input_data)[0]
    )

    # Retrieve the model's class scores.
    probabilities = model.predict_proba(input_data)[0]

    class_scores = {
        str(label): round(float(score), 6)
        for label, score in zip(model.classes_, probabilities)
    }

    return {
        "predicted_class": predicted_class,

        "predicted_class_score": class_scores[predicted_class],

        "class_scores": class_scores,

        "model_version": MODEL_VERSION,

        "model_training_data_origin": MODEL_TRAINING_DATA_ORIGIN,
    }