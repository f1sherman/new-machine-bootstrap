#!/usr/bin/env python3
"""Stage and run data-defined fragment studies through pinned Harbor."""
import argparse
from contextlib import contextmanager
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import tomllib
import uuid

import toml

ROOT = Path(__file__).resolve().parents[2]
HARBOR_VERSION = "0.26.0"
TLS_TIMEOUT_MARKER = 'EVAL_PRECREDENTIAL_TLS_TIMEOUT'

IMAGE_POLICIES = {"candidate": "allowlist", "verifier": "no-network"}
PINNED_ENVIRONMENT = "evals.runner.environment:PinnedDocker"
IMAGE_BUILD_TIMEOUT = 600


def is_image_id(value):
    return isinstance(value, str) and re.fullmatch(r"sha256:[0-9a-f]{64}", value) is not None


def digest(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()


def save(file, value):
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text(json.dumps(value, indent=2) + "\n")


def hashes(folder):
    result = {}
    for file in sorted(folder.rglob("*")):
        if file.is_symlink():
            raise ValueError(f"Inputs must not contain symlinks: {file}")
        if file.is_file():
            result[str(file.relative_to(folder))] = digest(file)
    return result


def compile_guidance(directory, output, assembler):
    if not any(directory.glob("*.md")):
        output.write_text("")
        return ""
    subprocess.run([str(assembler), str(directory), str(output)], check=True)
    return output.read_text()


def freeze_guidance(source, guidance, destination, ref=None):
    if ref is None:
        hashes(guidance)
        shutil.copytree(guidance, destination)
        return
    if not isinstance(ref, str) or not re.fullmatch(r"[0-9a-f]{40}", ref):
        raise ValueError("guidance_ref must be a full Git commit SHA")
    command = ["git", "--no-replace-objects", "-C", str(source)]
    repo = Path(subprocess.check_output(command + ["rev-parse", "--show-toplevel"], text=True).strip())
    relative = guidance.relative_to(repo)
    if subprocess.check_output(command + ["cat-file", "-t", ref], text=True).strip() != "commit":
        raise ValueError("guidance_ref must identify a commit")
    entries = subprocess.check_output(command + ["ls-tree", "--full-tree", "-rz", ref + ":" + relative.as_posix()])
    destination.mkdir(parents=True)
    for entry in entries.split(b"\0"):
        if not entry:
            continue
        metadata, filename = entry.split(b"\t", 1)
        mode, kind, oid = metadata.decode().split()
        path = Path(filename.decode())
        if mode not in ("100644", "100755") or kind != "blob" or path.is_absolute() or ".." in path.parts:
            raise ValueError("Pinned guidance must contain regular files inside its directory")
        target = destination / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(subprocess.check_output(command + ["cat-file", "blob", oid]))


def guidance_target(value):
    if value == "AGENTS.md" or re.fullmatch(r"skills/[a-z0-9][a-z0-9_-]*/SKILL\.md", value):
        return value
    raise ValueError("guidance_target must be AGENTS.md or skills/NAME/SKILL.md")


def stage(study_file, output, model, trials, *, conditions=("current", "without", "empty"),
          thinking="medium", max_turns=12):
    study = tomllib.loads(study_file.read_text())
    required = {"schema_version", "guidance_dir", "fragment", "tasks"}
    if not required <= set(study) or set(study) - required - {"assets", "template", "guidance_ref", "guidance_target", "pi_mode"} or study["schema_version"] != 1:
        raise ValueError("Study requires schema_version=1, guidance_dir, fragment, tasks")
    install_target = guidance_target(study.get("guidance_target", "AGENTS.md"))
    pi_mode = study.get("pi_mode", "json")
    if pi_mode not in ("json", "rpc"):
        raise ValueError("pi_mode must be json or rpc")
    if not conditions or len(set(conditions)) != len(conditions) or set(conditions) - {"current", "without", "empty"}:
        raise ValueError("Select distinct current, without, or empty conditions")
    if thinking not in ("medium", "xhigh") or not 1 <= max_turns <= 80:
        raise ValueError("Use medium/xhigh thinking and 1 to 80 native turns")
    source = study_file.parent
    guidance = (source / study["guidance_dir"]).resolve()
    tasks = (source / study["tasks"]).resolve()
    fragment = study["fragment"]
    if Path(fragment).name != fragment or not fragment.endswith(".md"):
        raise ValueError("fragment must name a file in guidance_dir")
    hashes(tasks)
    frozen = output / "inputs"
    freeze_guidance(source, guidance, frozen / "guidance", study.get("guidance_ref"))
    if not (frozen / "guidance" / fragment).is_file():
        raise ValueError("fragment must name a file in guidance_dir at the selected ref")
    if "template" in study:
        template = source / study["template"]
        hashes(template)
        shutil.copytree(template, frozen / "template")
        for task in sorted(tasks.iterdir()):
            if not task.is_dir():
                raise ValueError("Task entries must be directories")
            destination = frozen / "tasks" / task.name
            shutil.copytree(frozen / "template", destination)
            shutil.copytree(task, destination, dirs_exist_ok=True)
    else:
        shutil.copytree(tasks, frozen / "tasks")
    infrastructure = frozen / "infrastructure/evals"
    shutil.copytree(ROOT / "evals/runner", infrastructure / "runner", ignore=shutil.ignore_patterns("__pycache__"))
    (infrastructure / "harbor").mkdir()
    shutil.copy2(ROOT / "evals/harbor/pi_login.py", infrastructure / "harbor/pi_login.py")
    shutil.copy2(study_file, frozen / "study.toml")
    shutil.copy2(ROOT / "bin/assemble-guidance", frozen / "assemble-guidance")
    for asset in study.get("assets", []):
        destination = Path(asset["destination"])
        if destination.is_absolute() or ".." in destination.parts:
            raise ValueError("Asset destinations must stay inside the task")
        for task in (frozen / "tasks").iterdir():
            target = task / destination
            target.parent.mkdir(parents=True, exist_ok=True)
            asset_source = source / asset["source"]
            if asset_source.is_symlink() or not asset_source.is_file():
                raise ValueError("Assets must be regular files")
            shutil.copy2(asset_source, target)
    hashes(frozen)
    assembler = frozen / "assemble-guidance"
    current = compile_guidance(frozen / "guidance", output / "current.md", assembler)
    skill_header = None
    header = None
    if install_target != 'AGENTS.md':
        header = re.match(r'\A\ufeff?---\r?\n.*?\r?\n---(?:\r?\n|$)', current, re.DOTALL)
        if not header:
            raise ValueError('Skill guidance requires frontmatter')
        skill_header = header.group()
    if 'without' in conditions:
        without = output / "without-fragment"
        shutil.copytree(frozen / "guidance", without)
        (without / fragment).unlink()
        removed_dir = output / "removed-fragment"
        removed_dir.mkdir()
        shutil.copy2(frozen / "guidance" / fragment, removed_dir / fragment)
        removed = compile_guidance(removed_dir, output / "removed.md", assembler)
        alternate = compile_guidance(without, output / "without.md", assembler)
        if current.count(removed) != 1 or current.replace(removed, "", 1) != alternate:
            raise ValueError("Ablation changes more than the selected fragment")
        if header and not alternate.startswith(header.group()):
            raise ValueError('Skill ablation must preserve its frontmatter unchanged')
    if 'empty' in conditions:
        (output / "empty.md").write_text("")
    cases = sorted(p.name for p in (frozen / "tasks").iterdir() if p.is_dir())
    if not cases:
        raise ValueError("No Harbor tasks")
    host = "chatgpt.com" if model.startswith("openai-codex/") else "api.openai.com"
    pi_version = subprocess.check_output(["ruby", "-ryaml", "-e",
        'puts YAML.safe_load(File.read(ARGV[0])).fetch("tool_versions").fetch("runtimes").fetch("pi_coding_agent")',
        str(ROOT / "vars/tool_versions.yml")], text=True).strip()
    matrix = []
    variants = tuple(conditions)
    for repeat in range(trials):
        for index, case in enumerate(cases):
            for offset in range(len(variants)):
                variant = variants[(offset + repeat + index) % len(variants)]
                matrix.append({"case": case, "condition": variant, "repeat": repeat})
    for case in cases:
        for variant in variants:
            task = output / "tasks" / variant / case
            shutil.copytree(frozen / "tasks" / case, task)
            if any((task / directory / "docker-compose.yaml").exists()
                   for directory in ("environment", "tests")) or (task / "tests/Dockerfile").exists():
                raise ValueError("Custom task Compose or verifier images are not supported")
            config_file = task / "task.toml"
            config = tomllib.loads(config_file.read_text())
            if "steps" in config:
                raise ValueError("Multi-step studies need a runner capability change")
            environment = config.setdefault("environment", {})
            if set(environment) - {"cpus", "memory_mb", "storage_mb", "build_timeout_sec"}:
                raise ValueError("Task images and networking are controlled by the shared runner")
            config["schema_version"] = "1.4"
            environment.update(network_mode="allowlist", allowed_hosts=[host],
                               cpus=1, memory_mb=1024, build_timeout_sec=600)
            agent = config.setdefault("agent", {})
            if set(agent) - {"timeout_sec"}:
                raise ValueError("Task agent settings may contain only timeout_sec")
            agent.update(user="worker", timeout_sec=min(agent.get("timeout_sec", 180), 900))
            verifier = config.setdefault("verifier", {})
            if set(verifier) - {"timeout_sec"}:
                raise ValueError("Task verifier settings may contain only timeout_sec")
            verifier.update(environment_mode="separate", user="root", network_mode="no-network",
                            environment={"network_mode": "no-network"},
                            timeout_sec=min(verifier.get("timeout_sec", 60), 120))
            config_file.write_text(toml.dumps(config))
            dockerfile = task / "environment/Dockerfile"
            text = dockerfile.read_text()
            if not text.startswith("FROM nmb-eval-runtime\n"):
                raise ValueError("Task Dockerfile must extend FROM nmb-eval-runtime")
    save(output / "restrictions.json", {"services": {"main": {
        "cap_drop": ["ALL"], "cap_add": ["CHOWN", "DAC_OVERRIDE", "FOWNER"],
        "security_opt": ["no-new-privileges:true"], "pids_limit": 128}}})
    manifest = {"schema_version": 3, "owner": str(uuid.uuid4()), "model": model,
        "pi_version": pi_version, "pi_mode": pi_mode, "harbor_version": HARBOR_VERSION, "fragment": fragment,
        "guidance_target": install_target, "guidance_skill_header": skill_header,
        "thinking": thinking, "max_turns": max_turns,
        "inference_host": host, "matrix": matrix, "input_hashes": hashes(frozen),
        "task_hashes": hashes(output / "tasks"),
        "condition_hashes": {name: digest(output / f"{name}.md") for name in variants},
        "restrictions_sha256": digest(output / "restrictions.json")}
    save(output / "manifest.json", manifest)
    return manifest


def check_image_proof(trial, expected, sidecar):
    containers = []
    for role, policy in IMAGE_POLICIES.items():
        path = trial / f"{role}-image.json"
        if not path.is_file():
            raise ValueError(f"Missing {role} image proof: {path}")
        proof = json.loads(path.read_text())
        if not is_image_id(expected[role]) or proof.get("image") != expected[role]:
            raise ValueError(f"Mismatched {role} image proof: {path}")
        container = proof.get("container", "")
        if not isinstance(container, str) or not re.fullmatch(r"[0-9a-f]{64}", container):
            raise ValueError(f"Invalid {role} container ID: {path}")
        if proof.get("policy") != policy:
            raise ValueError(f"Image proof has the wrong Harbor network policy: {path}")
        containers.append(container)
        sidecar_container = proof.get("sidecar_container")
        if (not is_image_id(sidecar) or proof.get("sidecar_image") != sidecar
                or not isinstance(sidecar_container, str)
                or not re.fullmatch(r"[0-9a-f]{64}", sidecar_container)
                or proof.get("network") != f"container:{sidecar_container}"):
            raise ValueError(f"Missing or mismatched {role} sidecar proof: {path}")
        containers.append(sidecar_container)
    if len(set(containers)) != len(containers):
        raise ValueError("Candidate and verifier image proof must identify separate containers")


def terminal_tool_turn(message, tail):
    # Pi can settle after a terminating tool, even if the tool reports an error.
    # Outcome belongs to the verifier; here require the completed native turn.
    events = [event for event in tail if event.get("type") in
              ("turn_start", "turn_end", "agent_start", "agent_end", "agent_settled")]
    if [event["type"] for event in events] != ["turn_end", "agent_end", "agent_settled"]:
        return False
    turn = events[0]
    if message.get("stopReason") != "toolUse" or turn.get("message") != message:
        return False
    calls = [(part.get("id"), part.get("name")) for part in message.get("content", [])
             if part.get("type") == "toolCall"]
    results = [(result.get("toolCallId"), result.get("toolName"))
               for result in turn.get("toolResults", []) if result.get("role") == "toolResult"]
    return (bool(calls) and all(call_id and name for call_id, name in calls)
            and len({call_id for call_id, _ in calls}) == len(calls) == len(results)
            and set(calls) == set(results))


def collect(job, row, image_pins=None, sidecar=None):
    results = []
    for file in job.rglob("result.json"):
        result = json.loads(file.read_text())
        if "task_name" in result:
            results.append((file, result))
    if len(results) != 1:
        raise ValueError("Expected exactly one Harbor trial result")
    file, result = results[0]
    if result.get("exception_info"):
        raise ValueError("Harbor trial failed; inspect " + str(file))
    if image_pins is not None:
        check_image_proof(file.parent, image_pins, sidecar)
    rewards = result.get("verifier_result", {}).get("rewards")
    if not rewards or not all(type(value) in (int, float) and value in (0, 1) for value in rewards.values()):
        raise ValueError("Verifier must produce named binary rewards")
    boundary = file.parent / "agent/boundary.json"
    if not json.loads(boundary.read_text()).get("inference_tls"):
        raise ValueError("Missing successful sandbox preflight")
    events = []
    for line in (file.parent / "agent/pi.txt").read_text().split("\n"):
        try:
            events.append(json.loads(line))
        except ValueError:
            continue
    settled = [event for event in events if event.get("type") == "agent_settled"]
    messages = [(i, event["message"]) for i, event in enumerate(events)
                if event.get("type") == "message_end" and event.get("message", {}).get("role") == "assistant"]
    if not settled or settled[-1].get("aborted") is not False or not messages:
        raise ValueError("Native agent did not finish with a terminal response")
    index, message = messages[-1]
    terminal_text = (message.get("stopReason") == "stop"
                     and not any(part.get("type") == "toolCall" for part in message.get("content", [])))
    if not terminal_text and not terminal_tool_turn(message, events[index + 1:]):
        raise ValueError("Native agent did not finish with a terminal response")
    context = result.get("agent_result") or {}
    usage = {name: context.get(name) for name in ("n_input_tokens", "n_output_tokens", "n_cache_tokens")}
    if any(value is None for value in usage.values()):
        raise ValueError("Incomplete native agent usage")
    return {**row, "status": "complete", "passed": all(rewards.values()),
            "checks": rewards, "usage": usage,
            "evidence": str(file.parent.relative_to(job.parent.parent))}


def summarize(rows):
    pairs = []
    for baseline in (row for row in rows if row["condition"] == "current"):
        for condition in ("without", "empty"):
            match = next((row for row in rows if row["case"] == baseline["case"]
                and row["repeat"] == baseline["repeat"] and row["condition"] == condition), None)
            if match and baseline["passed"] and match["passed"]:
                pairs.append({"case": baseline["case"], "repeat": baseline["repeat"],
                    "condition": condition, "current": baseline["usage"], "alternative": match["usage"]})
    return {"successful_matched_usage": pairs,
        "usage_scope": "Harbor native main-agent usage. Input includes cache tokens; cache is a subset, not an added total. Failure usage stays in raw evidence only."}


def audit_recovery_origin(output):
    output = output.resolve()
    claim = output / 'setup-recovery.json'
    if not claim.exists():
        report = json.loads((output / 'report.json').read_text())
        if 'recovered_setup_errors' in report or list(output.glob('before-setup-recovery-*.json')):
            raise ValueError('Recovery claim missing; preserve historical controller evidence')
        return
    original = output / 'before-setup-recovery-receipts.json'
    if (not original.is_file() or digest(original) !=
            json.loads(claim.read_text())['original_receipts_sha256']):
        raise ValueError('Recovery origin receipts changed')
    for name, expected in json.loads(original.read_text()).items():
        saved = 'before-setup-recovery-' + name if name in ('report.json', 'summary.json') else name
        file = (output / saved).resolve()
        if not file.is_relative_to(output) or not file.is_file() or digest(file) != expected:
            raise ValueError('Recovery origin evidence changed: ' + name)


def seal(output):
    audit_recovery_origin(output)
    files = [output / "manifest.json", output / "report.json", output / "summary.json"]
    files += [output / 'setup-recovery.json']
    files += sorted(output.glob('before-setup-recovery-*.json'))
    files += sorted((output / "jobs").rglob("*")) if (output / "jobs").exists() else []
    files += sorted((output / "image-builds").glob("*.log"))
    files += [output / name for name in ("runtime-build.log", "sidecar-build.log")]
    save(output / "receipts.json", {str(file.relative_to(output)): digest(file)
         for file in files if file.is_file()})


def audit(output):
    output = output.resolve()
    audit_recovery_origin(output)
    receipts = json.loads((output / "receipts.json").read_text())
    for name, expected in receipts.items():
        file = (output / name).resolve()
        if not file.is_relative_to(output) or digest(file) != expected:
            raise ValueError("Evidence changed: " + name)
    manifest = json.loads((output / "manifest.json").read_text())
    report = json.loads((output / "report.json").read_text())
    if not report["results"] and any(row.get("phase") == "image-prebuild" for row in report["errors"]):
        raise ValueError("Run is incomplete: image prebuild failed before candidate launch")
    version = manifest["schema_version"]
    sidecar = None
    if version == 3:
        sidecar = manifest.get("sidecar_image")
        if not is_image_id(sidecar) or not (output / "inputs/harbor-sidecar/Dockerfile").is_file():
            raise ValueError("Missing sidecar image pin or frozen source")
        pins = manifest.get("image_pins")
        if not isinstance(pins, dict) or pins.keys() != {row["case"] for row in manifest["matrix"]}:
            raise ValueError("Missing or invalid prebuilt image pins")
        if "manifest.json" not in receipts:
            raise ValueError("Missing manifest receipt")
        for row in manifest["matrix"]:
            expected = pins[row["case"]]
            task = output / "tasks" / row["condition"] / row["case"] / "task.toml"
            config = tomllib.loads(task.read_text())
            candidate = config["environment"].get("docker_image")
            verifier = config["verifier"]["environment"].get("docker_image", candidate)
            if (expected != {"candidate": candidate, "verifier": verifier}
                    or not all(is_image_id(value) for value in expected.values())):
                raise ValueError(f"Task configuration does not match prebuilt image pins: {task}")
    elif version == 1 and "image_pins" not in manifest:
        pins = None
    else:
        raise ValueError("Unknown image evidence contract")
    for directory, key in (("inputs", "input_hashes"), ("tasks", "task_hashes")):
        if hashes(output / directory) != manifest[key]:
            raise ValueError("Frozen inputs changed: " + directory)
    for name, expected in manifest["condition_hashes"].items():
        if digest(output / f"{name}.md") != expected:
            raise ValueError("Guidance changed: " + name)
    if digest(output / "restrictions.json") != manifest["restrictions_sha256"]:
        raise ValueError("Sandbox restrictions changed")
    for index, row in enumerate(report["results"]):
        planned = manifest["matrix"][index]
        expected_job = f"run-{index}-{manifest['owner'][:8]}"
        job_name = row.get('job_name', expected_job)
        if job_name not in (expected_job, expected_job + '-setup-recovery'):
            raise ValueError('Invalid saved job name')
        job = output / 'jobs' / job_name
        actual = collect(job, planned, pins[planned["case"]] if pins is not None else None, sidecar)
        if pins is not None:
            for role in IMAGE_POLICIES:
                path = f'{actual["evidence"]}/{role}-image.json'
                if path not in receipts:
                    raise ValueError(f"Missing image receipt: {path}")
        if 'job_name' in row:
            actual['job_name'] = job_name
        # The saved location is a navigation hint, not a scoring input. Older
        # reports used host-absolute paths; relocation must not invalidate them.
        if actual != {**row, "evidence": actual["evidence"]}:
            raise ValueError("Report differs from native evidence")
    if report["errors"] or len(report["results"]) != len(manifest["matrix"]):
        raise ValueError("Run is incomplete")
    if summarize(report["results"]) != json.loads((output / "summary.json").read_text()):
        raise ValueError("Summary differs from native evidence")
    if pins is None:
        print("Historical run: actual task and verifier image IDs were not verified")
    else:
        print("Verified pinned candidate and verifier image IDs for every trial")
        print("Verified pinned egress sidecar image IDs and namespaces for both roles")
    print("Verified receipts, inputs, recorded native results, and summary; no Docker or model calls")


def docker_environment():
    return {key: os.environ[key] for key in (
        "PATH", "HOME", "LANG", "DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_CONFIG",
        "DOCKER_TLS_VERIFY", "DOCKER_CERT_PATH", "DOCKER_API_VERSION") if key in os.environ}


def image_id(image, env):
    output = subprocess.check_output(["docker", "image", "inspect", image,
        "--format", "{{.Id}}"], text=True, env=env, timeout=30).strip()
    if not is_image_id(output):
        raise ValueError(f"Docker returned no immutable ID for {image}")
    return output


def build_runtime(output, manifest, env):
    runtime = "nmb-eval-runtime:" + manifest["owner"]
    runtime_file = output / "inputs/infrastructure/evals/runner/Dockerfile"
    with (output / "runtime-build.log").open("w") as log:
        subprocess.run(["docker", "build", "--build-arg", f"PI_VERSION={manifest['pi_version']}",
            "-t", runtime, "-f", str(runtime_file), str(runtime_file.parent)],
            check=True, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=IMAGE_BUILD_TIMEOUT)
    manifest["runtime_image"] = image_id(runtime, env)
    # Each run owns its tag; concurrent studies cannot replace its base image.
    manifest["runtime_tag"] = runtime
    for dockerfile in (output / "tasks").rglob("Dockerfile"):
        dockerfile.write_text(dockerfile.read_text().replace("FROM nmb-eval-runtime\n", "FROM " + runtime + "\n", 1))
    manifest["task_hashes"] = hashes(output / "tasks")
    save(output / "manifest.json", manifest)


@contextmanager
def prebuild(output, log, *, case, roles):
    try:
        yield
    except (subprocess.SubprocessError, OSError, ValueError) as error:
        with (output / log).open("a") as stream:
            print(f"{type(error).__name__}: {error}", file=stream)
        save(output / "report.json", {"results": [], "errors": [{
            "phase": "image-prebuild", "status": "incomplete", "case": case,
            "roles": roles, "log": log, "error": str(error)}]})
        save(output / "summary.json", summarize([]))
        seal(output)
        raise


def build_task_images(output, manifest, env):
    (output / "image-builds").mkdir()
    pins = {}
    conditions = manifest["condition_hashes"]
    build_condition = next(iter(conditions))  # Image inputs are identical across conditions.
    for index, case in enumerate(sorted({row["case"] for row in manifest["matrix"]})):
        context = output / "tasks" / build_condition / case / "environment"
        tag = f'nmb-eval-task:{manifest["owner"]}-{index}'
        log_path = f"image-builds/{case}-candidate.log"
        with prebuild(output, log_path, case=case, roles=list(IMAGE_POLICIES)):
            if image_id(manifest["runtime_tag"], env) != manifest["runtime_image"]:
                raise ValueError("Frozen runtime image changed before task build")
            with (output / log_path).open("w") as log:
                subprocess.run(["docker", "build", "-t", tag, str(context)], env=env,
                               stdout=log, stderr=subprocess.STDOUT, check=True, timeout=IMAGE_BUILD_TIMEOUT)
            image = image_id(tag, env)
        pins[case] = {role: image for role in IMAGE_POLICIES}
    for case, images in pins.items():
        for condition in conditions:
            config_file = output / "tasks" / condition / case / "task.toml"
            config = tomllib.loads(config_file.read_text())
            config["environment"]["docker_image"] = images["candidate"]
            config_file.write_text(toml.dumps(config))
    manifest["image_pins"] = pins
    manifest["task_hashes"] = hashes(output / "tasks")
    save(output / "manifest.json", manifest)


def build_sidecar(output, manifest, env):
    from harbor.environments.docker.docker import DockerEnvironment

    context = output / "inputs/harbor-sidecar"
    tag = f'nmb-eval-sidecar:{manifest["owner"]}'
    with prebuild(output, "sidecar-build.log", case=None, roles=["egress-sidecar"]):
        shutil.copytree(DockerEnvironment._EGRESS_CONTROL_SIDECAR_CONTEXT_PATH, context, symlinks=True)
        manifest["input_hashes"] = hashes(output / "inputs")
        save(output / "manifest.json", manifest)
        with (output / "sidecar-build.log").open("w") as log:
            subprocess.run(["docker", "build", "-t", tag, str(context)], env=env,
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=IMAGE_BUILD_TIMEOUT)
        manifest["sidecar_image"] = image_id(tag, env)
        save(output / "manifest.json", manifest)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit", type=Path)
    parser.add_argument("--resume-unstarted", type=Path,
                        help=argparse.SUPPRESS)
    parser.add_argument("--study", type=Path)
    parser.add_argument("--model")
    parser.add_argument("--trials", type=int)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--conditions", nargs="+", choices=("current", "without", "empty"))
    parser.add_argument("--thinking", choices=("medium", "xhigh"))
    parser.add_argument("--max-turns", type=int)
    args = parser.parse_args()
    trial_overrides = any(value is not None for value in
                          (args.trials, args.conditions, args.thinking, args.max_turns))
    supplied_run_inputs = any(value is not None for value in (args.study, args.model, args.output))
    if args.audit:
        if supplied_run_inputs or trial_overrides or args.live or args.resume_unstarted:
            parser.error("Audit accepts only --audit")
        audit(args.audit.resolve())
        return
    if args.resume_unstarted:
        parser.error("Setup recovery is disabled; preserve the original run")
    if not args.study or not args.model or not args.output:
        parser.error("Supply --study, --model, and --output")
    if not args.model.startswith(("openai/", "openai-codex/")) or len(args.model.split("/")) != 2:
        parser.error("Use openai/model or openai-codex/model")
    args.trials = 2 if args.trials is None else args.trials
    args.conditions = ('current', 'without', 'empty') if args.conditions is None else args.conditions
    args.thinking = 'medium' if args.thinking is None else args.thinking
    args.max_turns = 12 if args.max_turns is None else args.max_turns
    if not 1 <= args.trials <= 10:
        parser.error("Use 1 to 10 repetitions")
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / "tmp"):
        parser.error("Keep evidence under this checkout's ignored tmp/")
    output.mkdir(parents=True, exist_ok=False)
    manifest = stage(args.study.resolve(), output, args.model, args.trials,
                     conditions=args.conditions, thinking=args.thinking, max_turns=args.max_turns)
    print(f"Staged {len(manifest['matrix'])} trials at {output}", flush=True)
    if not args.live:
        return
    if importlib.metadata.version("harbor") != HARBOR_VERSION:
        raise ValueError("Install the pinned Harbor version")
    env = docker_environment()
    env.update(PYTHONPATH=str(output / "inputs/infrastructure"), PYTHONDONTWRITEBYTECODE="1")
    oauth = args.model.startswith("openai-codex/")
    if oauth:
        env["PI_EVAL_HOST_PI"] = shutil.which("pi")
        env["PI_EVAL_HOST_AGENT_DIR"] = str(Path(os.environ.get("PI_CODING_AGENT_DIR", Path.home() / ".pi/agent")).resolve())
    else:
        env["OPENAI_API_KEY"] = os.environ["OPENAI_API_KEY"]
    host_tmp = output / "host-tmp"
    host_tmp.mkdir()
    env["TMPDIR"] = str(host_tmp)
    # Docker's embedded DNS forwarding can be blocked by the upstream sidecar.
    # Freeze only the already-allowed inference hostname, in both namespaces.
    # No additional egress or DNS destination is permitted.
    address = socket.getaddrinfo(manifest['inference_host'], 443, socket.AF_INET, socket.SOCK_STREAM)[0][4][0]
    manifest['inference_address'] = address
    restrictions = json.loads((output / 'restrictions.json').read_text())
    restrictions['services']['harbor-docker-egress-control-sidecar'] = {
        'extra_hosts': [manifest['inference_host'] + ':' + address]}
    save(output / 'restrictions.json', restrictions)
    manifest['restrictions_sha256'] = digest(output / 'restrictions.json')
    env['EVAL_INFERENCE_ADDRESS'] = address
    report = {"results": [], "errors": []}
    save(output / "report.json", report)
    with prebuild(output, "runtime-build.log", case=None, roles=["runtime"]):
        build_runtime(output, manifest, env)
    build_task_images(output, manifest, env)
    build_sidecar(output, manifest, env)
    env["NMB_EVAL_SIDECAR_IMAGE"] = manifest["sidecar_image"]
    harbor = str(Path(sys.executable).parent / "harbor")
    for index, row in enumerate(manifest["matrix"]):
        job = f"run-{index}-{manifest['owner'][:8]}"
        env["EVAL_PI_MODE"] = manifest["pi_mode"]
        env["EVAL_GUIDANCE_FILE"] = str(output / (row["condition"] + ".md"))
        env["EVAL_GUIDANCE_TARGET"] = manifest["guidance_target"]
        env["EVAL_GUIDANCE_SKILL_HEADER"] = manifest.get('guidance_skill_header') or ''
        pins = manifest["image_pins"][row["case"]]
        env["NMB_EVAL_IMAGE_PINS"] = json.dumps(pins)
        command = [harbor, "run", "--path", str(output / "tasks" / row["condition"] / row["case"]),
            "--agent", "evals.runner.agent:SandboxedPi", "--model", args.model,
            "--agent-kwarg", "skip_install=true", "--agent-kwarg", f"version={manifest['pi_version']}",
            "--agent-kwarg", f"thinking={manifest['thinking']}",
            "--agent-kwarg", f"max_turns={manifest['max_turns']}",
            "--agent-env", "PI_TELEMETRY=0", "--agent-env", "PI_SKIP_VERSION_CHECK=1",
            "--n-attempts", "1", "--n-concurrent", "1", "--max-retries", "0",
            "--jobs-dir", str(output / "jobs"), "--job-name", job,
            "--env", PINNED_ENVIRONMENT, "--extra-docker-compose", str(output / "restrictions.json")]
        try:
            with (output / f"{job}.log").open("w") as log:
                subprocess.run(command, env=env, check=True, stdout=log, stderr=subprocess.STDOUT)
            report["results"].append(collect(output / "jobs" / job, row, pins, manifest["sidecar_image"]))
        except (subprocess.CalledProcessError, ValueError, OSError) as error:
            report["errors"].append({**row, "status": "incomplete", "error": str(error)})
            save(output / "report.json", report)
            save(output / "summary.json", summarize(report["results"]))
            seal(output)
            raise
        save(output / "report.json", report)
        save(output / "summary.json", summarize(report["results"]))
        seal(output)
    if any(not row["passed"] for row in report["results"] if row["condition"] == "current"):
        raise SystemExit("Current guidance failed; preserve all evidence")


if __name__ == "__main__":
    main()
