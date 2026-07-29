#!/bin/zsh

export TMPDIR="$HOME/.tmp"
[[ -d "$TMPDIR" ]] || mkdir -p "$TMPDIR"

alias vim=nvim

memusage() {
    ps aux | grep -i "$1" | grep -v grep | while read -r line; do
        pid=$(echo "$line" | awk '{print $2}')
        ps -p "$pid" -o pid=,comm=,%mem=,rss= | awk '{printf "PID: %s  Command: %s  Mem: %s  RSS: %.2f MB\n", $1, $2, $3, $4/1024}'
    done
}

set skip-completed-text on
set completion-ignore-case on
set mark-symlinked-directories on
set -o vi

encrypt() { gpg --symmetric "$1"; }
decrypt() { gpg -o "${1//\.enc/}" -d "$1"; }

mkcd() {
  \mkdir -p "$1"
  cd "$1"
}

tempe() {
  cd "$(mktemp -d)"
  chmod -R 0700 .
  if [[ $# -eq 1 ]]; then
    \mkdir -p "$1"
    cd "$1"
    chmod -R 0700 .
  fi
}

export FZF_CTRL_T_COMMAND='rg --files --ignore-vcs'
export FZF_CTRL_R_OPTS='--bind enter:accept-or-print-query'

if [[ -n "${HOMEBREW_PREFIX:-}" ]] && [[ -d "${HOMEBREW_PREFIX}/share/zsh-completions" ]]; then
  FPATH="${HOMEBREW_PREFIX}/share/zsh-completions:$FPATH"
fi

HISTFILE="${ZDOTDIR:-$HOME}/.zhistory"
HISTSIZE=10000
SAVEHIST=10000
setopt EXTENDED_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_FIND_NO_DUPS
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY
unsetopt HIST_VERIFY
unsetopt CORRECT

setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT

bindkey "^N" down-line-or-search
bindkey "^P" up-line-or-search

autoload -Uz add-zsh-hook
_prompt_timer_preexec() { _prompt_cmd_start=$EPOCHREALTIME }
_prompt_timer_precmd() {
  _prompt_vi_mode=
  if [[ -n "$_prompt_cmd_start" ]]; then
    local dur=$(( EPOCHREALTIME - _prompt_cmd_start ))
    unset _prompt_cmd_start
    if (( dur >= 3600 )); then
      _prompt_cmd_time_display=" %F{yellow}$(printf '%dh%dm' $((dur/3600)) $(((dur%3600)/60)))%f"
    elif (( dur >= 60 )); then
      _prompt_cmd_time_display=" %F{yellow}$(printf '%dm%ds' $((dur/60)) $((dur%60)))%f"
    elif (( dur >= 1 )); then
      _prompt_cmd_time_display=" %F{yellow}$(printf '%.2fs' $dur)%f"
    else
      _prompt_cmd_time_display=
    fi
  else
    _prompt_cmd_time_display=
  fi
}
add-zsh-hook preexec _prompt_timer_preexec
add-zsh-hook precmd _prompt_timer_precmd

_prompt_vi_mode=
function zle-keymap-select() {
  case "$KEYMAP" in
    vicmd) _prompt_vi_mode=' %F{yellow}[N]%f' ;;
    *)     _prompt_vi_mode= ;;
  esac
  zle reset-prompt
}
function zle-line-init() {
  _prompt_vi_mode=
}
zle -N zle-keymap-select
zle -N zle-line-init

setopt PROMPT_SUBST
PROMPT='%F{cyan}%~%f${_prompt_vi_mode}${_prompt_cmd_time_display}
%(?.%F{green}.%F{red})❯%f '

# Allow `prompt <theme>` (e.g. `prompt pure`) from the local zsh override. Prezto's
# prompt module isn't loaded in full, so wire up promptinit directly and put
# the bundled pure theme on fpath so both prompt_pure_setup and its async
# autoload resolve.
if [[ -d ~/.zprezto/modules/prompt/external/pure ]]; then
  fpath=(~/.zprezto/modules/prompt/external/pure $fpath)
fi
autoload -Uz promptinit && promptinit 2>/dev/null

if [[ -r ~/.zprezto/modules/autosuggestions/external/zsh-autosuggestions.zsh ]]; then
  source ~/.zprezto/modules/autosuggestions/external/zsh-autosuggestions.zsh
fi

if [[ -r ~/.zprezto/modules/syntax-highlighting/external/zsh-syntax-highlighting.zsh ]]; then
  source ~/.zprezto/modules/syntax-highlighting/external/zsh-syntax-highlighting.zsh
fi

if command -v fzf >/dev/null; then
  _fzf_cache="${HOME}/.cache/zsh/fzf-init.zsh"
  _fzf_bin="$(command -v fzf)"
  if [[ ! -f "$_fzf_cache" || "$_fzf_bin" -nt "$_fzf_cache" ]]; then
    mkdir -p "${_fzf_cache:h}"
    "$_fzf_bin" --zsh > "$_fzf_cache"
  fi
  source "$_fzf_cache"
  unset _fzf_cache _fzf_bin
fi

alias duss="du -d 1 -h 2>/dev/null | sort -hr"

