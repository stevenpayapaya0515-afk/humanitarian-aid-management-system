"""Prepare unlabelled APIS 2022 household records; never invent training targets."""
import csv
import argparse
import hashlib
import json
import re
from pathlib import Path
import pandas as pd

KEY = ["REG", "HHID"]
SINGLE = {
    "Household Record": ["FSIZE", "URB", "RPSU", "REP", "RFACT"],
    "RTI - Housing": ["I1", "I2", "I3", "I4", "I5", "I6", "I7", "I8"],
    "RTJ - Water Sanitation and Hygiene": ["WS1", "WS11A"],
    "RTG5 - Social Protection - Philhealth, Children, Disaster Preparedness and Recovery":
        ["G16_NAT_DISAS", "G16A_EVAC", "G16B_RECOV"],
    "RTK - Other Relevant Information": ["K4", "K5"],
}
REPEATED = {
    "Member Record": "C101_LNO",
    "RTG1 - Social Protection - Social Insurance": "G1CODE",
    "RTG2 - Social Protection - Social Assistance": "G5CODE",
    "RTG3 - Social Protection - Labor Market Intervention": "G9CODE",
    "RTG4 - Government Feeding Program": "G11CODE",
    "RTH - Access to Government Services": "H1CODE",
}


def read_table(path):
    repairs = []
    with path.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.reader(stream)
        header = next(reader)
        rows = []
        for line, row in enumerate(reader, 2):
            if len(row) != len(header):
                # The supplied RTK export has unquoted commas in K8_OTHERS.
                # Preserve its fixed prefix and suffix, rejoining only that text.
                if path.name == "APIS PUF 2022 RTK - Other Relevant Information.CSV" and len(row) > len(header):
                    index = header.index("K8_OTHERS")
                    extra = len(row) - len(header)
                    row = row[:index] + [",".join(row[index:index + extra + 1])] + row[index + extra + 1:]
                    repairs.append({"csv_line": line, "field": "K8_OTHERS", "action": "Rejoined unquoted text commas"})
                else:
                    raise ValueError(f"Unexpected column count at {path.name}:{line}")
            rows.append(row)
    frame = pd.DataFrame(rows, columns=header)
    frame.attrs["csv_repairs"] = repairs
    frame = frame.apply(lambda col: col.str.strip())
    if not set(KEY).issubset(frame.columns) or frame[KEY].eq("").any().any():
        raise ValueError(f"Missing household keys: {path.name}")
    if not frame["REG"].str.fullmatch(r"\d{1,2}").all():
        raise ValueError(f"Invalid region code: {path.name}")
    frame["REG"] = frame["REG"].astype(int).astype(str)
    frame.attrs["csv_repairs"] = repairs
    return frame


def require_unique(frame, keys, name):
    if frame.duplicated(keys).any():
        raise ValueError(f"Duplicate keys in {name}; refusing a many-to-many join.")


def dictionary_items(path):
    result = {}
    for block in path.read_text(encoding="utf-8-sig").split("[Item]")[1:]:
        name = re.search(r"^Name=(.+)$", block, re.M)
        label = re.search(r"^Label=(.+)$", block, re.M)
        if name and label:
            result[name[1].strip()] = {
                "label": label[1].strip(),
                "values": [line[6:] for line in block.splitlines() if line.startswith("Value=")],
            }
    return result


def prepare(source, output):
    paths = {name: source / f"APIS PUF 2022 {name}.CSV" for name in [*SINGLE, *REPEATED]}
    dictionary = source / "APIS_PUF_2022.dcf"
    for path in [*paths.values(), dictionary]:
        if not path.is_file():
            raise FileNotFoundError(path)
    report = {
        "source": "PSA APIS 2022 PUF",
        "purpose": "Unlabelled preparation and join audit; not a trained model",
        "app_changed": False,
        "label_status": "No validated Low/Medium/High humanitarian target selected",
        "geography": "REG supports Caraga filtering, not Agusan del Norte identification",
        "limitations": [
            "User guide supports regional estimates, not reliable provincial tabulations.",
            "Blank values and questionnaire skips remain blank, not zero.",
            "2019 roof/wall codes must not be reused for 2022.",
            "K4 is weekly food consumption; K5 is monthly income, January-June 2022.",
            "Disaster recovery applies to a conditional subgroup, not every household.",
            "RFACT is for survey analysis, not an input feature.",
            "No linkage of households across FIES/APIS survey years is performed.",
        ],
        "tables": {},
    }
    merged = None
    base_keys = None
    for name, fields in SINGLE.items():
        frame = read_table(paths[name])
        require_unique(frame, KEY, name)
        if set(fields) - set(frame.columns):
            raise ValueError(f"Missing selected fields in {name}")
        keys = set(map(tuple, frame[KEY].to_numpy()))
        if base_keys is None:
            base_keys = keys
            merged = frame[KEY + fields].copy()
        else:
            if keys != base_keys:
                raise ValueError(f"Household coverage mismatch in {name}")
            merged = merged.merge(frame[KEY + fields], on=KEY, validate="one_to_one", how="left")
        report["tables"][name] = {"rows": len(frame), "households": len(keys), "csv_repairs": frame.attrs.get("csv_repairs", [])}
    for name, record_key in REPEATED.items():
        frame = read_table(paths[name])
        if record_key not in frame or frame[record_key].eq("").any():
            raise ValueError(f"Missing record keys in {name}")
        duplicate_records = int(frame.duplicated(KEY + [record_key], keep=False).sum())
        keys = set(map(tuple, frame[KEY].to_numpy()))
        if keys - base_keys:
            raise ValueError(f"Orphan household keys in {name}")
        report["tables"][name] = {
            "rows": len(frame), "households": len(keys),
            "households_without_records": len(base_keys - keys),
            "rows_with_duplicate_record_keys": duplicate_records,
            "handling": "Audited separately; not naively joined or flattened",
        }
    mapping = dictionary_items(dictionary)
    selected = [col for col in merged.columns if col not in KEY]
    if any(col not in mapping for col in selected):
        raise ValueError("Selected column missing from dictionary.")
    report["variable_dictionary"] = {col: mapping[col] for col in selected}
    report["households"] = len(merged)
    report["caraga_households"] = int(merged["REG"].eq("16").sum())
    report["region_counts"] = merged["REG"].value_counts().sort_index().to_dict()
    report["blank_counts"] = {col: int(merged[col].eq("").sum()) for col in selected}
    report["disaster_responses"] = {
        col: merged[col].value_counts(dropna=False).to_dict()
        for col in ["G16_NAT_DISAS", "G16A_EVAC", "G16B_RECOV"]
    }
    report["source_sha256"] = {
        path.name: hashlib.sha256(path.read_bytes()).hexdigest()
        for path in [*paths.values(), dictionary]
    }
    (output / "datasets").mkdir(parents=True, exist_ok=True)
    (output / "evaluation").mkdir(parents=True, exist_ok=True)
    merged.to_csv(output / "datasets/apis2022_households_unlabelled.csv", index=False)
    (output / "evaluation/apis2022_preparation.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    result = prepare(args.source_dir, args.output_dir)
    print(json.dumps({k: result[k] for k in ["households", "caraga_households", "label_status"]}, indent=2))
