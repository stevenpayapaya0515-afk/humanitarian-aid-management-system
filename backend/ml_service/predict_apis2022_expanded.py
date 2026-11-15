"""Offline expanded APIS 2022 candidate inspection only; NOT a FastAPI route.

This deliberately refuses app promotion: every prediction requires staff review.
Never load untrusted joblib files (pickle is executable).
"""
from functools import lru_cache
from pathlib import Path
import joblib
import pandas as pd
import sklearn
from .label_apis2022_expanded import (VERSION, FEATURES, add_proxy_labels,
    prepare, raw_feature_frame)
from .train_apis2022_expanded import MODEL_VERSION

MODEL_PATH = Path(__file__).resolve().parent / 'models' / 'apis2022_expanded_candidate.joblib'


@lru_cache(maxsize=1)
def load_candidate():
    if not MODEL_PATH.is_file():
        raise FileNotFoundError('Expanded offline model not trained yet.')
    bundle = joblib.load(MODEL_PATH)
    required = (bundle.get('version') == MODEL_VERSION
                and bundle.get('label_version') == VERSION
                and bundle.get('features') == FEATURES
                and bundle.get('label_kind') == 'researcher_defined_proxy'
                and bundle.get('app_ready') is False
                and bundle.get('sklearn_version') == sklearn.__version__)
    if not required:
        raise RuntimeError('Candidate/model version mismatch; retrain locally before using.')
    if set(bundle['pipeline'].classes_) != {'Low', 'Medium', 'High'}:
        raise RuntimeError('Invalid classification classes in candidate.')
    return bundle


def predict_existing_puf_record(record: dict) -> dict:
    """Single-row offline smoke test; not an LGU assessment JSON contract."""
    bundle = load_candidate()
    row = pd.DataFrame([record], dtype=str).fillna('')
    labelled = add_proxy_labels(prepare(row), bundle['income_cutoff'])
    if labelled.iloc[0]['expanded_proxy_class'] == 'Needs review':
        return {'status': 'Needs review', 'requires_staff_review': True,
                'app_ready': False, 'reason': 'Missing or unsupported draft proxy input'}
    pred = str(bundle['pipeline'].predict(raw_feature_frame(labelled))[0])
    return {'predicted_class': pred, 'proxy_rule_class': labelled.iloc[0]['expanded_proxy_class'],
            'model_version': MODEL_VERSION, 'label_version': VERSION,
            'requires_staff_review': True, 'app_ready': False,
            'interpretation': 'Experimental proxy-label agreement; not verified humanitarian eligibility'}
