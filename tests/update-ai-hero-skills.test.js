import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const PROJECT_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const UPDATER = path.join(PROJECT_ROOT, "bin/update-ai-hero-skills");
const TAG = "v-test";
const GRILL_WITH_DOCS_PREIMAGE = "Run a `/grilling` session, using the `/domain-modeling` skill.";
const GRILL_WITH_DOCS_REPLACEMENT = "Use the harness's skill mechanism, when available, to load and follow both the `grilling` and `domain-modeling` skills. Otherwise, read and follow the sibling files `../grilling/SKILL.md` and `../domain-modeling/SKILL.md`.";
const MERGE_PREIMAGE = "Always resolve; never `--abort`.";
const MERGE_REPLACEMENT = "Continue a clearly intended operation and do not `--abort` merely because resolution is difficult. If the available context cannot establish whether the operation itself should continue, stop and ask a human to decide.";
const SKILLS = {
  "grill-with-docs": "skills/engineering/grill-with-docs",
  "domain-modeling": "skills/engineering/domain-modeling",
  "resolving-merge-conflicts": "skills/engineering/resolving-merge-conflicts",
  grilling: "skills/productivity/grilling",
  "wait-what": "skills/productivity/wait-what",
  "writing-for-agents": "skills/productivity/writing-for-agents",
};
const DEEP_DESIGN_SKILLS = ["grill-with-docs", "domain-modeling", "grilling"];

function git(cwd, ...args) {
  return execFileSync("git", args, { cwd, encoding: "utf8" }).trim();
}

function write(root, relativePath, contents) {
  const destination = path.join(root, relativePath);
  mkdirSync(path.dirname(destination), { recursive: true });
  writeFileSync(destination, contents);
}

function createFixture() {
  const root = mkdtempSync(path.join(tmpdir(), "update-ai-hero-skills-test-"));
  const upstream = path.join(root, "upstream");
  const repoRoot = path.join(root, "consumer");
  mkdirSync(upstream);
  mkdirSync(path.join(repoRoot, "vars"), { recursive: true });
  writeFileSync(path.join(repoRoot, "vars/tool_versions.yml"), `---\ntool_versions:\n  git_tags:\n    mattpocock_skills: ${TAG}\n`);
  writeFileSync(path.join(upstream, "LICENSE"), "fixture MIT license\n");

  for (const [name, sourcePath] of Object.entries(SKILLS)) {
    let body = "Fixture body.";
    if (name === "grill-with-docs") body = GRILL_WITH_DOCS_PREIMAGE;
    if (name === "resolving-merge-conflicts") body = `Fixture body. ${MERGE_PREIMAGE}`;
    write(upstream, `${sourcePath}/SKILL.md`, `---\nname: ${name}\ndescription: Fixture ${name}\n---\n\n# ${name}\n\n${body}\n`);
    write(upstream, `${sourcePath}/agents/openai.yaml`, `interface:\n  display_name: "${name}"\n  short_description: "Fixture ${name}"\n`);
    write(upstream, `${sourcePath}/support/nested.txt`, `support for ${name}\n`);
  }
  write(upstream, "skills/engineering/not-selected/SKILL.md", "must not be copied\n");

  git(upstream, "init", "--quiet");
  git(upstream, "config", "user.name", "Fixture");
  git(upstream, "config", "user.email", "fixture@example.com");
  git(upstream, "add", ".");
  git(upstream, "commit", "--quiet", "-m", "fixture release");
  git(upstream, "tag", "-a", TAG, "-m", "fixture tag");

  return { root, upstream, repoRoot };
}

function runUpdater(fixture, ...args) {
  return spawnSync(process.execPath, [UPDATER, "--repo-root", fixture.repoRoot, "--source", fixture.upstream, ...args], {
    encoding: "utf8",
  });
}

function generatedSkill(fixture, name) {
  return path.join(fixture.repoRoot, "roles/common/files/vendor/mattpocock-skills", name);
}

function commitFixture(upstream, message) {
  git(upstream, "add", "-A");
  git(upstream, "commit", "--quiet", "-m", message);
}

function moveTag(upstream) {
  git(upstream, "tag", "-f", "-a", TAG, "-m", "moved fixture tag");
}

function withFixture(fn) {
  const fixture = createFixture();
  try {
    fn(fixture);
  } finally {
    rmSync(fixture.root, { recursive: true, force: true });
  }
}

test("generates only complete selected skills with adaptations and metadata", () => withFixture((fixture) => {
  const result = runUpdater(fixture);
  assert.equal(result.status, 0, result.stderr);

  const vendorRoot = path.dirname(generatedSkill(fixture, "grilling"));
  assert.deepEqual(readdirSync(vendorRoot).sort(), Object.keys(SKILLS).sort());
  for (const name of Object.keys(SKILLS)) {
    const destination = generatedSkill(fixture, name);
    assert.equal(readFileSync(path.join(destination, "support/nested.txt"), "utf8"), `support for ${name}\n`);
    assert.equal(readFileSync(path.join(destination, "LICENSE"), "utf8"), "fixture MIT license\n");
    const provenance = readFileSync(path.join(destination, "UPSTREAM.md"), "utf8");
    assert.match(provenance, new RegExp("Tag: `" + TAG + "`[\\s\\S]*Commit: `[0-9a-f]{40}`"));
    if (name === "grill-with-docs") assert.match(provenance, /sibling SKILL\.md files as the fallback/);
    assert.match(readFileSync(path.join(destination, ".managed-checksum"), "utf8"), /^[0-9a-f]{64}\n$/);
  }

  for (const name of DEEP_DESIGN_SKILLS) {
    const skill = readFileSync(path.join(generatedSkill(fixture, name), "SKILL.md"), "utf8");
    assert.match(skill, /^disable-model-invocation: true$/m);
    const codex = readFileSync(path.join(generatedSkill(fixture, name), "agents/openai.yaml"), "utf8");
    assert.match(codex, /^policy:\n  allow_implicit_invocation: false$/m);
  }

  const grillWithDocs = readFileSync(path.join(generatedSkill(fixture, "grill-with-docs"), "SKILL.md"), "utf8");
  assert.equal(grillWithDocs.includes(GRILL_WITH_DOCS_PREIMAGE), false);
  assert.equal(grillWithDocs.split(GRILL_WITH_DOCS_REPLACEMENT).length - 1, 1);
  assert.match(grillWithDocs, /^disable-model-invocation: true$/m);

  const mergeSkill = readFileSync(path.join(generatedSkill(fixture, "resolving-merge-conflicts"), "SKILL.md"), "utf8");
  assert.equal(mergeSkill.includes(MERGE_PREIMAGE), false);
  assert.equal(mergeSkill.split(MERGE_REPLACEMENT).length - 1, 1);
}));

