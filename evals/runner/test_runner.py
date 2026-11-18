"""Exercise staging and evidence gates without Docker, inference, or credentials."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
from importlib.util import module_from_spec, spec_from_file_location
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest

from evals.runner.run import (stage, summarize, collect, hashes, guidance_target,
                             unstarted_setup_failure, claim_setup_recovery, seal, TLS_TIMEOUT_MARKER)


class RunnerTests(unittest.TestCase):
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
            with self.assertRaisesRegex(ValueError, 'Compose overrides'):
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

    def test_recovery_cannot_reroll_started_or_unsafe_trials(self):
        with tempfile.TemporaryDirectory() as folder:
            job = Path(folder)
            result = {'task_name': 'fixture', 'exception_info': {
                'exception_type': 'NetworkConnectionError',
                'exception_message': "Command failed: assert r.returncode == 0\n"
                    'stdout: Traceback (most recent call last):\n'
                    '  File "<stdin>", line 17, in <module>\n'
                    'AssertionError: curl: (28) Operation timed out after 15000 milliseconds with 0 bytes received\n'
                    '\n\nstderr: None'}, 'agent_result': None}
            saved = job / 'result.json'
            log = job / 'trial.log'
            log.write_text('Sandbox TLS probe failed before credential installation.\n')
            saved.write_text(json.dumps(result))
            unstarted_setup_failure(job)
            for message, error_type in (
                    (result['exception_info']['exception_message'].replace('15000', '15037'),
                     'NetworkConnectionError'),
                    (result['exception_info']['exception_message'].replace(
                        'curl: (28) Operation timed out after 15000 milliseconds with 0 bytes received',
                        TLS_TIMEOUT_MARKER), 'NonZeroAgentExitCodeError')):
                changed = {**result, 'exception_info': {**result['exception_info'],
                           'exception_message': message, 'exception_type': error_type}}
                saved.write_text(json.dumps(changed))
                unstarted_setup_failure(job)
            saved.write_text(json.dumps(result))
            for name in ('agent/pi.txt', 'agent/pi/sessions/native.jsonl'):
                path = job / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('native evidence')
                with self.subTest(name=name), self.assertRaises(ValueError):
                    unstarted_setup_failure(job)
                path.unlink()
            for marker in ('auth.json', 'pi --print'):
                log.write_text(marker)
                with self.subTest(marker=marker), self.assertRaises(ValueError):
                    unstarted_setup_failure(job)
            log.write_text('preflight failed')
            original = json.loads(saved.read_text())
            for field in ('n_input_tokens', 'n_output_tokens', 'n_cache_tokens'):
                changed = {**original, 'agent_result': {field: 1}}
                saved.write_text(json.dumps(changed))
                with self.subTest(field=field), self.assertRaises(ValueError):
                    unstarted_setup_failure(job)
            for message in ('Unexpected network access: https://example.com',
                            'assert r.returncode == 0', 'AssertionError: uid mismatch'):
                changed = json.loads(json.dumps(original))
                changed['exception_info']['exception_message'] = message
                saved.write_text(json.dumps(changed))
                with self.subTest(message=message), self.assertRaises(ValueError):
                    unstarted_setup_failure(job)
            # Probe source contains the TLS assertion even for a security failure.
            changed['exception_info']['exception_message'] = (
                f"Command contains raise AssertionError('{TLS_TIMEOUT_MARKER}')\n" +
                original['exception_info']['exception_message'].replace(
                    'AssertionError: curl: (28) Operation timed out after 15000 milliseconds with 0 bytes received',
                    'AssertionError: Unexpected network access: https://example.com'))
            saved.write_text(json.dumps(changed))
            with self.assertRaises(ValueError):
                unstarted_setup_failure(job)

    def test_recovery_cannot_reseal_changed_original_evidence(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            for name in ('manifest.json', 'report.json', 'summary.json'):
                (output / name).write_text('{}\n')
            failed = output / 'jobs/original/result.json'
            failed.parent.mkdir(parents=True)
            failed.write_text('original failed result\n')
            seal(output)
            claim_setup_recovery(output)
            for name in ('report.json', 'summary.json', 'receipts.json'):
                (output / ('before-setup-recovery-' + name)).write_bytes((output / name).read_bytes())
            (output / 'report.json').write_text('{"recovered_setup_errors": []}\n')
            seal(output)
            receipt = (output / 'receipts.json').read_bytes()
            for replacement in (None, 'changed failed result\n'):
                if replacement is None:
                    failed.unlink()
                else:
                    failed.write_text(replacement)
                with self.assertRaisesRegex(ValueError, 'Recovery origin evidence changed'):
                    seal(output)
                self.assertEqual((output / 'receipts.json').read_bytes(), receipt)
            failed.write_text('original failed result\n')
            seal(output)
            claim = output / 'setup-recovery.json'
            saved_claim = claim.read_bytes()
            claim.unlink()
            failed.unlink()
            with self.assertRaisesRegex(ValueError, 'Recovery claim missing'):
                seal(output)
            self.assertEqual((output / 'receipts.json').read_bytes(), receipt)
            claim.write_bytes(saved_claim)
            failed.write_text('original failed result\n')
            seal(output)
            (output / 'before-setup-recovery-receipts.json').write_text('{}\n')
            with self.assertRaisesRegex(ValueError, 'Recovery origin receipts changed'):
                seal(output)

    def test_setup_recovery_admits_one_overlapping_controller(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            original = b'{"original": "receipts"}\n'
            (output / 'receipts.json').write_bytes(original)
            ready = threading.Barrier(2)

            def claim():
                ready.wait(timeout=5)
                try:
                    claim_setup_recovery(output)
                    return 'admitted'
                except ValueError as error:
                    self.assertIn('already claimed', str(error))
                    return 'blocked'

            with ThreadPoolExecutor(max_workers=2) as pool:
                futures = [pool.submit(claim) for _ in range(2)]
                self.assertCountEqual([future.result(timeout=5) for future in futures],
                                      ['admitted', 'blocked'])
            saved = (output / 'setup-recovery.json').read_bytes()
            self.assertEqual(json.loads(saved)['original_receipts_sha256'],
                             hashlib.sha256(original).hexdigest())
            with self.assertRaisesRegex(ValueError, 'already claimed'):
                claim_setup_recovery(output)
            self.assertEqual((output / 'setup-recovery.json').read_bytes(), saved)
            self.assertEqual((output / 'receipts.json').read_bytes(), original)

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
