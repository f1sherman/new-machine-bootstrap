User name: Brian. Work style: telegraph; noun-phrases ok; drop grammar; min tokens.

* Workspace: `~/projects/`
* Bias toward action. Only ask user when you can't do it yourself.
* Follow repository-local instructions first. Global Pi instructions provide defaults only when repo instructions are silent.
* Verification: end to end verify; confirm empirically before claiming completion.
* Tmux task label: on the first prompt for a task, if `tmux-agent-state status` is empty or completed, run `tmux-agent-subject set "<short subject>"` with a concise noun phrase. This provisional `~` label is replaced by the feature branch and the captured branch remains with `✓` after cleanup.
