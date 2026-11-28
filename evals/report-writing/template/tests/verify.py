"""Check document delivery and literal evidence, not the meaning of the report."""
from html.parser import HTMLParser
import json
from pathlib import Path
import re

REPORT = Path('/workspace/report.html')
LOGS = Path('/logs/verifier')
BLOCKS = set('address article aside blockquote br caption dd details dialog div dl dt '
             'fieldset figcaption figure footer h1 h2 h3 h4 h5 h6 header hgroup hr li '
             'main menu nav ol p pre search section summary table tbody td tfoot th thead tr ul'.split())


class Report(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.tags = set()
        self.problems = set()
        self.text = []
        self.in_style = False
        self.in_body = False

    def handle_starttag(self, tag, attrs):
        self.tags.add(tag)
        attributes = dict(attrs)
        if len(attributes) != len(attrs):
            self.problems.add('duplicate_attribute')
        attrs = attributes
        if tag == 'body':
            self.in_body = True
        if self.in_body and tag in BLOCKS:
            self.text.append(' ')
        if tag == 'style':
            self.in_style = True
        if tag in {'audio', 'base', 'embed', 'form', 'frame', 'frameset', 'iframe', 'link',
                   'math', 'object', 'portal', 'script', 'svg', 'template', 'video'}:
            self.problems.add(tag)
        if any(name.startswith('on') or name in {'src', 'srcdoc', 'srcset', 'background', 'ping'}
               for name in attrs):
            self.problems.add('active_or_resource_attribute')
        if tag == 'meta' and (attrs.get('http-equiv') or '').lower().strip() == 'refresh':
            self.problems.add('meta_refresh')
        href = (attrs.get('href') or '').strip()
        if href and not (tag == 'a' and (
                href.startswith(('#', 'https://', 'http://')) or supporting_path(href))):
            self.problems.add('unexpected_link_scheme')
        self.check_style(attrs.get('style') or '')

    def handle_endtag(self, tag):
        if self.in_body and tag in BLOCKS:
            self.text.append(' ')
        if tag == 'style':
            self.in_style = False
        if tag == 'body':
            self.in_body = False

    def check_style(self, css):
        if re.search(r'@import|url\s*\(|image-set\s*\(', css, re.I):
            self.problems.add('css_resource')

    def handle_data(self, data):
        if self.in_style:
            self.check_style(data)
        elif self.in_body:
            self.text.append(data)


def supporting_path(value):
    # Allow ordinary sibling paths and fragments, not schemes, parent traversal,
    # encoded paths, absolute paths, or protocol-relative URLs. Do not follow links.
    path = value.split('#', 1)[0].removeprefix('./')
    return bool(re.fullmatch(r'[\w.-]+(?:/[\w.-]+)*', path, re.ASCII)
                and all(part not in {'.', '..'} for part in path.split('/'))
                and not any(ord(c) < 32 or ord(c) == 127 for c in value))


def normalized(value):
    return ' '.join(value.replace('`', '').split())


def grade(path, expected):
    page = Report()
    zero = dict.fromkeys(['html', 'inert_surface', *expected], 0)
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= 256_000:
        return zero, {
            'report': 'missing, nonregular, empty, or larger than 256000 bytes'}
    try:
        page.feed(path.read_text(encoding='utf-8'))
        page.close()
    except (ValueError, UnicodeError, AssertionError):
        return zero, {
            'report': 'not parseable UTF-8 HTML'}
    body = normalized(''.join(page.text))
    missing = {key: [s for s in values if not (
        re.search(r'(?<![\w-])' + re.escape(s) + r'(?![\w-])', body)
        if key == 'row_ids' else normalized(s) in body)]
        for key, values in expected.items() if key not in {'success_tokens', 'private_usage'}}
    numbers = set(re.findall(r'\b\d+\b', re.sub(r'(?<=\d),(?=\d{3}\b)', '', body)))
    if 'success_tokens' in expected:
        missing['success_tokens'] = sorted(set(expected['success_tokens']) - numbers)
        missing['private_usage'] = sorted(set(expected['private_usage']) & numbers)
    checks = {'html': int({'html', 'title', 'body'} <= page.tags and bool(body)),
              'inert_surface': int(not page.problems),
              **{key: int(not values) for key, values in missing.items()}}
    return checks, {'missing_or_disallowed': missing, 'problems': sorted(page.problems)}


if __name__ == '__main__':
    expected = json.loads(Path('/tests/literals.json').read_text())
    checks, details = grade(REPORT, expected)
    LOGS.mkdir(parents=True, exist_ok=True)
    for name, value in (('reward', checks), ('assessment', details)):
        (LOGS / (name + '.json')).write_text(json.dumps(value) + '\n')
