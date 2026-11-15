#!/usr/bin/env python3
"""AidTrack APIS PUF 2022: reproducible household-level feature assembly.

Builds the 85-column household-indicators CSV from 11 APIS PUF 2022 extracts.
Does not create vulnerability labels. The training script creates those.

Usage:
    python -m ml_service.build_apis2022_dataset \
       --input-dir ./original-apis-2022 --output-dir ./ml_service/datasets

The source's coded responses are preserved verbatim. Program CODE1 counts are
neutral response-code summaries, NOT verified binary aid-receipt definitions.
"""
from __future__ import annotations

import argparse
import collections
import csv
import hashlib
import json
from pathlib import Path

SOURCES = {
 'hh': 'APIS PUF 2022 Household Record.CSV',
 'member': 'APIS PUF 2022 Member Record.CSV',
 'g1': 'APIS PUF 2022 RTG1 - Social Protection - Social Insurance.CSV',
 'g2': 'APIS PUF 2022 RTG2 - Social Protection - Social Assistance.CSV',
 'g3': 'APIS PUF 2022 RTG3 - Social Protection - Labor Market Intervention.CSV',
 'g4': 'APIS PUF 2022 RTG4 - Government Feeding Program.CSV',
 'g5': 'APIS PUF 2022 RTG5 - Social Protection - Philhealth, Children, Disaster Preparedness and Recovery.CSV',
 'h': 'APIS PUF 2022 RTH - Access to Government Services.CSV',
 'i': 'APIS PUF 2022 RTI - Housing.CSV',
 'j': 'APIS PUF 2022 RTJ - Water Sanitation and Hygiene.CSV',
 'k': 'APIS PUF 2022 RTK - Other Relevant Information.CSV',
}
HH_FIELDS = ['REG','HHID','FSIZE','CHLD_6_11','CHLD_12_15','EDUC_6_11','EDUC_12_15','H04_SEX','H05_AGE','H06_STATUS','H12_HGC','URB','RPSU','REP','RFACT']
MEM_FIELDS = ['MEMBER_ROWS','MEM_AGE_0_5','MEM_AGE_6_11','MEM_AGE_12_17','MEM_AGE_18_59','MEM_AGE_60_PLUS','MEM_AGE_UNKNOWN','MEM_D44_DISEASE_CODE1_COUNT','MEM_ROSTER_MATCHES_FSIZE','MEM_ROSTER_SHORTFALL']
G5_FIELDS = ['G13_PHEALTH','G13A_ASSISTANCE','G14_AWARE','G14A_CONSULT','G15_KIT','G15A_TYPE','G16_NAT_DISAS','G16A_EVAC','G16B_RECOV','G16C_HELP']
HOUSING_FIELDS = ['I1','I2','I3','I4','I5','I6','I7','I8']
WATER_FIELDS = ['WS1','WS11A','WS14','WS15']
FIN_FIELDS = ['K4','K5']
PROGRAM_SPECS = {
  'g1': ('G1CODE','G1',['1','2','3','4','5']),
  'g2': ('G5CODE','G5',['1','2','3','4','5','6','7','8']),
  'g3': ('G9CODE','G9',['1','2','3','4']),
  'g4': ('G11CODE','G11',['1','2']),
  'h': ('H1CODE','H1',[f'{i:02d}' for i in range(1,13)]),
}


def key(row):
    return row['REG'].strip(), row['HHID'].strip()


def entries(path):
    with path.open('r',encoding='utf-8-sig',newline='') as f:
        for line_no,row in enumerate(csv.DictReader(f),2):
            # RTK contains two rows with a harmless extra trailing blank cell.
            if None in row:
                extras=row.pop(None)
                if any(str(value).strip() for value in extras):
                    raise ValueError(f'Nonempty extra CSV field at {path.name}:{line_no}: {extras!r}')
            yield {k:(v or '').strip() for k,v in row.items()}


def unique_table(path, fields):
    table={}
    for row in entries(path):
        k=key(row)
        if k in table:
            raise ValueError(f'Unexpected duplicate household key in {path.name}: {k}')
        table[k]={f:row[f] for f in fields}
    return table


def aggregate_members(path):
    table=collections.defaultdict(lambda: {f:0 for f in MEM_FIELDS})
    for row in entries(path):
        rec=table[key(row)]
        rec['MEMBER_ROWS']+=1
        s=row['C05_AGE']
        try: age=int(s)
        except (ValueError,TypeError): age=-1
        if 0 <= age <= 5: rec['MEM_AGE_0_5']+=1
        elif 6 <= age <= 11: rec['MEM_AGE_6_11']+=1
        elif 12 <= age <= 17: rec['MEM_AGE_12_17']+=1
        elif 18 <= age <= 59: rec['MEM_AGE_18_59']+=1
        elif 60 <= age <= 130: rec['MEM_AGE_60_PLUS']+=1
        else: rec['MEM_AGE_UNKNOWN']+=1
        if row['D44_DISEASE']=='1': rec['MEM_D44_DISEASE_CODE1_COUNT']+=1
    return table


