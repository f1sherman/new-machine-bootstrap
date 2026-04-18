# shellcheck shell=bash

if [[ -n "$ZSH_ENV_LOADED" ]]; then
  return 0
fi
export ZSH_ENV_LOADED=1

pathprepend() {
  local dir="${1%/}"
  if [ -d "${dir}" ]; then
    if [[ ":$PATH:" != *":${dir}:"* ]]; then
      PATH="${dir}:$PATH"
    else
      PATH=":$PATH:"
      PATH=${PATH//:${dir}:/:}
      PATH=${PATH#:}
      PATH=${PATH%:}
      PATH="${dir}:$PATH"
    fi
  fi
}

pathprepend "${HOME}/.local/bin"

{% if ansible_facts['os_family'] == "Darwin" %}
export HOMEBREW_PREFIX="{{ brew_prefix }}"
export HOMEBREW_CELLAR="{{ brew_prefix }}/Cellar"
export HOMEBREW_REPOSITORY="{{ brew_prefix }}"
{% else %}
export HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
export HOMEBREW_CELLAR="${HOMEBREW_PREFIX}/Cellar"
export HOMEBREW_REPOSITORY="${HOMEBREW_PREFIX}/Homebrew"
{% endif %}
fpath=("${HOMEBREW_PREFIX}/share/zsh/site-functions" $fpath)
pathprepend "${HOMEBREW_PREFIX}/bin"
pathprepend "${HOMEBREW_PREFIX}/sbin"
pathprepend "${HOMEBREW_PREFIX}/opt/curl/bin"
pathprepend "/usr/local/sbin"
pathprepend "/usr/local/bin"

_mise_shims="${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims"
if [[ -d "$_mise_shims" ]]; then
  pathprepend "$_mise_shims"
fi
unset _mise_shims

export GIT_MERGE_AUTOEDIT=no

export HISTSIZE='32768'
export HISTFILESIZE="${HISTSIZE}"

export LANG='en_US.UTF-8'
export LC_ALL='en_US.UTF-8'

export CLICOLOR='true'
export LSCOLORS='gxfxbEaEBxxEhEhBaDaCaD'

export RIPGREP_CONFIG_PATH="${HOME}/.ripgreprc"

export FZF_DEFAULT_COMMAND='rg --files'

export PAGER='less -S'
export GH_PAGER='delta'

alias assume=". assume"

for API_NAME in "openai" "anthropic"; do
  API_KEY_FILE="${HOME}/.config/api-keys/${API_NAME}"
  if [ -f "$API_KEY_FILE" ] && [ -s "$API_KEY_FILE" ]; then
    API_ENV_NAME="${(U)API_NAME}_API_KEY"
    API_ENV_VALUE="$(<"$API_KEY_FILE")"
    export "${API_ENV_NAME}=${API_ENV_VALUE}"
  fi
done
