"""Validate semantic-judge output; schema validity is not semantic correctness."""
import json
from pathlib import Path


def parse(text):
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('Duplicate judgment key')
            result[key] = value
        return result
    return json.loads(text, object_pairs_hook=unique_object)


def validate(value, criteria, document):
    if not isinstance(value, dict) or set(value) != {'criteria'}:
        raise ValueError('Expected only criteria')
    rows = value['criteria']
    if not isinstance(rows, dict) or set(rows) != set(criteria):
        raise ValueError('Missing or unsupported criteria')
    for row in rows.values():
        if not isinstance(row, dict) or set(row) != {'status', 'reason', 'excerpts'}:
            raise ValueError('Unsupported judgment fields')
        if row['status'] not in ('met', 'missing', 'contradicted', 'uncertain'):
            raise ValueError('Unsupported status')
        if not isinstance(row['reason'], str) or not row['reason'].strip():
            raise ValueError('Missing explanation')
        if not isinstance(row['excerpts'], list) or any(not isinstance(s, str) or not s.strip() or s not in document for s in row['excerpts']):
            raise ValueError('Unsupported excerpt')
        if row['status'] in ('met', 'contradicted') and not row['excerpts']:
            raise ValueError('A supported or contradictory claim needs an exact excerpt')
    return value


def main():
    # Invalid judge output is missing measurement, not a candidate's scored
    # behavioral failure. Let Harbor retain it as an incomplete trial.
    path = Path('/workspace/assessment.json')
    if path.is_symlink() or path.stat().st_size > 1024 * 1024:
        raise ValueError('Invalid assessment artifact')
    # A separate verifier rebuilds the frozen task image. These are its baked
    # inputs, not captured outputs; do not declare reference inputs as artifacts.
    artifact = Path('/workspace/artifact')
    rubric = parse((artifact / 'rubric.json').read_text())
    if not isinstance(rubric, dict) or not rubric:
        raise ValueError('Invalid frozen rubric')
    value = validate(parse(path.read_text()), rubric,
                     (artifact / 'document.md').read_text())
    Path('/logs/verifier/assessment.json').write_text(json.dumps(value, indent=2))
    Path('/logs/verifier/reward.json').write_text('{"valid_judgment": 1}\n')

if __name__ == '__main__':
    main()
