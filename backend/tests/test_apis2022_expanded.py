"""Run at backend root: python -m unittest tests.test_apis2022_expanded -v"""
import unittest
import pandas as pd
from ml_service.label_apis2022_expanded import (FEATURES, REQUIRED, add_proxy_labels,
    prepare, raw_feature_frame)
from ml_service.train_apis2022_expanded import group_split


def record(**overrides):
    base = dict(REG='16',HHID='00001',RPSU='1',I2='1',I3='01',I4='1',I8='1',
       WS1='11',WS11A='12',FSIZE='4',MEMBER_ROWS='4',MEM_ROSTER_MATCHES_FSIZE='1',
       MEM_AGE_0_5='0',MEM_AGE_6_11='0',MEM_AGE_12_17='0',MEM_AGE_60_PLUS='0',
       K5='20000',G15_KIT='1',G16_NAT_DISAS='2',G16A_EVAC='',G16B_RECOV='')
    base.update(overrides)
    return base

class ExpandedRubricTests(unittest.TestCase):
    def labelled(self, **changes):
        return add_proxy_labels(prepare(pd.DataFrame([record(**changes)],dtype=str)), 2500).iloc[0]

    def test_low_when_no_stressors(self):
        self.assertEqual(self.labelled()['expanded_proxy_class'], 'Low')

    def test_disaster_skip_is_not_negative_answer_imputation(self):
        item=self.labelled()
        self.assertEqual(float(item['proxy_disaster_disruption']),0)
        self.assertEqual(float(item['proxy_preparedness_gap']),0)

    def test_multi_domain_high_is_explicit_rule(self):
        item=self.labelled(K5='2000',G16_NAT_DISAS='1',G16A_EVAC='1',
                           G16B_RECOV='2',G15_KIT='2')
        self.assertEqual(item['expanded_proxy_class'], 'High')
        self.assertEqual(int(item['expanded_proxy_score']),3)

    def test_incomplete_member_roster_is_review(self):
        self.assertEqual(self.labelled(MEMBER_ROWS='3',MEM_ROSTER_MATCHES_FSIZE='0')['expanded_proxy_class'],'Needs review')

    def test_disaster_missing_followup_is_review(self):
        self.assertEqual(self.labelled(G16_NAT_DISAS='1',G16A_EVAC='',G16B_RECOV='')['expanded_proxy_class'],'Needs review')

    def test_invalid_shelter_code_is_review(self):
        self.assertEqual(self.labelled(I2='999')['expanded_proxy_class'],'Needs review')

    def test_no_target_or_sampling_identifiers_are_predictors(self):
        row=prepare(pd.DataFrame([record()],dtype=str))
        x=raw_feature_frame(row)
        self.assertEqual(x.columns.tolist(), FEATURES)
        self.assertTrue({'REG','HHID','RPSU','RFACT','expanded_proxy_class'}.isdisjoint(x.columns))

    def test_duplicate_households_fail(self):
        df=pd.DataFrame([record(),record()],dtype=str)
        with self.assertRaisesRegex(ValueError,'Duplicate'):
            prepare(df)

    def test_regions_and_psus_are_separated(self):
        records=[]
        for region in ('1','2','16'):
            for psu in range(10):
                for hh in range(2):
                    records.append(record(REG=region,RPSU=str(psu),HHID=f'{region}{psu}{hh}'))
        df=pd.DataFrame(records,dtype=str)
        train,noncaraga,caraga=group_split(df)
        self.assertEqual(len(caraga),20)
        self.assertEqual(set(df.iloc[train].REG),{'1','2'})
        a=set((df.iloc[train].REG+':'+df.iloc[train].RPSU))
        b=set((df.iloc[noncaraga].REG+':'+df.iloc[noncaraga].RPSU))
        self.assertTrue(a.isdisjoint(b))

if __name__ == '__main__': unittest.main()
