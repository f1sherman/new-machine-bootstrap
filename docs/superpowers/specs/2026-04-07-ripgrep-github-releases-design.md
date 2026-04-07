# Install ripgrep from GitHub Releases on Linux

## Problem

The `.ripgreprc` config includes `--engine=auto` (added May 2020), which requires ripgrep 13.0.0+. On Linux (Codespaces and dev hosts), ripgrep is installed via apt, which ships an older version that doesn't support this flag. This causes every `rg` invocation to fail with:

```
error: Found argument '--engine' which wasn't expected, or isn't valid in this context
```

macOS is unaffected because Homebrew provides a current version.

## Solution

Install ripgrep from GitHub Releases instead of apt on Linux, using the existing `install_github_binary.yml` framework. This is the same approach already used for fzf, delta, tmux, nvim, yq, and zoxide.

## Changes

### 1. Remove ripgrep from apt package list

In `roles/linux/tasks/install_packages.yml`, remove `ripgrep` from the `apt` task's package list.

### 2. Add GitHub Releases install task

Add a new task block in `roles/linux/tasks/install_packages.yml` using `install_github_binary.yml` with:

- `github_repo`: `BurntSushi/ripgrep`
- `binary_name`: `rg`
- `download_type`: `deb`
- `asset_pattern`: `ripgrep_{version}-1_{arch}.deb`
- `install_dest`: not needed for deb type (installs system-wide via dpkg)
- `arch_map`: `{x86_64: amd64, aarch64: arm64}`

The `.deb` download type is preferred over tarball because ripgrep's tarball assets use different libc variants per architecture (musl for x86_64, gnu for aarch64), which can't be expressed in a single `asset_pattern`. The `.deb` packages use a consistent naming scheme.

### 3. Remove apt ripgrep before GitHub install

Add a task to remove the apt-installed ripgrep (if present) before installing from GitHub Releases, similar to the existing pattern for fzf and neovim. This prevents version conflicts.

### 4. No changes to ripgreprc

The `.ripgreprc` config remains unchanged. The `--engine=auto` flag will work correctly with the newer version from GitHub Releases.

## Verification

After provisioning a Codespace:
- `rg --version` should show 14.0.0+ (current latest is 15.1.0)
- `rg --files` should work without error
- `FZF_DEFAULT_COMMAND` (`rg --files`) should work correctly