if [[ -n "$TMUX" ]]; then
  zmodload zsh/datetime
  typeset -gi _tmux_title_transition_serial=0
  typeset -g _tmux_title_transition_last_timestamp=""

  _tmux_window_title_command() {
    emulate -L zsh
    setopt extendedglob

    local -a command_words
    local word
    local -i index=1
    command_words=("${(@Q)${(z)1}}")

    while (( index <= $#command_words )); do
      word="${command_words[index]}"
      if [[ "$word" == [A-Za-z_][A-Za-z0-9_]#=* ]]; then
        (( index++ ))
        continue
      fi

      case "$word" in
        command|builtin|nohup)
          (( index++ ))
          while (( index <= $#command_words )); do
            word="${command_words[index]}"
            [[ "$word" == -- ]] && { (( index++ )); break; }
            [[ "$word" == -* ]] || break
            (( index++ ))
          done
          ;;
        exec)
          (( index++ ))
          while (( index <= $#command_words )); do
            word="${command_words[index]}"
            [[ "$word" == -- ]] && { (( index++ )); break; }
            case "$word" in
              -a) (( index += 2 )) ;;
              -*) (( index++ )) ;;
              *) break ;;
            esac
          done
          ;;
        noglob|nocorrect)
          (( index++ ))
          ;;
        time)
          (( index++ ))
          if [[ "${command_words[index]:-}" == -p ]]; then
            (( index++ ))
          fi
          ;;
        env)
          (( index++ ))
          while (( index <= $#command_words )); do
            word="${command_words[index]}"
            [[ "$word" == -- ]] && { (( index++ )); break; }
            case "$word" in
              -u|-C|-S|--unset|--chdir|--split-string) (( index += 2 )) ;;
              --unset=*|--chdir=*|--split-string=*|-u?*|-C?*|-S?*) (( index++ )) ;;
              -*) (( index++ )) ;;
              *) break ;;
            esac
          done
          ;;
        sudo)
          (( index++ ))
          while (( index <= $#command_words )); do
            word="${command_words[index]}"
            [[ "$word" == -- ]] && { (( index++ )); break; }
            case "$word" in
              -u|-g|-h|-p|-C|-R|-T|-D|-r|-t|-U|--user|--group|--host|--prompt|--close-from|--chroot|--command-timeout|--chdir|--role|--type|--other-user) (( index += 2 )) ;;
              --user=*|--group=*|--host=*|--prompt=*|--close-from=*|--chroot=*|--command-timeout=*|--chdir=*|--role=*|--type=*|--other-user=*|-[ughpCRTDrtU]?*) (( index++ )) ;;
              -*) (( index++ )) ;;
              *) break ;;
            esac
          done
          ;;
        *)
          print -r -- "${word:t}"
          return 0
          ;;
      esac
    done
  }

  _tmux_title_transition_dispatch() {
    local program="$1" suppress_edge="${2:-0}" request_id
    local timestamp="${TMUX_TITLE_TRANSITION_NOW:-${EPOCHREALTIME/./}}"
    [[ "$timestamp" == <-> ]] || return 0
    if [[ -n "$_tmux_title_transition_last_timestamp" && "$timestamp" < "$_tmux_title_transition_last_timestamp" ]]; then
      timestamp="$_tmux_title_transition_last_timestamp"
    fi
    _tmux_title_transition_last_timestamp="$timestamp"
    _tmux_title_transition_serial=$((_tmux_title_transition_serial + 1))
    printf -v request_id '%s.%010d.%010d' "$timestamp" "$$" "$_tmux_title_transition_serial"
    command tmux-title-transition "$TMUX_PANE" "$request_id" "$program" "$suppress_edge" &>/dev/null &!
  }

  # Markers stay live for non-vim foreground commands (agents) so the outer
  # tmux can use edge fallback; vim consumes C-h/j/k/l itself, so its launch
  # suppresses markers (matching append_edge_marker in tmux-remote-title).
  _tmux_window_title_preexec() {
    local expanded_command="${3:-${2:-$1}}" program suppress_edge=0
    program="$(_tmux_window_title_command "$expanded_command")"
    [[ -n "$program" ]] || return 0
    case "$program" in
      *vim*) suppress_edge=1 ;;
    esac
    _tmux_title_transition_dispatch "$program" "$suppress_edge"
  }

  _tmux_window_title_precmd() {
    _tmux_title_transition_dispatch zsh 0
  }

  add-zsh-hook preexec _tmux_window_title_preexec
  add-zsh-hook precmd _tmux_window_title_precmd

  # chpwd-only: pane_current_path changes don't fire any tmux event hook,
  # so we still need a zsh-side trigger when the user `cd`s. Other label
  # refresh paths (pane focus, pane title, new pane) are covered by the
  # tmux event hooks defined in tmux.conf.
  _tmux_label_update() {
    _tmux_title_transition_dispatch zsh 0
    command tmux-sync-pane-border-status "$TMUX_PANE" &>/dev/null &!
  }
  add-zsh-hook chpwd _tmux_label_update
fi

autoload -Uz compinit
if [[ -f ~/.zcompdump && -z ~/.zcompdump(#qNmh+24) ]]; then
  compinit -C
else
  compinit
fi

if [[ -z "$CLAUDECODE" ]] && command -v zoxide > /dev/null; then
  _zoxide_cache="${HOME}/.cache/zsh/zoxide-init.zsh"
  _zoxide_bin="$(command -v zoxide)"
  if [[ ! -f "$_zoxide_cache" || "$_zoxide_bin" -nt "$_zoxide_cache" ]]; then
    mkdir -p "${_zoxide_cache:h}"
    "$_zoxide_bin" init zsh --cmd cd > "$_zoxide_cache"
  fi
  source "$_zoxide_cache"
  unset _zoxide_cache _zoxide_bin
fi
