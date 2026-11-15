"""AidTrack APIS 2022 *research-only* multi-domain proxy rubric.

The target is created by researcher-defined rules, NOT independently observed
humanitarian vulnerability. No official PSA/DSWD severity cutoffs are implied.
Thresholds and interpretation require instructor/LGU review before deployment.

Disaster coding assumption: 1=yes, 2=no for G15/G16/G16A/G16B;
these mappings must be checked against the official 2022 APIS codebook.
Conditional blanks on G16A/G16B when G16=2 are legitimate survey skips.
"""
from __future__ import annotations
import numpy as np
import pandas as pd
from .label_apis2022 import CODES

VERSION = "apis2022-expanded-research-proxy-draft-v1"
# The 25th percentile is computed on non-Caraga training groups only.
INCOME_QUANTILE = 0.25
HIGH_AT = 3  # Experimental: >=3 of 8 flags = High; 1-2 = Medium; 0 = Low
DOMAINS = ["shelter_materials", "housing_security", "water", "sanitation",
           "income_relative", "dependency_pressure", "disaster_disruption", "preparedness_gap"]
CATEGORICAL = ["I2", "I3", "I4", "I8", "WS1", "WS11A",
               "G15_KIT", "G16_NAT_DISAS", "G16A_EVAC", "G16B_RECOV"]
NUMERIC = ["FSIZE", "MEM_AGE_0_5", "MEM_AGE_6_11", "MEM_AGE_12_17",
           "MEM_AGE_60_PLUS", "K5_PER_CAPITA"]
FEATURES = CATEGORICAL + NUMERIC
REQUIRED = set(CATEGORICAL + ["REG", "HHID", "RPSU", "K5", "FSIZE", "MEMBER_ROWS",
                  "MEM_ROSTER_MATCHES_FSIZE", "MEM_AGE_0_5", "MEM_AGE_6_11",
                  "MEM_AGE_12_17", "MEM_AGE_60_PLUS"])


def check_input(frame: pd.DataFrame) -> None:
    missing = REQUIRED.difference(frame.columns)
    if missing:
        raise ValueError(f"Missing columns: {sorted(missing)}")
    if frame.duplicated(["REG", "HHID"]).any():
        raise ValueError("Duplicate REG/HHID household key")
    if frame[["REG", "HHID", "RPSU"]].eq("").any().any():
        raise ValueError("Missing sampling/household identifier")


def prepare(frame: pd.DataFrame) -> pd.DataFrame:
    check_input(frame)
    out = frame.copy()
    for name in ["K5", "FSIZE", "MEMBER_ROWS", "MEM_AGE_0_5", "MEM_AGE_6_11",
                 "MEM_AGE_12_17", "MEM_AGE_60_PLUS"]:
        # strict: incompatible data becomes NA and is held for human review
        out[name] = pd.to_numeric(out[name], errors="coerce")
    out["K5_PER_CAPITA"] = out["K5"].div(out["FSIZE"].where(out["FSIZE"] > 0))
    return out


def add_proxy_labels(frame: pd.DataFrame, income_cutoff: float,
                     high_at: int = HIGH_AT) -> pd.DataFrame:
    """Add experimental labels, preserving unknowns as Needs review."""
    if not np.isfinite(income_cutoff) or income_cutoff < 0:
        raise ValueError("Invalid training-only income cutoff")
    if high_at not in (3, 4):
        raise ValueError("Only registered sensitivity thresholds 3 or 4 are supported")
    out = frame.copy()
    flags = {}
    valid = pd.Series(True, index=out.index)
    housing = {}
    for name, (adequate, deprived) in CODES.items():
        x = pd.to_numeric(out[name], errors="coerce")
        flag = x.map({**{v: 0.0 for v in adequate}, **{v: 1.0 for v in deprived}})
        housing[name] = flag
        valid &= flag.notna()
    flags["shelter_materials"] = pd.concat([housing[n] for n in ("I2", "I3", "I4")], axis=1).max(axis=1)
    flags["housing_security"] = housing["I8"]
    flags["water"] = housing["WS1"]
    flags["sanitation"] = housing["WS11A"]

    income = out["K5_PER_CAPITA"]
    valid &= income.notna() & (income >= 0)
    flags["income_relative"] = (income <= income_cutoff).astype(float)

    # Member-derived counts used only if the roster matches household size.
    roster_valid = (out["MEM_ROSTER_MATCHES_FSIZE"] == "1") & out["MEMBER_ROWS"].eq(out["FSIZE"])
    for n in ("MEM_AGE_0_5", "MEM_AGE_6_11", "MEM_AGE_12_17", "MEM_AGE_60_PLUS"):
        roster_valid &= out[n].notna() & out[n].ge(0)
    dependents = out[["MEM_AGE_0_5", "MEM_AGE_6_11", "MEM_AGE_12_17", "MEM_AGE_60_PLUS"]].sum(axis=1)
    roster_valid &= dependents <= out["FSIZE"]
    valid &= roster_valid
    flags["dependency_pressure"] = ((dependents >= 2) & (dependents / out["FSIZE"] >= .5)).astype(float)

    # All disaster coding assumptions require confirmation from the survey codebook.
    disaster, evac, recovered, kit = [out[c].astype(str).str.strip() for c in
                                     ("G16_NAT_DISAS", "G16A_EVAC", "G16B_RECOV", "G15_KIT")]
    has_disaster = disaster.eq("1")
    skip_ok = (~has_disaster) & evac.eq("") & recovered.eq("")
    disaster_ok = disaster.isin(["1", "2"]) & kit.isin(["1", "2"]) & (
        (has_disaster & evac.isin(["1", "2"]) & recovered.isin(["1", "2"])) | skip_ok)
    valid &= disaster_ok
    flags["disaster_disruption"] = (has_disaster & (evac.eq("1") | recovered.eq("2"))).astype(float)
    flags["preparedness_gap"] = (has_disaster & kit.eq("2")).astype(float)

    for domain in DOMAINS:
        out[f"proxy_{domain}"] = flags[domain].where(valid).astype("Float64")
    total = sum(flags[d] for d in DOMAINS)
    out["expanded_proxy_score"] = total.where(valid).astype("Float64")
    classes = np.select([total.eq(0), total.ge(high_at)], ["Low", "High"], default="Medium")
    out["expanded_proxy_class"] = np.where(valid, classes, "Needs review")
    out["expanded_label_version"] = VERSION
    return out


def raw_feature_frame(frame: pd.DataFrame) -> pd.DataFrame:
    """Never pass labels, sampling identifiers, or derived proxy flags to the model."""
    result = frame[CATEGORICAL].astype(str).copy()
    for n in NUMERIC:
        result[n] = pd.to_numeric(frame[n], errors="coerce")
    return result[FEATURES]
