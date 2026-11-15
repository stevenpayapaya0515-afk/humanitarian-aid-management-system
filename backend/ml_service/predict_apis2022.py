"""Offline APIS 2022 adapter. Not wired to live assessment routes."""
from functools import lru_cache
from pathlib import Path
import joblib
import pandas as pd
import sklearn
from .label_apis2022 import VERSION, CODES, label_row

FEATURES = list(CODES)
MODEL_VERSION = "apis2022-rf-rule-agreement-v1"
MODEL_PATH = Path(__file__).resolve().parent / "models" / "apis2022_candidate.joblib"


class NeedsReview(ValueError):
    """Answers cannot support this limited living-condition proxy."""


def prepare_answers(answers):
    if answers.get("survey_version") != "APIS2022":
        raise NeedsReview("Record APIS 2022 answers; legacy codes cannot be reused.")
    if answers.get("single_family") is not True:
        raise NeedsReview("Confirm one family; otherwise staff review is required.")
    clean = {}
    for name in FEATURES:
        value = answers.get(name)
        if type(value) is not int or value not in set.union(*CODES[name]):
            raise NeedsReview(f"Record a supported {name} answer; unknown requires review.")
        clean[name] = value
    return clean


@lru_cache(maxsize=1)
def load_model():
    if not MODEL_PATH.is_file():
        raise FileNotFoundError("Train the APIS 2022 candidate in this backend environment.")
    bundle = joblib.load(MODEL_PATH)
    if not isinstance(bundle, dict) or any([
        bundle.get("version") != MODEL_VERSION,
        bundle.get("label_version") != VERSION,
        bundle.get("features") != FEATURES,
        bundle.get("label_kind") != "researcher_defined_proxy",
        bundle.get("app_ready") is not False,
        bundle.get("sklearn_version") != sklearn.__version__,
    ]):
        raise RuntimeError("Incompatible candidate; retrain with this backend environment.")
    model = bundle.get("pipeline")
    if model is None or set(model.classes_) != {"Low", "Medium", "High"}:
        raise RuntimeError("Invalid model classes.")
    if list(model.feature_names_in_) != FEATURES:
        raise RuntimeError("Invalid model input order.")
    return model


def predict_candidate(answers):
    clean = prepare_answers(answers)
    rule = label_row(clean)
    model = load_model()
    frame = pd.DataFrame([{name: str(clean[name]) for name in FEATURES}], columns=FEATURES)
    predicted = str(model.predict(frame)[0])
    scores = {str(label): round(float(score), 6)
              for label, score in zip(model.classes_, model.predict_proba(frame)[0])}
    return {
        "predicted_class": predicted,
        "predicted_class_score": scores[predicted],
        "class_scores": scores,
        "model_version": MODEL_VERSION,
        "label_version": VERSION,
        "rule_class": rule["proxy_class"],
        "deprivation_count": rule["deprivation_count"],
        "model_agrees_with_rules": predicted == rule["proxy_class"],
        "requires_staff_review": True,
        "assessment_scope": "Draft living-condition proxy; not aid eligibility",
    }
