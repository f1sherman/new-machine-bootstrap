"""Grade terminal-command meaning and presentation using the shared sandbox."""
import json
from pathlib import Path
import re

from command_sandbox import execute, protect_verifier, terminal_response


def normalize(call, case):
    args = list(call['args'])
    if call['command'] == 'cat' and args[:1] == ['--']:
        args.pop(0)
    for canonical, aliases in case.get('options', {}).items():
        normalized = []
        for arg in args:
            option = next((name for name in [canonical, *aliases] if arg.startswith(name + '=')), None)
            if option:
                normalized.extend([canonical, arg[len(option) + 1:]])
            else:
                normalized.append(canonical if arg in aliases else arg)
        args = normalized
    return {'command': call['command'], 'args': args}


def grade(response, case):
    blocks = re.findall(r'```(?:bash|sh|shell|zsh)?[^\S\n]*\n(.*?)```', response, re.S)
    checks = {'answer_format': len(blocks) == 1, 'task': False,
              'line_limit': False, 'no_heredoc': False}
    details = {'checks': checks, 'shells': {}}
    if len(blocks) != 1:
        return details
    command = blocks[0]
    checks['answer_format'] = bool(command.strip())
    checks['line_limit'] = all(len(line) <= 80 for line in command.splitlines())
    # Conservative syntax screen; manual review distinguishes literal << data.
    checks['no_heredoc'] = '<<' not in command
    files = {}
    if case.get('program') in ('jq', 'awk'):
        files['input.json' if case['program'] == 'jq' else 'input.txt'] = case['input']
    successful = []
    for shell in ('bash', 'zsh'):
        observed = execute(command, shell, files=files, capture='calls' in case)
        details['shells'][shell] = observed
        valid = observed['status'] == 0 and not observed['timeout'] and not observed['stderr']
        if 'calls' in case:
            valid = valid and ([normalize(x, case) for x in observed['calls']]
                              == [normalize(x, case) for x in case['calls']])
        else:
            valid = valid and observed['stdout'] == case['stdout']
        successful.append(bool(valid))
    checks['task'] = all(successful)
    return details


if __name__ == '__main__':
    protect_verifier()
    result = grade(terminal_response(), json.loads(Path('/tests/case.json').read_text()))
    Path('/logs/verifier/assessment.json').write_text(json.dumps(result, indent=2) + '\n')
    Path('/logs/verifier/reward.json').write_text(json.dumps(
        {name: int(value) for name, value in result['checks'].items()}) + '\n')
