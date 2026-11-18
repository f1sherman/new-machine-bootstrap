"""Calibrate staged Python verifiers in disposable networkless containers; no inference."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

from evals.runner.run import ROOT, build_runtime, docker_environment, save, stage


def logged(command, file, env, timeout=600):
    with file.open('w') as log:
        subprocess.run(command, env=env, check=True, stdout=log, stderr=subprocess.STDOUT,
                       timeout=timeout)


def image_id(image, env):
    return subprocess.check_output(['docker', 'image', 'inspect', image,
        '--format', '{{.Id}}'], env=env, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--study', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / 'tmp'):
        parser.error("Keep calibration under this checkout's ignored tmp/")
    output.mkdir(parents=True, exist_ok=False)
    # Staging freezes the same task assembly as live execution. This model label
    # only satisfies the staging schema; calibration never starts an agent.
    manifest = stage(args.study.resolve(), output, 'openai/calibration', 1,
                     conditions=('current',))
    tasks = sorted((output / 'tasks/current').iterdir())
    for task in tasks:
        if not (task / 'tests/calibrate.py').is_file():
            raise ValueError('Supply tests/calibrate.py for ' + task.name)
    env = docker_environment()
    build_runtime(output, manifest, env)
    results = {'mode': 'calibration', 'inference_calls': 0, 'results': []}
    save(output / 'calibration.json', results)
    for index, task in enumerate(tasks):
        context = output / 'calibration' / task.name
        context.mkdir(parents=True)
        shutil.copytree(task / 'tests', context / 'tests')
        shutil.copy2(output / 'inputs/infrastructure/evals/runner/calibration.Dockerfile',
                     context / 'Dockerfile')
        image = f"nmb-eval-calibration:{manifest['owner']}-{index}"
        logged(['docker', 'build', '-t', image + '-task', str(task / 'environment')],
               context / 'task-build.log', env)
        logged(['docker', 'build', '--build-arg', 'TASK_IMAGE=' + image + '-task',
                '-t', image, str(context)], context / 'verifier-build.log', env)
        container = f"nmb-calibration-{manifest['owner']}-{index}"
        try:
            logged(['docker', 'run', '--rm', '--name', container,
                    '--label', 'nmb.eval.owner=' + manifest['owner'],
                    '--network', 'none', '--pids-limit', '128',
                    image, 'python3', '/tests/calibrate.py', task.name],
                   context / 'results.json', env, timeout=120)
        finally:
            # Remove only this run's exact container after an interrupted CLI.
            subprocess.run(['docker', 'rm', '-f', container], env=env, timeout=30,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        results['results'].append({'case': task.name,
            'task_image': image_id(image + '-task', env), 'verifier_image': image_id(image, env),
            'observations': json.loads((context / 'results.json').read_text())})
        save(output / 'calibration.json', results)
        print('Calibrated ' + task.name, flush=True)
    print(f"Calibrated {len(tasks)} tasks without inference at {output}")


if __name__ == '__main__':
    main()
