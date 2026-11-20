# Native PR workflow smoke test

Can the shared runner take a normal PR request through a real Git diff, native Pi tools and an observable submission? A draft in the final answer is not completion. A pass supports using this runner for this class of fixture; it is not evidence for keeping or removing guidance.

The synthetic delivery-queue repository changes the retry delay from 5 to 30 seconds. The candidate has a local bare origin and discovers a fixture skill. The skill and `fixture-pr` replace the production PR skill, review, publication API and monitoring. The CLI accepts the exact title and body for the pushed fixture head and writes a local receipt. The separate verifier checks that receipt for the intended head and basic diff facts. This is not a prose-quality judge, an adversarial receipt test or a test of GitHub integration.

Before inference, run the production verifier against a draft without submission, a valid submission and equivalent wording. Run only one `current` trial with a 12-turn, 900-second cap. This is a runner check, not a fragment comparison. Do not reroll, run a semantic judge or connect the fixture to a publication service.

```bash
f=evals/runner-smoke/study.toml
p=tmp/harbor-venv/bin/python
umask 077
"$p" -m evals.runner.calibrate --study "$f" --output tmp/pr-smoke-cal
"$p" -m evals.runner.run --study "$f" --conditions current --trials 1 \
  --model openai-codex/gpt-6.2-sol --thinking medium --max-turns 12 \
  --output tmp/pr-smoke-live --live
"$p" -m evals.runner.run --audit tmp/pr-smoke-live
```
