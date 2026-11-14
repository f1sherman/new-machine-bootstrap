# Runnable evaluation evidence

This study asks whether guidance leads agents to check in runnable evidence for
actual work. Two synthetic CSV-export tasks run in disposable, network-disabled
Git repositories. The grader executes the staged artifacts in a fresh checkout,
checks actual CSV output, compares saved observations with the current source,
and mutates that source to check whether the runner detects drift. It checks
synthetic private markers. It does not publish a PR or test live agent discovery.

`records/results.json` retains every case's original and corrected grades,
condition and source hashes, settings, and matched successful token totals.
It does not retain the model's full tool traces or generated diffs. Those were
reviewed and regraded during this work; after temporary files expire, the
original runs cannot be independently regraded. Fresh runs remain possible.

## Results

All 12 workflows in the first candidate round and all 14 in the second
completed. In the first round, the full guidance failed both cases; one
without-recheck case passed. All other cases failed. This round is retained as
a failed iteration, not replaced.

In the second round, the full guidance passed both cases after the grader was
corrected. The historical and empty controls each passed zero of two. Ablations
passed as follows: without-fixtures 2/2, without-evidence 0/2, without-privacy
1/2, without-recheck 0/2. One trial per case and condition is a small diagnostic
sample, not a broad reliability estimate. The same two synthetic cases informed
previous work; they are not unseen validation.

The full and without-fixtures conditions both passed both tasks. Their combined
reported tokens were 67,070 and 77,043 respectively, including repeated context.
The difference is not a stable cost estimate. Failed conditions have no matched
successful-token comparison. The privacy check uses synthetic markers and does
not prove safety for real private data. No safeguard is removed because of an
ablation result.

The grader initially missed source hashes recorded inside a `conditions` array.
It therefore rejected a valid positional-output runner. We added a calibrated
case for that representation, reran all existing grader controls, and regraded
all saved responses in both rounds without new model calls. The original grades
remain beside corrected grades. Earlier calibration failure while constructing
that new fixture was fixed before the complete calibration passed. Independent
review also found rejected `.js` runners, `--output=value`, and Node options
before the script. After calibration and regrading all 26 workflows, four
previously missed documentation checks passed. No overall pass outcome changed;
the intermediate checks remain in the results. A separate stale-source runner
exposed an absolute-output collision that could falsely pass drift detection.
Each replay now gets its own output path, including when later options follow;
valid and stale-source examples were calibrated. Regrading all 26 workflows
again changed no checks.

## Run

Requires Node 22 or later, Docker, Pi authentication for fresh model calls, and
the `@earendil-works/pi-ai` SDK. The container has no network access; model calls
are made on the host. The runner never publishes results.

```bash
f=evals/checked-in-evals/workflow
image=nmb-checked-in-evals:workflow
docker build -t "$image" "$f"
node evals/checked-in-evals/prepare.mjs
node "$f/run.mjs" --calibrate --image "$image" \
  --output /tmp/checked-in-evals-calibration
sdk="$HOME/.pi/agent/npm/node_modules/@earendil-works"
sdk="$sdk/pi-ai/dist/compat.js"
node "$f/run.mjs" --image "$image" --sdk-module "$sdk" \
  --output /tmp/checked-in-evals-run
```

Each output path must be new. Use a different temporary name for each run.
Temporary directories may be removed by the OS; finish review and retain concise
results before they expire. Review generated fixtures before making model calls.
A run stops on an incomplete trial and does not retry automatically. It removes
its exact labelled containers. After an interruption, inspect the recorded
container IDs and remove only those owned by that run.

The original traces contain synthetic fixture data and are not checked in. Do not
publish temporary records without reviewing every field for private material.
