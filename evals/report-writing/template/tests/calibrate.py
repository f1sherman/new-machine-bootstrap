"""Run the Harbor entry point on known constructions, without using a model."""
import html
import json
from pathlib import Path
import subprocess
import sys

from verify import LOGS, REPORT

case = sys.argv[1]
literals = json.loads(Path('/tests/literals.json').read_text())
reward = LOGS / 'reward.json'


def verify():
    reward.unlink(missing_ok=True)
    subprocess.run(['sh', '/tests/test.sh'], check=True)
    return json.loads(reward.read_text())


passed = dict.fromkeys(['html', 'inert_surface', *literals], 1)
all_text = [html.escape(value) for key, values in literals.items()
            if key != 'private_usage' for value in values]
main = '<main><h1>Reference</h1>' + ''.join(f'<p>{value}</p>' for value in all_text) + '</main>'
alternate = '<h1>Reference</h1><details><summary>Evidence</summary><ul>' + ''.join(
    f'<li>{value}</li>' for value in reversed(all_text)) + '</ul></details>'
results = {}
regressions = []
if 'exact_prompt' in literals:
    regressions.append(('paraphrased_prompt', main.replace(html.escape(literals['exact_prompt'][0]),
                        'A task summary.'), passed | {'exact_prompt': 0}))
if 'success_tokens' in literals:
    value = literals['success_tokens'][0]
    regressions.extend([
        ('missing_success_usage', main.replace(value, 'unknown'), passed | {'success_tokens': 0}),
        ('leaked_failure_usage', main + '<p>9,481</p>', passed | {'private_usage': 0}),
        ('leaked_incomplete_usage', main + '<p>9,157</p>', passed | {'private_usage': 0}),
        ('equivalent_usage_separator', main.replace(value, '4,379'), passed),
    ])
for label, text, expected in (
    ('no_output', None, dict.fromkeys(passed, 0)),
    ('known_literals', main, passed),
    ('equivalent_markup', alternate, passed),
    ('missing_row_not_fixed_by_comment', main.replace(all_text[0], '<!-- '+all_text[0]+' -->'),
     passed | {'row_ids': 0}),
    ('altered_guidance', main.replace(html.escape(literals['tested_guidance'][0]), 'Paraphrase.'),
     passed | {'tested_guidance': 0}),
    ('missing_exact_output', main.replace(html.escape(literals['exact_outputs'][-1]), 'A plausible paraphrase.'),
     passed | {'exact_outputs': 0}),
    ('remote_asset', main + '<link rel="stylesheet" href="https://example.invalid/style.css">',
     passed | {'inert_surface': 0}),
    ('inline_script', main + '<script>1</script>', passed | {'inert_surface': 0}),
    ('duplicate_attribute', main + '<p class="a" class="b">Ambiguous markup</p>',
     passed | {'inert_surface': 0}),
    ('supporting_relative_links', main + '<a href="evidence/study.md">Study</a>'
     '<a href="./results.md#limits">Results</a>', passed),
    ('relative_stylesheet', main + '<link rel="stylesheet" href="style.css">',
     passed | {'inert_surface': 0}),
    ('relative_image', main + '<img src="figure.png" alt="Figure">',
     passed | {'inert_surface': 0}),
    ('relative_css_fetch', main + '<style>p{background:url(figure.png)}</style>',
     passed | {'inert_surface': 0}),
    ('script_navigation', main + '<a href="javascript:void(0)">Bad link</a>',
     passed | {'inert_surface': 0}),
    ('parent_navigation', main + '<a href="../private.md">Bad link</a>',
     passed | {'inert_surface': 0}),
    *regressions,
):
    REPORT.unlink(missing_ok=True)
    if text is not None:
        REPORT.write_text('<!doctype html><html lang="en"><head><title>Test</title></head>'
                          f'<body>{text}</body></html>')
    result = verify()
    if result != expected:
        raise AssertionError((case, label, result, expected))
    results[label] = result
print(json.dumps(results))
