# Reassess one guidance fragment

Prompt revision: 6.

## Parent launch

Keep orchestration in the parent thread. Launch one BB child thread with its own
worktree for each future fragment. Supply the fragment, source ref, current
inventory, open related work, and execution bound. Set a timeout that covers
setup, the full matrix, and review. Complete parent review of one fragment's
disposition before selecting the next.

## Child assignment

Read the repository instructions, `evals/README.md`, `evals/runner/README.md`,
and the installed `eval-design` skill. Use the supplied worktree.

1. Verify the source ref, fragment inventory, and related work. Record the source
   commit, prompt revision and hash, selected fragment hash, and inventory hash.
   Compute the inventory hash from the filename-to-SHA256 mapping with Python
   `json.dumps(mapping, sort_keys=True)`, default separators, no trailing newline.
   Record any metadata-file hash separately. Stop if launch inputs have changed.
2. Identify every material rule, the problem it prevents, and overlapping
   safeguards. Inspect history and existing evals. Reuse useful cases rather
   than historical conclusions. Label reused, synthetic, and stress cases;
   map them to rules and mark gaps. Keep tasks free of tested-policy reminders.
3. Freeze cases, checks, repetitions, decision criteria, execution limits, and
   known limits before paid generation. Reserve fresh confirmation cases when
   removal or authorized tuning could require them. Calibrate correct, wrong,
   and equivalent safe behavior through the actual grader before inference.
4. Use shared task templates, the native-agent runner, and calibration launcher.
   Build missing study-specific fixtures, behavior checks, and calibration
   checks. An older package without `tests/calibrate.py` is not a shared
   capability blocker. Stop paid trials on setup failure; continue safe setup
   diagnosis and repairs. Return a precise shared capability blocker if
   execution or isolation is missing; keep infrastructure changes under parent
   review rather than building a private replacement.
   Run generated code unprivileged inside the isolated container. Check that
   grading criteria, results, artifacts, and calibration fixtures are protected.
   Capture arguments independently of stdout and check real program output.
5. Run `openai-codex/gpt-6.1-terra` with medium reasoning. Match complete current
   guidance, that guidance minus exactly this fragment, and empty guidance.
   Keep Pi's built-in prompt and all other inputs fixed. Keep execution attached
   to a foreground command or registered job. On timeout, inspect the existing
   run owner and process before recovery; collect existing trials without
   duplicate inference. Behavioral failures remain results, not retry requests.
6. Inspect every candidate's tools, results, and final reply. Grade actual
   behavior and state, not claims. Apply presentation rules to the returned
   copy-paste answer rather than internal tool commands. Report task success,
   policy compliance, and infrastructure errors separately. Accept equivalent
   safe behavior, including refusals where allowed. Regrade saved answers after
   grader repairs and retain original scores. Compare native tokens only on
   matched successful trials; cached input is already included in input.
7. Apply the [evidence and decision rules](README.md#evidence-and-decisions).
   Record the recommendation separately from the strength of the evidence and
   state which rules the study covers. Keep guided failures visible. Use fresh
   confirmation only when the decision needs it. A tested revision needs
   separate authorization and fresh confirmation.
8. Commit runnable fixtures and a reviewed record with the frozen design,
   hashes, per-case observations, disposition, limits, verification, and temporary
   evidence paths. Keep credentials, private traces, and provider reasoning out
   of Git. Keep raw evidence in ignored `tmp/` through review and needed regrading;
   permanent retention is not required. Return the commit, evidence, and any
   needed changes to shared tools or assignment instructions to the parent.

Leave production guidance unchanged. The parent owns acceptance, publication,
production inspection, deployment, and cleanup. Start no other fragment, spawn
no children, push nothing, open no PR, merge nothing, and run no provisioning.
