"""APIS socioeconomic proxy inference; never an aid eligibility decision."""
from functools import lru_cache
from pathlib import Path
import joblib
import pandas as pd
from .apis_rules import FEATURES, VERSION, VALID, classify

MODEL_PATH = Path(__file__).resolve().parent / "apis_outputs" / "apis2019_prototype.joblib"
MODEL_VERSION = VERSION
MODEL_TRAINING_DATA_ORIGIN = "psa_apis2019"

class AssessmentNeedsReview(ValueError):
    pass

@lru_cache(maxsize=1)
def load_model():
    if not MODEL_PATH.is_file():
        raise FileNotFoundError("Build the APIS baseline before classification.")
    try:
        bundle = joblib.load(MODEL_PATH)
        if (not isinstance(bundle, dict) or bundle.get("version") != VERSION
                or bundle.get("features") != FEATURES
                or bundle.get("label_kind") != "researcher_defined_proxy"):
            raise RuntimeError("Incompatible APIS model bundle.")
        model = bundle["pipeline"]
        if set(model.classes_) != {"Low", "Medium", "High"}:
            raise RuntimeError("Unexpected model classes.")
        return model
    except Exception as error:
        raise RuntimeError("Rebuild the APIS model using this backend environment.") from error

def predict_vulnerability(assessment: dict) -> dict:
    missing = [k for k in FEATURES if type(assessment.get(k)) is not int or assessment[k] not in VALID[k]]
    if missing or assessment.get("apis_single_family") is not True:
        raise AssessmentNeedsReview(
            "Needs review: record a new assessment with all six socioeconomic answers "
            "and confirm a single-family household. Unknown answers and multi-family "
            "households are outside this prototype's prediction scope."
        )
    reference = classify(assessment)
    model = load_model()
    data = pd.DataFrame([{k: assessment[k] for k in FEATURES}], columns=FEATURES)
    label = str(model.predict(data)[0])
    scores = {str(k): round(float(v), 6) for k, v in zip(model.classes_, model.predict_proba(data)[0])}
    return {
        "predicted_class": label, "predicted_class_score": scores[label],
        "class_scores": scores, "model_version": MODEL_VERSION,
        "model_training_data_origin": MODEL_TRAINING_DATA_ORIGIN,
        "proxy_details": {"rule_class": reference["class"], "flag_count": reference["score"],
                          "reasons": reference["reasons"], "model_agrees_with_rules": label == reference["class"]},
    }
