"""Prepare authorized APIS ZIP locally and evaluate a clearly labelled proxy model.
Run from backend: python -m ml_service.build_apis_baseline --zip PATH
Does not load .env or touch the database. Writes the APIS model used by the updated app.
Restart the backend after rebuilding; a running process caches its loaded model.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import zipfile
import joblib
import pandas as pd
import sklearn
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder
from .apis_rules import FEATURES, VERSION, classify

KEY = ['REG','HHID']
FILES = {
    'household': 'APIS PUF 2019 Household.CSV',
    'housing': 'APIS PUF 2019 RTJ - Housing.CSV',
    'water': 'APIS PUF 2019 RTK - Water and Sanitation.CSV',
    'other': 'APIS PUF 2019 RTM - Other Relevant Information and Drug Awareness and Prevention.CSV',
}
MAPPING = {'JQ2':'roof_material','JQ3':'wall_material','JQ6':'electricity',
           'WSQ1':'drinking_water_source','WSQ11A':'toilet_facility',
           'WRK_18':'working_adult_present'}
CLASSES = ['Low','Medium','High']

def prepare(path):
    with zipfile.ZipFile(path) as archive:
        tables={}
        for kind,filename in FILES.items():
            df=pd.read_csv(io.BytesIO(archive.read(filename)),dtype=str)
            for c in df: df[c]=df[c].str.strip().replace('',pd.NA)
            if df[KEY].isna().any().any() or df.duplicated(KEY).any():
                raise ValueError(f'{kind}: missing or duplicate household keys')
            tables[kind]=df
        base=tables['household'][KEY+['FSIZE','WRK_18','RFACT']].copy()
        for name,cols in [('housing',['JQ2','JQ3','JQ6']),('water',['WSQ1','WSQ11A']),('other',['L5'])]:
            if set(map(tuple,base[KEY].values)) != set(map(tuple,tables[name][KEY].values)):
                raise ValueError(f'{name}: household keys do not match')
            base=base.merge(tables[name][KEY+cols],on=KEY,how='left',validate='one_to_one')
    for c in set(base.columns)-set(KEY): base[c]=pd.to_numeric(base[c],errors='coerce')
    base=base.rename(columns=MAPPING)
    results=[classify(row) for row in base.to_dict('records')]
    base['proxy_class']=[r['class'] for r in results]
    base['proxy_score']=[r['score'] for r in results]
    base['proxy_reasons']=['; '.join(r['reasons']) for r in results]
    # Context only. Income is 2019 PHP, not inflation-adjusted and not a label input.
    base=base.rename(columns={'FSIZE':'family_size','L5':'monthly_family_income_2019_php','RFACT':'survey_weight'})
    return base

def model():
    return Pipeline([
        ('encode',ColumnTransformer([('codes',OneHotEncoder(handle_unknown='ignore'),FEATURES)])),
        ('forest',RandomForestClassifier(n_estimators=200,min_samples_leaf=2,
             class_weight='balanced_subsample',random_state=42,n_jobs=2)),
    ])

def evaluate(fitted,frame):
    y=frame['proxy_class'];p=fitted.predict(frame[FEATURES])
    return {'records':len(frame),'accuracy':float(accuracy_score(y,p)),
            'confusion_matrix_order':CLASSES,
            'confusion_matrix':confusion_matrix(y,p,labels=CLASSES).tolist(),
            'classification_report':classification_report(y,p,labels=CLASSES,output_dict=True,zero_division=0)}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zip',required=True,type=Path)
    parser.add_argument('--output',type=Path,default=Path(__file__).parent/'apis_outputs')
    args=parser.parse_args()
    frame=prepare(args.zip)
    usable=frame[frame.proxy_class!='Needs review'].copy()
    # Caraga is held out entirely to inspect geographical transfer.
    caraga=usable[usable.REG=='16'];rest=usable[usable.REG!='16']
    train,test=train_test_split(rest,test_size=.2,stratify=rest.proxy_class,random_state=42)
    assert not set(map(tuple,train[KEY].values)) & set(map(tuple,test[KEY].values))
    fitted=model();fitted.fit(train[FEATURES],train.proxy_class)
    report={
        'version':VERSION,'source':'PSA APIS 2019 PUF','source_sha256':hashlib.sha256(args.zip.read_bytes()).hexdigest(),
        'records_total':len(frame),'records_usable':len(usable),'needs_review':int((frame.proxy_class=='Needs review').sum()),
        'caraga_total':int((frame.REG=='16').sum()),'caraga_usable':len(caraga),
        'class_distribution':frame.proxy_class.value_counts().to_dict(),
        'training_records':len(train),'features':FEATURES,
        'excluded_predictors':['REG','HHID','proxy_score','proxy_reasons','proxy_class','survey_weight','family_size','monthly_family_income_2019_php'],
        'holdout_non_caraga':evaluate(fitted,test),'holdout_caraga':evaluate(fitted,caraga),
        'majority_baseline_non_caraga':float((test.proxy_class==train.proxy_class.mode()[0]).mean()),
        'rule_baseline_accuracy':1.0,
        'rule_baseline_explanation':'Exactly 1.0 by construction: rules define the target, not independent truth.',
        'limitations':[
            'Researcher-defined socioeconomic proxy, NOT PSA poverty status or validated humanitarian vulnerability.',
            'Labels are generated from the same six input fields: RF metrics measure rule imitation only.',
            'Low = zero flags; Medium = one/two; High = three to five. Equal weights and cutoffs are prototype choices.',
            'No independent expert labels, temporal validation, disaster exposure, displacement or damage outcome.',
            'No claim that regional survey households represent Cabadbaran specifically.',
            'Metrics are unweighted record-level ML results, not population prevalence estimates.',
            'A 2019 baseline requires temporal and local validation before operational decisions.',
            'No automatic aid eligibility or allocation; ambiguous inputs need human review.',
        ],
        'versions':{'sklearn':sklearn.__version__,'pandas':pd.__version__},
        'app_model_path':'ml_service/apis_outputs/apis2019_prototype.joblib',
    }
    args.output.mkdir(parents=True,exist_ok=True)
    frame.to_csv(args.output/'apis2019_prepared.csv',index=False)
    (args.output/'evaluation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    # Training-only fit retained so reported holdouts remain genuinely held out.
    joblib.dump({'pipeline':fitted,'version':VERSION,'features':FEATURES,'label_kind':'researcher_defined_proxy'},args.output/'apis2019_prototype.joblib')
    print(json.dumps({k:report[k] for k in ['records_total','records_usable','needs_review','caraga_total','caraga_usable','class_distribution']},indent=2))
    for k in ['holdout_non_caraga','holdout_caraga']:
        print(k,report[k]['records'],'rule-agreement accuracy',report[k]['accuracy'])
    print('Saved to',args.output,'; restart the updated backend to load this model.')

if __name__=='__main__':main()
