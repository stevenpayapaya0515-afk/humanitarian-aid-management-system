"""AidTrack: remove obsolete synthetic-era form questions without losing FIES fields.

Run from project root: py -3 fix_assessment_form.py
Requires database/22_remove_legacy_assessment_requirements.sql to be run in pgAdmin
before using the new form to save assessments.
"""
from __future__ import annotations

from pathlib import Path
import re
import shutil
import sys
from datetime import datetime

DART = Path('frontend/lib/screens/assessment/household_assessment.dart')
SCHEMA = Path('backend/schemas/assessments.py')
LEGACY = ('monthly_income_range', 'employment_status', 'livelihood_type', 'beneficiary_status')


def remove_once(source: str, pattern: str, title: str) -> str:
    updated, count = re.subn(pattern, '', source, count=0, flags=re.DOTALL)
    if count != 1:
        raise ValueError(f'{title}: expected exactly 1 match, found {count}. No files were changed.')
    return updated


def replace_once(source: str, before: str, after: str, title: str) -> str:
    count = source.count(before)
    if count != 1:
        raise ValueError(f'{title}: expected exactly 1 match, found {count}. No files were changed.')
    return source.replace(before, after, 1)



def replace_label(source: str, phrase_before: str, phrase_after: str, title: str) -> str:
    # Leave indentation to the actual file; text matches exactly once.
    return replace_once(source, phrase_before, phrase_after, title)

def update_dart(src: str) -> str:
    if 'Socioeconomic Information' not in src and "'monthly_income_range': _monthlyIncomeRange" not in src:
        if '_beneficiaryStatusController' not in src and 'FIES-style' in src:
            print('Flutter form already cleaned; skipping.')
            return src
        raise ValueError('Flutter form differs from expected source. No files were changed.')

    # Remove the old synthetic-era dropdowns, constants, state, and beneficiary field.
    src = remove_once(src,
        r'  // Beneficiary record\.\n  final _beneficiaryStatusController = TextEditingController\(text: .+?\);\n\n'
        r'  // Dropdown values matching the training dataset\.\n.*?(?=  static const List<String> _damageOptions =)',
        'Old socioeconomic dropdown definitions')

    src = remove_once(src,
        r'  String\? _monthlyIncomeRange;\n  String\? _employmentStatus;\n  String\? _livelihoodType;\n',
        'Old socioeconomic state')
    src = replace_once(src, '      _beneficiaryStatusController,\n', '', 'Old beneficiary listener')
    src = replace_once(src, '    _beneficiaryStatusController.dispose();\n', '', 'Old beneficiary disposal')
    src = remove_once(src,
        r'    if \(_beneficiaryStatusController\.text\.trim\(\)\.isEmpty\) \{\n.*?\n    \}\n\n',
        'Old beneficiary validation')

    for line, label in [
        ("        'monthly_income_range': _monthlyIncomeRange,\n", 'Monthly income API payload'),
        ("        'employment_status': _employmentStatus,\n", 'Employment API payload'),
        ("        'livelihood_type': _livelihoodType,\n", 'Livelihood API payload'),
        ("        'beneficiary_status': _beneficiaryStatusController.text.trim(),\n", 'Beneficiary status API payload'),
    ]:
        src = replace_once(src, line, '', label)

    # Form card: removes only the synthetic-era socioeconomic section, NOT financial
    # history or household demographics/APIS living-condition data.
    card = (r'            // ======================================\n'
            r'            // SOCIOECONOMIC INFORMATION\n'
            r'            // ======================================\n'
            r'.*?'
            r'            // ======================================\n'
            r'            // ASSISTANCE AND DISASTER INFORMATION\n'
            r'            // ======================================\n')
    updated, count = re.subn(card,
        '            // ======================================\n'
        '            // FAMILY FINANCIAL HISTORY (FIES-STYLE)\n'
        '            // ======================================\n',
        src, count=0, flags=re.DOTALL)
    if count != 1:
        raise ValueError(f'Obsolete socioeconomic form section: expected 1 match, found {count}.')
    src = updated

    # Make scope visible and avoid implying the research FIES model is connected.
    src = replace_once(src,
        "title: 'Family Income and Expenses',",
        "title: 'Annual Family Financial Information',",
        'Financial section heading')
    src = replace_once(src,
        "'Annual financial history for staff review.'",
        "'Selected FIES-style annual figures for staff review (not a full FIES survey).'",
        'Financial section subtitle')
    src = replace_once(src,
        "'Optional. Leave unknown amounts blank; enter 0 only when confirmed.'",
        "'Optional. Amounts below are in PHP for a full calendar year. Leave unknown values blank; enter 0 only if confirmed.'",
        'Financial input instruction')
    src = replace_once(src,
        "Questions adapted from FIES concepts. Saved for staff review; the current model uses living-condition answers.",
        "Selected FIES-style financial questions. The active APIS classification still uses living-condition answers; FIES machine learning is not yet activated.",
        'Research model clarification')
    src = replace_once(src,
        "title: 'Living Conditions',",
        "title: 'Household Living Conditions (APIS)',",
        'APIS heading clarification')
    src = replace_once(src,
        "'Record the household’s current living conditions. Select Unknown when information is unavailable.'",
        "'Coded answers used by the current APIS classifier. Select Unknown if unverified.'",
        'APIS subtitle clarification')

    for name in ('_monthlyIncomeRange', '_employmentStatus', '_livelihoodType',
                 '_beneficiaryStatusController', 'Socioeconomic Information'):
        if name in src:
            raise ValueError(f'Old field still present after transformation: {name}')
    for required in ('_buildFinancialHistory()', 'annual_food_expenditure',
                     'financial_reference_year', '_buildPopulationSummary()',
                     'roof_material', 'previous_humanitarian_assistance'):
        if required not in src:
            raise ValueError(f'Required existing behavior missing: {required}')
    return src


def update_schema(src: str) -> str:
    for field, max_length in [('monthly_income_range', 30), ('employment_status', 40),
                              ('livelihood_type', 50), ('beneficiary_status', 30)]:
        before = f'    {field}: str = Field(min_length=1, max_length={max_length})'
        after = f'    {field}: str | None = Field(default=None, max_length={max_length})'
        if before in src:
            src = replace_once(src, before, after, f'Backend {field}')
        elif after not in src:
            raise ValueError(f'Backend {field} declaration differs; aborting all changes.')
    return src


def main() -> int:
    for path in (DART, SCHEMA):
        if not path.is_file():
            print(f'ERROR: {path} not found. Run the script from the AidTrack project root.')
            return 1
    try:
        old_dart = DART.read_text(encoding='utf-8')
        old_schema = SCHEMA.read_text(encoding='utf-8')
        dart = update_dart(old_dart)
        schema = update_schema(old_schema)
        if old_dart == dart and old_schema == schema:
            print('Already applied. No further edits required.')
            return 0
    except ValueError as exc:
        print('NOT APPLIED:', exc)
        return 1

    # Complete every check above before touching user files.
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    originals = [(DART, old_dart, dart), (SCHEMA, old_schema, schema)]
    for path, old, new in originals:
        if old != new:
            backup = path.with_name(path.name + '.' + timestamp + '.bak')
            shutil.copy2(path, backup)
            path.write_text(new, encoding='utf-8')
            print(f'Updated {path}; backup: {backup}')
    print('Finished: obsolete assessment form fields removed; existing FIES and APIS questions preserved.')
    print('IMPORTANT: Run database/22_remove_legacy_assessment_requirements.sql in pgAdmin before saving assessments.')
    print('Then run flutter analyze and backend tests; no ML model was switched.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
