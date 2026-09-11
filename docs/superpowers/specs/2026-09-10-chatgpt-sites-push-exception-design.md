# ChatGPT Sites Push Exception Design

**Status:** Self-approved

## Goal

Allow ChatGPT Sites to publish generated site repositories to the service's
`main` branch without disabling direct-to-main protection for normal Git
repositories.

## Non-goals

- Do not weaken force-push restrictions.
- Do not exempt other hosting services or repository types.
- Do not depend on one generated site repository path or UUID.
- Do not change the normal pull request workflow.

## Assumptions

- ChatGPT Sites publishes through a remote whose URL host is
  `git.chatgpt-team.site`.
- The generated remote path and local repository path can change for each site.
- A direct push to `main` is required because the Sites workflow does not expose
  a pull request flow.
- Both Codex and Pi managed hooks must make the same decision.

## Recommended Approach

Allow two strict command shapes. The first is a plain `git push`. The second
adds exactly one command-scoped `-c http.extraHeader=<nonempty value>` setting
before `push` so ChatGPT Sites can authenticate. In both forms, the destination
must be an explicit HTTPS URL on the exact `git.chatgpt-team.site` host and the
sole refspec must be the unforced `HEAD:main`. Header values can contain spaces
when shell-quoted, but cannot contain shell expansion or control syntax.

Require a valid Git repository. Resolve the URL through Git's local URL-rewrite
rules without network access and require the effective URL to remain on the same
exact host. Named remotes, implicit remotes, other or multiple Git configuration
options, push options, shell wrappers, shell expansion, environment assignments,
extra refspecs, forced refspecs, and unresolved repository state do not qualify.
They keep the normal fail-closed result. The Pi hook will apply the same strict
rule through its existing Git command interface.

This approach follows the service boundary without trusting Git's broad remote
configuration surface. It deliberately requires ChatGPT Sites to use the
explicit URL form shown by its publishing workflow.

## Alternatives Considered

### Exempt all repositories under `daily-sites`

This is simple, but it relies on a temporary local path convention. It can also
allow a normal Git remote if a repository is placed under that directory.

### Exempt one repository UUID and remote URL

This is the narrowest immediate fix, but each generated site can have a new
UUID. It would require repeated configuration changes and would not solve the
workflow class.

### Disable the direct-to-main hook in ChatGPT

This would unblock publishing, but it would also remove protection for all
normal repositories used in ChatGPT. The scope is too broad.

## Components and Boundaries

- `roles/common/files/bin/codex-block-git-push-main` owns the Codex pre-tool
  decision. It will resolve remote URLs through Git and recognize only the
  ChatGPT Sites host.
- `roles/common/files/pi/extensions/managed-hooks.ts` owns the Pi pre-tool
  decision. It will use the same host rule before returning a block reason.
- Hook tests own temporary Git repositories and assert observable allow or block
  results. No deployed files are changed by tests.

## Error Handling

Unknown repositories, malformed commands, empty authentication headers, URL
rewrites to another host, and non-matching URLs keep the current fail-closed
behavior. Only the strict plain or authenticated command with both an explicit
and effective exact service host gets the exception.

## Testing and Verification

1. Prove that a direct push to `main` with a normal URL is blocked.
2. Prove that plain and authenticated explicit `git.chatgpt-team.site` URL
   pushes of `HEAD:main` are allowed.
3. Prove that empty headers, other or repeated Git configuration, named or
   implicit remotes, force modes, options, shell expansion, URL rewrites, and
   extra refspecs remain blocked.
4. Run the Codex hook test and the Pi managed-hooks test.
5. Run provisioning and confirm the managed hook is deployed from this branch.
6. Run `bin/provision --check` to confirm idempotence.

## Rollout

Provision the updated managed files. Existing hook registration does not change.
A new ChatGPT Site publish attempt can then push to the Sites remote directly.
