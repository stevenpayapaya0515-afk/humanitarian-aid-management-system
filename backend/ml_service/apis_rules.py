"""AidTrack research prototype rules v1; NOT official PSA poverty/aid eligibility."""
VERSION = 'apis2019-proxy-v1'
FEATURES = ['roof_material', 'wall_material', 'electricity', 'drinking_water_source',
            'toilet_facility', 'working_adult_present']
VALID = {
    'roof_material': {1,2,3,4,5,6}, 'wall_material': {1,2,3,4,5,6},
    'electricity': {1,2},
    'drinking_water_source': {11,12,13,14,21,31,32,41,42,51,61,71,72,81,91,92},
    'toilet_facility': {11,12,13,14,21,22,23,31,41,51,95},
    'working_adult_present': {0,1},
}

def classify(row):
    """Unknown/ambiguous inputs require review, never default to Low."""
    if any(row.get(k) not in VALID[k] for k in FEATURES):
        return {'class': 'Needs review', 'score': None, 'reasons': []}
    flags = {
        'Light or makeshift roof/walls': row['roof_material'] in {2,3,5,6} or row['wall_material'] in {2,3,5,6},
        'No electricity': row['electricity'] == 2,
        'Unprotected well/spring or surface drinking water': row['drinking_water_source'] in {32,42,81},
        'Open-drain, open-pit, bucket, hanging or no toilet': row['toilet_facility'] in {14,23,41,51,95},
        'No working family member aged 18 or above': row['working_adult_present'] == 0,
    }
    reasons = [k for k,v in flags.items() if v]
    score = len(reasons)
    return {'class': 'Low' if score == 0 else 'Medium' if score <= 2 else 'High',
            'score': score, 'reasons': reasons}
