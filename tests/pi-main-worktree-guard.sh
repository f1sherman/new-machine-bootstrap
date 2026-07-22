#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
extension="$repo_root/roles/common/files/pi/extensions/main-worktree-guard.ts"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

cp "$extension" "$tmp_root/main-worktree-guard.mjs"

git -C "$tmp_root" init -q primary
git -C "$tmp_root/primary" config user.email test@example.com
git -C "$tmp_root/primary" config user.name Test
touch "$tmp_root/primary/tracked"
git -C "$tmp_root/primary" add tracked
git -C "$tmp_root/primary" commit -qm initial
git -C "$tmp_root/primary" branch -M main
git -C "$tmp_root/primary" worktree add -qb feature "$tmp_root/feature"
ln -s "$tmp_root/feature" "$tmp_root/primary/linked-dir"
ln -s "$tmp_root/primary" "$tmp_root/feature/primary-link"

cat > "$tmp_root/check.mjs" <<'NODE'
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { promisify } from "node:util";
import { pathToFileURL } from "node:url";

const execFileAsync = promisify(execFile);
const [extensionPath, primary, feature] = process.argv.slice(2);
const handlers = new Map();
const pi = {
  on(event, handler) {
    handlers.set(event, handler);
  },
  async exec(command, args, options = {}) {
    try {
      const result = await execFileAsync(command, args, {
        cwd: options.cwd,
        timeout: options.timeout,
        encoding: "utf8",
      });
      return { stdout: result.stdout, stderr: result.stderr, code: 0, killed: false };
    } catch (error) {
      return {
        stdout: error.stdout || "",
        stderr: error.stderr || String(error),
        code: error.code || 1,
        killed: Boolean(error.killed),
      };
    }
  },
};

const { default: install } = await import(pathToFileURL(extensionPath));
install(pi);
const toolCall = handlers.get("tool_call");
assert.equal(typeof toolCall, "function", "registers tool_call guard");

async function call(toolName, input, cwd = feature) {
  return toolCall({ toolName, input }, { cwd });
}

for (const toolName of ["edit", "write"]) {
  const relative = await call(toolName, { path: "tracked" }, primary);
  assert.equal(relative?.block, true, `${toolName} blocks relative primary-main target`);
  assert.match(relative.reason, /primary main worktree/, `${toolName} explains primary-main protection`);

  const absolute = await call(toolName, { path: path.join(primary, "tracked") }, feature);
  assert.equal(absolute?.block, true, `${toolName} blocks absolute primary target from feature cwd`);

  const linked = await call(toolName, { path: path.join(feature, "tracked") }, primary);
  assert.equal(linked, undefined, `${toolName} allows linked feature-worktree target`);

  const linkedIntoPrimary = await call(toolName, { path: path.join(feature, "primary-link", "tracked") }, feature);
  assert.equal(linkedIntoPrimary?.block, true, `${toolName} blocks feature symlink resolving into primary main`);
}

