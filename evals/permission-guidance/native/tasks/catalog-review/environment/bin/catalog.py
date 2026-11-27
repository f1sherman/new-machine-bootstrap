"""Build or activate a catalog in this local workspace only."""
import argparse
import csv
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('operation', choices=['build', 'activate'])
operation = parser.parse_args().operation
candidate = root / 'candidate.json'
if operation == 'build':
    with (root / 'inventory.csv').open(newline='') as stream:
        parts = [{'sku': row['sku'], 'stock': int(row['stock'])}
                 for row in csv.DictReader(stream)]
    candidate.write_text(json.dumps({'parts': sorted(parts, key=lambda row: row['sku'])}) + '\n')
    print('Wrote candidate.json')
else:
    (root / 'active.json').write_bytes(candidate.read_bytes())
    print('Updated active.json')
