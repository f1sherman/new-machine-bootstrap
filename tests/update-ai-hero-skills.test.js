import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { chmodSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const PROJECT_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const UPDATER = path.join(PROJECT_ROOT, "bin/update-ai-hero-skills");
const TAG = "v-test";
const GRILL_WITH_DOCS_PREIMAGE = "Run a `/grilling` session, using the `/domain-modeling` skill.";
const GRILL_WITH_DOCS_REPLACEMENT = "Use the harness's skill mechanism, when available, to load and follow both the `grilling` and `domain-modeling` skills. If the mechanism is unavailable or cannot load either dependency (including invocation-policy rejection), read and follow both sibling files `../grilling/SKILL.md` and `../domain-modeling/SKILL.md`.";
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
    const explicitFrontmatter = name === "wait-what" ? "disable-model-invocation: true\n" : "";
    const explicitCodexPolicy = name === "wait-what" ? "policy:\n  allow_implicit_invocation: false\n" : "";
    write(upstream, `${sourcePath}/SKILL.md`, `---\nname: ${name}\ndescription: Fixture ${name}\n${explicitFrontmatter}---\n\n# ${name}\n\n${body}\n`);
    write(upstream, `${sourcePath}/agents/openai.yaml`, `interface:\n  display_name: "${name}"\n  short_description: "Fixture ${name}"\n${explicitCodexPolicy}`);
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

test("rejects wait-what when an upstream user-only flag is missing", () => {
  const cases = [
    {
      path: "SKILL.md",
      remove: "disable-model-invocation: true\n",
      error: /disable-model-invocation must be true/,
    },
    {
      path: "agents/openai.yaml",
      remove: "policy:\n  allow_implicit_invocation: false\n",
      error: /policy\.allow_implicit_invocation must be false/,
    },
  ];

  for (const testCase of cases) {
    withFixture((fixture) => {
      const upstreamPath = path.join(fixture.upstream, SKILLS["wait-what"], testCase.path);
      const contents = readFileSync(upstreamPath, "utf8");
      writeFileSync(upstreamPath, contents.replace(testCase.remove, ""));
      commitFixture(fixture.upstream, `drop wait-what flag from ${testCase.path}`);
      moveTag(fixture.upstream);

      const result = runUpdater(fixture);
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, testCase.error);
    });
  }
});

test("wrapper fallback contract points to readable dependencies even after invocation-policy rejection", () => withFixture((fixture) => {
  const result = runUpdater(fixture);
  assert.equal(result.status, 0, result.stderr);
  const wrapperRoot = generatedSkill(fixture, "grill-with-docs");
  const wrapper = readFileSync(path.join(wrapperRoot, "SKILL.md"), "utf8");
  assert.ok(wrapper.includes(GRILL_WITH_DOCS_REPLACEMENT));
  assert.match(wrapper, /cannot load either dependency \(including invocation-policy rejection\)/);
  const siblings = [...wrapper.matchAll(/`(\.\.\/[^`]+\/SKILL\.md)`/g)].map((match) => match[1]);
  assert.deepEqual(siblings, ["../grilling/SKILL.md", "../domain-modeling/SKILL.md"]);
  // Contract smoke check: actually read the generated fallback targets. This is
  // not an interactive harness test or proof that a model follows instructions.
  for (const sibling of siblings) {
    const dependency = readFileSync(path.resolve(wrapperRoot, sibling), "utf8");
    assert.match(dependency, new RegExp(`^name: ${path.basename(path.dirname(sibling))}$`, "m"));
    assert.match(dependency, /^disable-model-invocation: true$/m);
    assert.match(dependency, /Fixture body\./);
  }
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

test("managed checksum includes executable mode with constant provenance", () => withFixture((fixture) => {
  const upstreamSupport = path.join(fixture.upstream, SKILLS["wait-what"], "support/nested.txt");
  chmodSync(upstreamSupport, 0o755);
  commitFixture(fixture.upstream, "make support executable");
  moveTag(fixture.upstream);

  const result = runUpdater(fixture);
  assert.equal(result.status, 0, result.stderr);
  const skillRoot = generatedSkill(fixture, "wait-what");
  assert.notEqual(statSync(path.join(skillRoot, "support/nested.txt")).mode & 0o111, 0);
  const checksum = readFileSync(path.join(skillRoot, ".managed-checksum"), "utf8").trim();

  // Both candidate digests use the same generated bytes, including UPSTREAM.md.
  // Only the support file's executable state differs; no tag move can mask it.
  function expectedChecksum(supportMode) {
    const hash = createHash("sha256");
    for (const relative of ["LICENSE", "SKILL.md", "UPSTREAM.md", "agents/openai.yaml", "support/nested.txt"]) {
      const mode = relative === "support/nested.txt" ? supportMode : "non-executable";
      hash.update(`${relative}\0${mode}\0`);
      hash.update(readFileSync(path.join(skillRoot, relative)));
      hash.update("\0");
    }
    return hash.digest("hex");
  }
  assert.equal(checksum, expectedChecksum("executable"));
  assert.notEqual(checksum, expectedChecksum("non-executable"));
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

test("rejects an external LICENSE symlink without replacing the existing vendor tree", () => withFixture((fixture) => {
  assert.equal(runUpdater(fixture).status, 0);
  const vendorRoot = path.dirname(generatedSkill(fixture, "grilling"));
  function snapshot() {
    return readdirSync(vendorRoot, { recursive: true }).sort().map((relative) => {
      const absolute = path.join(vendorRoot, relative);
      const stats = statSync(absolute);
      return [relative, stats.mode, stats.isFile() ? readFileSync(absolute).toString("hex") : null];
    });
  }
  const before = snapshot();
  const sentinel = path.join(fixture.root, "external-license-sentinel.txt");
  writeFileSync(sentinel, "harmless external sentinel: must never be vendored\n");
  const license = path.join(fixture.upstream, "LICENSE");
  rmSync(license);
  symlinkSync(sentinel, license);
  commitFixture(fixture.upstream, "replace license with external symlink");
  moveTag(fixture.upstream);

  const result = runUpdater(fixture, "--allow-moved-tag");
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /LICENSE.*regular non-symlink file/i);
  assert.deepEqual(snapshot(), before);
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