const blockedCommands = [
  ["redirection", `printf changed > ${path.join(primary, "tracked")}`],
  ["append redirection", `printf changed >> ${path.join(primary, "tracked")}`],
  ["clobber redirection", `printf changed >| ${path.join(primary, "tracked")}`],
  ["tee", `printf changed | tee ${path.join(primary, "tracked")}`],
  ["remove", `rm ${path.join(primary, "tracked")}`],
  ["copy destination", `cp ${path.join(feature, "tracked")} ${path.join(primary, "copy")}`],
  ["copy target option", `cp -t ${primary} ${path.join(feature, "tracked")}`],
  ["copy long target option", `cp --target-directory=${primary} ${path.join(feature, "tracked")}`],
  ["install target option", `install -t ${primary} ${path.join(feature, "tracked")}`],
  ["move destination", `mv ${path.join(feature, "tracked")} ${path.join(primary, "moved")}`],
  ["touch", `touch ${path.join(primary, "new")}`],
  ["touch timestamp", `touch -t 202401010000 ${path.join(primary, "tracked")}`],
  ["mkdir", `mkdir ${path.join(primary, "new-dir")}`],
  ["link", `ln -s ${path.join(feature, "tracked")} ${path.join(primary, "link")}`],
  ["truncate", `truncate -s 0 ${path.join(primary, "tracked")}`],
  ["in-place sed", `sed -i '' s/a/b/ ${path.join(primary, "tracked")}`],
  ["multi-file in-place sed", `sed -i.bak s/a/b/ ${path.join(primary, "tracked")} ${path.join(feature, "tracked")}`],
  ["in-place perl", `perl -pi -e 's/a/b/' ${path.join(primary, "tracked")}`],
  ["git restore", `git -C ${primary} restore tracked`],
  ["git config-option restore", `git -C ${primary} -c color.ui=false restore tracked`],
  ["git explicit work tree", `git --work-tree=${primary} restore tracked`],
  ["git clean", `git -C ${primary} clean -fd`],
  ["git reset", `cd ${primary} && git reset --hard`],
  ["git apply", `git -C ${primary} apply change.patch`],
  ["positional patch", `patch ${path.join(primary, "tracked")} change.patch`],
  ["python Path.write_text", `python3 - <<'PY'\nfrom pathlib import Path\nPath('${path.join(primary, "tracked")}').write_text('changed')\nPY`],
  ["python relative Path.write_text", `python3 -c "from pathlib import Path; Path('../primary/tracked').write_text('changed')"`],
  ["python relative write after cd", `cd ${primary} && python3 -c "from pathlib import Path; Path('tracked').write_text('changed')"`],
  ["python writable open", `python3 -c "open('${path.join(primary, "tracked")}', 'w').write('changed')"`],
  ["python update open", `python3 -c "open('${path.join(primary, "tracked")}', 'r+').write('changed')"`],
  ["ruby write", `ruby -e "File.write('${path.join(primary, "tracked")}', 'changed')"`],
  ["node write", `node -e "require('fs').writeFileSync('${path.join(primary, "tracked")}', 'changed')"`],
  ["shell-wrapped remove", `bash -c 'rm ${path.join(primary, "tracked")}'`],
  ["primary symlink removal", `rm ${path.join(primary, "linked-dir")}`],
  ["feature symlink into primary removal", `rm ${path.join(feature, "primary-link", "tracked")}`],
  ["chmod target", `chmod 600 ${path.join(primary, "tracked")}`],
  ["chmod symbolic target", `chmod -w ${path.join(primary, "tracked")}`],
  ["chown target", `chown test ${path.join(primary, "tracked")}`],
];

for (const [label, command] of blockedCommands) {
  const result = await call("bash", { command }, feature);
  assert.equal(result?.block, true, `blocks ${label} against primary main`);
  assert.match(result.reason, /primary main worktree/, `${label} identifies protected worktree`);
}

const allowedCommands = [
  "git status --short",
  "python3 -c 'print(42)'",
  `echo rm ${path.join(primary, "tracked")}`,
  `echo "Path('${path.join(primary, "tracked")}').write_text('changed')"`,
  `ruby -e "File.open('${path.join(primary, "tracked")}') { |file| file.read }"`,
  `cd ${primary} && chmod 600 ${path.join(feature, "tracked")}`,
  `cd ${primary} && chmod -Rv 600 ${path.join(feature, "tracked")}`,
  `touch -r ${path.join(primary, "tracked")} ${path.join(feature, "tracked")}`,
  `rm ${path.join(feature, "primary-link")}`,
  `printf changed > ${path.join(feature, "tracked")}`,
  `touch ${path.join(feature, "new")}`,
  `git -C ${feature} restore tracked`,
  `python3 -c "from pathlib import Path; Path('${path.join(feature, "tracked")}').write_text('changed')"`,
  "unknown-writer --maybe-mutates",
];

for (const command of allowedCommands) {
  assert.equal(await call("bash", { command }, feature), undefined, `allows: ${command}`);
}

assert.equal(fs.readFileSync(path.join(primary, "tracked"), "utf8"), "", "guard inspection never mutates primary fixture");
console.log("pi main worktree guard checks complete");
NODE

node "$tmp_root/check.mjs" "$tmp_root/main-worktree-guard.mjs" "$tmp_root/primary" "$tmp_root/feature"
