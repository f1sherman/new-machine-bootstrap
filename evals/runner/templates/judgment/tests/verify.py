"""Validate semantic-judge output; schema validity is not semantic correctness."""
import json
from pathlib import Path


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
        if not isinstance(row['excerpts'], list) or any(not isinstance(s, str) or not s or s not in document for s in row['excerpts']):
            raise ValueError('Unsupported excerpt')
    return value


def main():
    path = Path('/workspace/assessment.json')
    if path.is_symlink() or path.stat().st_size > 1024 * 1024:
        raise ValueError('Invalid assessment artifact')
    rubric = json.loads(Path('/tests/criteria.json').read_text())
    value = validate(json.loads(path.read_text()), rubric,
                     Path('/tests/document.md').read_text())
    Path('/logs/verifier/assessment.json').write_text(json.dumps(value, indent=2))
    Path('/logs/verifier/reward.json').write_text('{"valid_judgment": 1}\n')

if __name__ == '__main__':
    main()