def aggregate_program(path, spec):
    category_col,response_col,codes=spec
    catcols=[f'{response_col}_RESPONSE_{c}' for c in codes]
    totalcol=f'{response_col}_CODE1_COUNT'
    table=collections.defaultdict(dict)
    for row in entries(path):
        k=key(row);c=row[category_col]
        if c not in codes: raise ValueError(f'Unexpected {category_col}={c!r} in {path.name} at {k}')
        col=f'{response_col}_RESPONSE_{c}'
        if col in table[k]: raise ValueError(f'Duplicate category {col} for household {k} in {path.name}')
        table[k][col]=row[response_col]
    for k,rec in table.items():
        if set(rec)!=set(catcols): raise ValueError(f'Missing program category for {k} in {path.name}')
        rec[totalcol]=sum(rec[col]=='1' for col in catcols)
    return table, catcols+[totalcol]


def verify_keysets(master, tables):
    mk=set(master)
    for name,t in tables.items():
        missing=mk-set(t);extra=set(t)-mk
        if missing or extra:
            raise ValueError(f'Non-matching REG+HHID in {name}: missing={len(missing)}, extra={len(extra)}')


def source_digest(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        while b:=f.read(1024*1024): h.update(b)
    return h.hexdigest()


def build(source_dir: Path, output_dir: Path):
    output_dir.mkdir(parents=True,exist_ok=True)
    paths={n:source_dir/f for n,f in SOURCES.items()}
    for n,p in paths.items():
        if not p.is_file(): raise FileNotFoundError(f'Missing source ({n}): {p}')
    hh=unique_table(paths['hh'],HH_FIELDS)
    tables={'members':aggregate_members(paths['member']),
            'G5':unique_table(paths['g5'],G5_FIELDS),
            'housing':unique_table(paths['i'],HOUSING_FIELDS),
            'water':unique_table(paths['j'],WATER_FIELDS),
            'financial':unique_table(paths['k'],FIN_FIELDS)}
    program_fields=[]
    for n,spec in PROGRAM_SPECS.items():
        t,cols=aggregate_program(paths[n],spec)
        tables[n]=t
        program_fields.extend(cols)
    verify_keysets(hh,tables)
    keys=list(hh)
    fields=HH_FIELDS+MEM_FIELDS+G5_FIELDS+HOUSING_FIELDS+WATER_FIELDS+FIN_FIELDS+program_fields
    assert len(fields)==len(set(fields)), 'Duplicate output field name'
    unlabeled=output_dir/'apis2022_household_indicators.csv'
    member_size_mismatch=0
    output_sample=[]
    with unlabeled.open('w',newline='',encoding='utf-8') as fh:
        writer=csv.DictWriter(fh,fieldnames=fields,lineterminator='\n');writer.writeheader()
        for k in keys:
            d = dict(hh[k])
            for tab in tables.values():
                d.update(tab[k])
            d['MEM_ROSTER_MATCHES_FSIZE'] = 1 if int(d['MEMBER_ROWS']) == int(d['FSIZE']) else 0
            d['MEM_ROSTER_SHORTFALL'] = int(d['FSIZE']) - int(d['MEMBER_ROWS'])
            if not d['MEM_ROSTER_MATCHES_FSIZE']:
                member_size_mismatch += 1
            writer.writerow(d)
            if len(output_sample) < 3:
                output_sample.append({f: d[f] for f in
                    ('REG','HHID','FSIZE','MEMBER_ROWS','G16_NAT_DISAS','G15_KIT','G5_CODE1_COUNT')})
    source_hashes={SOURCES[n]:source_digest(p) for n,p in paths.items()}
    quality={
        'row_grain':'One row per unique (REG, HHID) APIS PUF household',
        'survey_year':2022,
        'household_rows':len(hh),
        'columns_without_label':len(fields),
        'input_sources':len(paths),
        'household_key_match_for_all_11_sources':True,
        'member_count_vs_fsize_mismatch_households':member_size_mismatch,
        'caraga_reg_16_rows':sum(k[0]=='16' for k in keys),
        'assumed_code1_means_yes':False,
        'codebook_validated':False,
        'model_trained_or_validated':False,
        'source_sha256':source_hashes,
        'sample':output_sample,
    }
    (output_dir.parent/'metadata').mkdir(parents=True,exist_ok=True)
    (output_dir.parent/'metadata'/'quality_report.json').write_text(json.dumps(quality,indent=2)+'\n',encoding='utf-8')
    dictfile=output_dir.parent/'metadata'/'feature_dictionary.csv'
    descriptions={
     'REG':('Household','Region code; 16 corresponds to Caraga','Split / filter only; not recommended as a model input'),
     'HHID':('Household','Household identifier (leading zeros preserved)','Identifier; not model feature'),
     'FSIZE':('Household','Household size','Candidate demographic feature'),
     'CHLD_6_11':('Household','Original coded child-age 6-11 field; exact meaning requires codebook','Review coding'),
     'CHLD_12_15':('Household','Original coded child-age 12-15 field; exact meaning requires codebook','Review coding'),
     'RFACT':('Household','Survey expansion/sampling factor','Survey analysis only; not direct model feature'),
     'RPSU':('Household','Survey PSU field','Survey split / geography controls; not model feature'),
     'REP':('Household','Survey replicate/stratum-like field; verify codebook','Sampling metadata; not model feature'),
     'H04_SEX':('Household','Household reference person sex code','Sensitive/fairness review before model use'),
     'H05_AGE':('Household','Household reference person age','Candidate demographic feature after fairness review'),
     'H12_HGC':('Household','Household reference person education code','Verify codebook'),
     'K4':('RTK other relevant information','Raw coded numeric K4','Verify exact financial variable definition'),
     'K5':('RTK other relevant information','Raw coded numeric K5','Verify exact financial variable definition'),
     'G15_KIT':('RTG5 social protection/disaster','Disaster preparedness kit response code','Candidate after codebook validation'),
     'G16_NAT_DISAS':('RTG5 social protection/disaster','Natural disaster experience response code','Candidate after codebook validation'),
     'G16A_EVAC':('RTG5 social protection/disaster','Evacuation response code, conditional; blank preserved','Candidate after codebook validation'),
     'G16B_RECOV':('RTG5 social protection/disaster','Recovery response code, conditional; blank preserved','Candidate after codebook validation'),
     'G16C_HELP':('RTG5 social protection/disaster','Original combined disaster help code string','Categorical, codebook needed'),
     'G13_PHEALTH':('RTG5 social protection/disaster','Original PhilHealth response code','Review carefully; aid receipt not a vulnerability ground truth'),
     'WS1':('RTJ WASH','Original water source response code','Candidate after codebook validation'),
     'WS11A':('RTJ WASH','Original sanitation response code','Candidate after codebook validation'),
    }
    for f in MEM_FIELDS:
        if f=='MEM_ROSTER_MATCHES_FSIZE': desc='1 if member rows equal FSIZE, otherwise 0'; guide='Quality flag only; never use as model feature'
        elif f=='MEM_ROSTER_SHORTFALL': desc='FSIZE minus member record rows'; guide='Quality flag only; never use as model feature'
        elif f=='MEMBER_ROWS': desc='Number of member record rows'; guide='Audit roster coverage'
        elif f=='MEM_D44_DISEASE_CODE1_COUNT': desc='Count of members where raw D44_DISEASE response is coded 1';guide='Review health variable semantics and privacy before model use'
        else: desc='Count of members in an age bracket using available member rows';guide='Candidate only after checking roster completeness'
        descriptions[f]=('Member Record',desc,guide)
    for keyname,(cat,response,codes) in PROGRAM_SPECS.items():
        label={'g1':'RTG1 social insurance','g2':'RTG2 social assistance','g3':'RTG3 labor intervention','g4':'RTG4 feeding programs','h':'RTH government services'}[keyname]
        for c in codes:
            f=f'{response}_RESPONSE_{c}'
            descriptions[f]=(label,f'Original {response} response for category {cat}={c}; preserves 1/2 code','Categorical; program codebook needed')
        descriptions[f'{response}_CODE1_COUNT']=(label,f'Count of categories with {response} response exactly equal to 1','Neutral code count, not confirmed aid receipt')
    for f in HH_FIELDS:
        descriptions.setdefault(f,('Household Record','Original APIS household field; exact coding requires questionnaire/codebook','Review before use'))
    for f in G5_FIELDS:
        descriptions.setdefault(f,('RTG5 social protection/disaster','Original APIS social protection/disaster field; blank preserved','Codebook needed'))
    for f in HOUSING_FIELDS:
        descriptions.setdefault(f,('RTI Housing','Original APIS household housing response code','Potential feature after codebook validation'))
    for f in WATER_FIELDS:
        descriptions.setdefault(f,('RTJ WASH','Original APIS water/sanitation response code','Potential feature after codebook validation'))
    with dictfile.open('w',newline='',encoding='utf-8') as f:
        w=csv.writer(f,lineterminator='\n');w.writerow(['column','source','description','model_use_guidance'])
        for k in fields:
            w.writerow([k,*descriptions[k]])
    print(json.dumps({k:v for k,v in quality.items() if k not in ('source_sha256','sample')},indent=2))
    return quality

if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--input-dir',type=Path,required=True,help='Folder holding all 11 original APIS PUF CSVs')
    ap.add_argument('--output-dir',type=Path,required=True,help='Destination datasets/ folder')
    args=ap.parse_args()
    build(args.input_dir,args.output_dir)
