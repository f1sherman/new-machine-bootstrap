# Guidance evaluation mapping

Run `bin/guidance-coverage` from any directory. It reads
`evals/guidance-coverage.yml` and lists the Pi base fragments, linked studies,
conditions, cases, model, records, and limitations. It requires Ruby and the
standard library. The initial mapping covers workspace and writing studies;
other fragments are listed as unmapped, not automatically as missing evals.

Each study appears once in the YAML. Its `coverage` entries associate individual
fragments with cases and conditions. `direct` means the comparison removes the
named component; `combined` means it removes more than one component;
`background` means the guidance was present but not directly compared. A
relationship is not a claim that the model passed or that every rule in a
fragment is covered. Read the linked record before using the result.

The source and case hashes identify the repository inputs present for the
study. The report compares them with the current assembled base and case file.
A changed hash signals that the mapping needs review. A match does not prove
that the complete provider request matched the repository file, that an eval
passed, or that its grader was valid. The report also checks that the fragments
assemble to the checked-in base and that referenced fragments and case IDs
exist. It does not validate condition names, fetch records, run evals, or
establish semantic coverage.

The initial Terra records are pinned to commits in open study PRs #756 and
#759. Their frozen records remain separate from the manifest; the manifest does
not copy scores or raw trial responses. Update the links only after checking
that the replacement record preserves the study and its limitations. Do not
publish private raw trial evidence.
