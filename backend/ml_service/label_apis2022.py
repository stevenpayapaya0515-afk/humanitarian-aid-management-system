"""Draft four-domain living-condition proxy, not official PSA/MPI labels."""
import argparse
import json
from pathlib import Path
import pandas as pd

VERSION = "apis2022-living-conditions-draft-v1"
# Explicit project adaptations of material/source/facility categories.
CODES = {
    "I2": ({1, 2, 3, 6}, {4, 5, 7}),
    "I3": ({1, 2, 3, 4, 6, 7}, {5, 8, 10}),
    "I4": ({1, 2, 3}, {4, 5, 6}),
    "I8": ({1}, {2}),
    "WS1": ({11, 12, 13, 14, 21, 31, 41, 51, 61, 71, 72, 91}, {32, 42, 81}),
    "WS11A": ({11, 12, 13, 21, 22, 31}, {14, 23, 41, 51, 95}),
}


def flag(value, name):
    text = str(value).strip()
    if not text.isdigit():
        return None
    code = int(text)
    adequate, deprived = CODES[name]
    return 0 if code in adequate else 1 if code in deprived else None


def label_row(row, high_at=2):
    if high_at not in (2, 3):
        raise ValueError("Supported draft thresholds: 2 or 3")
    f = {name: flag(row.get(name, ""), name) for name in CODES}
    # Require every material classification to be understood; no silent imputation.
    if any(value is None for value in f.values()):
        return {"proxy_class": "Needs review", "deprivation_count": None}
    score = max(f["I2"], f["I3"], f["I4"]) + f["I8"] + f["WS1"] + f["WS11A"]
    return {
        "proxy_class": "Low" if score == 0 else "High" if score >= high_at else "Medium",
        "deprivation_count": score,
    }


def run(source, output):
    frame = pd.read_csv(source, dtype=str, keep_default_na=False)
    required = {"REG", "HHID", *CODES}
    if not required.issubset(frame.columns):
        raise ValueError("Missing required source columns")
    if frame.duplicated(["REG", "HHID"]).any():
        raise ValueError("Duplicate household keys")
    labels = pd.DataFrame([label_row(row) for row in frame.to_dict("records")])
    alternative = [label_row(row, 3)["proxy_class"] for row in frame.to_dict("records")]
    result = pd.concat([frame, labels], axis=1)
    result["label_version"] = VERSION
    report = {
        "version": VERSION, "status": "DRAFT RESEARCH PROXY; NOT VALIDATED FOR AID DECISIONS",
        "thresholds": {"Low": "0 of 4 domains", "Medium": "1 of 4", "High": "2 to 4"},
        "threshold_origin": "Researcher-defined; NOT a PSA, UNDP or WHO severity threshold",
        "households": len(frame),
        "class_counts": labels["proxy_class"].value_counts().to_dict(),
        "caraga_class_counts": result.loc[frame.REG.astype(int).eq(16), "proxy_class"].value_counts().to_dict(),
        "alternative_high_at_3": pd.Series(alternative).value_counts().to_dict(),
        "changed_if_high_at_3": int((labels["proxy_class"] != alternative).sum()),
        "limitations": [
            "Four selected living-condition domains, not full MPI or all humanitarian vulnerability.",
            "Water tests source type only: not collection time, availability or measured quality.",
            "Sanitation tests facility type only: not shared use or waste treatment.",
            "Roof code 4 and floor code 4 are project material mappings requiring local review.",
            "Other/unknown/unmapped categories require review; no missing-to-zero conversion.",
            "Training RF on these same variables measures rule reproduction, not independent validity.",
            "Low means none of these four flags, never no need for assistance.",
            "PSA regional sample does not identify or represent Agusan del Norte separately.",
        ],
        "sources": [
            "https://hdr.undp.org/content/2022-global-multidimensional-poverty-index-mpi",
            "https://washdata.org/topics/drinking-water",
            "https://www.who.int/teams/environment-climate-change-and-health/water-sanitation-and-health/monitoring-and-evidence/wash-monitoring",
            "Uploaded APIS_PUF_2022.dcf and 2022 APIS Questionnaire",
        ],
    }
    (output / "datasets").mkdir(parents=True, exist_ok=True)
    (output / "evaluation").mkdir(parents=True, exist_ok=True)
    result.to_csv(output / "datasets/apis2022_proxy_draft.csv", index=False)
    (output / "evaluation/apis2022_rubric_review.json").write_text(json.dumps(report, indent=2)+"\n")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, default=Path(__file__).resolve().parent / "datasets/apis2022_households_unlabelled.csv")
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    print(json.dumps(run(args.csv, args.output_dir), indent=2))
