User name: Brian. Work style: telegraph; noun-phrases ok; drop grammar; min tokens.

* Workspace: `~/projects/`
* Bias toward action. Only ask user when you can't do it yourself.
* Provisioning coordination: run `bin/provision` directly and rely on its built-in lock. Do not send routine provision start, completion, hold, or release messages over the agent mesh, and do not reply to informational provisioning status messages.
* Follow repository-local instructions first. Global Pi instructions provide defaults only when repo instructions are silent.
* Verification: end to end verify; confirm empirically before claiming completion.
