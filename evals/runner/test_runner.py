"""Exercise staging and evidence gates without Docker, inference, or credentials."""
from contextlib import redirect_stderr
import io
from importlib.util import module_from_spec, spec_from_file_location
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from evals.runner.run import (ROOT, main, stage, summarize, collect, hashes, guidance_target,
                             check_image_proof)


class RunnerTests(unittest.TestCase):
    def test_audit_and_recovery_reject_explicit_run_limits_before_access(self):
        frozen = str(ROOT / 'tmp/recovery-command-must-not-be-read')
        for mode in ('--audit', '--resume-unstarted'):
            for setting in (('--max-turns', '1'), ('--conditions', 'current'),
                            ('--thinking', 'medium'), ('--trials', '1'), ('--model', '')):
                with (
                    self.subTest(mode=mode, setting=setting),
                    patch('sys.argv', ['run', mode, frozen, *setting]),
                    patch('evals.runner.run.audit',
                          side_effect=AssertionError('Unexpected evidence access')) as audit,
                    patch('evals.runner.run.subprocess.run') as jobs,
                    redirect_stderr(io.StringIO()),
                ):
                    with self.assertRaises(SystemExit) as error:
                        main()
                    self.assertEqual(error.exception.code, 2)
                    audit.assert_not_called()
                    jobs.assert_not_called()

    def test_guidance_cannot_replace_credentials_or_escape_agent_directory(self):
        for path in ('auth.json', '../auth.json', '/tmp/auth.json',
                     'skills/x/../../auth.json', 'skills/../SKILL.md',
                     'skills/x/other.md', 'skills//SKILL.md'):
            with self.subTest(path=path), self.assertRaises(ValueError):
                guidance_target(path)
        self.assertEqual(guidance_target('skills/example/SKILL.md'), 'skills/example/SKILL.md')
        self.assertEqual(guidance_target('AGENTS.md'), 'AGENTS.md')

    def test_new_packages_and_cases_need_no_runner_changes(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            guidance = root / 'pieces'
            guidance.mkdir()
            (guidance / '01-one.md').write_text('First rule.\n')
            (guidance / '02-two.md').write_text('Second rule.\n')
            for case in ('write-a-note', 'edit-a-note'):
                task = root / 'tasks' / case
                (task / 'environment').mkdir(parents=True)
                (task / 'environment/Dockerfile').write_text('FROM nmb-eval-runtime\n')
                (task / 'instruction.md').write_text('Save the requested note.\n')
                (task / 'task.toml').write_text('schema_version = "1.4"\n')
            study = root / 'study.toml'
            study.write_text('schema_version = 1\nguidance_dir = "pieces"\nfragment = "02-two.md"\ntasks = "tasks"\n')
            output = root / 'run'
            output.mkdir()
            manifest = stage(study, output, 'openai/model', 2)
            self.assertEqual(len(manifest['matrix']), 12)
            self.assertEqual((output / 'current.md').read_text(), 'First rule.\nSecond rule.\n')
            self.assertEqual((output / 'without.md').read_text(), 'First rule.\n')
            self.assertEqual((output / 'empty.md').read_text(), '')
            self.assertEqual({row['case'] for row in manifest['matrix']}, {'write-a-note', 'edit-a-note'})
            self.assertNotEqual(manifest['matrix'][0]['condition'], manifest['matrix'][6]['condition'])
            (guidance / '01-one.md').unlink()
            single = root / 'single'
            single.mkdir()
            stage(study, single, 'openai/model', 1)
            self.assertEqual((single / 'current.md').read_text(), 'Second rule.\n')
            self.assertEqual((single / 'without.md').read_text(), '')
            (guidance / '01-one.md').write_text('First rule.\n')
            # A changed frozen task cannot retain the same input identity.
            before = manifest['task_hashes']
            (output / 'tasks/current/write-a-note/instruction.md').write_text('Different task')
            self.assertNotEqual(before, hashes(output / 'tasks'))
            # Task-local networking is rejected, never merged with the policy.
            (root / 'tasks/write-a-note/task.toml').write_text('[environment]\nnetwork_mode = "public"\n')
            other = root / 'other'
            other.mkdir()
            with self.assertRaisesRegex(ValueError, 'networking'):
                stage(study, other, 'openai/model', 1)
            (root / 'tasks/write-a-note/task.toml').write_text('schema_version = "1.4"\n')
            (root / 'tasks/write-a-note/environment/docker-compose.yaml').write_text(
                'services:\n  main:\n    network_mode: host\n')
            compose = root / 'compose'
            compose.mkdir()
            with self.assertRaisesRegex(ValueError, 'Custom task Compose'):
                stage(study, compose, 'openai/model', 1)

    def test_pinned_guidance_survives_fragment_removal(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            env = {'PATH': os.environ['PATH'], 'HOME': folder,
                   'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': os.devnull}

            def git(*args):
                return subprocess.check_output(['git', '-C', folder, *args], env=env, text=True).strip()

            git('init', '-q', '-b', 'main')
            git('config', 'user.name', 'Fixture')
            git('config', 'user.email', 'fixture@example.test')
            (root / 'pieces').mkdir()
            (root / 'pieces/01-one.md').write_text('First rule.\n')
            fragment = root / 'pieces/02-two.md'
            fragment.write_text('Second rule.\n')
            git('add', 'pieces')
            git('-c', 'commit.gpgsign=false', 'commit', '-qm', 'Original guidance')
            ref = git('rev-parse', 'HEAD')
            fragment.unlink()
            (root / 'pieces/01-one.md').write_text('Changed after study.\n')
            task = root / 'tasks/any-case'
            (task / 'environment').mkdir(parents=True)
            (task / 'environment/Dockerfile').write_text('FROM nmb-eval-runtime\n')
            (task / 'task.toml').write_text('schema_version = "1.4"\n')
            (task / 'instruction.md').write_text('Save a note.\n')
            (root / 'nested').mkdir()
            study = root / 'nested/study.toml'

            def run(ref, name):
                study.write_text('schema_version = 1\nguidance_dir = "../pieces"\n'
                    'fragment = "02-two.md"\ntasks = "../tasks"\n'
                    f'guidance_ref = "{ref}"\n')
                output = root / name
                output.mkdir()
                return output, stage(study, output, 'openai/model', 1)

            output, manifest = run(ref, 'pinned')
            self.assertEqual((output / 'current.md').read_text(), 'First rule.\nSecond rule.\n')
            self.assertEqual((output / 'without.md').read_text(), 'First rule.\n')
            self.assertEqual((output / 'inputs/guidance/02-two.md').read_text(), 'Second rule.\n')
            self.assertEqual(hashes(output / 'inputs'), manifest['input_hashes'])
            with self.assertRaisesRegex(ValueError, 'full Git commit SHA'):
                run('main', 'mutable-ref')
            (root / 'pieces/unsafe.md').symlink_to('01-one.md')
            git('add', 'pieces')
            git('-c', 'commit.gpgsign=false', 'commit', '-qm', 'Unsafe archived link')
            with self.assertRaisesRegex(ValueError, 'regular files'):
                run(git('rev-parse', 'HEAD'), 'unsafe-ref')

    def test_template_defaults_overrides_and_frozen_inputs(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'pieces').mkdir()
            (root / 'pieces/01-one.md').write_text('One rule.\n')
            template = root / 'template'
            (template / 'environment').mkdir(parents=True)
            (template / 'environment/Dockerfile').write_text('FROM nmb-eval-runtime\n')
            (template / 'task.toml').write_text('[agent]\ntimeout_sec = 40\n')
            (template / 'environment/fixture.txt').write_text('default')
            for name in ('default', 'override'):
                task = root / 'tasks' / name
                task.mkdir(parents=True)
                (task / 'instruction.md').write_text('Inspect fixture.txt.\n')
            override = root / 'tasks/override/environment'
            override.mkdir()
            (override / 'fixture.txt').write_text('case-specific')
            (root / 'helper.py').write_text('print("asset")\n')
            study = root / 'study.toml'
            study.write_text('schema_version = 1\nguidance_dir = "pieces"\n'
                'fragment = "01-one.md"\ntasks = "tasks"\ntemplate = "template"\n'
                '[[assets]]\nsource = "helper.py"\ndestination = "tests/helper.py"\n')
            output = root / 'run'
            output.mkdir()
            manifest = stage(study, output, 'openai/model', 1)
            self.assertEqual(len(manifest['matrix']), 6)
            for condition in ('current', 'without', 'empty'):
                tasks = output / 'tasks' / condition
                self.assertEqual((tasks / 'default/environment/fixture.txt').read_text(), 'default')
                self.assertEqual((tasks / 'override/environment/fixture.txt').read_text(), 'case-specific')
                self.assertEqual((tasks / 'default/tests/helper.py').read_text(), 'print("asset")\n')
                self.assertIn('timeout_sec = 40', (tasks / 'default/task.toml').read_text())
            (template / 'environment/fixture.txt').write_text('changed upstream')
            self.assertEqual(hashes(output / 'inputs'), manifest['input_hashes'])
            # Templates cannot grant networking that task settings cannot grant.
            (template / 'task.toml').write_text('[environment]\nnetwork_mode = "public"\n')
            rejected = root / 'rejected'
            rejected.mkdir()
            with self.assertRaisesRegex(ValueError, 'networking'):
                stage(study, rejected, 'openai/model', 1)

    def test_image_evidence_must_match_pins_and_keep_roles_separate(self):
        with tempfile.TemporaryDirectory() as folder:
            trial = Path(folder)
            task = 'sha256:' + 'a' * 64
            sidecar = 'sha256:' + 'b' * 64
            pins = {'candidate': task, 'verifier': task}
            proof = {}
            for role, policy, container, side in (('candidate', 'allowlist', '1', '2'),
                                                   ('verifier', 'no-network', '3', '4')):
                proof[role] = {'image': task, 'container': container * 64, 'policy': policy,
                               'sidecar_image': sidecar, 'sidecar_container': side * 64,
                               'network': 'container:' + side * 64}
                (trial / f'{role}-image.json').write_text(json.dumps(proof[role]))
            check_image_proof(trial, pins, sidecar)
            verifier = trial / 'verifier-image.json'
            for change in ({'image': sidecar}, {'sidecar_image': task}, {'network': 'bridge'},
                           {'container': proof['candidate']['container']}):
                verifier.write_text(json.dumps({**proof['verifier'], **change}))
                with self.subTest(change=change), self.assertRaises(ValueError):
                    check_image_proof(trial, pins, sidecar)
            verifier.unlink()
            with self.assertRaisesRegex(ValueError, 'Missing verifier image proof'):
                check_image_proof(trial, pins, sidecar)

    def test_setup_recovery_refuses_even_without_overrides(self):
        with (patch('sys.argv', ['run', '--resume-unstarted', 'unused']),
              redirect_stderr(io.StringIO()) as stderr, self.assertRaises(SystemExit)):
            main()
        self.assertIn('Setup recovery is disabled', stderr.getvalue())

    def test_judgments_refuse_ambiguous_and_unquoted_claims(self):
        path = Path(__file__).parent / 'templates/judgment/tests/verify.py'
        spec = spec_from_file_location('judgment_verifier', path)
        verifier = module_from_spec(spec)
        spec.loader.exec_module(verifier)
        document = 'The workflow remains inactive.'
        row = {'status': 'met', 'reason': 'The document limits activation.',
               'excerpts': [document]}
        value = {'criteria': {'scope': row}}
        self.assertEqual(verifier.validate(verifier.parse(json.dumps(value)), ['scope'], document), value)
        for status in ('met', 'contradicted'):
            unquoted = {'criteria': {'scope': {**row, 'status': status, 'excerpts': []}}}
            with self.subTest(status=status), self.assertRaisesRegex(ValueError, 'exact excerpt'):
                verifier.validate(unquoted, ['scope'], document)
        for status in ('missing', 'uncertain'):
            omitted = {'criteria': {'scope': {**row, 'status': status, 'excerpts': []}}}
            self.assertEqual(verifier.validate(omitted, ['scope'], document), omitted)
        for duplicate in ('{"criteria":{},"criteria":{}}',
                          '{"criteria":{"scope":{},"scope":{}}}',
                          '{"criteria":{"scope":{"status":"met","status":"missing"}}}'):
            with self.subTest(duplicate=duplicate), self.assertRaisesRegex(ValueError, 'Duplicate'):
                verifier.parse(duplicate)
        with self.assertRaises(ValueError):
            verifier.parse('{"criteria":')
        with self.assertRaises(ValueError):
            verifier.validate({**value, 'publish': True}, ['scope'], document)
        with self.assertRaises(ValueError):
            verifier.validate(value, ['another-criterion'], document)
        unsupported = {'criteria': {'scope': {**row, 'excerpts': ['An invented excerpt.']}}}
        with self.assertRaisesRegex(ValueError, 'Unsupported excerpt'):
            verifier.validate(unsupported, ['scope'], document)

    def test_native_evidence_and_successful_pair_gates(self):
        with tempfile.TemporaryDirectory() as folder:
            job = Path(folder)
            (job / 'agent').mkdir()
            result = {'task_name': 'any-task', 'verifier_result': {'rewards': {'task': 1, 'policy': 1}},
                'agent_result': {'n_input_tokens': 20, 'n_output_tokens': 2, 'n_cache_tokens': 10}}
            (job / 'result.json').write_text(json.dumps(result))
            (job / 'agent/boundary.json').write_text('{"inference_tls":true}')
            events = [{'type': 'message_end', 'message': {'role': 'assistant', 'stopReason': 'stop',
                'content': [{'type': 'text', 'text': 'Saved.'}]}}, {'type': 'agent_settled', 'aborted': False}]
            (job / 'agent/pi.txt').write_text('\n'.join(json.dumps(x) for x in events))
            plan = {'case': 'any-task', 'condition': 'current', 'repeat': 0}
            baseline = collect(job, plan)
            alternative = {**baseline, 'condition': 'without'}
            self.assertEqual(len(summarize([baseline, alternative])['successful_matched_usage']), 1)
            alternative['passed'] = False
            self.assertEqual(summarize([baseline, alternative])['successful_matched_usage'], [])
            events[-1]['aborted'] = True
            (job / 'agent/pi.txt').write_text('\n'.join(json.dumps(x) for x in events))
            with self.assertRaisesRegex(ValueError, 'terminal response'):
                collect(job, plan)
            result['exception_info'] = {'exception_message': 'timeout'}
            (job / 'result.json').write_text(json.dumps(result))
            with self.assertRaisesRegex(ValueError, 'trial failed'):
                collect(job, plan)


if __name__ == '__main__':
    unittest.main()