test("regeneration removes stale generated files and check mode detects drift", () => withFixture((fixture) => {
  assert.equal(runUpdater(fixture).status, 0);
  write(generatedSkill(fixture, "wait-what"), "stale.txt", "stale\n");
  const drift = runUpdater(fixture, "--check");
  assert.notEqual(drift.status, 0);
  assert.match(drift.stderr, /out of date/i);

  assert.equal(runUpdater(fixture).status, 0);
  assert.equal(runUpdater(fixture, "--check").status, 0);
  assert.equal(readdirSync(generatedSkill(fixture, "wait-what")).includes("stale.txt"), false);
}));

test("mode-only updates change the managed checksum", () => withFixture((fixture) => {
  assert.equal(runUpdater(fixture).status, 0);
  const generatedSupport = path.join(generatedSkill(fixture, "wait-what"), "support/nested.txt");
  const checksumPath = path.join(generatedSkill(fixture, "wait-what"), ".managed-checksum");
  const contentsBefore = readFileSync(generatedSupport);
  const checksumBefore = readFileSync(checksumPath, "utf8");

  const upstreamSupport = path.join(fixture.upstream, SKILLS["wait-what"], "support/nested.txt");
  chmodSync(upstreamSupport, 0o755);
  commitFixture(fixture.upstream, "make support executable");
  assert.match(git(fixture.upstream, "diff", "--summary", "HEAD^", "HEAD"), /mode change 100644 => 100755/);
  moveTag(fixture.upstream);

  const result = runUpdater(fixture, "--allow-moved-tag");
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(readFileSync(generatedSupport), contentsBefore);
  assert.notEqual(readFileSync(checksumPath, "utf8"), checksumBefore);
  assert.notEqual(statSync(generatedSupport).mode & 0o111, 0);
}));

test("rejects a moved existing tag unless explicitly allowed", () => withFixture((fixture) => {
  assert.equal(runUpdater(fixture).status, 0);
  write(fixture.upstream, `${SKILLS["wait-what"]}/new.txt`, "new release contents\n");
  commitFixture(fixture.upstream, "move release");
  moveTag(fixture.upstream);

  const rejected = runUpdater(fixture);
  assert.notEqual(rejected.status, 0);
  assert.match(rejected.stderr, /moved tag/i);
  const allowed = runUpdater(fixture, "--allow-moved-tag");
  assert.equal(allowed.status, 0, allowed.stderr);
  assert.equal(readFileSync(path.join(generatedSkill(fixture, "wait-what"), "new.txt"), "utf8"), "new release contents\n");
}));

test("rejects symlinks in selected source trees", () => withFixture((fixture) => {
  symlinkSync("nested.txt", path.join(fixture.upstream, SKILLS["wait-what"], "support/link.txt"));
  commitFixture(fixture.upstream, "add forbidden symlink");
  moveTag(fixture.upstream);

  const result = runUpdater(fixture);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /symlink/i);
}));

test("rejects a selected skill root symlink", () => withFixture((fixture) => {
  const selectedRoot = path.join(fixture.upstream, SKILLS["wait-what"]);
  rmSync(selectedRoot, { recursive: true });
  symlinkSync("writing-for-agents", selectedRoot);
  commitFixture(fixture.upstream, "replace selected skill root with symlink");
  moveTag(fixture.upstream);

  const result = runUpdater(fixture);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /symlink/i);
}));

for (const mutation of ["absent", "duplicated"]) {
  test(`fails when the grill-with-docs patch preimage is ${mutation}`, () => withFixture((fixture) => {
    const skillPath = path.join(fixture.upstream, SKILLS["grill-with-docs"], "SKILL.md");
    const original = readFileSync(skillPath, "utf8");
    writeFileSync(skillPath, mutation === "absent" ? original.replace(GRILL_WITH_DOCS_PREIMAGE, "Use some skills.") : `${original}\n${GRILL_WITH_DOCS_PREIMAGE}\n`);
    commitFixture(fixture.upstream, `make grill-with-docs preimage ${mutation}`);
    moveTag(fixture.upstream);

    const result = runUpdater(fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /exactly once/i);
  }));

  test(`fails when the merge-conflict patch preimage is ${mutation}`, () => withFixture((fixture) => {
    const skillPath = path.join(fixture.upstream, SKILLS["resolving-merge-conflicts"], "SKILL.md");
    const original = readFileSync(skillPath, "utf8");
    writeFileSync(skillPath, mutation === "absent" ? original.replace(MERGE_PREIMAGE, "Resolve it somehow.") : `${original}\n${MERGE_PREIMAGE}\n`);
    commitFixture(fixture.upstream, `make preimage ${mutation}`);
    moveTag(fixture.upstream);

    const result = runUpdater(fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /exactly once/i);
  }));
}
