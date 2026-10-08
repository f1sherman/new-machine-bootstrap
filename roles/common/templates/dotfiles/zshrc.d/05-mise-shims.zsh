# shellcheck shell=bash

# Login shells run macOS path_helper after ~/.zshenv, which moves the system
# directories ahead of the mise shims. A shell that inherits ZSH_ENV_LOADED
# skips ~/.zshenv entirely. Put the shims first again so scripts that start
# with `#!/usr/bin/env ruby` get the mise Ruby, not the system one.
_mise_shims="${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims"
if [[ -d "$_mise_shims" ]]; then
  path=("$_mise_shims" "${(@)path:#$_mise_shims}")
fi
unset _mise_shims
