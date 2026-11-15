"""Exercise staging and evidence gates without Docker, inference, or credentials."""
import json
from pathlib import Path
import tempfile
import unittest

from evals.runner.run import stage, summarize, collect, hashes


class RunnerTests(unittest.TestCase):
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
